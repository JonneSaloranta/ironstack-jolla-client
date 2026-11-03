# Testing

Tests live in `tests/` and run headless inside the SDK build engine - no
emulator or device needed.

```bash
sfdk build-shell bash -c 'cd tests && qmake -qt=5 && make -s \
    && ./cpp/tst-cpp && ./qml/tst-qml -platform minimal'
```

### C++ (`tests/cpp`)

`tst_apiclient.cpp` runs `ApiClient` and `Settings` against a small fake
HTTP server on localhost:

- the API key goes only to the configured server - an absolute URL on
  another host, port or scheme is refused before any connection is made
- the Bearer header, request path and JSON body
- error messages for 400 (DRF validation shapes), 401, 403, 404, 429, 5xx
  and an unreachable server
- `unauthorized()` fires for the saved key only, not for a key being tried
  on the login page
- base URL normalization, logout, the offline cache and the session in
  progress surviving a restart - including calls made from JavaScript the
  way QML makes them (twice a JS object silently became an empty JSON
  document on the way into C++)
- `SyncQueue`: order, nothing lost without a connection or across a
  restart, retry on 5xx, a rejected request dropped and reported

### QML (`tests/qml`)

- `tst_compile.qml` compiles every QML file of the app. This catches syntax
  errors, unknown types, and properties that don't exist in the Qt/Silica
  version on the device (for example `Column.bottomPadding` needs
  `import QtQuick 2.6`; Sailfish OS ships Qt 5.6).
- `tst_store.qml` unit-tests the pure JavaScript helpers in
  `qml/js/store.js`: unit conversion, formatting, and the session rules
  shared by training mode and the full view (when an exercise is done,
  which one is next, what to prefill, merging queued sets in).

- `tst_progress.qml`: the Progress page's figures (`progress.js`) - weekly
  and muscle-group volume, records grouped by exercise, body measurement
  changes, the body tracking reminder.
- `tst_nutritionstats.qml`: nutrition statistics, the weight trend, observed
  maintenance and the calorie adjustment suggestion (`nutritionstats.js`;
  the expected figures are the ones IronStack's own `trends.py` gives for
  the same readings), and turning an Open Food Facts product into a food
  (`openfoodfacts.js`).
- `tst_nutrition.qml` and `tst_calculators.qml`: nutrition maths and the
  calculators.

A new page or component must be added to `tests/qml/tst_compile.qml`.

## One-time setup

The test runners link against QtTest and QtQuickTest, whose development
packages are not in the build target by default:

```bash
sfdk tools package-install SailfishOS-5.1.0.11-i486 \
    qt5-qttest-devel qt5-qtdeclarative-qtquicktest-devel
sfdk build-requires reset     # sync the build snapshot with the target
```

## What these tests don't cover

Compiling a component doesn't evaluate its bindings or talk to a server.
Behaviour against a real IronStack (login, logging sets, finishing a
session) is checked by hand in the emulator; see [EMULATOR.md](EMULATOR.md).
