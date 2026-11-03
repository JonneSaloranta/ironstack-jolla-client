#ifndef SETTINGS_H
#define SETTINGS_H

#include <QJSValue>
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
    // Rest timer length after logging a set; 0 turns the timer off.
    Q_PROPERTY(int restSeconds READ restSeconds WRITE setRestSeconds NOTIFY restSecondsChanged)
    // The stretching timer's mute, kept per device like on the web.
    Q_PROPERTY(bool timerSound READ timerSound WRITE setTimerSound NOTIFY timerSoundChanged)
    // When the running rest period ends, in ms since the epoch; 0 = no rest
    // running. Runtime only, shared by the session page, the cover and the
    // end-of-rest notification.
    Q_PROPERTY(double restEndsAt READ restEndsAt WRITE setRestEndsAt NOTIFY restEndsAtChanged)

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
    int restSeconds() const;
    void setRestSeconds(int seconds);
    bool timerSound() const;
    void setTimerSound(bool on);
    double restEndsAt() const { return m_restEndsAt; }
    void setRestEndsAt(double endsAt);

    int activeSessionId() const { return m_activeSessionId; }
    void setActiveSessionId(int id);
    QString activeSessionName() const { return m_activeSessionName; }
    void setActiveSessionName(const QString &name);
    QString activeSessionStarted() const { return m_activeSessionStarted; }
    void setActiveSessionStarted(const QString &started);

    Q_INVOKABLE void clearActiveSession();

    // Last data loaded from the server, kept on the phone so a workout can
    // go on without a connection. Values are anything JSON-like.
    Q_INVOKABLE QVariant cached(const QString &key) const;
    // From QML: a JS object reaches a QVariant parameter wrapped as a
    // QJSValue, which QJsonDocument can't serialize - hence QJSValue here.
    Q_INVOKABLE void setCached(const QString &key, const QJSValue &value);
    void setCachedVariant(const QString &key, const QVariant &value);
    Q_INVOKABLE void logout();

    // "https://host/" or "https://host" -> "https://host"
    static QString normalizeBaseUrl(const QString &url);

signals:
    void baseUrlChanged();
    void apiKeyChanged();
    void configuredChanged();
    void unitSystemChanged();
    void restSecondsChanged();
    void restEndsAtChanged();
    void timerSoundChanged();
    void activeSessionChanged();

private:
    QSettings m_settings;
    int m_activeSessionId = -1;
    QString m_activeSessionName;
    QString m_activeSessionStarted;
    double m_restEndsAt = 0;
};

#endif
