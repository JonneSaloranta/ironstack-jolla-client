#ifndef SYNCQUEUE_H
#define SYNCQUEUE_H

#include <QJSValue>
#include <QObject>
#include <QTimer>
#include <QVariantList>

class ApiClient;

// Writes that must not be lost to a bad gym connection - logging a set,
// finishing a workout - go through this queue instead of straight to
// ApiClient. Items are kept on disk, sent strictly in order, and retried
// until the server answers:
//
//   2xx                      -> done, itemSynced()
//   no connection, 429, 5xx  -> kept, retried later (order preserved)
//   401                      -> kept; ApiClient sends the user to log in
//   other 4xx                -> dropped, itemFailed() - retrying a request
//                               the server rejected would never succeed
//
// Every POST gets an Idempotency-Key (a UUID kept on disk with the item and
// sent unchanged with every retry - IronStack docs/API.md "Retrying
// writes"), so a retry after a lost response doesn't log a set twice: the
// server answers it with the stored response instead.
class SyncQueue : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)
    Q_PROPERTY(int count READ count NOTIFY itemsChanged)
    Q_PROPERTY(bool syncing READ syncing NOTIFY syncingChanged)
    // Last reason the queue couldn't make progress, e.g. "no connection";
    // empty once it syncs again.
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    SyncQueue(ApiClient *api, const QString &storagePath, QObject *parent = nullptr);

    QVariantList items() const { return m_items; }
    int count() const { return m_items.size(); }
    bool syncing() const { return m_syncing; }
    QString lastError() const { return m_lastError; }

    // Returns the item id. `body` is a JS object (or null).
    Q_INVOKABLE int enqueue(const QString &method, const QString &path, const QJSValue &body);
    int enqueueVariant(const QString &method, const QString &path, const QVariant &body);
    Q_INVOKABLE void flush();
    Q_INVOKABLE void clear();

    void setRetryInterval(int ms) { m_retryTimer.setInterval(ms); }

signals:
    void itemsChanged();
    void syncingChanged();
    void lastErrorChanged();
    void itemSynced(int id, const QString &method, const QString &path, const QVariant &data);
    void itemFailed(int id, const QString &method, const QString &path, int status, const QString &error);

private:
    void sendNext();
    void load();
    void save() const;
    void setSyncing(bool syncing);
    void setLastError(const QString &error);

    ApiClient *m_api;
    QString m_storagePath;
    QVariantList m_items;
    int m_nextId = 1;
    bool m_syncing = false;
    QString m_lastError;
    QTimer m_retryTimer;
};

#endif
