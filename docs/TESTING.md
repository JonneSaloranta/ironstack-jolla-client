# Testing

QML tests live in `tests/` and run headless inside the SDK build engine -
no emulator or device needed.

```bash
sfdk build-shell bash -c 'cd tests && qmake -qt=5 && make -s && ./tst-harbour-ironstack -platform minimal'
```

- `tst_compile.qml` compiles every QML file of the app. This catches syntax
  errors, unknown types, and properties that don't exist in the Qt/Silica
  version on the device (for example `Column.bottomPadding` needs
  `import QtQuick 2.6`; Sailfish OS ships Qt 5.6).
- `tst_store.qml` unit-tests the pure JavaScript helpers in
  `qml/js/store.js` (unit conversion, formatting, caches).

A new page or component must be added to `tst_compile.qml`.

## One-time setup

The test runner links against QtQuickTest, whose development package is not
in the build target by default:

```bash
sfdk tools package-install SailfishOS-5.1.0.11-i486 qt5-qtdeclarative-qtquicktest-devel
sfdk build-requires reset     # sync the build snapshot with the target
```

## What these tests don't cover

Compiling a component doesn't evaluate its bindings or talk to a server.
Behaviour against a real IronStack (login, logging sets, finishing a
session) is checked by hand in the emulator; see [EMULATOR.md](EMULATOR.md).
