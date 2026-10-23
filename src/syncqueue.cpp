#include "syncqueue.h"
#include "apiclient.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QSaveFile>

SyncQueue::SyncQueue(ApiClient *api, const QString &storagePath, QObject *parent)
    : QObject(parent)
    , m_api(api)
    , m_storagePath(storagePath)
{
    m_retryTimer.setInterval(15000);
    m_retryTimer.setSingleShot(true);
    connect(&m_retryTimer, &QTimer::timeout, this, &SyncQueue::flush);
    load();
    if (!m_items.isEmpty())
        QTimer::singleShot(0, this, &SyncQueue::flush);
}

int SyncQueue::enqueue(const QString &method, const QString &path, const QJSValue &body)
{
    return enqueueVariant(method, path, (body.isUndefined() || body.isNull()) ? QVariant() : body.toVariant());
}

int SyncQueue::enqueueVariant(const QString &method, const QString &path, const QVariant &body)
{
    QVariantMap item;
    const int id = m_nextId++;
    item.insert(QStringLiteral("id"), id);
    item.insert(QStringLiteral("method"), method.toUpper());
    item.insert(QStringLiteral("path"), path);
    if (body.isValid())
        item.insert(QStringLiteral("body"), body);
    item.insert(QStringLiteral("queuedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    m_items.append(item);
    save();
    emit itemsChanged();
    flush();
    return id;
}

void SyncQueue::flush()
{
    if (m_syncing || m_items.isEmpty())
        return;
    m_retryTimer.stop();
    sendNext();
}

void SyncQueue::clear()
{
    m_items.clear();
    m_retryTimer.stop();
    save();
    emit itemsChanged();
    setLastError(QString());
}

void SyncQueue::sendNext()
{
    if (m_items.isEmpty()) {
        setSyncing(false);
        setLastError(QString());
        return;
    }
    setSyncing(true);
    const QVariantMap item = m_items.first().toMap();
    const int id = item.value(QStringLiteral("id")).toInt();
    const QString method = item.value(QStringLiteral("method")).toString();
    const QString path = item.value(QStringLiteral("path")).toString();

    m_api->send(method, path, item.value(QStringLiteral("body")),
                [this, id, method, path](bool ok, int status, const QVariant &data, const QString &error) {
        // The queue may have been cleared (logout) while this was in flight.
        if (m_items.isEmpty() || m_items.first().toMap().value(QStringLiteral("id")).toInt() != id) {
            setSyncing(false);
            return;
        }
        const bool retryLater = status == 0 || status == 401 || status == 429 || status >= 500;
        if (!ok && retryLater) {
            setSyncing(false);
            setLastError(error);
            m_retryTimer.start();
            return;
        }
        m_items.removeFirst();
        save();
        emit itemsChanged();
        if (ok)
            emit itemSynced(id, method, path, data);
        else
            emit itemFailed(id, method, path, status, error);
        sendNext();
    });
}

void SyncQueue::load()
{
    QFile file(m_storagePath);
    if (!file.open(QIODevice::ReadOnly))
        return;
    const QVariantMap stored = QJsonDocument::fromJson(file.readAll()).toVariant().toMap();
    m_items = stored.value(QStringLiteral("items")).toList();
    m_nextId = qMax(1, stored.value(QStringLiteral("nextId")).toInt());
}

void SyncQueue::save() const
{
    QDir().mkpath(QFileInfo(m_storagePath).absolutePath());
    QSaveFile file(m_storagePath);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning("SyncQueue: cannot write %s", qPrintable(m_storagePath));
        return;
    }
    QVariantMap stored;
    stored.insert(QStringLiteral("items"), m_items);
    stored.insert(QStringLiteral("nextId"), m_nextId);
    file.write(QJsonDocument::fromVariant(stored).toJson(QJsonDocument::Compact));
    file.commit();
}

void SyncQueue::setSyncing(bool syncing)
{
    if (syncing == m_syncing)
        return;
    m_syncing = syncing;
    emit syncingChanged();
}

void SyncQueue::setLastError(const QString &error)
{
    if (error == m_lastError)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}
