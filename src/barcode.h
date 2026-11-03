#ifndef BARCODE_H
#define BARCODE_H

#include <QImage>
#include <QObject>
#include <QString>
#include <QVariant>
#include <vector>

// Reading the barcodes found on food packages - EAN-13 (UPC-A included),
// EAN-8 and UPC-E - from a camera image, for an Open Food Facts lookup.
// Written here rather than bundling a barcode library: these three are
// all a food product carries, and they're small enough to decode and test
// in full.
//
// An image is read along several horizontal and vertical lines, both
// ways round, so the code can be held sideways or upside down. Each line
// is turned into black and white runs against its local average
// brightness, and every place that starts like a barcode (a quiet zone,
// then bar-space-bar of equal width) is tried as each of the three kinds;
// a digit is the pattern its four runs match best, the way ZXing reads
// them. A result counts only if its check digit is right and at least two
// lines agree, so a single misread line isn't enough.
namespace Barcode {

// The code on one line of luminance values (0-255), or "" - an EAN-13 or
// UPC-E (expanded to its UPC-A form, with a leading 0) as 13 digits, an
// EAN-8 as 8.
QString decodeLine(const std::vector<int> &luminance);

// The code most lines of `image` agree on (at least two), or "".
QString decode(const QImage &image);

// The check digit of an EAN/UPC body (all digits but the last).
int checkDigit(const QString &body);

// UPC-E's 8 digits (number system, 6 digits, check) as UPC-A's 12, or ""
// when it isn't a valid UPC-E.
QString upceToUpca(const QString &upce);

} // namespace Barcode

// For QML: the scanner page grabs the viewfinder now and then and asks
// this for a code.
class BarcodeReader : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;
    // `image` is a QImage, as QQuickItemGrabResult.image gives it.
    Q_INVOKABLE QString decode(const QVariant &image) const;
};

#endif
