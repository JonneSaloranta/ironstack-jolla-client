#ifndef SETTINGS_H
#define SETTINGS_H

#include <QObject>
#include <QSettings>

// Persisted connection settings plus a little runtime state the cover
// page needs (the cover cannot see page-level ids, only context
// properties).
class Settings : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)
    Q_PROPERTY(QString apiKey READ apiKey WRITE setApiKey NOTIFY apiKeyChanged)
    Q_PROPERTY(bool configured READ configured NOTIFY configuredChanged)
    Q_PROPERTY(QString unitSystem READ unitSystem WRITE setUnitSystem NOTIFY unitSystemChanged)

    Q_PROPERTY(int activeSessionId READ activeSessionId WRITE setActiveSessionId NOTIFY activeSessionChanged)
    Q_PROPERTY(QString activeSessionName READ activeSessionName WRITE setActiveSessionName NOTIFY activeSessionChanged)
    Q_PROPERTY(QString activeSessionStarted READ activeSessionStarted WRITE setActiveSessionStarted NOTIFY activeSessionChanged)

public:
    explicit Settings(QObject *parent = nullptr);

    QString baseUrl() const;
    void setBaseUrl(const QString &url);
    QString apiKey() const;
    void setApiKey(const QString &key);
    bool configured() const;
    QString unitSystem() const;
    void setUnitSystem(const QString &system);

    int activeSessionId() const { return m_activeSessionId; }
    void setActiveSessionId(int id);
    QString activeSessionName() const { return m_activeSessionName; }
    void setActiveSessionName(const QString &name);
    QString activeSessionStarted() const { return m_activeSessionStarted; }
    void setActiveSessionStarted(const QString &started);

    Q_INVOKABLE void clearActiveSession();
    Q_INVOKABLE void logout();

    // "https://host/" or "https://host" -> "https://host"
    static QString normalizeBaseUrl(const QString &url);

signals:
    void baseUrlChanged();
    void apiKeyChanged();
    void configuredChanged();
    void unitSystemChanged();
    void activeSessionChanged();

private:
    QSettings m_settings;
    int m_activeSessionId = -1;
    QString m_activeSessionName;
    QString m_activeSessionStarted;
};

#endif
