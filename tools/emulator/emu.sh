#!/bin/bash
# Drive the Sailfish OS emulator from the command line: install the app,
# launch it, tap/swipe, type, and take screenshots. See docs/EMULATOR.md
# "Scripted testing".
#
#   tools/emulator/emu.sh setup              # once per emulator boot
#   tools/emulator/emu.sh deploy             # install RPMS/*.i486.rpm and (re)launch
#   tools/emulator/emu.sh launch [LANG]      # (re)launch, e.g. launch fi_FI.utf8
#   tools/emulator/emu.sh wake               # screen on, unlocked
#   tools/emulator/emu.sh tap X Y
#   tools/emulator/emu.sh swipe X1 Y1 X2 Y2 [MS]
#   tools/emulator/emu.sh type "text"
#   tools/emulator/emu.sh shot NAME          # -> screenshots/NAME.png
#   tools/emulator/emu.sh touch < commands   # raw touch commands (see touch.c)
#   tools/emulator/emu.sh warnings           # QML/JS warnings since the last launch
#   tools/emulator/emu.sh sh "command"       # run a command in the emulator as root
#
# Coordinates are screen pixels of the emulated device (720x1600 for the
# default Jolla C2 model). Needs the emulator running (sfdk emulator start).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SDK=${SAILFISH_SDK:-$HOME/SailfishOS}
VM=${EMULATOR_VM:-$(VBoxManage list runningvms | sed -n 's/^"\(SailfishOS-[^"]*\)".*/\1/p' | head -1)}
KEY=$SDK/vmshare/ssh/private_keys/sdk
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
          -o ConnectTimeout=15 -i "$KEY")
SHOTS=${SCREENSHOT_DIR:-$ROOT/screenshots}
USER_ENV='XDG_RUNTIME_DIR=/run/user/100000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket'

emu() { ssh "${SSH_OPTS[@]}" -p 2223 root@127.0.0.1 "$@"; }
push() { scp "${SSH_OPTS[@]}" -P 2223 "$1" "root@127.0.0.1:$2" >/dev/null; }
as_user() { echo "runuser -u defaultuser -- env $USER_ENV $*"; }

# Screen on and unlocked - after a while the emulator locks itself like a
# phone, and taps then land on the lock screen instead of the app.
wake() {
    emu 'dbus-send --system --print-reply --dest=com.nokia.mce /com/nokia/mce/request \
           com.nokia.mce.request.req_display_state_on >/dev/null
         dbus-send --system --print-reply --dest=com.nokia.mce /com/nokia/mce/request \
           com.nokia.mce.request.req_tklock_mode_change string:unlocked >/dev/null'
}

launch() {
    wake
    local lang=${1:-}
    local env_opt=""
    [ -n "$lang" ] && env_opt="-E LANG=$lang"
    # Anchored patterns: an unanchored "harbour-ironstack" would also match
    # this ssh session's own command line and kill it.
    emu "pkill -f '^/usr/bin/harbour-ironstack' || true; sleep 1
         date '+%Y-%m-%d %H:%M:%S' > /tmp/harbour-ironstack-launched
         $(as_user systemctl --user stop ironstack-e2e) 2>/dev/null || true
         $(as_user systemd-run --user --unit=ironstack-e2e --collect $env_opt \
             sailjail -p harbour-ironstack.desktop -- /usr/bin/harbour-ironstack) >/dev/null 2>&1
         sleep 6"
}

case "${1:-}" in
setup)
    # Build the touch tool with the i486 target and copy it over.
    mkdir -p "$HOME/.cache/harbour-ironstack-emu"
    cp "$ROOT/tools/emulator/touch.c" "$HOME/.cache/harbour-ironstack-emu/"
    (cd "$ROOT" && "$SDK/bin/sfdk" build-shell bash -c \
        "gcc -O2 -std=gnu99 -o $HOME/.cache/harbour-ironstack-emu/touch $HOME/.cache/harbour-ironstack-emu/touch.c")
    push "$HOME/.cache/harbour-ironstack-emu/touch" /root/touch
    # Grant the app's sailjail permissions (what tapping "Accept" on the
    # first-launch prompt does).
    perms=$(sed -n 's/^Permissions=//p' "$ROOT/harbour-ironstack.desktop");
    perms="${perms%;};"
    emu "F=/home/.system/var/lib/sailjail/settings/user-100000.settings
         systemctl stop sailjaild
         sed -i '/^\[harbour-ironstack\]/,/^Permissions=/d' \$F 2>/dev/null || true
         printf '[harbour-ironstack]\nAllowed=1\nAgreed=1\nAutogrant=0\nGranted=$perms\nPermissions=$perms\n' >> \$F
         systemctl start sailjaild"
    echo "ready"
    ;;
deploy)
    rpm=$(ls -t "$ROOT"/RPMS/harbour-ironstack-*.i486.rpm | head -1)
    push "$rpm" /tmp/harbour-ironstack.rpm
    emu 'rpm -Uvh --force /tmp/harbour-ironstack.rpm >/dev/null'
    launch "${2:-}"
    echo "deployed $(basename "$rpm")"
    ;;
launch) launch "${2:-}" ;;
wake) wake ;;
tap) printf 'tap %d %d\nsleep 500\n' "$2" "$3" | emu /root/touch ;;
swipe) printf 'swipe %d %d %d %d %d\nsleep 500\n' "$2" "$3" "$4" "$5" "${6:-300}" | emu /root/touch ;;
touch) emu /root/touch ;;
type) VBoxManage controlvm "$VM" keyboardputstring "$2" ;;
shot)
    mkdir -p "$SHOTS"
    emu "rm -f /home/defaultuser/Pictures/$2.png
         runuser -u defaultuser -g privileged -- env $USER_ENV \
           dbus-send --session --print-reply --dest=org.nemomobile.lipstick \
           /org/nemomobile/lipstick/screenshot org.nemomobile.lipstick.saveScreenshot \
           string:/home/defaultuser/Pictures/$2.png >/dev/null"
    scp "${SSH_OPTS[@]}" -P 2223 "root@127.0.0.1:/home/defaultuser/Pictures/$2.png" "$SHOTS/" >/dev/null
    echo "$SHOTS/$2.png"
    ;;
warnings)
    # Runtime problems the compile test can't see: bad bindings, unknown
    # signal handlers, type errors in JS.
    emu 'journalctl --no-pager -o cat --since "$(cat /tmp/harbour-ironstack-launched)" \
         | grep "/usr/share/harbour-ironstack/" | sort | uniq -c' || true
    ;;
sh) shift; emu "$@" ;;
*) sed -n '2,20p' "$0"; exit 1 ;;
esac
