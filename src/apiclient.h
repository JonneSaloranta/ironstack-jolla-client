#ifndef APICLIENT_H
#define APICLIENT_H

#include <QHash>
#include <QJSValue>
#include <functional>
#include <QObject>
#include <QUrl>
#include <QVariant>

class QNetworkAccessManager;
class QNetworkReply;
class QQmlEngine;
class Settings;

// Thin wrapper around IronStack's REST API (/api/v1/, docs/API.md in the
// server repo). Every call takes a JS callback:
//     callback(ok, status, data, error)
// where data is the parsed JSON body and error a human-readable message.
class ApiClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    ApiClient(Settings *settings, QObject *parent = nullptr);

    void setEngine(QQmlEngine *engine) { m_engine = engine; }
    bool busy() const { return !m_pending.isEmpty(); }

    // path is relative to /api/v1/ ("sessions/") or an absolute URL on the
    // same server (a paginated response's "next").
    Q_INVOKABLE void request(const QString &method, const QString &path,
                             const QJSValue &body, const QJSValue &callback);

    // Same as request(), but against credentials that are not saved yet -
    // the login page tests a key before storing it.
    Q_INVOKABLE void requestWith(const QString &baseUrl, const QString &apiKey,
                                 const QString &method, const QString &path,
                                 const QJSValue &body, const QJSValue &callback);

    using Handler = std::function<void(bool ok, int status, const QVariant &data, const QString &error)>;

    // C++ entry point (the sync queue uses it). An invalid `body` sends no
    // body; anything else is serialized as JSON.
    void send(const QString &method, const QString &path, const QVariant &body, Handler handler);

signals:
    void busyChanged();
    // The saved key was rejected (revoked or wrong) - the app goes back
    // to the login page.
    void unauthorized();

private:
    void sendWith(const QString &baseUrl, const QString &apiKey, const QString &method,
                  const QString &path, const QVariant &body, Handler handler);
    void finish(QNetworkReply *reply);
    Handler jsHandler(const QJSValue &callback);
    static QString errorMessage(int status, const QVariant &data, QNetworkReply *reply);

    struct Pending {
        Handler handler;
        bool usesSavedKey;
    };

    Settings *m_settings;
    QNetworkAccessManager *m_network;
    QQmlEngine *m_engine = nullptr;
    QHash<QNetworkReply *, Pending> m_pending;
};

#endif
