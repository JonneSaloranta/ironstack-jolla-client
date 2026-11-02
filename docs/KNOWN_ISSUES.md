# Known issues

Open problems found while testing. Remove an entry when it's fixed.

## Record subtitle cuts off the date

**Seen on:** Jolla Phone (2026), Sailfish OS 5.2.0.22, Finnish, default
text size, portrait. Dashboard > "Viimeisimmät ennätykset" (also affects
the Records page, which uses the same `RecordItem`).

The second line of a record row is built from three parts:
record type, weight x reps and the achievement date, e.g.

> Toistokohtainen ennätys (12RM) - 20 kg x 12 - 1. marraskuuta 2026

In Finnish this is wider than the screen. The label uses
`TruncationMode.Fade` (`qml/components/RecordItem.qml`), so the end
fades out and the year is lost ("1. marraskuuta 202"). The date is the
part that gets cut because it comes last, and Finnish month names
written out (`Formatter.DateMedium`) are long. Shorter rows on the same
screen fit.

**Possible fixes:**
- Let the subtitle wrap (`wrapMode: Text.Wrap`); the row already grows
  with its content.
- Or move the date onto its own line or use a shorter date format
  (`Formatter.DateMediumWithoutYear` for the current year,
  `DateFull`/numeric otherwise).
- Check the same in landscape and with a larger text size.
