# Releasing

The version lives in one place, the repo-root `VERSION` file (`X.Y.Z`).
The RPM spec reads it (`Version: %(cat %{_sourcedir}/../VERSION)`), the
spec passes it to qmake, and the app shows it (`APP_VERSION`, e.g. in
the app log's report). A plain `qmake` run reads the file itself.

## A new version

1. On a branch, bump `VERSION` and add a section to `CHANGELOG.md`:
   `## [X.Y.Z] - YYYY-MM-DD` and what changed for someone using the app.
   A new version is needed for every package that goes to a phone, so
   `rpm -Uvh` upgrades without `--force`.
2. Open a pull request into master. CI (`.github/workflows/ci.yml`) runs
   the tests and builds the aarch64, armv7hl and i486 RPMs.
3. Merge it. On master, CI does the same again and, since `vX.Y.Z` has no
   release yet, publishes one: tag `vX.Y.Z` on that commit, the three
   RPMs attached, and notes made of the CHANGELOG.md section followed by
   every commit since the previous release, grouped by type
   (`tools/ci/release_notes.py`).

A merge that doesn't bump `VERSION` builds and tests but publishes
nothing. If the release job fails, the next green push to master
publishes it - it asks whether `vX.Y.Z` exists rather than whether
`VERSION` changed.

## CI

- The SDK is coderus's `sailfishos-platform-sdk` image for the app's
  Sailfish OS release (`SFOS_RELEASE`, 5.1.0.11 like the local SDK), pinned
  by digest. `tools/ci/sdk.sh` runs inside it: `build ARCH` makes the RPM
  out of tree, `test` installs the test packages into the i486 target
  (docs/TESTING.md) and runs `tests/`.
- Actions are pinned by commit SHA; Dependabot proposes updates weekly.
- To move to a newer SDK: change `SFOS_RELEASE` and the image's tag and
  digest together, then check the RPM on a phone.

Not in CI: the Harbour check. Run it locally on the aarch64 RPM before a
store upload:
`sfdk -c target=SailfishOS-5.1.0.11-aarch64 check <rpm>` (without the
target it runs the i486 objdump and fails).
