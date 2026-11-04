#ifndef LOGGER_H
#define LOGGER_H

#include <QFile>
#include <QMutex>
#include <QObject>
#include <QString>

// The app's own log, for a user to copy or share when something goes
// wrong: every qDebug/qInfo/qWarning/qCritical - the app's, Qt's and
// QML's (console.log, JavaScript errors) - at or above the chosen level
// goes to a file in the app's data directory, rotated at MaxFileSize with
// one older file kept. Everything still goes to stderr as before.
//
// Never logs the API key: anything that looks like one is masked.
class Logger : public QObject
{
    Q_OBJECT
    // 0 debug, 1 info, 2 warning, 3 errors only.
    Q_PROPERTY(int level READ level WRITE setLevel NOTIFY levelChanged)
    Q_PROPERTY(QString path READ path CONSTANT)

public:
    enum Level { Debug = 0, Info = 1, Warning = 2, Error = 3 };
    Q_ENUM(Level)

    static const qint64 MaxFileSize = 512 * 1024;

    explicit Logger(const QString &path, QObject *parent = nullptr);
    ~Logger() override;

    // Routes Qt's messages through `logger` (nullptr restores the default).
    static void install(Logger *logger);
    // Whether the installed logger keeps messages of `level` (true without
    // one) - for a message that's worth more detail when it's kept.
    static bool keeps(Level level);

    int level() const;
    void setLevel(int level);
    QString path() const { return m_path; }

    // One message, as the handler gets it. Public for tests.
    void handle(QtMsgType type, const QMessageLogContext &context, const QString &message);
    // A line written whatever the level, e.g. the app starting - it
    // separates one run from the next.
    void note(const QString &message);

    // The older file and the current one, oldest line first.
    Q_INVOKABLE QString text() const;
    // text() under a few lines on the app, the system and the level, for
    // sending to whoever looks into the problem.
    Q_INVOKABLE QString report() const;
    Q_INVOKABLE void clear();

    static Level levelOf(QtMsgType type);
    static QString mask(const QString &message);

signals:
    void levelChanged();

private:
    void write(const QByteArray &line);
    QString rotatedPath() const { return m_path + QStringLiteral(".1"); }

    const QString m_path;
    mutable QMutex m_mutex;
    QFile m_file;
    int m_level = Warning;
};

#endif
