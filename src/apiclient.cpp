#include "apiclient.h"
#include "settings.h"

#include <QBuffer>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
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
                        const QVariant &body, const QJSValue &callback)
{
    requestWith(m_settings->baseUrl(), m_settings->apiKey(), method, path, body, callback);
}

void ApiClient::requestWith(const QString &baseUrl, const QString &apiKey,
                            const QString &method, const QString &path,
                            const QVariant &body, const QJSValue &callback)
{
    const QString base = Settings::normalizeBaseUrl(baseUrl);
    const QUrl root(base + QStringLiteral("/api/v1/"));

    QUrl url;
    if (path.startsWith(QStringLiteral("http://")) || path.startsWith(QStringLiteral("https://"))) {
        url = QUrl(path);
        // Never send the key anywhere but the configured server.
        if (url.scheme() != root.scheme() || url.host() != root.host()
                || url.port(-1) != root.port(-1)) {
            QJSValue cb(callback);
            if (cb.isCallable())
                cb.call(QJSValueList() << false << 0 << QJSValue() << tr("Refused to follow a link to another server."));
            return;
        }
    } else {
        url = root.resolved(QUrl(path));
    }

    QNetworkRequest req(url);
    req.setRawHeader("Authorization", "Bearer " + apiKey.toUtf8());
    req.setRawHeader("Accept", "application/json");
    req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, false);

    QByteArray payload;
    if (body.isValid() && !body.isNull()) {
        payload = QJsonDocument::fromVariant(body).toJson(QJsonDocument::Compact);
        req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    }

    // Qt 5.6 has no QByteArray overload of sendCustomRequest.
    QBuffer *buffer = new QBuffer;
    buffer->setData(payload);
    buffer->open(QIODevice::ReadOnly);
    QNetworkReply *reply = m_network->sendCustomRequest(req, method.toUpper().toLatin1(), buffer);
    buffer->setParent(reply);
    m_callbacks.insert(reply, callback);
    m_usesSavedKey.insert(reply, base == m_settings->baseUrl() && apiKey == m_settings->apiKey());
    if (m_callbacks.size() == 1)
        emit busyChanged();

    QTimer *timer = new QTimer(reply);
    timer->setSingleShot(true);
    connect(timer, &QTimer::timeout, reply, &QNetworkReply::abort);
    timer->start(TimeoutMs);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() { finish(reply); });
}

void ApiClient::finish(QNetworkReply *reply)
{
    reply->deleteLater();
    QJSValue callback = m_callbacks.take(reply);
    const bool usesSavedKey = m_usesSavedKey.take(reply);
    if (m_callbacks.isEmpty())
        emit busyChanged();

    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QByteArray raw = reply->readAll();
    QVariant data;
    if (!raw.isEmpty())
        data = QJsonDocument::fromJson(raw).toVariant();

    const bool ok = status >= 200 && status < 300;
    const QString error = ok ? QString() : errorMessage(status, data, reply);

    if (status == 401 && usesSavedKey)
        emit unauthorized();

    if (!callback.isCallable())
        return;
    QJSValue jsData = m_engine ? m_engine->toScriptValue(data) : QJSValue();
    QJSValue result = callback.call(QJSValueList() << ok << status << jsData << error);
    if (result.isError())
        qWarning("ApiClient callback error: %s", qPrintable(result.toString()));
}

QString ApiClient::errorMessage(int status, const QVariant &data, QNetworkReply *reply)
{
    switch (status) {
    case 0:
        if (reply->error() == QNetworkReply::OperationCanceledError)
            return tr("The server did not answer in time.");
        return tr("Could not reach the server: %1").arg(reply->errorString());
    case 401:
        return tr("The API key was not accepted. It may have been revoked.");
    case 403:
        return tr("This API key does not have permission for that.");
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
