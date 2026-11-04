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
class QNetworkRequest;
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
    bool busy() const { return !m_pending.isEmpty() || m_localPending > 0; }
    // Where readData() reads from: the app's qml/data directory.
    void setDataDir(const QString &dir) { m_dataDir = dir; }

    // path is relative to /api/v1/ ("sessions/") or an absolute URL on the
    // same server (a paginated response's "next").
    Q_INVOKABLE void request(const QString &method, const QString &path,
                             const QJSValue &body, const QJSValue &callback);

    // Same as request(), but against credentials that are not saved yet -
    // the login page tests a key before storing it.
    Q_INVOKABLE void requestWith(const QString &baseUrl, const QString &apiKey,
                                 const QString &method, const QString &path,
                                 const QJSValue &body, const QJSValue &callback);

    // Like requestWith(), with extra headers (an Idempotency-Key) - the
    // transfer to a server, which always goes over the network.
    Q_INVOKABLE void requestTo(const QString &baseUrl, const QString &apiKey, const QString &method,
                               const QString &path, const QJSValue &body, const QJSValue &headers,
                               const QJSValue &callback);

    // Standalone mode (Settings::standalone): request(), send() and
    // upload() go to `handler(method, path, body)` instead of the
    // network; it returns {status, data} the way the server would answer.
    // requestWith() and requestTo() always use the network.
    Q_INVOKABLE void setLocalBackend(const QJSValue &handler);
    // A bundled data file (seed.json) by plain name; "" if there's none.
    Q_INVOKABLE QString readData(const QString &name) const;
    // The data directory as a file:// URL, for its images.
    Q_INVOKABLE QString dataUrl() const;

    // POSTs `filePath` (an image) as multipart field `field`, with
    // `fields` (a JS object of strings) next to it - IronStack's
    // exercises/<id>/images/. A photo larger than MaxImageDimension is
    // scaled down and sent as JPEG first, as the server would anyway.
    Q_INVOKABLE void upload(const QString &path, const QString &field, const QString &filePath,
                            const QJSValue &fields, const QJSValue &callback);

    static const int MaxImageDimension = 1600;
    // The image as uploaded: the file as it is when it's small enough,
    // else scaled to MaxImageDimension (turned upright by its EXIF
    // orientation) as JPEG. Sets `fileName` and `contentType`; empty on
    // an unreadable file.
    static QByteArray uploadImage(const QString &filePath, QString *fileName, QString *contentType);

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
    // The request for `path` with the key and headers, or an invalid
    // URL when `path` is a link to elsewhere.
    QNetworkRequest buildRequest(const QString &base, const QString &apiKey, const QString &path,
                                 const QVariantMap &headers) const;
    void track(QNetworkReply *reply, const QString &base, const QString &apiKey, const QString &method,
               Handler handler, int timeoutMs);
    void finish(QNetworkReply *reply);
    Handler jsHandler(const QJSValue &callback, const QString &request);
    void localRequest(const QString &method, const QString &path, const QVariant &body, Handler handler);

public:
    // The message shown for a failed request: `path` as requested,
    // `timedOut` for a status 0 that ran out of time.
    static QString messageFor(int status, const QVariant &data, const QString &path,
                              const QString &method, bool timedOut);

private:

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
    QJSValue m_localBackend;
    int m_localPending = 0;
    QString m_dataDir;
};

#endif
