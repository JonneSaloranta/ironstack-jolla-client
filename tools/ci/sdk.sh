#!/bin/bash
# Runs inside the Sailfish SDK container (coderus/sailfishos-platform-sdk,
# see .github/workflows/ci.yml) with the checkout mounted at /share:
#
#   tools/ci/sdk.sh build ARCH    # the RPM, into /share/out/
#   tools/ci/sdk.sh test          # tests/ in the i486 target
#
# The checkout is copied first: the container's user (mersdk) can't write
# to the runner's files, and a build must not leave anything in the tree.
set -euo pipefail

RELEASE=${SFOS_RELEASE:?set SFOS_RELEASE, e.g. 5.1.0.11}
SRC=$HOME/src
rm -rf "$SRC"
cp -r /share "$SRC"
cd "$SRC"

case "${1:-}" in
build)
    ARCH=${2:?arch}
    TARGET=SailfishOS-$RELEASE-$ARCH
    # A shadow build, like tools/build.sh.
    mkdir -p "$HOME/build-$ARCH"
    cd "$HOME/build-$ARCH"
    # The version is VERSION's, not one mb2 derives from a git tag.
    mb2 -t "$TARGET" --no-fix-version build "$SRC"
    mkdir -p /share/out
    cp RPMS/harbour-ironstack-*."$ARCH".rpm /share/out/
    ls -l /share/out
    ;;
test)
    TARGET=SailfishOS-$RELEASE-i486
    # Not in the build target by default (docs/TESTING.md).
    sb2 -t "$TARGET" -m sdk-install -R zypper --non-interactive in \
        qt5-qttest-devel qt5-qtdeclarative-qtquicktest-devel sailfishshare-components
    # The app's own build dependencies, as the spec lists them.
    sb2 -t "$TARGET" -m sdk-install -R zypper --non-interactive in \
        $(sed -n 's/^BuildRequires: *//p' rpm/harbour-ironstack.spec | sed 's/ *>=.*//' | tr '\n' ' ')
    sb2 -t "$TARGET" bash -c 'cd tests && qmake -qt=5 && make -s \
        && ./cpp/tst-cpp && ./barcode/tst-barcode -platform minimal \
        && ./qml/tst-qml -platform minimal'
    ;;
*)
    sed -n '2,9p' "$0"
    exit 1
    ;;
esac
