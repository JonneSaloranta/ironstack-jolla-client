TARGET = harbour-ironstack

CONFIG += sailfishapp
QT += network

SOURCES += \
    src/main.cpp \
    src/apiclient.cpp \
    src/settings.cpp

HEADERS += \
    src/apiclient.h \
    src/settings.h

DISTFILES += \
    qml/harbour-ironstack.qml \
    qml/cover/*.qml \
    qml/pages/*.qml \
    qml/components/*.qml \
    qml/js/*.js \
    rpm/harbour-ironstack.spec \
    harbour-ironstack.desktop \
    translations/*.ts

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172

CONFIG += sailfishapp_i18n
TRANSLATIONS += \
    translations/harbour-ironstack-fi.ts \
    translations/harbour-ironstack-en.ts
