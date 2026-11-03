#include "barcode.h"

#include <QHash>
#include <algorithm>
#include <cmath>

namespace {

// A digit's four run widths, in modules, as seen from left to right: L
// (odd parity) codes start with a space, R codes have the same widths
// starting with a bar, and G (even parity) codes are L reversed.
const int L_PATTERNS[10][4] = {
    { 3, 2, 1, 1 }, { 2, 2, 2, 1 }, { 2, 1, 2, 2 }, { 1, 4, 1, 1 }, { 1, 1, 3, 2 },
    { 1, 2, 3, 1 }, { 1, 1, 1, 4 }, { 1, 3, 1, 2 }, { 1, 2, 1, 3 }, { 3, 1, 1, 2 },
};

// EAN-13's first digit, from which of the left six digits are G codes
// (bit 5 = the first of them).
const int FIRST_DIGIT_PARITY[10] = { 0x00, 0x0B, 0x0D, 0x0E, 0x13, 0x19, 0x1C, 0x15, 0x16, 0x1A };

// UPC-E's check digit (number system 0) from its six digits' parity; the
// same bits inverted for number system 1.
const int UPCE_PARITY[10] = { 0x38, 0x34, 0x32, 0x31, 0x2C, 0x26, 0x23, 0x2A, 0x29, 0x25 };

// ZXing's limits: how far runs may be from the pattern, per module, on
// average and for any one run.
const double MAX_AVG_VARIANCE = 0.48;
const double MAX_INDIVIDUAL_VARIANCE = 0.7;

// How far `counts` (pixels) are from `pattern` (modules), or a large value
// when they don't fit at all. 0 = exact.
double variance(const int *counts, const int *pattern, int length)
{
    double total = 0;
    double modules = 0;
    for (int i = 0; i < length; ++i) {
        total += counts[i];
        modules += pattern[i];
    }
    if (total < modules)
        return 1e9;
    const double unit = total / modules;
    const double maxIndividual = MAX_INDIVIDUAL_VARIANCE * unit;
    double sum = 0;
    for (int i = 0; i < length; ++i) {
        const double diff = std::fabs(counts[i] - pattern[i] * unit);
        if (diff > maxIndividual)
            return 1e9;
        sum += diff;
    }
    return sum / total;
}

const int GUARD[3] = { 1, 1, 1 };
const int MIDDLE[5] = { 1, 1, 1, 1, 1 };
const int UPCE_END[6] = { 1, 1, 1, 1, 1, 1 };

bool matches(const std::vector<int> &runs, int at, const int *pattern, int length)
{
    if (at < 0 || at + length > int(runs.size()))
        return false;
    return variance(&runs[at], pattern, length) < MAX_AVG_VARIANCE;
}

// The digit at runs[at..at+3]: 0-9 for an L (or R) code, 10-19 for a G
// code (only with `withG`), -1 for none.
int digitAt(const std::vector<int> &runs, int at, bool withG)
{
    if (at + 4 > int(runs.size()))
        return -1;
    double best = MAX_AVG_VARIANCE;
    int found = -1;
    for (int d = 0; d < 10; ++d) {
        double v = variance(&runs[at], L_PATTERNS[d], 4);
        if (v < best) {
            best = v;
            found = d;
        }
        if (!withG)
            continue;
        const int reversed[4] = { L_PATTERNS[d][3], L_PATTERNS[d][2], L_PATTERNS[d][1], L_PATTERNS[d][0] };
        v = variance(&runs[at], reversed, 4);
        if (v < best) {
            best = v;
            found = d + 10;
        }
    }
    return found;
}

// A quiet zone: a white run at least about as wide as a guard - or the
// edge of the line.
bool quietAt(const std::vector<int> &runs, int at, int guardWidth)
{
    if (at < 0 || at >= int(runs.size()))
        return true;
    return runs[at] * 2 >= guardWidth;
}

QString ean13At(const std::vector<int> &runs, int start)
{
    int at = start + 3;
    QString digits;
    int parity = 0;
    for (int i = 0; i < 6; ++i, at += 4) {
        const int d = digitAt(runs, at, true);
        if (d < 0)
            return QString();
        if (d >= 10)
            parity |= 1 << (5 - i);
        digits += QChar('0' + d % 10);
    }
    if (!matches(runs, at, MIDDLE, 5))
        return QString();
    at += 5;
    for (int i = 0; i < 6; ++i, at += 4) {
        const int d = digitAt(runs, at, false);
        if (d < 0)
            return QString();
        digits += QChar('0' + d);
    }
    if (!matches(runs, at, GUARD, 3))
        return QString();
    int first = -1;
    for (int d = 0; d < 10; ++d) {
        if (FIRST_DIGIT_PARITY[d] == parity)
            first = d;
    }
    if (first < 0)
        return QString();
    const QString code = QChar('0' + first) + digits;
    return Barcode::checkDigit(code.left(12)) == code.at(12).digitValue() ? code : QString();
}

QString ean8At(const std::vector<int> &runs, int start, int guardWidth)
{
    int at = start + 3;
    QString digits;
    for (int i = 0; i < 4; ++i, at += 4) {
        const int d = digitAt(runs, at, false);
        if (d < 0)
            return QString();
        digits += QChar('0' + d);
    }
    if (!matches(runs, at, MIDDLE, 5))
        return QString();
    at += 5;
    for (int i = 0; i < 4; ++i, at += 4) {
        const int d = digitAt(runs, at, false);
        if (d < 0)
            return QString();
        digits += QChar('0' + d);
    }
    if (!matches(runs, at, GUARD, 3) || !quietAt(runs, at + 3, guardWidth))
        return QString();
    return Barcode::checkDigit(digits.left(7)) == digits.at(7).digitValue() ? digits : QString();
}

QString upceAt(const std::vector<int> &runs, int start, int guardWidth)
{
    int at = start + 3;
    QString digits;
    int parity = 0;
    for (int i = 0; i < 6; ++i, at += 4) {
        const int d = digitAt(runs, at, true);
        if (d < 0)
            return QString();
        if (d >= 10)
            parity |= 1 << (5 - i);
        digits += QChar('0' + d % 10);
    }
    if (!matches(runs, at, UPCE_END, 6) || !quietAt(runs, at + 6, guardWidth))
        return QString();
    for (int system = 0; system < 2; ++system) {
        for (int check = 0; check < 10; ++check) {
            const int expected = system == 0 ? UPCE_PARITY[check] : (~UPCE_PARITY[check] & 0x3F);
            if (expected != parity)
                continue;
            const QString upca = Barcode::upceToUpca(QChar('0' + system) + digits + QChar('0' + check));
            return upca.isEmpty() ? QString() : QStringLiteral("0") + upca;
        }
    }
    return QString();
}

// Black and white runs of a line against `threshold` per pixel, starting
// with a white run (0 wide if the line starts black).
std::vector<int> runsOf(const std::vector<int> &luminance, const std::vector<int> &threshold)
{
    std::vector<int> runs;
    bool black = false;
    int count = 0;
    for (size_t i = 0; i < luminance.size(); ++i) {
        const bool pixelBlack = luminance[i] < threshold[i];
        if (pixelBlack != black) {
            runs.push_back(count);
            black = pixelBlack;
            count = 0;
        }
        ++count;
    }
    runs.push_back(count);
    return runs;
}

QString decodeRuns(const std::vector<int> &runs)
{
    // Odd runs are black: a start guard begins with a bar.
    for (int i = 1; i + 2 < int(runs.size()); i += 2) {
        if (!matches(runs, i, GUARD, 3))
            continue;
        const int guardWidth = runs[i] + runs[i + 1] + runs[i + 2];
        if (!quietAt(runs, i - 1, guardWidth))
            continue;
        QString code = ean13At(runs, i);
        if (code.isEmpty())
            code = ean8At(runs, i, guardWidth);
        if (code.isEmpty())
            code = upceAt(runs, i, guardWidth);
        if (!code.isEmpty())
            return code;
    }
    return QString();
}

QString decodeOneWay(const std::vector<int> &luminance)
{
    const int n = int(luminance.size());
    if (n < 40)
        return QString();
    // Against the local average: copes with light falling unevenly.
    std::vector<long> sums(n + 1, 0);
    for (int i = 0; i < n; ++i)
        sums[i + 1] = sums[i] + luminance[i];
    const int half = std::max(8, n / 20);
    std::vector<int> local(n);
    for (int i = 0; i < n; ++i) {
        const int from = std::max(0, i - half);
        const int to = std::min(n, i + half + 1);
        local[i] = int((sums[to] - sums[from]) / (to - from));
    }
    QString code = decodeRuns(runsOf(luminance, local));
    if (!code.isEmpty())
        return code;
    // Against the middle of the line's range: copes with wide bars.
    int lo = 255, hi = 0;
    for (int value : luminance) {
        lo = std::min(lo, value);
        hi = std::max(hi, value);
    }
    if (hi - lo < 24)
        return QString();
    return decodeRuns(runsOf(luminance, std::vector<int>(n, (lo + hi) / 2)));
}

} // namespace

namespace Barcode {

int checkDigit(const QString &body)
{
    int sum = 0;
    // From the right: the last digit of the body is weighted 3.
    for (int i = 0; i < body.size(); ++i) {
        const int digit = body.at(body.size() - 1 - i).digitValue();
        sum += digit * (i % 2 == 0 ? 3 : 1);
    }
    return (10 - sum % 10) % 10;
}

QString upceToUpca(const QString &upce)
{
    if (upce.size() != 8)
        return QString();
    const QString d = upce.mid(1, 6);
    const QChar last = d.at(5);
    QString body = upce.left(1);
    switch (last.digitValue()) {
    case 0:
    case 1:
    case 2:
        body += d.left(2) + last + QStringLiteral("0000") + d.mid(2, 3);
        break;
    case 3:
        body += d.left(3) + QStringLiteral("00000") + d.mid(3, 2);
        break;
    case 4:
        body += d.left(4) + QStringLiteral("00000") + d.mid(4, 1);
        break;
    default:
        body += d.left(5) + QStringLiteral("0000") + last;
        break;
    }
    if (checkDigit(body) != upce.at(7).digitValue())
        return QString();
    return body + upce.at(7);
}

QString decodeLine(const std::vector<int> &luminance)
{
    QString code = decodeOneWay(luminance);
    if (!code.isEmpty())
        return code;
    return decodeOneWay(std::vector<int>(luminance.rbegin(), luminance.rend()));
}

QString decode(const QImage &source)
{
    if (source.isNull())
        return QString();
    QImage image = source.convertToFormat(QImage::Format_RGB32);
    // A phone camera's frame is far more than a barcode needs.
    if (image.width() > 1280 || image.height() > 1280)
        image = image.scaled(1280, 1280, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    const int w = image.width();
    const int h = image.height();

    QHash<QString, int> votes;
    const int lines = 15;
    for (int k = 0; k < lines; ++k) {
        const double at = 0.15 + 0.7 * k / (lines - 1);
        const int y = int(at * (h - 1));
        const QRgb *row = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        std::vector<int> luminance(w);
        for (int x = 0; x < w; ++x)
            luminance[x] = qGray(row[x]);
        QString code = decodeLine(luminance);
        if (!code.isEmpty())
            votes[code]++;

        const int x = int(at * (w - 1));
        std::vector<int> column(h);
        for (int yy = 0; yy < h; ++yy)
            column[yy] = qGray(reinterpret_cast<const QRgb *>(image.constScanLine(yy))[x]);
        code = decodeLine(column);
        if (!code.isEmpty())
            votes[code]++;
    }

    QString best;
    int bestVotes = 1;
    for (auto it = votes.constBegin(); it != votes.constEnd(); ++it) {
        if (it.value() > bestVotes) {
            best = it.key();
            bestVotes = it.value();
        }
    }
    return best;
}

} // namespace Barcode

QString BarcodeReader::decode(const QVariant &image) const
{
    return Barcode::decode(image.value<QImage>());
}
