#include <QHash>
#include <QImage>
#include <QImageReader>
#include <QJSValue>
#include <QQmlEngine>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QtTest>

#include "apiclient.h"
#include "logger.h"
#include "settings.h"
#include "syncqueue.h"

// Minimal HTTP/1.1 server on localhost: records each request and answers
// with a configured status and JSON body.
class FakeServer : public QObject
{
    Q_OBJECT

public:
    FakeServer()
    {
        m_server.listen(QHostAddress::LocalHost);
        connect(&m_server, &QTcpServer::newConnection, this, &FakeServer::accept);
    }

    QString baseUrl() const { return QStringLiteral("http://127.0.0.1:%1").arg(m_server.serverPort()); }
    quint16 port() const { return m_server.serverPort(); }

    int status = 200;
    // Per-request statuses, used up first (then `status`).
    QList<int> statuses;
    QByteArray body = "{}";
    QList<QByteArray> requests;

private:
    void accept()
    {
        while (QTcpSocket *socket = m_server.nextPendingConnection()) {
            connect(socket, &QTcpSocket::readyRead, this, [this, socket]() { read(socket); });
            connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
        }
    }

    void read(QTcpSocket *socket)
    {
        QByteArray &buffer = m_buffers[socket];
        buffer += socket->readAll();
        const int headerEnd = buffer.indexOf("\r\n\r\n");
        if (headerEnd < 0)
            return;
        int contentLength = 0;
        for (const QByteArray &line : buffer.left(headerEnd).split('\n')) {
            if (line.toLower().startsWith("content-length:"))
                contentLength = line.mid(15).trimmed().toInt();
        }
        if (buffer.size() < headerEnd + 4 + contentLength)
            return;

        requests << buffer;
        m_buffers.remove(socket);
        const int code = statuses.isEmpty() ? status : statuses.takeFirst();
        QByteArray response = "HTTP/1.1 " + QByteArray::number(code) + " Status\r\n"
                "Content-Type: application/json\r\n"
                "Content-Length: " + QByteArray::number(body.size()) + "\r\n"
                "Connection: close\r\n\r\n" + body;
        socket->write(response);
        socket->disconnectFromHost();
    }

    QTcpServer m_server;
    QHash<QTcpSocket *, QByteArray> m_buffers;
};

#define WAIT_FOR_RESULT() QTRY_VERIFY_WITH_TIMEOUT(!result().isUndefined(), 5000)

class TestApiClient : public QObject
{
    Q_OBJECT

private:
    // Calls api.request()/requestWith() through a JS callback (the same way
    // QML does) and waits for it. Returns {ok, status, data, error}.
    QJSValue makeCallback()
    {
        m_engine->globalObject().deleteProperty(QStringLiteral("result"));
        return m_engine->evaluate(QStringLiteral(
            "(function(ok, status, data, error) {"
            "    result = { ok: ok, status: status, data: data, error: error }"
            "})"));
    }

    QJSValue result() { return m_engine->globalObject().property(QStringLiteral("result")); }

    QTemporaryDir m_configDir;
    QQmlEngine *m_engine = nullptr;
    Settings *m_settings = nullptr;
    ApiClient *m_api = nullptr;
    FakeServer *m_server = nullptr;

private slots:
    void initTestCase()
    {
        // Keep QSettings away from the real ~/.config.
        QVERIFY(m_configDir.isValid());
        qputenv("XDG_CONFIG_HOME", m_configDir.path().toUtf8());
        QCoreApplication::setOrganizationName(QStringLiteral("org.ironstack.test"));
        QCoreApplication::setApplicationName(QStringLiteral("tst-cpp"));
    }

    void init()
    {
        m_engine = new QQmlEngine;
        m_settings = new Settings;
        m_api = new ApiClient(m_settings);
        m_api->setEngine(m_engine);
        m_server = new FakeServer;
        m_settings->setBaseUrl(m_server->baseUrl());
        m_settings->setApiKey(QStringLiteral("isk_saved"));
    }

    void cleanup()
    {
        delete m_api;
        delete m_settings;
        delete m_server;
        delete m_engine;
    }

    void normalizeBaseUrl_data()
    {
        QTest::addColumn<QString>("input");
        QTest::addColumn<QString>("expected");
        QTest::newRow("plain") << "https://gym.example" << "https://gym.example";
        QTest::newRow("trailing slashes") << " https://gym.example/// " << "https://gym.example";
        QTest::newRow("no scheme defaults to https") << "gym.example/" << "https://gym.example";
        QTest::newRow("http kept") << "http://10.0.2.2:8000/" << "http://10.0.2.2:8000";
        QTest::newRow("empty") << "" << "";
    }

    void normalizeBaseUrl()
    {
        QFETCH(QString, input);
        QFETCH(QString, expected);
        QCOMPARE(Settings::normalizeBaseUrl(input), expected);
    }

    void sendsKeyToApiPath()
    {
        m_server->body = "{\"unit_system\": \"metric\"}";
        m_api->request(QStringLiteral("GET"), QStringLiteral("profile/"), QJSValue(QJSValue::NullValue), makeCallback());
        WAIT_FOR_RESULT();

        QCOMPARE(result().property("ok").toBool(), true);
        QCOMPARE(result().property("status").toInt(), 200);
        QCOMPARE(result().property("data").property("unit_system").toString(), QStringLiteral("metric"));
        QCOMPARE(m_server->requests.size(), 1);
        const QByteArray request = m_server->requests.first();
        QVERIFY(request.startsWith("GET /api/v1/profile/ HTTP/1.1"));
        QVERIFY(request.contains("Authorization: Bearer isk_saved"));
    }

    void sendsJsonBody()
    {
        m_server->status = 201;
        m_server->body = "{\"id\": 5}";
        QVariantMap body;
        body.insert(QStringLiteral("weight"), 82.5);
        body.insert(QStringLiteral("reps"), 5);
        m_api->request(QStringLiteral("POST"), QStringLiteral("sets/"), m_engine->toScriptValue(body),
                       makeCallback());
        WAIT_FOR_RESULT();

        QCOMPARE(result().property("ok").toBool(), true);
        const QByteArray request = m_server->requests.first();
        QVERIFY(request.startsWith("POST /api/v1/sets/ HTTP/1.1"));
        QVERIFY(request.contains("Content-Type: application/json"));
        QVERIFY(request.endsWith("{\"reps\":5,\"weight\":82.5}"));
    }

    void sendsBodyBuiltInJavaScript()
    {
        // QML passes a JS object, not a QVariantMap - the case every page
        // actually hits. Regression: the body arrived empty, so starting a
        // workout created a freeform session instead.
        m_server->status = 201;
        m_engine->globalObject().setProperty(QStringLiteral("api"), m_engine->newQObject(m_api));
        QQmlEngine::setObjectOwnership(m_api, QQmlEngine::CppOwnership);
        QJSValue call = m_engine->evaluate(QStringLiteral(
            "(function(cb) { api.request('POST', 'sessions/', { workout: 66, notes: 'x', rpe: null }, cb) })"));
        call.call(QJSValueList() << makeCallback());
        WAIT_FOR_RESULT();
        QVERIFY(m_server->requests.first().endsWith("{\"notes\":\"x\",\"rpe\":null,\"workout\":66}"));

        // and no body at all for null
        m_server->requests.clear();
        call = m_engine->evaluate(QStringLiteral("(function(cb) { api.request('GET', 'profile/', null, cb) })"));
        call.call(QJSValueList() << makeCallback());
        WAIT_FOR_RESULT();
        QVERIFY(m_server->requests.first().endsWith("\r\n\r\n"));
    }

    void followsSameServerAbsoluteUrl()
    {
        // A paginated response's "next" is an absolute URL on the same server.
        m_server->body = "{\"results\": []}";
        m_api->request(QStringLiteral("GET"), m_server->baseUrl() + QStringLiteral("/api/v1/sessions/?page=2"),
                       QJSValue(QJSValue::NullValue), makeCallback());
        WAIT_FOR_RESULT();
        QCOMPARE(result().property("ok").toBool(), true);
        QVERIFY(m_server->requests.first().startsWith("GET /api/v1/sessions/?page=2 HTTP/1.1"));
    }

    void linksStayOnTheConfiguredServer_data()
    {
        QTest::addColumn<QString>("url");
        // A "next" link as a server behind a proxy may build it.
        QTest::newRow("other host") << "http://evil.example/api/v1/sessions/?page=2";
        QTest::newRow("other port") << "http://127.0.0.1:1/api/v1/sessions/?page=2";
        QTest::newRow("other scheme") << "https://127.0.0.1:%1/api/v1/sessions/?page=2";
        QTest::newRow("under a path") << "https://example.org/ironstack/api/v1/sessions/?page=2";
    }

    void linksStayOnTheConfiguredServer()
    {
        // The API key must never be sent anywhere but the configured server:
        // only the link's API path and query are asked from it.
        QFETCH(QString, url);
        if (url.contains(QStringLiteral("%1")))
            url = url.arg(m_server->port());
        m_server->body = "{\"results\": []}";
        m_api->request(QStringLiteral("GET"), url, QJSValue(QJSValue::NullValue), makeCallback());
        WAIT_FOR_RESULT();
        QCOMPARE(result().property("ok").toBool(), true);
        QCOMPARE(m_server->requests.size(), 1);
        QVERIFY(m_server->requests.first().startsWith("GET /api/v1/sessions/?page=2 HTTP/1.1"));
    }

    void refusesLinksOutsideTheApi()
    {
        m_api->request(QStringLiteral("GET"), QStringLiteral("http://evil.example/steal?key=1"),
                       QJSValue(QJSValue::NullValue), makeCallback());
        WAIT_FOR_RESULT();
        QCOMPARE(result().property("ok").toBool(), false);
        QCOMPARE(result().property("status").toInt(), 0);
        QCOMPARE(result().property("error").toString(),
                 QStringLiteral("Refused to follow a link to another server."));
        QTest::qWait(100);
        QCOMPARE(m_server->requests.size(), 0);
    }

    void errorMessages_data()
    {
        QTest::addColumn<int>("status");
        QTest::addColumn<QByteArray>("body");
        QTest::addColumn<QString>("expected");
        QTest::newRow("400 field errors") << 400
            << QByteArray("{\"reps\": [\"Ensure this value is greater than or equal to 0.\"]}")
            << "reps: Ensure this value is greater than or equal to 0.";
        QTest::newRow("400 detail") << 400 << QByteArray("{\"detail\": \"Bad thing.\"}") << "Bad thing.";
        QTest::newRow("400 list") << 400 << QByteArray("[\"Session is no longer in progress.\"]")
            << "Session is no longer in progress.";
        QTest::newRow("403") << 403 << QByteArray("{}")
            << "This API key does not have the permission it needs: profile - Read. "
               "Add it in IronStack under Profile > API keys.";
        QTest::newRow("404") << 404 << QByteArray("{}") << "Not found.";
        QTest::newRow("429") << 429 << QByteArray("{}") << "Too many requests. Wait a moment and try again.";
        QTest::newRow("500") << 500 << QByteArray("") << "The server had an error (500).";
    }

    void errorMessages()
    {
        QFETCH(int, status);
        QFETCH(QByteArray, body);
        QFETCH(QString, expected);
        m_server->status = status;
        m_server->body = body;
        m_api->request(QStringLiteral("GET"), QStringLiteral("profile/"), QJSValue(QJSValue::NullValue), makeCallback());
        WAIT_FOR_RESULT();
        QCOMPARE(result().property("ok").toBool(), false);
        QCOMPARE(result().property("status").toInt(), status);
        QCOMPARE(result().property("error").toString(), expected);
    }

    void contextForPath_data()
    {
        QTest::addColumn<QString>("path");
        QTest::addColumn<QString>("context");
        QTest::newRow("profile") << "profile/" << "profile";
        QTest::newRow("diary") << "diary-entries/3/" << "nutrition";
        QTest::newRow("query") << "sessions/?status=in_progress" << "workouts";
        QTest::newRow("absolute") << "/api/v1/stretch-sessions/?page=2" << "stretching";
        QTest::newRow("last performance") << "exercises/1/last-performance/" << "workouts";
        QTest::newRow("exercise") << "exercises/1/" << "exercises";
        QTest::newRow("nutrition profile") << "nutrition/profile/" << "nutrition";
        QTest::newRow("social") << "social/messages/3/" << "social";
        QTest::newRow("coaching") << "coaching/clients/" << "coaching";
        QTest::newRow("assistant") << "assistant/conversations/" << "assistant";
        QTest::newRow("unknown") << "nope/" << "";
    }

    void contextForPath()
    {
        QFETCH(QString, path);
        QFETCH(QString, context);
        QCOMPARE(ApiClient::contextForPath(path), context);
    }

    void acceptLanguage()
    {
        QCOMPARE(ApiClient::acceptLanguage(QLocale(QStringLiteral("fi_FI"))), QByteArray("fi, en;q=0.5"));
        QCOMPARE(ApiClient::acceptLanguage(QLocale(QStringLiteral("en_GB"))), QByteArray("en"));
        QCOMPARE(ApiClient::acceptLanguage(QLocale::c()), QByteArray("en"));
    }

    void permissionForMethod()
    {
        QCOMPARE(ApiClient::permissionForMethod(QStringLiteral("GET")), QStringLiteral("Read"));
        QCOMPARE(ApiClient::permissionForMethod(QStringLiteral("post")), QStringLiteral("Create"));
        QCOMPARE(ApiClient::permissionForMethod(QStringLiteral("PATCH")), QStringLiteral("Update"));
        QCOMPARE(ApiClient::permissionForMethod(QStringLiteral("PUT")), QStringLiteral("Update"));
        QCOMPARE(ApiClient::permissionForMethod(QStringLiteral("DELETE")), QStringLiteral("Delete"));
    }

    void unauthorizedOnlyForSavedKey()
    {
        // A rejected saved key sends the app back to the login page; a key
        // still being tried on the login page must not.
        m_server->status = 401;
        QSignalSpy spy(m_api, &ApiClient::unauthorized);

        m_api->requestWith(m_server->baseUrl(), QStringLiteral("isk_typed"), QStringLiteral("GET"),
                           QStringLiteral("profile/"), QJSValue(QJSValue::NullValue), makeCallback());
        WAIT_FOR_RESULT();
        QCOMPARE(spy.count(), 0);

        m_api->request(QStringLiteral("GET"), QStringLiteral("profile/"), QJSValue(QJSValue::NullValue), makeCallback());
        WAIT_FOR_RESULT();
        QCOMPARE(spy.count(), 1);
        QCOMPARE(result().property("error").toString(),
                 QStringLiteral("The API key was not accepted. It may have been revoked."));
    }

    void unreachableServer()
    {
        m_settings->setBaseUrl(QStringLiteral("http://127.0.0.1:1"));
        m_api->request(QStringLiteral("GET"), QStringLiteral("profile/"), QJSValue(QJSValue::NullValue), makeCallback());
        WAIT_FOR_RESULT();
        QCOMPARE(result().property("ok").toBool(), false);
        QCOMPARE(result().property("status").toInt(), 0);
        QCOMPARE(result().property("error").toString(), QStringLiteral("Can't reach the server."));
    }

    void busyWhileRequestsPending()
    {
        QSignalSpy spy(m_api, &ApiClient::busyChanged);
        QVERIFY(!m_api->busy());
        m_api->request(QStringLiteral("GET"), QStringLiteral("profile/"), QJSValue(QJSValue::NullValue), makeCallback());
        QVERIFY(m_api->busy());
        WAIT_FOR_RESULT();
        QVERIFY(!m_api->busy());
        QCOMPARE(spy.count(), 2);
    }

    // --- SyncQueue ------------------------------------------------------

    void queueSendsInOrder()
    {
        QTemporaryDir dir;
        SyncQueue queue(m_api, dir.path() + QStringLiteral("/pending.json"));
        QSignalSpy synced(&queue, &SyncQueue::itemSynced);
        m_server->status = 201;
        QVariantMap first;
        first.insert(QStringLiteral("reps"), 1);
        QVariantMap second;
        second.insert(QStringLiteral("reps"), 2);
        queue.enqueueVariant(QStringLiteral("POST"), QStringLiteral("sets/"), first);
        queue.enqueueVariant(QStringLiteral("POST"), QStringLiteral("sets/"), second);
        QTRY_COMPARE_WITH_TIMEOUT(synced.count(), 2, 5000);
        QCOMPARE(queue.count(), 0);
        QVERIFY(m_server->requests.at(0).endsWith("{\"reps\":1}"));
        QVERIFY(m_server->requests.at(1).endsWith("{\"reps\":2}"));
    }

    void queueSurvivesNoConnection()
    {
        // Offline: nothing is lost, it's on disk for the next app start,
        // and goes out once the server is reachable.
        QTemporaryDir dir;
        const QString path = dir.path() + QStringLiteral("/pending.json");
        const QString serverUrl = m_server->baseUrl();
        m_settings->setBaseUrl(QStringLiteral("http://127.0.0.1:1"));
        {
            SyncQueue queue(m_api, path);
            queue.enqueueVariant(QStringLiteral("PATCH"), QStringLiteral("sessions/5/"),
                                 QVariantMap { { QStringLiteral("status"), QStringLiteral("completed") } });
            QTRY_VERIFY_WITH_TIMEOUT(!queue.lastError().isEmpty(), 5000);
            QCOMPARE(queue.count(), 1);
        }
        m_settings->setBaseUrl(serverUrl);
        SyncQueue restarted(m_api, path);
        QCOMPARE(restarted.count(), 1);
        QSignalSpy synced(&restarted, &SyncQueue::itemSynced);
        QTRY_COMPARE_WITH_TIMEOUT(synced.count(), 1, 5000);
        QCOMPARE(restarted.count(), 0);
        QVERIFY(m_server->requests.first().startsWith("PATCH /api/v1/sessions/5/ HTTP/1.1"));
        QVERIFY(restarted.lastError().isEmpty());
    }

    void queueDropsRejectedAndContinues()
    {
        // A 400 (say, the session was already finished elsewhere) will never
        // succeed - report it and move on to the next item.
        QTemporaryDir dir;
        SyncQueue queue(m_api, dir.path() + QStringLiteral("/pending.json"));
        QSignalSpy failed(&queue, &SyncQueue::itemFailed);
        QSignalSpy synced(&queue, &SyncQueue::itemSynced);
        m_server->statuses = { 400, 201 };
        m_server->body = "{\"detail\": \"This session is no longer in progress.\"}";
        const int rejected = queue.enqueueVariant(QStringLiteral("POST"), QStringLiteral("sets/"), QVariantMap());
        queue.enqueueVariant(QStringLiteral("POST"), QStringLiteral("sets/"), QVariantMap());
        QTRY_COMPARE_WITH_TIMEOUT(synced.count(), 1, 5000);
        QCOMPARE(failed.count(), 1);
        QCOMPARE(failed.first().at(0).toInt(), rejected);
        QCOMPARE(failed.first().at(3).toInt(), 400);
        QCOMPARE(failed.first().at(4).toString(), QStringLiteral("This session is no longer in progress."));
        QCOMPARE(queue.count(), 0);
    }

    void queueRetriesServerErrors()
    {
        QTemporaryDir dir;
        SyncQueue queue(m_api, dir.path() + QStringLiteral("/pending.json"));
        queue.setRetryInterval(50);
        QSignalSpy synced(&queue, &SyncQueue::itemSynced);
        m_server->statuses = { 503, 502, 201 };
        queue.enqueueVariant(QStringLiteral("POST"), QStringLiteral("sets/"), QVariantMap());
        QTRY_COMPARE_WITH_TIMEOUT(synced.count(), 1, 5000);
        QCOMPARE(m_server->requests.size(), 3);
    }

    static QByteArray header(const QByteArray &request, const QByteArray &name)
    {
        for (const QByteArray &line : request.split('\n')) {
            if (line.toLower().startsWith(name.toLower() + ':'))
                return line.mid(name.size() + 1).trimmed();
        }
        return QByteArray();
    }

    void queueSendsIdempotencyKey()
    {
        // Every retry of one POST carries the same key, so the server can
        // tell a retry from a second set; each POST has its own key; a
        // PATCH (already idempotent) has none.
        QTemporaryDir dir;
        SyncQueue queue(m_api, dir.path() + QStringLiteral("/pending.json"));
        queue.setRetryInterval(50);
        QSignalSpy synced(&queue, &SyncQueue::itemSynced);
        m_server->statuses = { 502, 201, 201, 200 };
        queue.enqueueVariant(QStringLiteral("POST"), QStringLiteral("sets/"), QVariantMap());
        queue.enqueueVariant(QStringLiteral("POST"), QStringLiteral("sets/"), QVariantMap());
        queue.enqueueVariant(QStringLiteral("PATCH"), QStringLiteral("sessions/5/"), QVariantMap());
        QTRY_COMPARE_WITH_TIMEOUT(synced.count(), 3, 5000);
        QCOMPARE(m_server->requests.size(), 4);
        const QByteArray first = header(m_server->requests.at(0), "Idempotency-Key");
        QCOMPARE(first.size(), 36);
        QCOMPARE(header(m_server->requests.at(1), "Idempotency-Key"), first);
        const QByteArray second = header(m_server->requests.at(2), "Idempotency-Key");
        QCOMPARE(second.size(), 36);
        QVERIFY(second != first);
        QVERIFY(header(m_server->requests.at(3), "Idempotency-Key").isEmpty());
    }

    void queueKeyedAfterUpgrade()
    {
        // A POST queued by a version without keys gets one when loaded.
        QTemporaryDir dir;
        const QString path = dir.path() + QStringLiteral("/pending.json");
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("{\"items\":[{\"id\":1,\"method\":\"POST\",\"path\":\"sets/\",\"body\":{}}],\"nextId\":2}");
        file.close();
        m_server->status = 201;
        SyncQueue queue(m_api, path);
        QSignalSpy synced(&queue, &SyncQueue::itemSynced);
        QTRY_COMPARE_WITH_TIMEOUT(synced.count(), 1, 5000);
        QCOMPARE(header(m_server->requests.at(0), "Idempotency-Key").size(), 36);
    }

    void queueClear()
    {
        QTemporaryDir dir;
        const QString path = dir.path() + QStringLiteral("/pending.json");
        m_settings->setBaseUrl(QStringLiteral("http://127.0.0.1:1"));
        {
            SyncQueue queue(m_api, path);
            queue.enqueueVariant(QStringLiteral("POST"), QStringLiteral("sets/"), QVariantMap());
            queue.clear();
            QCOMPARE(queue.count(), 0);
        }
        SyncQueue restarted(m_api, path);
        QCOMPARE(restarted.count(), 0);
    }

    void activeSessionAndCacheSurviveRestart()
    {
        m_settings->setActiveSessionId(42);
        m_settings->setActiveSessionName(QStringLiteral("Workout A"));
        QVariantMap session;
        session.insert(QStringLiteral("id"), 42);
        session.insert(QStringLiteral("performed_exercises"), QVariantList { QVariantMap { { QStringLiteral("id"), 7 } } });
        m_settings->setCachedVariant(QStringLiteral("session"), session);

        Settings restarted;
        QCOMPARE(restarted.activeSessionId(), 42);
        QCOMPARE(restarted.activeSessionName(), QStringLiteral("Workout A"));
        const QVariantMap back = restarted.cached(QStringLiteral("session")).toMap();
        QCOMPARE(back.value(QStringLiteral("id")).toInt(), 42);
        QCOMPARE(back.value(QStringLiteral("performed_exercises")).toList().size(), 1);
        QVERIFY(!restarted.cached(QStringLiteral("missing")).isValid());

        restarted.setCachedVariant(QStringLiteral("shopping/12/0"), QVariantList { 5 });
        restarted.setCachedVariant(QStringLiteral("shopping/12/week"), QVariantList { 6 });
        restarted.setCachedVariant(QStringLiteral("shopping/120/0"), QVariantList { 7 });
        restarted.removeCached(QStringLiteral("shopping/12"));
        QVERIFY(!restarted.cached(QStringLiteral("shopping/12/0")).isValid());
        QVERIFY(!restarted.cached(QStringLiteral("shopping/12/week")).isValid());
        QVERIFY(restarted.cached(QStringLiteral("shopping/120/0")).isValid());

        restarted.clearActiveSession();
        QCOMPARE(Settings().activeSessionId(), -1);
        restarted.logout();
        QVERIFY(!Settings().cached(QStringLiteral("session")).isValid());
    }

    void cacheFromJavaScript()
    {
        // The way QML calls it - regression: the JS object was stored empty.
        m_engine->globalObject().setProperty(QStringLiteral("settings"), m_engine->newQObject(m_settings));
        QQmlEngine::setObjectOwnership(m_settings, QQmlEngine::CppOwnership);
        QJSValue result = m_engine->evaluate(QStringLiteral(
            "settings.setCached('session', { session: { id: 3, sets: [1, 2] }, title: 'A' });"
            "var back = settings.cached('session');"
            "back.session.id + ':' + back.session.sets.length + ':' + back.title"));
        QCOMPARE(result.toString(), QStringLiteral("3:2:A"));
    }

    void logoutClearsKeyAndSession()
    {
        m_settings->setActiveSessionId(3);
        m_settings->setRestEndsAt(12345);
        QVERIFY(m_settings->configured());
        m_settings->logout();
        QVERIFY(!m_settings->configured());
        QCOMPARE(m_settings->activeSessionId(), -1);
        QCOMPARE(m_settings->restEndsAt(), 0.0);
        QCOMPARE(m_settings->baseUrl(), m_server->baseUrl());
    }

    void loggerLevels()
    {
        QTemporaryDir dir;
        Logger logger(dir.path() + QStringLiteral("/logs/app.log"));
        const QMessageLogContext context;
        logger.setLevel(Logger::Warning);
        logger.handle(QtDebugMsg, context, QStringLiteral("a debug line"));
        logger.handle(QtInfoMsg, context, QStringLiteral("an info line"));
        logger.handle(QtWarningMsg, context, QStringLiteral("a warning line"));
        logger.handle(QtCriticalMsg, context, QStringLiteral("an error line"));
        QString text = logger.text();
        QVERIFY(!text.contains(QStringLiteral("debug line")));
        QVERIFY(!text.contains(QStringLiteral("info line")));
        QVERIFY(text.contains(QStringLiteral(" W a warning line\n")));
        QVERIFY(text.contains(QStringLiteral(" E an error line\n")));

        logger.setLevel(Logger::Debug);
        logger.handle(QtDebugMsg, context, QStringLiteral("a debug line"));
        QVERIFY(logger.text().contains(QStringLiteral(" D a debug line")));

        logger.setLevel(Logger::Error);
        logger.handle(QtWarningMsg, context, QStringLiteral("not kept"));
        QVERIFY(!logger.text().contains(QStringLiteral("not kept")));

        logger.note(QStringLiteral("app started"));
        QVERIFY(logger.text().contains(QStringLiteral(" - app started\n")));

        logger.clear();
        QCOMPARE(logger.text(), QString());
        logger.handle(QtCriticalMsg, context, QStringLiteral("after clearing"));
        QVERIFY(logger.text().contains(QStringLiteral("after clearing")));
    }

    void loggerMasksKeys()
    {
        QTemporaryDir dir;
        Logger logger(dir.path() + QStringLiteral("/app.log"));
        logger.handle(QtWarningMsg, QMessageLogContext(),
                      QStringLiteral("Authorization: Bearer isk_LtWQAuQjs3cr3t_Value-9 sent"));
        logger.handle(QtWarningMsg, QMessageLogContext(),
                      QStringLiteral("{\"key\": \"isk_AbCdEfGhs3cr3t-x_y\"}"));
        const QString text = logger.text();
        QVERIFY(!text.contains(QStringLiteral("s3cr3t")));
        QVERIFY(text.contains(QStringLiteral("Authorization: Bearer *** sent")));
        QVERIFY(text.contains(QStringLiteral("{\"key\": \"isk_***\"}")));
        // the full report too, with the versions on top
        QVERIFY(logger.report().startsWith(QStringLiteral("IronStack for Sailfish OS")));
        QVERIFY(!logger.report().contains(QStringLiteral("s3cr3t")));
    }

    void loggerRotates()
    {
        QTemporaryDir dir;
        const QString path = dir.path() + QStringLiteral("/app.log");
        Logger logger(path);
        const QString line(1000, QLatin1Char('x'));
        const int lines = int(Logger::MaxFileSize / 1000) * 2 + 10;
        for (int i = 0; i < lines; i++)
            logger.handle(QtWarningMsg, QMessageLogContext(), QString::number(i) + QLatin1Char(' ') + line);
        QVERIFY(QFileInfo(path).size() <= Logger::MaxFileSize);
        QVERIFY(QFileInfo::exists(path + QStringLiteral(".1")));
        // the newest line is kept, the oldest are gone, oldest first
        const QString text = logger.text();
        QVERIFY(text.contains(QStringLiteral(" W %1 x").arg(lines - 1)));
        QVERIFY(!text.contains(QStringLiteral(" W 0 x")));
        const QStringList kept = text.split(QLatin1Char('\n'), QString::SkipEmptyParts);
        QVERIFY(kept.first().section(QLatin1Char(' '), 3, 3).toInt()
                < kept.last().section(QLatin1Char(' '), 3, 3).toInt());
    }

    void logPath()
    {
        const QUrl url(QStringLiteral("https://example.org/api/v1/diary-entries/?date=2026-11-04"));
        QCOMPARE(ApiClient::logPath(url, false), QStringLiteral("diary-entries/"));
        QCOMPARE(ApiClient::logPath(url, true), QStringLiteral("diary-entries/?date=2026-11-04"));
    }

    void uploadImageScalesLargePhotos()
    {
        QTemporaryDir dir;
        const QString large = dir.path() + QStringLiteral("/large.jpg");
        QImage photo(3200, 1800, QImage::Format_RGB32);
        photo.fill(Qt::darkGreen);
        QVERIFY(photo.save(large, "JPEG"));

        QString name;
        QString type;
        const QByteArray data = ApiClient::uploadImage(QStringLiteral("file://") + large, &name, &type);
        QCOMPARE(type, QStringLiteral("image/jpeg"));
        QCOMPARE(name, QStringLiteral("image.jpg"));
        const QImage sent = QImage::fromData(data);
        QCOMPARE(sent.size(), QSize(1600, 900));
    }

    void uploadImageKeepsSmallOnes()
    {
        QTemporaryDir dir;
        const QString small = dir.path() + QStringLiteral("/Holiday photo.png");
        QImage drawing(400, 300, QImage::Format_ARGB32);
        drawing.fill(Qt::transparent);
        QVERIFY(drawing.save(small, "PNG"));
        QFile file(small);
        QVERIFY(file.open(QIODevice::ReadOnly));

        QString name;
        QString type;
        QCOMPARE(ApiClient::uploadImage(small, &name, &type), file.readAll());
        QCOMPARE(type, QStringLiteral("image/png"));
        // The phone's own file name isn't sent.
        QCOMPARE(name, QStringLiteral("image.png"));

        QVERIFY(ApiClient::uploadImage(dir.path() + QStringLiteral("/missing.jpg"), &name, &type).isEmpty());
    }

    // Standalone mode: a JS handler answers instead of the network.
    QJSValue localHandler(const QString &body)
    {
        return m_engine->evaluate(QStringLiteral("(function(method, path, body) {"
                                                 "  calls = (typeof calls === 'undefined' ? [] : calls);"
                                                 "  calls.push(method + ' ' + path + ' ' + JSON.stringify(body));"
                                                 "  %1 })").arg(body));
    }

    void standaloneAnswersLocally()
    {
        m_settings->setStandalone(true);
        QVERIFY(m_settings->configured());
        m_api->setLocalBackend(localHandler(QStringLiteral("return { status: 201, data: { id: 7 } }")));
        QVariantMap body;
        body.insert(QStringLiteral("reps"), 5);
        m_api->request(QStringLiteral("post"), QStringLiteral("sets/"), m_engine->toScriptValue(body), makeCallback());
        // Never inside request() itself, like a network reply.
        QVERIFY(result().isUndefined());
        QVERIFY(m_api->busy());
        WAIT_FOR_RESULT();
        QCOMPARE(result().property("ok").toBool(), true);
        QCOMPARE(result().property("status").toInt(), 201);
        QCOMPARE(result().property("data").property("id").toInt(), 7);
        QCOMPARE(m_engine->globalObject().property("calls").property(0).toString(),
                 QStringLiteral("POST sets/ {\"reps\":5}"));
        QVERIFY(m_server->requests.isEmpty());
        QTRY_VERIFY(!m_api->busy());
        m_settings->setStandalone(false);
    }

    void standaloneErrors()
    {
        m_settings->setStandalone(true);
        m_api->setLocalBackend(localHandler(QStringLiteral("return { status: 400, data: { name: ['Required.'] } }")));
        m_api->request(QStringLiteral("POST"), QStringLiteral("exercises/"), QJSValue(), makeCallback());
        WAIT_FOR_RESULT();
        QCOMPARE(result().property("ok").toBool(), false);
        QCOMPARE(result().property("error").toString(), QStringLiteral("name: Required."));

        // A bug in the backend is a 500, not a crash.
        m_api->setLocalBackend(localHandler(QStringLiteral("return undefinedThing.x")));
        m_api->request(QStringLiteral("GET"), QStringLiteral("sessions/"), QJSValue(), makeCallback());
        WAIT_FOR_RESULT();
        QCOMPARE(result().property("status").toInt(), 500);
        m_settings->setStandalone(false);
    }

    void standaloneKeepsLoginAndTransferOnTheNetwork()
    {
        m_settings->setStandalone(true);
        m_api->setLocalBackend(localHandler(QStringLiteral("return { status: 200, data: {} }")));
        m_server->body = "{\"username\": \"someone\"}";
        m_api->requestWith(m_server->baseUrl(), QStringLiteral("isk_typed"), QStringLiteral("GET"),
                           QStringLiteral("profile/"), QJSValue(), makeCallback());
        WAIT_FOR_RESULT();
        QCOMPARE(result().property("data").property("username").toString(), QStringLiteral("someone"));

        QVariantMap headers;
        headers.insert(QStringLiteral("Idempotency-Key"), QStringLiteral("abc-123"));
        m_api->requestTo(m_server->baseUrl(), QStringLiteral("isk_typed"), QStringLiteral("POST"),
                         QStringLiteral("sets/"), QJSValue(), m_engine->toScriptValue(headers), makeCallback());
        WAIT_FOR_RESULT();
        QCOMPARE(m_server->requests.size(), 2);
        QVERIFY(m_server->requests.at(1).contains("Idempotency-Key: abc-123"));
        QVERIFY(m_server->requests.at(1).contains("Authorization: Bearer isk_typed"));
        m_settings->setStandalone(false);
    }

    void standaloneQueueGoesLocal()
    {
        QTemporaryDir dir;
        m_settings->setStandalone(true);
        m_api->setLocalBackend(localHandler(QStringLiteral("return { status: 201, data: { new_records: [] } }")));
        SyncQueue queue(m_api, dir.path() + QStringLiteral("/pending.json"));
        QSignalSpy synced(&queue, &SyncQueue::itemSynced);
        queue.enqueueVariant(QStringLiteral("POST"), QStringLiteral("sets/"), QVariantMap());
        QTRY_COMPARE(synced.count(), 1);
        QCOMPARE(queue.count(), 0);
        QVERIFY(m_server->requests.isEmpty());
        m_settings->setStandalone(false);
    }

    void readDataOnlyPlainNames()
    {
        QTemporaryDir dir;
        QFile file(dir.path() + QStringLiteral("/seed.json"));
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("{\"version\": 1}");
        file.close();
        m_api->setDataDir(dir.path());
        QCOMPARE(m_api->readData(QStringLiteral("seed.json")), QStringLiteral("{\"version\": 1}"));
        QCOMPARE(m_api->readData(QStringLiteral("../seed.json")), QString());
        QCOMPARE(m_api->readData(QStringLiteral("missing.json")), QString());
    }

    void uploadSendsMultipart()
    {
        m_server->status = 201;
        m_server->body = "{\"id\": 5}";
        QTemporaryDir dir;
        const QString path = dir.path() + QStringLiteral("/small.png");
        QImage image(10, 10, QImage::Format_RGB32);
        image.fill(Qt::red);
        QVERIFY(image.save(path, "PNG"));

        QVariantMap fields;
        fields.insert(QStringLiteral("caption"), QStringLiteral("Start position"));
        m_api->upload(QStringLiteral("exercises/7/images/"), QStringLiteral("image"), path,
                      m_engine->toScriptValue(fields), makeCallback());
        WAIT_FOR_RESULT();

        QCOMPARE(result().property("ok").toBool(), true);
        QCOMPARE(result().property("data").property("id").toInt(), 5);
        const QByteArray request = m_server->requests.first();
        QVERIFY(request.startsWith("POST /api/v1/exercises/7/images/ HTTP/1.1"));
        QVERIFY(request.contains("Authorization: Bearer isk_saved"));
        QVERIFY(request.contains("Content-Type: multipart/form-data; boundary="));
        QVERIFY(request.contains("name=\"caption\"\r\n\r\nStart position"));
        QVERIFY(request.contains("name=\"image\"; filename=\"image.png\""));
        QVERIFY(request.contains("Content-Type: image/png"));
    }

    void uploadUnreadableFile()
    {
        m_api->upload(QStringLiteral("exercises/7/images/"), QStringLiteral("image"),
                      QStringLiteral("/nonexistent/photo.jpg"), QJSValue(), makeCallback());
        WAIT_FOR_RESULT();
        QCOMPARE(result().property("ok").toBool(), false);
        QCOMPARE(result().property("status").toInt(), 0);
        QVERIFY(m_server->requests.isEmpty());
    }
};

QTEST_GUILESS_MAIN(TestApiClient)
#include "tst_apiclient.moc"
