# QML tests, run headless inside the SDK build engine:
#   sfdk build-shell bash -c 'cd tests && qmake && make && ./tst-harbour-ironstack -platform minimal'
# See docs/TESTING.md.
TEMPLATE = app
TARGET = tst-harbour-ironstack
CONFIG += warn_on qmltestcase
SOURCES += main.cpp
DEFINES += QUICK_TEST_SOURCE_DIR=\\\"$$PWD\\\"
DISTFILES += *.qml
