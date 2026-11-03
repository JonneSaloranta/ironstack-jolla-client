# Trying the app in the Sailfish OS Emulator

The emulator is a Sailfish OS virtual machine (VirtualBox) that ships with
the Sailfish SDK. It is the main way to try the app until there is a real
device to deploy to.

Everything below uses `sfdk`, the SDK's command line tool. It lives in
`~/SailfishOS/bin/sfdk`; a symlink in `~/.local/bin/sfdk` puts it on `PATH`.

## One-time setup

### 1. VirtualBox kernel module

The emulator needs VirtualBox's kernel module (`vboxdrv`). After a kernel
update it has to be rebuilt:

```bash
sudo /sbin/vboxconfig
lsmod | grep vboxdrv          # should print a line
```

If `vboxconfig` fails and `/var/log/vbox-setup.log` shows
`fatal error: VBox/cdefs.h: No such file or directory`, the installed
VirtualBox is too old for the running kernel (VirtualBox 7.1 doesn't build
on Linux 7.2; 7.2.22 does). Install a newer one from
<https://www.virtualbox.org/wiki/Linux_Downloads>, replacing the old package
in the same transaction, then rebuild:

```bash
sudo apt install ./virtualbox-7.2_<version>~Debian~bookworm_amd64.deb virtualbox-7.1-
sudo /sbin/vboxconfig
```

On Debian testing, the bookworm package is the one whose dependencies
resolve (the trixie one needs `libvpx9`, which testing no longer has).
Existing VMs, the Sailfish emulator included, are kept.

The build engine runs in Docker and does not need VirtualBox - only the
emulator does.

### 1b. Network between the build engine and the emulator

`sfdk deploy` copies the RPM from the Docker build engine to the emulator
(`10.220.220.1`). The engine container uses legacy iptables for that and
needs the host's `iptable_nat` module; without it, deploying times out with
`ssh: connect to host 10.220.220.1 port 22: Connection timed out`.

```bash
sudo modprobe iptable_nat
echo iptable_nat | sudo tee /etc/modules-load.d/sailfish-sdk.conf   # keep it after reboots
sudo ufw allow in on br-sfdk-$USER                                   # if ufw is enabled
```

Until that's done, `tools/emulator/emu.sh deploy` installs the RPM over the
emulator's host-side SSH port instead (see "Scripted testing" below).

### 2. Default build target and device

```bash
sfdk config --global target=SailfishOS-5.1.0.11-i486
sfdk config --global device="Sailfish OS Emulator 5.1.0.11"
```

The emulator is an x86 VM, so it always runs the **i486** build. The phone
uses **aarch64** (see "Building for a phone" below).

List what's installed with `sfdk tools list`, `sfdk emulator list` and
`sfdk device list`.

### 3. An IronStack instance to talk to

The app needs a running IronStack server. The simplest is the local
development one from the IronStack repository:

```bash
cd ~/Projektit/IronStack
docker compose up
```

Inside the emulator, the host machine is **`10.0.2.2`** (VirtualBox NAT), so
the local server is `http://10.0.2.2:8000`. `localhost` inside the emulator is
the emulator itself, not your computer.

Then create an API key in the IronStack web UI (on the host, at
<http://localhost:8000/api/keys/new/>):

| Context | Permissions |
|---|---|
| profile, exercises, programs, records, analytics | Read |
| workouts | Create, Read, Update, Delete |

Copy the key (`isk_...`) - it is shown only once.

## Everyday loop

```bash
cd ~/Projektit/ironstack-jolla-app
sfdk emulator start            # boots the VM and opens its window
sfdk build                     # builds RPMS/harbour-ironstack-*.i486.rpm
sfdk deploy --sdk              # installs the RPM in the emulator
```

Then open **IronStack** from the emulator's app grid. On the very first
launch Sailfish OS asks for the app's permission (Internet) -
tap **Accept**. Then enter `http://10.0.2.2:8000` as the server address and
paste the API key.

After a code change, run `sfdk build && sfdk deploy --sdk` again and restart
the app in the emulator (close it by swiping down from the top edge, or with
the cover's close button in the home screen).

Stop the emulator with `sfdk emulator stop` when done.

### Using the emulator

- Mouse drag = swipe. Swipe from the left or right edge to go home, drag down
  on a page to open its pull-down menu.
- The keyboard works for text fields.
- The emulator models a Jolla C2 by default; another screen size can be
  picked with `sfdk emulator set device-model="..."` (see
  `sfdk emulator device-model-list`) while it's stopped.

## Reading logs

The app's `console.log`, QML warnings and C++ `qWarning` go to the journal,
which needs root to read:

```bash
tools/emulator/emu.sh sh 'journalctl -f'
```

A QML error (a typo, a missing property) shows up there as
`file:///usr/share/harbour-ironstack/qml/...: <message>`, usually with a blank
or half-drawn page in the emulator.

For an interactive shell inside the emulator: `sfdk emulator exec -t bash`
(as `defaultuser`).

## Scripted testing

`tools/emulator/emu.sh` drives the emulator without touching it: install and
launch the app, tap and swipe, type, take screenshots. Useful for checking a
change end to end, or for UI screenshots.

```bash
sfdk emulator start
tools/emulator/emu.sh setup        # once per emulator boot: touch tool + app permissions
sfdk build
tools/emulator/emu.sh deploy       # install the newest i486 RPM and (re)launch
tools/emulator/emu.sh tap 360 306          # tap the server address field
tools/emulator/emu.sh type "http://10.0.2.2:8000"
tools/emulator/emu.sh shot login           # -> screenshots/login.png
tools/emulator/emu.sh launch fi_FI.utf8    # relaunch in Finnish
```

- Coordinates are pixels of the emulated screen (720x1600 on the default
  Jolla C2 model); a screenshot shows where things are.
- Taps and swipes come from a virtual touchscreen (`tools/emulator/touch.c`,
  built with the i486 target by `setup`). For gestures that need a pause in
  the middle, like holding a pull-down menu open for a screenshot, pipe raw
  commands to `emu.sh touch`:

  ```bash
  (echo "down 360 400"; for y in $(seq 420 20 720); do echo "move 360 $y"; done; echo "sleep 2000"; echo up) \
      | tools/emulator/emu.sh touch &
  sleep 3; tools/emulator/emu.sh shot pulley; wait
  ```

- Text goes in through VirtualBox's keyboard (`VBoxManage controlvm ...
  keyboardputstring`), so a text field has to be focused first.
- `setup` grants the app's sailjail permissions the way tapping "Accept" on
  the first-launch prompt would.
- `emu.sh warnings` lists the QML/JS warnings logged since the last launch -
  binding errors and the like that the compile test can't see. Worth a
  look after every UI change.
- `emu.sh shot` shows a "Screenshot captured" banner across the top of
  the screen for a few seconds, and that banner takes the taps there. A
  tap on a dialog's Save or Cancel right after a screenshot does nothing,
  which looks like an app bug. Wait about 5 s after a screenshot, or take
  it after the tap.
- `emu.sh warnings` only shows lines from the app's own files. Silica's
  messages, like "cannot push while transition is in progress", need
  `emu.sh sh "journalctl --since -5min -o cat"`.

### Checking themes, text size and orientation

A change to a page should be looked at in the settings users actually run:

```bash
tools/emulator/emu.sh ambience airy        # light theme; "ruska" is the dark default
tools/emulator/emu.sh fontsize gigantic    # normal, large, huge, gigantic
tools/emulator/emu.sh launch               # relaunch to pick them up
```

Landscape: stop the emulator, `sfdk emulator set orientation=landscape`, and
start it again. Every page except training mode follows the device's
orientation; training mode stays portrait on purpose (its controls are laid
out for a thumb). Put the emulator back with `orientation=portrait`,
`ambience ruska` and `fontsize normal` afterwards.

Last checked (0.1, Sailfish OS 5.1, Jolla C2 model): dark and light themes,
gigantic text and landscape all render without clipped or overlapping text.

## Faster QML iteration (optional)

For QML-only changes, Sailfish IDE (`~/SailfishOS/bin/qtcreator`) can run the
app in the emulator with QmlLive, reloading QML on save without a rebuild.
Open `harbour-ironstack.pro`, pick the i486 kit, and enable QmlLive from the
run settings. C++ changes still need a full build and deploy.

## Building for a phone

```bash
sfdk -c target=SailfishOS-5.1.0.11-aarch64 build
sfdk check RPMS/harbour-ironstack-*.aarch64.rpm     # Harbour validation
```

Copy the aarch64 RPM to a phone in developer mode and install it with
`pkcon install-local`, or add the phone as a device (`sfdk device list`,
Sailfish IDE > Options > Sailfish OS > Devices) and use `sfdk deploy --sdk`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `sfdk emulator start` fails with a VirtualBox / kernel driver error | `sudo /sbin/vboxconfig` (see setup step 1) |
| `Timeout connecting to the "sailfish-sdk-build-engine..." virtual machine` | The build engine was still starting; run the command again. `sfdk engine set ssh.timeout=90` makes it wait longer |
| `D-Bus connection failed ... dbus-nonce` warning | Harmless; `sfdk engine stop && sfdk engine start` clears it |
| App says "Could not reach the server" | Use `http://10.0.2.2:8000`, not `localhost`; check `docker compose ps` in IronStack |
| App says "The API key was not accepted" | The key was mistyped or revoked; create a new one |
| App says "This API key does not have permission for that" | The key is missing a permission from the table above |
| The app does not appear after deploy | Check `sfdk deploy --sdk` output; the RPM must be the i486 one |
| `sfdk deploy` times out connecting to `10.220.220.1` | Load `iptable_nat` (setup step 1b), or use `tools/emulator/emu.sh deploy` |
| App starts to a blank screen with a permission prompt behind it | Accept the sailjail prompt, or run `tools/emulator/emu.sh setup` |
