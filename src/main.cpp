#include <QGuiApplication>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickView>
#include <QScopedPointer>
#include <QTranslator>

#include <sailfishapp.h>

#include "apiclient.h"
#include "settings.h"

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
    ApiClient api(&settings);

    QScopedPointer<QQuickView> view(SailfishApp::createView());
    api.setEngine(view->engine());
    view->rootContext()->setContextProperty(QStringLiteral("settings"), &settings);
    view->rootContext()->setContextProperty(QStringLiteral("api"), &api);
    view->setSource(SailfishApp::pathToMainQml());
    view->show();

    return app->exec();
}
