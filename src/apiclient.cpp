#include "apiclient.h"
#include "settings.h"

#include <QBuffer>
#include <QCoreApplication>
#include <QDateTime>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStringList>
#include <QQmlEngine>
#include <QTimer>

namespace {
const int TimeoutMs = 20000;
}

ApiClient::ApiClient(Settings *settings, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
    , m_network(new QNetworkAccessManager(this))
{
}

void ApiClient::request(const QString &method, const QString &path,
                        const QJSValue &body, const QJSValue &callback)
{
    requestWith(m_settings->baseUrl(), m_settings->apiKey(), method, path, body, callback);
}

void ApiClient::requestWith(const QString &baseUrl, const QString &apiKey,
                            const QString &method, const QString &path,
                            const QJSValue &body, const QJSValue &callback)
{
    // Taken as a QJSValue: a JS object passed to a QVariant parameter
    // arrives as a QVariant wrapping a QJSValue, which QJsonDocument
    // silently turns into an empty body.
    const QVariant variantBody = (body.isUndefined() || body.isNull()) ? QVariant() : body.toVariant();
    sendWith(baseUrl, apiKey, method, path, variantBody, jsHandler(callback));
}

void ApiClient::send(const QString &method, const QString &path, const QVariant &body, Handler handler,
                     const QVariantMap &headers)
{
    sendWith(m_settings->baseUrl(), m_settings->apiKey(), method, path, body, handler, headers);
}

ApiClient::Handler ApiClient::jsHandler(const QJSValue &callback)
{
    return [this, callback](bool ok, int status, const QVariant &data, const QString &error) {
        QJSValue cb(callback);
        if (!cb.isCallable())
            return;
        QJSValue jsData = m_engine ? m_engine->toScriptValue(data) : QJSValue();
        QJSValue result = cb.call(QJSValueList() << ok << status << jsData << error);
        if (result.isError())
            qWarning("ApiClient callback error: %s", qPrintable(result.toString()));
    };
}

void ApiClient::sendWith(const QString &baseUrl, const QString &apiKey, const QString &method,
                         const QString &path, const QVariant &body, Handler handler,
                         const QVariantMap &headers)
{
    const QString base = Settings::normalizeBaseUrl(baseUrl);
    const QUrl root(base + QStringLiteral("/api/v1/"));

    QUrl url;
    if (path.startsWith(QStringLiteral("http://")) || path.startsWith(QStringLiteral("https://"))) {
        url = QUrl(path);
        // Never send the key anywhere but the configured server.
        if (url.scheme() != root.scheme() || url.host() != root.host()
                || url.port(-1) != root.port(-1)) {
            if (handler)
                handler(false, 0, QVariant(), tr("Refused to follow a link to another server."));
            return;
        }
    } else {
        url = root.resolved(QUrl(path));
    }

    QNetworkRequest req(url);
    req.setRawHeader("Authorization", "Bearer " + apiKey.toUtf8());
    req.setRawHeader("Accept", "application/json");
    req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, false);
    for (auto it = headers.constBegin(); it != headers.constEnd(); ++it)
        req.setRawHeader(it.key().toUtf8(), it.value().toString().toUtf8());

    QByteArray payload;
    if (body.isValid()) {
        payload = QJsonDocument::fromVariant(body).toJson(QJsonDocument::Compact);
        req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    }

    // Qt 5.6 has no QByteArray overload of sendCustomRequest.
    QBuffer *buffer = new QBuffer;
    buffer->setData(payload);
    buffer->open(QIODevice::ReadOnly);
    QNetworkReply *reply = m_network->sendCustomRequest(req, method.toUpper().toLatin1(), buffer);
    buffer->setParent(reply);
    m_pending.insert(reply, Pending { handler, base == m_settings->baseUrl() && apiKey == m_settings->apiKey(), method.toUpper() });
    if (m_pending.size() == 1)
        emit busyChanged();

    QTimer *timer = new QTimer(reply);
    timer->setSingleShot(true);
    connect(timer, &QTimer::timeout, reply, &QNetworkReply::abort);
    timer->start(TimeoutMs);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() { finish(reply); });
}

bool ApiClient::isOpenFoodFactsUrl(const QUrl &url)
{
    return url.isValid() && url.scheme() == QLatin1String("https") && url.port(-1) == -1
            && url.userInfo().isEmpty()
            && (url.host() == QLatin1String("search.openfoodfacts.org")
                || url.host() == QLatin1String("world.openfoodfacts.org"));
}

void ApiClient::openFoodFacts(const QString &urlText, const QJSValue &callback)
{
    Handler handler = jsHandler(callback);
    const QUrl url(urlText);
    if (!isOpenFoodFactsUrl(url)) {
        handler(false, 0, QVariant(), tr("Refused to follow a link to another server."));
        return;
    }
    const qint64 minute = QDateTime::currentMSecsSinceEpoch() / 60000;
    if (minute != m_offMinute) {
        m_offMinute = minute;
        m_offSearches = 0;
        m_offReads = 0;
    }
    const bool search = url.host() == QLatin1String("search.openfoodfacts.org");
    int &used = search ? m_offSearches : m_offReads;
    if (used >= (search ? 8 : 12)) {
        handler(false, 429, QVariant(), tr("Too many requests. Wait a moment and try again."));
        return;
    }
    used++;

    QNetworkRequest req(url);
    req.setRawHeader("Accept", "application/json");
    req.setRawHeader("User-Agent", QStringLiteral("harbour-ironstack/%1 (Sailfish OS IronStack client)")
                     .arg(QCoreApplication::applicationVersion()).toUtf8());
    req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, false);
    QNetworkReply *reply = m_network->get(req);
    QTimer *timer = new QTimer(reply);
    timer->setSingleShot(true);
    connect(timer, &QTimer::timeout, reply, &QNetworkReply::abort);
    timer->start(TimeoutMs);
    connect(reply, &QNetworkReply::finished, this, [reply, handler]() {
        reply->deleteLater();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QVariant data = QJsonDocument::fromJson(reply->readAll()).toVariant();
        // OFF answers an unknown barcode with 404 and {"status": 0}.
        const bool ok = (status >= 200 && status < 300) || (status == 404 && data.isValid());
        QString error;
        if (!ok) {
            if (status == 0)
                error = reply->error() == QNetworkReply::OperationCanceledError
                        ? tr("Open Food Facts did not answer in time.") : tr("Can't reach Open Food Facts.");
            else if (status == 429 || status == 503)
                error = tr("Open Food Facts is busy. Wait a moment and try again.");
            else
                error = tr("Open Food Facts had an error (%1).").arg(status);
        }
        handler(ok, status, data, error);
    });
}

void ApiClient::finish(QNetworkReply *reply)
{
    reply->deleteLater();
    const Pending pending = m_pending.take(reply);
    if (m_pending.isEmpty())
        emit busyChanged();

    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QByteArray raw = reply->readAll();
    QVariant data;
    if (!raw.isEmpty())
        data = QJsonDocument::fromJson(raw).toVariant();

    const bool ok = status >= 200 && status < 300;
    const QString error = ok ? QString() : errorMessage(status, data, reply, pending.method);

    if (status == 401 && pending.usesSavedKey)
        emit unauthorized();

    if (pending.handler)
        pending.handler(ok, status, data, error);
}

QString ApiClient::contextForPath(const QString &path)
{
    QString relative = path;
    const int api = relative.indexOf(QStringLiteral("/api/v1/"));
    if (api >= 0)
        relative = relative.mid(api + 8);
    const QStringList parts = relative.split(QLatin1Char('/'), QString::SkipEmptyParts);
    if (parts.isEmpty())
        return QString();
    const QString first = parts.first().section(QLatin1Char('?'), 0, 0);
    // exercises/<id>/last-performance/ reads logged sets.
    if (first == QLatin1String("exercises") && parts.size() >= 3 && parts.at(2) == QLatin1String("last-performance"))
        return QStringLiteral("workouts");
    static const QHash<QString, QString> contexts {
        { QStringLiteral("profile"), QStringLiteral("profile") },
        { QStringLiteral("exercises"), QStringLiteral("exercises") },
        { QStringLiteral("muscle-groups"), QStringLiteral("exercises") },
        { QStringLiteral("equipment"), QStringLiteral("exercises") },
        { QStringLiteral("programs"), QStringLiteral("programs") },
        { QStringLiteral("workouts"), QStringLiteral("programs") },
        { QStringLiteral("prescriptions"), QStringLiteral("programs") },
        { QStringLiteral("up-next"), QStringLiteral("programs") },
        { QStringLiteral("sessions"), QStringLiteral("workouts") },
        { QStringLiteral("performed-exercises"), QStringLiteral("workouts") },
        { QStringLiteral("sets"), QStringLiteral("workouts") },
        { QStringLiteral("measurement-types"), QStringLiteral("measurements") },
        { QStringLiteral("measurements"), QStringLiteral("measurements") },
        { QStringLiteral("activity-types"), QStringLiteral("activities") },
        { QStringLiteral("activities"), QStringLiteral("activities") },
        { QStringLiteral("records"), QStringLiteral("records") },
        { QStringLiteral("analytics"), QStringLiteral("analytics") },
        { QStringLiteral("foods"), QStringLiteral("nutrition") },
        { QStringLiteral("meal-slots"), QStringLiteral("nutrition") },
        { QStringLiteral("recipes"), QStringLiteral("nutrition") },
        { QStringLiteral("recipe-ingredients"), QStringLiteral("nutrition") },
        { QStringLiteral("diary-entries"), QStringLiteral("nutrition") },
        { QStringLiteral("nutrition-goals"), QStringLiteral("nutrition") },
        { QStringLiteral("nutrition-targets"), QStringLiteral("nutrition") },
        { QStringLiteral("nutrition"), QStringLiteral("nutrition") },
        { QStringLiteral("diet-plans"), QStringLiteral("nutrition") },
        { QStringLiteral("diet-plan-meals"), QStringLiteral("nutrition") },
        { QStringLiteral("diet-plan-items"), QStringLiteral("nutrition") },
        { QStringLiteral("stretches"), QStringLiteral("stretching") },
        { QStringLiteral("stretch-routines"), QStringLiteral("stretching") },
        { QStringLiteral("stretch-routine-items"), QStringLiteral("stretching") },
        { QStringLiteral("stretch-sessions"), QStringLiteral("stretching") },
    };
    return contexts.value(first);
}

QString ApiClient::permissionForMethod(const QString &method)
{
    const QString upper = method.toUpper();
    if (upper == QLatin1String("POST"))
        return QStringLiteral("Create");
    if (upper == QLatin1String("PUT") || upper == QLatin1String("PATCH"))
        return QStringLiteral("Update");
    if (upper == QLatin1String("DELETE"))
        return QStringLiteral("Delete");
    return QStringLiteral("Read");
}

QString ApiClient::errorMessage(int status, const QVariant &data, QNetworkReply *reply,
                                const QString &method)
{
    switch (status) {
    case 0:
        if (reply->error() == QNetworkReply::OperationCanceledError)
            return tr("The server did not answer in time.");
        qWarning("ApiClient: %s", qPrintable(reply->errorString()));
        return tr("Can't reach the server.");
    case 401:
        return tr("The API key was not accepted. It may have been revoked.");
    case 403: {
        // Name what to tick on the key in IronStack (Profile > API keys).
        const QString context = contextForPath(reply->url().path());
        if (!context.isEmpty())
            return tr("This API key does not have the permission it needs: %1 - %2. "
                      "Add it in IronStack under Profile > API keys.")
                    .arg(context, permissionForMethod(method));
        return tr("This API key does not have permission for that.");
    }
    case 404:
        return tr("Not found.");
    case 429:
        return tr("Too many requests. Wait a moment and try again.");
    default:
        break;
    }

    if (status == 400) {
        // DRF validation errors: {"field": ["message", ...], ...} or
        // {"detail": "..."} or ["message"].
        QStringList messages;
        const QVariantMap map = data.toMap();
        for (auto it = map.constBegin(); it != map.constEnd(); ++it) {
            const QStringList parts = it.value().toStringList();
            const QString text = parts.isEmpty() ? it.value().toString() : parts.join(QLatin1Char(' '));
            if (it.key() == QLatin1String("detail") || it.key() == QLatin1String("non_field_errors"))
                messages << text;
            else
                messages << it.key() + QStringLiteral(": ") + text;
        }
        if (messages.isEmpty())
            messages = data.toStringList();
        if (!messages.isEmpty())
            return messages.join(QLatin1Char('\n'));
    }

    const QString detail = data.toMap().value(QStringLiteral("detail")).toString();
    if (!detail.isEmpty())
        return detail;
    if (status >= 500)
        return tr("The server had an error (%1).").arg(status);
    return tr("Request failed (%1).").arg(status);
}
