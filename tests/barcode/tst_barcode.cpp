#include <QPainter>
#include <QTest>
#include <QTransform>

#include "barcode.h"

// Draws real EAN/UPC barcodes - the modules a printer would - and reads
// them back the way a camera frame would show them: scaled, blurred,
// noisy, unevenly lit, sideways and upside down.
class TestBarcode : public QObject
{
    Q_OBJECT

    static QString lCode(int d)
    {
        static const char *codes[10] = { "0001101", "0011001", "0010011", "0111101", "0100011",
                                         "0110001", "0101111", "0111011", "0110111", "0001011" };
        return QString::fromLatin1(codes[d]);
    }
    static QString rCode(int d)
    {
        QString s = lCode(d);
        for (QChar &c : s)
            c = c == '0' ? '1' : '0';
        return s;
    }
    static QString gCode(int d)
    {
        QString s = rCode(d);
        std::reverse(s.begin(), s.end());
        return s;
    }

    // The modules (1 = bar) of a code, quiet zones not included.
    static QString ean13Modules(const QString &code)
    {
        static const int parity[10] = { 0x00, 0x0B, 0x0D, 0x0E, 0x13, 0x19, 0x1C, 0x15, 0x16, 0x1A };
        const int p = parity[code.at(0).digitValue()];
        QString m = QStringLiteral("101");
        for (int i = 0; i < 6; ++i) {
            const int d = code.at(1 + i).digitValue();
            m += (p & (1 << (5 - i))) ? gCode(d) : lCode(d);
        }
        m += QStringLiteral("01010");
        for (int i = 0; i < 6; ++i)
            m += rCode(code.at(7 + i).digitValue());
        return m + QStringLiteral("101");
    }
    static QString ean8Modules(const QString &code)
    {
        QString m = QStringLiteral("101");
        for (int i = 0; i < 4; ++i)
            m += lCode(code.at(i).digitValue());
        m += QStringLiteral("01010");
        for (int i = 4; i < 8; ++i)
            m += rCode(code.at(i).digitValue());
        return m + QStringLiteral("101");
    }
    static QString upceModules(const QString &upce)
    {
        static const int parity[10] = { 0x38, 0x34, 0x32, 0x31, 0x2C, 0x26, 0x23, 0x2A, 0x29, 0x25 };
        const int system = upce.at(0).digitValue();
        int p = parity[upce.at(7).digitValue()];
        if (system == 1)
            p = ~p & 0x3F;
        QString m = QStringLiteral("101");
        for (int i = 0; i < 6; ++i) {
            const int d = upce.at(1 + i).digitValue();
            m += (p & (1 << (5 - i))) ? gCode(d) : lCode(d);
        }
        return m + QStringLiteral("010101");
    }

    // A picture of the modules: `module` pixels each, bars `height` high,
    // on a white label with quiet zones, on a grey background.
    static QImage draw(const QString &modules, int module, int height = 120)
    {
        const int quiet = 11 * module;
        QImage image(modules.size() * module + 2 * quiet + 200, height + 200, QImage::Format_RGB32);
        image.fill(QColor(110, 110, 110));
        QPainter painter(&image);
        painter.fillRect(100, 100, modules.size() * module + 2 * quiet, height, Qt::white);
        for (int i = 0; i < modules.size(); ++i) {
            if (modules.at(i) == '1')
                painter.fillRect(100 + quiet + i * module, 100, module, height, Qt::black);
        }
        return image;
    }

    static QImage noisy(QImage image, int amount, quint32 seed)
    {
        quint32 state = seed;
        for (int y = 0; y < image.height(); ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(image.scanLine(y));
            for (int x = 0; x < image.width(); ++x) {
                state = state * 1664525u + 1013904223u;
                const int n = int(state >> 24) % (2 * amount + 1) - amount;
                const int g = qBound(0, qGray(row[x]) + n, 255);
                row[x] = qRgb(g, g, g);
            }
        }
        return image;
    }

    // Light falling from the left: the right side much darker.
    static QImage shaded(QImage image)
    {
        for (int y = 0; y < image.height(); ++y) {
            QRgb *row = reinterpret_cast<QRgb *>(image.scanLine(y));
            for (int x = 0; x < image.width(); ++x) {
                const double f = 1.0 - 0.6 * x / image.width();
                const int g = int(qGray(row[x]) * f);
                row[x] = qRgb(g, g, g);
            }
        }
        return image;
    }

    // Out of focus: scaled down and up again.
    static QImage blurred(const QImage &image, double factor)
    {
        return image.scaled(int(image.width() / factor), int(image.height() / factor), Qt::IgnoreAspectRatio,
                            Qt::SmoothTransformation)
                .scaled(image.size(), Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    }

private slots:
    void checkDigits()
    {
        QCOMPARE(Barcode::checkDigit(QStringLiteral("640843000025")), 8);
        QCOMPARE(Barcode::checkDigit(QStringLiteral("9638507")), 4);
        QCOMPARE(Barcode::upceToUpca(QStringLiteral("04252614")), QStringLiteral("042100005264"));
        QCOMPARE(Barcode::upceToUpca(QStringLiteral("04252615")), QString());
    }

    void reads_data()
    {
        QTest::addColumn<QString>("modules");
        QTest::addColumn<QString>("expected");
        QTest::newRow("EAN-13") << ean13Modules(QStringLiteral("6408430000258")) << "6408430000258";
        QTest::newRow("EAN-13 first digit 0 (UPC-A)") << ean13Modules(QStringLiteral("0072250037129")) << "0072250037129";
        QTest::newRow("EAN-13 first digit 7") << ean13Modules(QStringLiteral("7394376621932")) << "7394376621932";
        QTest::newRow("EAN-8") << ean8Modules(QStringLiteral("96385074")) << "96385074";
        QTest::newRow("UPC-E") << upceModules(QStringLiteral("04252614")) << "0042100005264";
        QTest::newRow("UPC-E system 1") << upceModules(QStringLiteral("12345670")) << QString("0" + Barcode::upceToUpca(QStringLiteral("12345670")));
    }

    void reads()
    {
        QFETCH(QString, modules);
        QFETCH(QString, expected);
        const QImage plain = draw(modules, 3);
        QCOMPARE(Barcode::decode(plain), expected);
        // Small and large in the frame.
        QCOMPARE(Barcode::decode(draw(modules, 2)), expected);
        QCOMPARE(Barcode::decode(draw(modules, 7, 300)), expected);
        // Not a whole number of pixels per module.
        QCOMPARE(Barcode::decode(plain.scaled(plain.width() * 1.37, plain.height(), Qt::IgnoreAspectRatio,
                                              Qt::SmoothTransformation)), expected);
        // Sideways and upside down.
        QCOMPARE(Barcode::decode(plain.transformed(QTransform().rotate(90))), expected);
        QCOMPARE(Barcode::decode(plain.transformed(QTransform().rotate(180))), expected);
        // A real camera: soft focus, sensor noise, uneven light.
        QCOMPARE(Barcode::decode(noisy(blurred(draw(modules, 4), 1.8), 25, 7)), expected);
        QCOMPARE(Barcode::decode(shaded(draw(modules, 4))), expected);
    }

    void nothingWithoutABarcode()
    {
        QImage grey(640, 480, QImage::Format_RGB32);
        grey.fill(QColor(120, 120, 120));
        QCOMPARE(Barcode::decode(noisy(grey, 80, 3)), QString());
        // Stripes that only look like bars.
        QImage stripes(640, 480, QImage::Format_RGB32);
        stripes.fill(Qt::white);
        QPainter painter(&stripes);
        for (int x = 40; x < 600; x += 9)
            painter.fillRect(x, 0, 3 + (x / 9) % 4, 480, Qt::black);
        painter.end();
        QCOMPARE(Barcode::decode(stripes), QString());
        QCOMPARE(Barcode::decode(QImage()), QString());
        // A broken check digit isn't read as some other code.
        QString modules = ean13Modules(QStringLiteral("6408430000258"));
        QCOMPARE(Barcode::decode(draw(modules.left(modules.size() - 10) + rCode(9) + QStringLiteral("101"), 3)),
                 QString());
    }

    void fromQml()
    {
        BarcodeReader reader;
        QCOMPARE(reader.decode(QVariant::fromValue(draw(ean8Modules(QStringLiteral("96385074")), 3))),
                 QStringLiteral("96385074"));
        QCOMPARE(reader.decode(QVariant()), QString());
    }
};

QTEST_MAIN(TestBarcode)
#include "tst_barcode.moc"
