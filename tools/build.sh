#!/bin/bash
# Build the RPM outside the source tree, one directory per architecture, so
# emulator (i486) and phone (aarch64) objects never mix:
#
#   tools/build.sh            # i486, for the emulator
#   tools/build.sh aarch64    # a phone
#   tools/build.sh armv7hl    # an older 32-bit phone
#
# The RPM lands in ../build-ironstack-<arch>/RPMS/. `tools/emulator/emu.sh
# deploy` installs the newest i486 one; for a phone, copy the aarch64 one
# over and install it with `devel-su rpm -Uvh`. Extra arguments go to
# `sfdk build`.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SDK=${SAILFISH_SDK:-$HOME/SailfishOS}
ARCH=${1:-i486}
[ $# -gt 0 ] && shift
TARGET=$("$SDK/bin/sfdk" tools target list 2>/dev/null | awk '{print $1}' | grep -- "-$ARCH\$" | sort -V | tail -1)
if [ -z "$TARGET" ]; then
    echo "No $ARCH build target installed (sfdk tools target list)." >&2
    exit 1
fi

# qmake refuses a shadow build next to an in-tree one.
if [ -e "$ROOT/Makefile" ] || [ -e "$ROOT/.qmake.stash" ]; then
    echo "The source tree holds an in-tree build (Makefile, .qmake.stash);" >&2
    echo "remove it first: git -C '$ROOT' clean -fdX -- '*.o' 'moc_*' Makefile .qmake.stash harbour-ironstack documentation.list RPMS 'translations/*.qm'" >&2
    exit 1
fi

OUT="$(dirname "$ROOT")/build-ironstack-$ARCH"
mkdir -p "$OUT"
cd "$OUT"
"$SDK/bin/sfdk" -c target="$TARGET" build "$@" "$ROOT"
ls -t "$OUT"/RPMS/harbour-ironstack-*."$ARCH".rpm | head -1
