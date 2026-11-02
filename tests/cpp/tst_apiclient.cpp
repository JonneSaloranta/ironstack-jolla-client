#include <QHash>
#include <QJSValue>
#include <QQmlEngine>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QtTest>

#include "apiclient.h"
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

    void refusesOtherServers_data()
    {
        QTest::addColumn<QString>("url");
        QTest::newRow("other host") << "http://evil.example/api/v1/profile/";
        QTest::newRow("other port") << "http://127.0.0.1:1/api/v1/profile/";
        QTest::newRow("other scheme") << "https://127.0.0.1:%1/api/v1/profile/";
    }

    void refusesOtherServers()
    {
        // The API key must never be sent anywhere but the configured server.
        QFETCH(QString, url);
        if (url.contains(QStringLiteral("%1")))
            url = url.arg(m_server->port());
        m_api->request(QStringLiteral("GET"), url, QJSValue(QJSValue::NullValue), makeCallback());
        WAIT_FOR_RESULT();
        QCOMPARE(result().property("ok").toBool(), false);
        QCOMPARE(result().property("status").toInt(), 0);
        // Refused up front - not merely a connection that happened to fail.
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
        QTest::newRow("403") << 403 << QByteArray("{}") << "This API key does not have permission for that.";
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
};

QTEST_GUILESS_MAIN(TestApiClient)
#include "tst_apiclient.moc"
