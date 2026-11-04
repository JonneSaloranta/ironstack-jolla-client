TEMPLATE = app
TARGET = tst-cpp
QT += testlib network qml gui
CONFIG += warn_on testcase c++11

INCLUDEPATH += ../../src
SOURCES += \
    tst_apiclient.cpp \
    ../../src/apiclient.cpp \
    ../../src/settings.cpp \
    ../../src/syncqueue.cpp \
    ../../src/logger.cpp
HEADERS += \
    ../../src/apiclient.h \
    ../../src/settings.h \
    ../../src/syncqueue.h \
    ../../src/logger.h
