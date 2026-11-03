TEMPLATE = app
TARGET = tst-barcode
QT += testlib gui
CONFIG += warn_on testcase c++11

INCLUDEPATH += ../../src
SOURCES += \
    tst_barcode.cpp \
    ../../src/barcode.cpp
HEADERS += \
    ../../src/barcode.h
