TEMPLATE = app
TARGET = tst-cpp
QT += testlib network qml
QT -= gui
CONFIG += warn_on testcase c++11

INCLUDEPATH += ../../src
SOURCES += \
    tst_apiclient.cpp \
    ../../src/apiclient.cpp \
    ../../src/settings.cpp
HEADERS += \
    ../../src/apiclient.h \
    ../../src/settings.h
