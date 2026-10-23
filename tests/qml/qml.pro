TEMPLATE = app
TARGET = tst-qml
CONFIG += warn_on qmltestcase
SOURCES += main.cpp
DEFINES += QUICK_TEST_SOURCE_DIR=\\\"$$PWD\\\"
DISTFILES += *.qml
