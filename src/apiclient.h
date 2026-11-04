#ifndef APICLIENT_H
#define APICLIENT_H

#include <QHash>
#include <QJSValue>
#include <functional>
#include <QLocale>
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
    // body; anything else is serialized as JSON. `headers` are added to
    // the request as they are (e.g. Idempotency-Key).
    void send(const QString &method, const QString &path, const QVariant &body, Handler handler,
              const QVariantMap &headers = QVariantMap());

signals:
    void busyChanged();
    // The saved key was rejected (revoked or wrong) - the app goes back
    // to the login page.
    void unauthorized();

private:
    void sendWith(const QString &baseUrl, const QString &apiKey, const QString &method,
                  const QString &path, const QVariant &body, Handler handler,
                  const QVariantMap &headers = QVariantMap());
    void finish(QNetworkReply *reply);
    Handler jsHandler(const QJSValue &callback, const QString &request);
    static QString errorMessage(int status, const QVariant &data, QNetworkReply *reply,
                                const QString &method);

public:
    // The API key context (IronStack docs/API.md "Contexts and
    // permissions") a path under /api/v1/ belongs to, e.g. "nutrition" for
    // "diary-entries/3/"; "" if unknown.
    static QString contextForPath(const QString &path);
    // "Create", "Read", "Update" or "Delete" - the permission a method needs.
    static QString permissionForMethod(const QString &method);
    // A request's URL as the log shows it: the path under /api/v1/, the
    // query only when `withQuery` (it can hold search words and dates).
    static QString logPath(const QUrl &url, bool withQuery);
    // The Accept-Language header for `locale`: its language, then English.
    static QByteArray acceptLanguage(const QLocale &locale = QLocale());

private:

    struct Pending {
        Handler handler;
        bool usesSavedKey;
        QString method;
        qint64 startedMs;
    };

    Settings *m_settings;
    QNetworkAccessManager *m_network;
    QQmlEngine *m_engine = nullptr;
    QHash<QNetworkReply *, Pending> m_pending;
};

#endif
