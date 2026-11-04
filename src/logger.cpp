#include "logger.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QCoreApplication>
#include <QLocale>
#include <QMutexLocker>
#include <QRegularExpression>
#include <QSysInfo>
#include <QTextStream>

#include <cstdio>

namespace {

Logger *s_logger = nullptr;
QtMessageHandler s_previous = nullptr;

void messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    if (s_logger)
        s_logger->handle(type, context, message);
    if (s_previous)
        s_previous(type, context, message);
    else
        fprintf(stderr, "%s\n", qPrintable(qFormatLogMessage(type, context, message)));
}

const char *levelLetter(Logger::Level level)
{
    switch (level) {
    case Logger::Debug: return "D";
    case Logger::Info: return "I";
    case Logger::Warning: return "W";
    case Logger::Error: return "E";
    }
    return "?";
}

QString readFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return QString();
    return QString::fromUtf8(file.readAll());
}

} // namespace

Logger::Logger(const QString &path, QObject *parent)
    : QObject(parent)
    , m_path(path)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
}

Logger::~Logger()
{
    if (s_logger == this)
        install(nullptr);
}

void Logger::install(Logger *logger)
{
    if (logger && !s_logger)
        s_previous = qInstallMessageHandler(messageHandler);
    else if (!logger && s_logger)
        qInstallMessageHandler(s_previous);
    s_logger = logger;
}

bool Logger::keeps(Level level)
{
    return !s_logger || level >= s_logger->level();
}

int Logger::level() const
{
    QMutexLocker lock(&m_mutex);
    return m_level;
}

void Logger::setLevel(int level)
{
    level = qBound(int(Debug), level, int(Error));
    {
        QMutexLocker lock(&m_mutex);
        if (level == m_level)
            return;
        m_level = level;
    }
    emit levelChanged();
}

Logger::Level Logger::levelOf(QtMsgType type)
{
    switch (type) {
    case QtDebugMsg: return Debug;
    case QtInfoMsg: return Info;
    case QtWarningMsg: return Warning;
    case QtCriticalMsg:
    case QtFatalMsg: return Error;
    }
    return Warning;
}

// IronStack's keys are "isk_" and URL-safe characters; keep only that, in
// case one ever ends up in a message (a URL, a JSON dump), and whatever
// follows "Bearer".
QString Logger::mask(const QString &message)
{
    static const QRegularExpression bearer(QStringLiteral("(Bearer\\s+)\\S+"));
    static const QRegularExpression key(QStringLiteral("isk_[A-Za-z0-9_\\-]+"));
    QString masked = message;
    masked.replace(bearer, QStringLiteral("\\1***"));
    return masked.replace(key, QStringLiteral("isk_***"));
}

static QString timestamp()
{
    return QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss.zzz"));
}

void Logger::note(const QString &message)
{
    write((timestamp() + QStringLiteral(" - ") + mask(message)).toUtf8() + '\n');
}

void Logger::handle(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    const Level level = levelOf(type);
    {
        QMutexLocker lock(&m_mutex);
        if (level < m_level)
            return;
    }
    QString line = timestamp() + QLatin1Char(' ') + QLatin1String(levelLetter(level)) + QLatin1Char(' ');
    if (context.category && qstrcmp(context.category, "default") != 0)
        line += QLatin1String(context.category) + QStringLiteral(": ");
    line += mask(message);
    // QML warnings carry their own file:line; a C++ message's is only
    // there in debug builds.
    if (context.file && context.line > 0 && !message.contains(QLatin1String(context.file)))
        line += QStringLiteral(" (%1:%2)").arg(QFileInfo(QString::fromUtf8(context.file)).fileName())
                .arg(context.line);
    write(line.toUtf8() + '\n');
}

void Logger::write(const QByteArray &line)
{
    QMutexLocker lock(&m_mutex);
    if (!m_file.isOpen()) {
        m_file.setFileName(m_path);
        if (!m_file.open(QIODevice::WriteOnly | QIODevice::Append))
            return;
    }
    if (m_file.size() + line.size() > MaxFileSize) {
        m_file.close();
        QFile::remove(rotatedPath());
        QFile::rename(m_path, rotatedPath());
        m_file.setFileName(m_path);
        if (!m_file.open(QIODevice::WriteOnly | QIODevice::Append))
            return;
    }
    m_file.write(line);
    m_file.flush();
}

QString Logger::text() const
{
    QMutexLocker lock(&m_mutex);
    return readFile(rotatedPath()) + readFile(m_path);
}

QString Logger::report() const
{
    static const char *const levelNames[] = { "debug", "info", "warning", "error" };
    QString header;
    QTextStream out(&header);
    out << "IronStack for Sailfish OS " << QCoreApplication::applicationVersion() << '\n'
        << "System: " << QSysInfo::prettyProductName() << ", " << QSysInfo::currentCpuArchitecture()
        << ", Qt " << qVersion() << '\n'
        << "Language: " << QLocale().uiLanguages().value(0) << ", region " << QLocale().name() << '\n'
        << "Log level: " << levelNames[level()] << '\n'
        << "Saved: " << QDateTime::currentDateTime().toString(Qt::ISODate) << '\n'
        << '\n';
    out.flush();
    const QString log = text();
    return header + (log.isEmpty() ? QStringLiteral("(empty)\n") : log);
}

void Logger::clear()
{
    QMutexLocker lock(&m_mutex);
    m_file.close();
    QFile::remove(rotatedPath());
    QFile::remove(m_path);
}
