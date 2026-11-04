#include <QGuiApplication>
#include <QLocale>
#include <QSysInfo>
#include <QNetworkConfigurationManager>
#include <QStandardPaths>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickView>
#include <QScopedPointer>
#include <QTranslator>

#include <sailfishapp.h>

#include "apiclient.h"
#include "barcode.h"
#include "logger.h"
#include "settings.h"
#include "syncqueue.h"

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    app->setOrganizationName(QStringLiteral("org.ironstack"));
    app->setApplicationName(QStringLiteral("harbour-ironstack"));
    app->setApplicationVersion(QStringLiteral(APP_VERSION));

    // SailfishApp loads translations/harbour-ironstack-<locale>.qm. For a
    // locale without one (or none set at all), fall back to the English
    // file - it carries the plural forms ("1 workout", "2 workouts") that
    // the untranslated "%n workout(s)" source strings don't have.
    const QString translationsDir = SailfishApp::pathTo(QStringLiteral("translations")).toLocalFile();
    QTranslator localeTranslation;
    QTranslator englishFallback;
    if (!localeTranslation.load(QLocale(), QStringLiteral("harbour-ironstack"), QStringLiteral("-"),
                                translationsDir)
            && englishFallback.load(QStringLiteral("harbour-ironstack-en"), translationsDir)) {
        app->installTranslator(&englishFallback);
    }

    Settings settings;
    // ~/.local/share/org.ironstack/harbour-ironstack/ironstack.log, for
    // Settings > "App log" (copied or shared when reporting a problem).
    Logger logger(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                  + QStringLiteral("/ironstack.log"));
    logger.setLevel(settings.logLevel());
    QObject::connect(&settings, &Settings::logLevelChanged,
                     &logger, [&]() { logger.setLevel(settings.logLevel()); });
    Logger::install(&logger);
    logger.note(QStringLiteral("harbour-ironstack %1 started (%2, language %3, region %4)")
                .arg(QStringLiteral(APP_VERSION), QSysInfo::prettyProductName(),
                     QLocale().uiLanguages().value(0), QLocale().name()));

    ApiClient api(&settings);
    // ~/.local/share/org.ironstack/harbour-ironstack/ - inside the sandbox.
    SyncQueue queue(&api, QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                    + QStringLiteral("/pending.json"));
    QNetworkConfigurationManager network;
    QObject::connect(&network, &QNetworkConfigurationManager::onlineStateChanged,
                     &queue, [&queue](bool online) { if (online) queue.flush(); });

    QScopedPointer<QQuickView> view(SailfishApp::createView());
    api.setEngine(view->engine());
    view->rootContext()->setContextProperty(QStringLiteral("settings"), &settings);
    view->rootContext()->setContextProperty(QStringLiteral("api"), &api);
    view->rootContext()->setContextProperty(QStringLiteral("syncQueue"), &queue);
    view->rootContext()->setContextProperty(QStringLiteral("appLog"), &logger);
    BarcodeReader barcodeReader;
    view->rootContext()->setContextProperty(QStringLiteral("barcodeReader"), &barcodeReader);
    view->setSource(SailfishApp::pathToMainQml());
    view->show();

    const int result = app->exec();
    // The view and its QML go before the logger.
    view.reset();
    Logger::install(nullptr);
    return result;
}
