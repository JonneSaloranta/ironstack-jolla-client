#include "apiclient.h"
#include "logger.h"
#include "settings.h"

#include <QBuffer>
#include <QDir>
#include <QStandardPaths>
#include <QUuid>
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QHttpMultiPart>
#include <QImage>
#include <QImageReader>
#include <QMimeDatabase>
#include <QLoggingCategory>
#include <QJsonDocument>
#include <QLocale>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStringList>
#include <QQmlEngine>
#include <QTimer>

namespace {
const int TimeoutMs = 20000;
// An image over mobile data takes longer.
const int UploadTimeoutMs = 120000;
}

Q_LOGGING_CATEGORY(lcApi, "api")

ApiClient::ApiClient(Settings *settings, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
    , m_network(new QNetworkAccessManager(this))
{
}

void ApiClient::request(const QString &method, const QString &path,
                        const QJSValue &body, const QJSValue &callback)
{
    if (m_settings->standalone()) {
        const QVariant variantBody = (body.isUndefined() || body.isNull()) ? QVariant() : body.toVariant();
        const QString request = method.toUpper() + QLatin1Char(' ') + logPath(QUrl(path), false);
        localRequest(method, path, variantBody, jsHandler(callback, request));
        return;
    }
    requestWith(m_settings->baseUrl(), m_settings->apiKey(), method, path, body, callback);
}

void ApiClient::requestTo(const QString &baseUrl, const QString &apiKey, const QString &method,
                          const QString &path, const QJSValue &body, const QJSValue &headers,
                          const QJSValue &callback)
{
    const QVariant variantBody = (body.isUndefined() || body.isNull()) ? QVariant() : body.toVariant();
    const QString request = method.toUpper() + QLatin1Char(' ') + logPath(QUrl(path), false);
    sendWith(baseUrl, apiKey, method, path, variantBody, jsHandler(callback, request),
             headers.toVariant().toMap());
}

void ApiClient::setLocalBackend(const QJSValue &handler)
{
    m_localBackend = handler;
}

void ApiClient::localRequest(const QString &method, const QString &path, const QVariant &body, Handler handler)
{
    // Answered on the next turn of the event loop, like a network reply:
    // pages count their requests before any callback runs.
    if (++m_localPending == 1 && m_pending.isEmpty())
        emit busyChanged();
    const qint64 started = QDateTime::currentMSecsSinceEpoch();
    QTimer::singleShot(0, this, [this, method, path, body, handler, started]() {
        int status = 503;
        QVariant data;
        QJSValue backend(m_localBackend);
        if (backend.isCallable() && m_engine) {
            const QJSValue result = backend.call(QJSValueList() << method.toUpper() << path
                                                 << m_engine->toScriptValue(body));
            if (result.isError()) {
                qCCritical(lcApi, "Local backend error on %s %s: %s (%s:%d)", qPrintable(method.toUpper()),
                           qPrintable(logPath(QUrl(path), false)), qPrintable(result.toString()),
                           qPrintable(QUrl(result.property(QStringLiteral("fileName")).toString()).fileName()),
                           result.property(QStringLiteral("lineNumber")).toInt());
                status = 500;
            } else {
                status = result.property(QStringLiteral("status")).toInt();
                const QJSValue value = result.property(QStringLiteral("data"));
                if (!value.isUndefined() && !value.isNull())
                    data = value.toVariant();
            }
        } else {
            qCWarning(lcApi, "Local backend not ready for %s %s", qPrintable(method.toUpper()),
                      qPrintable(logPath(QUrl(path), false)));
        }
        const bool ok = status >= 200 && status < 300;
        const QString error = ok ? QString()
                : status == 503 ? tr("The data on this phone isn't ready yet.")
                : status >= 500 ? tr("Something went wrong with the data on this phone. The app log has the details.")
                : messageFor(status, data, path, method, false);
        const qint64 ms = QDateTime::currentMSecsSinceEpoch() - started;
        if (ok)
            qCDebug(lcApi, "local %s %s %d (%lld ms)", qPrintable(method.toUpper()),
                    qPrintable(logPath(QUrl(path), Logger::keeps(Logger::Debug))), status, ms);
        else
            qCWarning(lcApi, "local %s %s failed: %d %s (%lld ms)", qPrintable(method.toUpper()),
                      qPrintable(logPath(QUrl(path), false)), status, qPrintable(error), ms);
        if (--m_localPending == 0 && m_pending.isEmpty())
            emit busyChanged();
        if (handler)
            handler(ok, status, data, error);
    });
}

QString ApiClient::dataUrl() const
{
    return m_dataDir.isEmpty() ? QString() : QUrl::fromLocalFile(m_dataDir).toString();
}

QString ApiClient::readData(const QString &name) const
{
    // Only a plain file name in the app's own data directory.
    if (m_dataDir.isEmpty() || name.isEmpty() || name.contains(QLatin1Char('/')) || name.startsWith(QLatin1Char('.')))
        return QString();
    QFile file(m_dataDir + QLatin1Char('/') + name);
    if (!file.open(QIODevice::ReadOnly))
        return QString();
    return QString::fromUtf8(file.readAll());
}

void ApiClient::requestWith(const QString &baseUrl, const QString &apiKey,
                            const QString &method, const QString &path,
                            const QJSValue &body, const QJSValue &callback)
{
    // Taken as a QJSValue: a JS object passed to a QVariant parameter
    // arrives as a QVariant wrapping a QJSValue, which QJsonDocument
    // silently turns into an empty body.
    const QVariant variantBody = (body.isUndefined() || body.isNull()) ? QVariant() : body.toVariant();
    const QString request = method.toUpper() + QLatin1Char(' ') + logPath(QUrl(path), false);
    sendWith(baseUrl, apiKey, method, path, variantBody, jsHandler(callback, request));
}

void ApiClient::send(const QString &method, const QString &path, const QVariant &body, Handler handler,
                     const QVariantMap &headers)
{
    if (m_settings->standalone()) {
        localRequest(method, path, body, handler);
        return;
    }
    sendWith(m_settings->baseUrl(), m_settings->apiKey(), method, path, body, handler, headers);
}

ApiClient::Handler ApiClient::jsHandler(const QJSValue &callback, const QString &request)
{
    return [this, callback, request](bool ok, int status, const QVariant &data, const QString &error) {
        QJSValue cb(callback);
        if (!cb.isCallable())
            return;
        QJSValue jsData = m_engine ? m_engine->toScriptValue(data) : QJSValue();
        QJSValue result = cb.call(QJSValueList() << ok << status << jsData << error);
        // A JavaScript error in the page's callback would otherwise vanish.
        if (result.isError())
            qCCritical(lcApi, "JavaScript error handling %s: %s (%s:%d)", qPrintable(request),
                       qPrintable(result.toString()),
                       qPrintable(QUrl(result.property(QStringLiteral("fileName")).toString()).fileName()),
                       result.property(QStringLiteral("lineNumber")).toInt());
    };
}

// The phone's language, the one the app shows itself in: the server's
// translated names (`display_name`, `exercise_display_name`, ...) then
// match the rest of the page. English after it, the app's own fallback,
// for a language the server doesn't have - else it would answer in the
// IronStack profile's language.
QByteArray ApiClient::acceptLanguage(const QLocale &locale)
{
    // The UI language, which picks the app's translation too - not
    // name(), which follows the region format and can be another one.
    const QString ui = locale.uiLanguages().value(0, locale.name());
    const QString language = ui.section(QLatin1Char('-'), 0, 0).section(QLatin1Char('_'), 0, 0);
    if (language.isEmpty() || language == QLatin1String("C") || language == QLatin1String("en"))
        return QByteArrayLiteral("en");
    return language.toLatin1() + ", en;q=0.5";
}

QNetworkRequest ApiClient::buildRequest(const QString &base, const QString &apiKey, const QString &path,
                                        const QVariantMap &headers) const
{
    const QUrl root(base + QStringLiteral("/api/v1/"));

    QUrl url;
    if (path.startsWith(QStringLiteral("http://")) || path.startsWith(QStringLiteral("https://"))) {
        // A page's "next" link is absolute, built by the server from the
        // request it saw - behind a reverse proxy that can be http:// or
        // another host or port than the address the app uses. Only its
        // API path and query are kept and asked from the configured
        // server, so the key never goes anywhere else.
        const QUrl link(path);
        const QString linkPath = link.path();
        const int api = linkPath.indexOf(QStringLiteral("/api/v1/"));
        if (!link.isValid() || api < 0)
            return QNetworkRequest();
        url = root.resolved(QUrl(linkPath.mid(api + 8)));
        url.setQuery(link.query());
    } else {
        url = root.resolved(QUrl(path));
    }

    QNetworkRequest req(url);
    req.setRawHeader("Authorization", "Bearer " + apiKey.toUtf8());
    req.setRawHeader("Accept", "application/json");
    req.setRawHeader("Accept-Language", acceptLanguage());
    req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, false);
    for (auto it = headers.constBegin(); it != headers.constEnd(); ++it)
        req.setRawHeader(it.key().toUtf8(), it.value().toString().toUtf8());
    return req;
}

void ApiClient::sendWith(const QString &baseUrl, const QString &apiKey, const QString &method,
                         const QString &path, const QVariant &body, Handler handler,
                         const QVariantMap &headers)
{
    const QString base = Settings::normalizeBaseUrl(baseUrl);
    QNetworkRequest req = buildRequest(base, apiKey, path, headers);
    if (req.url().isEmpty()) {
        if (handler)
            handler(false, 0, QVariant(), tr("Refused to follow a link to another server."));
        return;
    }

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
    track(reply, base, apiKey, method, handler, TimeoutMs);
}

void ApiClient::upload(const QString &path, const QString &field, const QString &filePath,
                       const QJSValue &fields, const QJSValue &callback)
{
    const QString base = Settings::normalizeBaseUrl(m_settings->baseUrl());
    const QString apiKey = m_settings->apiKey();
    Handler handler = jsHandler(callback, QStringLiteral("POST ") + logPath(QUrl(path), false));
    QNetworkRequest req = buildRequest(base, apiKey, path, QVariantMap());

    QString fileName;
    QString contentType;
    const QByteArray image = uploadImage(filePath, &fileName, &contentType);
    if (image.isEmpty()) {
        qCWarning(lcApi, "Can't read the image to upload (%s)", qPrintable(QFileInfo(filePath).suffix()));
        if (handler)
            handler(false, 0, QVariant(), tr("Can't read that image."));
        return;
    }

    if (m_settings->standalone()) {
        // Kept in the app's data directory, the local backend gets its URL.
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                + QStringLiteral("/images");
        QDir().mkpath(dir);
        const QString target = dir + QLatin1Char('/') + QUuid::createUuid().toString().mid(1, 36)
                + QLatin1Char('.') + QFileInfo(fileName).suffix();
        QFile out(target);
        if (!out.open(QIODevice::WriteOnly) || out.write(image) != image.size()) {
            qCWarning(lcApi, "Can't save the image on the phone");
            if (handler)
                handler(false, 0, QVariant(), tr("Can't save that image on this phone."));
            return;
        }
        out.close();
        QVariantMap localBody = fields.toVariant().toMap();
        localBody.insert(field, QUrl::fromLocalFile(target).toString());
        localRequest(QStringLiteral("POST"), path, localBody, handler);
        return;
    }

    QHttpMultiPart *multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);
    const QVariantMap extra = fields.toVariant().toMap();
    for (auto it = extra.constBegin(); it != extra.constEnd(); ++it) {
        QHttpPart part;
        part.setHeader(QNetworkRequest::ContentDispositionHeader,
                       QStringLiteral("form-data; name=\"%1\"").arg(it.key()));
        part.setBody(it.value().toString().toUtf8());
        multiPart->append(part);
    }
    QHttpPart filePart;
    filePart.setHeader(QNetworkRequest::ContentTypeHeader, contentType);
    // The name only says what kind of file it is; the phone's own file
    // name isn't sent.
    filePart.setHeader(QNetworkRequest::ContentDispositionHeader,
                       QStringLiteral("form-data; name=\"%1\"; filename=\"%2\"").arg(field, fileName));
    filePart.setBody(image);
    multiPart->append(filePart);

    QNetworkReply *reply = m_network->post(req, multiPart);
    multiPart->setParent(reply);
    track(reply, base, apiKey, QStringLiteral("POST"), handler, UploadTimeoutMs);
}

QByteArray ApiClient::uploadImage(const QString &filePath, QString *fileName, QString *contentType)
{
    QString local = filePath;
    if (local.startsWith(QStringLiteral("file://")))
        local = QUrl(local).toLocalFile();

    QImageReader reader(local);
    reader.setAutoTransform(true);
    const QSize size = reader.size();
    if (!reader.canRead() || !size.isValid())
        return QByteArray();

    const QString suffix = QFileInfo(local).suffix().toLower();
    const bool small = qMax(size.width(), size.height()) <= MaxImageDimension;
    // Small enough, and with nothing for the EXIF orientation to turn: as it is.
    if (small && reader.transformation() == QImageIOHandler::TransformationNone) {
        QFile file(local);
        if (!file.open(QIODevice::ReadOnly))
            return QByteArray();
        *contentType = QMimeDatabase().mimeTypeForFile(local).name();
        *fileName = QStringLiteral("image.") + (suffix.isEmpty() ? QStringLiteral("jpg") : suffix);
        return file.readAll();
    }

    QImage image = reader.read();
    if (image.isNull())
        return QByteArray();
    if (!small)
        image = image.scaled(MaxImageDimension, MaxImageDimension, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    QByteArray data;
    QBuffer buffer(&data);
    buffer.open(QIODevice::WriteOnly);
    // A PNG may be a drawing with transparency; a photo goes as JPEG.
    const bool png = suffix == QLatin1String("png");
    if (!image.save(&buffer, png ? "PNG" : "JPEG", png ? -1 : 90))
        return QByteArray();
    *contentType = png ? QStringLiteral("image/png") : QStringLiteral("image/jpeg");
    *fileName = png ? QStringLiteral("image.png") : QStringLiteral("image.jpg");
    return data;
}

void ApiClient::track(QNetworkReply *reply, const QString &base, const QString &apiKey, const QString &method,
                      Handler handler, int timeoutMs)
{
    m_pending.insert(reply, Pending { handler, base == m_settings->baseUrl() && apiKey == m_settings->apiKey(),
                                      method.toUpper(), QDateTime::currentMSecsSinceEpoch() });
    if (m_pending.size() == 1)
        emit busyChanged();

    QTimer *timer = new QTimer(reply);
    timer->setSingleShot(true);
    connect(timer, &QTimer::timeout, reply, &QNetworkReply::abort);
    timer->start(timeoutMs);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() { finish(reply); });
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
    const QString error = ok ? QString()
            : messageFor(status, data, reply->url().path(), pending.method,
                         reply->error() == QNetworkReply::OperationCanceledError);

    // The request in the app's log (Logger): never the key or a body.
    const qint64 ms = QDateTime::currentMSecsSinceEpoch() - pending.startedMs;
    if (ok && Logger::keeps(Logger::Debug)) {
        qCDebug(lcApi, "%s %s %d (%lld ms, %d bytes)", qPrintable(pending.method),
                qPrintable(logPath(reply->url(), true)), status, ms, raw.size());
    } else if (ok) {
        qCInfo(lcApi, "%s %s %d (%lld ms)", qPrintable(pending.method),
               qPrintable(logPath(reply->url(), false)), status, ms);
    } else {
        // Without an HTTP status, Qt's own reason (DNS, TLS, refused...).
        const QString detail = status == 0 ? QStringLiteral(" - ") + reply->errorString() : QString();
        qCWarning(lcApi, "%s %s failed: %d %s (%lld ms)%s", qPrintable(pending.method),
                  qPrintable(logPath(reply->url(), false)), status, qPrintable(error), ms,
                  qPrintable(detail));
    }

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
        { QStringLiteral("tutorials"), QStringLiteral("profile") },
        { QStringLiteral("social"), QStringLiteral("social") },
        { QStringLiteral("coaching"), QStringLiteral("coaching") },
        { QStringLiteral("assistant"), QStringLiteral("assistant") },
    };
    return contexts.value(first);
}

QString ApiClient::logPath(const QUrl &url, bool withQuery)
{
    QString path = url.path();
    const int api = path.indexOf(QStringLiteral("/api/v1/"));
    if (api >= 0)
        path = path.mid(api + 8);
    if (withQuery && url.hasQuery())
        path += QLatin1Char('?') + url.query();
    return path;
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

QString ApiClient::messageFor(int status, const QVariant &data, const QString &path,
                              const QString &method, bool timedOut)
{
    switch (status) {
    case 0:
        if (timedOut)
            return tr("The server did not answer in time.");
        return tr("Can't reach the server.");
    case 401:
        return tr("The API key was not accepted. It may have been revoked.");
    case 403: {
        // Name what to tick on the key in IronStack (Profile > API keys).
        const QString context = contextForPath(path);
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
