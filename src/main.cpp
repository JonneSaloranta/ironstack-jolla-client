#include <QGuiApplication>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickView>
#include <QScopedPointer>

#include <sailfishapp.h>

#include "apiclient.h"
#include "settings.h"

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    app->setOrganizationName(QStringLiteral("org.ironstack"));
    app->setApplicationName(QStringLiteral("harbour-ironstack"));

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
