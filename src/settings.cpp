#include "settings.h"

#include <QStandardPaths>

// Sailjail only lets the app write under ~/.config/<org>/<app>/, while
// QSettings' default file is ~/.config/<org>/<app>.conf - one level up,
// outside the sandbox - so the path is given explicitly.
static QString settingsPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation)
            + QStringLiteral("/harbour-ironstack.conf");
}

Settings::Settings(QObject *parent)
    : QObject(parent)
    , m_settings(settingsPath(), QSettings::IniFormat)
{
}

QString Settings::baseUrl() const
{
    return m_settings.value(QStringLiteral("server/baseUrl")).toString();
}

void Settings::setBaseUrl(const QString &url)
{
    const QString normalized = normalizeBaseUrl(url);
    if (normalized == baseUrl())
        return;
    const bool wasConfigured = configured();
    m_settings.setValue(QStringLiteral("server/baseUrl"), normalized);
    emit baseUrlChanged();
    if (wasConfigured != configured())
        emit configuredChanged();
}

QString Settings::apiKey() const
{
    return m_settings.value(QStringLiteral("server/apiKey")).toString();
}

void Settings::setApiKey(const QString &key)
{
    const QString trimmed = key.trimmed();
    if (trimmed == apiKey())
        return;
    const bool wasConfigured = configured();
    m_settings.setValue(QStringLiteral("server/apiKey"), trimmed);
    emit apiKeyChanged();
    if (wasConfigured != configured())
        emit configuredChanged();
}

bool Settings::configured() const
{
    return !baseUrl().isEmpty() && !apiKey().isEmpty();
}

QString Settings::unitSystem() const
{
    return m_settings.value(QStringLiteral("profile/unitSystem"), QStringLiteral("metric")).toString();
}

void Settings::setUnitSystem(const QString &system)
{
    if (system == unitSystem())
        return;
    m_settings.setValue(QStringLiteral("profile/unitSystem"), system);
    emit unitSystemChanged();
}

int Settings::restSeconds() const
{
    return m_settings.value(QStringLiteral("training/restSeconds"), 90).toInt();
}

void Settings::setRestSeconds(int seconds)
{
    if (seconds == restSeconds())
        return;
    m_settings.setValue(QStringLiteral("training/restSeconds"), seconds);
    emit restSecondsChanged();
}

void Settings::setRestEndsAt(double endsAt)
{
    if (endsAt == m_restEndsAt)
        return;
    m_restEndsAt = endsAt;
    emit restEndsAtChanged();
}

void Settings::setActiveSessionId(int id)
{
    if (id == m_activeSessionId)
        return;
    m_activeSessionId = id;
    emit activeSessionChanged();
}

void Settings::setActiveSessionName(const QString &name)
{
    if (name == m_activeSessionName)
        return;
    m_activeSessionName = name;
    emit activeSessionChanged();
}

void Settings::setActiveSessionStarted(const QString &started)
{
    if (started == m_activeSessionStarted)
        return;
    m_activeSessionStarted = started;
    emit activeSessionChanged();
}

void Settings::clearActiveSession()
{
    setRestEndsAt(0);
    m_activeSessionId = -1;
    m_activeSessionName.clear();
    m_activeSessionStarted.clear();
    emit activeSessionChanged();
}

void Settings::logout()
{
    clearActiveSession();
    setApiKey(QString());
}

QString Settings::normalizeBaseUrl(const QString &url)
{
    QString result = url.trimmed();
    while (result.endsWith(QLatin1Char('/')))
        result.chop(1);
    if (!result.isEmpty() && !result.contains(QStringLiteral("://")))
        result.prepend(QStringLiteral("https://"));
    return result;
}
