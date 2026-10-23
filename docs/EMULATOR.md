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

If `vboxconfig` fails to compile against a very new kernel, the installed
VirtualBox is older than the kernel; install a newer VirtualBox from
<https://www.virtualbox.org/wiki/Linux_Downloads> and run it again.

The build engine runs in Docker and does not need VirtualBox - only the
emulator does.

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

Then open **IronStack** from the emulator's app grid. On the first launch,
enter `http://10.0.2.2:8000` as the server address and paste the API key.

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

The app's `console.log`, QML warnings and C++ `qWarning` go to the journal.
Follow it while using the app:

```bash
sfdk emulator exec -t journalctl -f
```

Or start the app from the command line to see its output directly (close
the copy running in the emulator first):

```bash
sfdk emulator exec -t harbour-ironstack
```

For an interactive shell inside the emulator: `sfdk emulator exec -t bash`.

A QML error (a typo, a missing property) shows up there as
`file:///usr/share/harbour-ironstack/qml/...: <message>`, usually with a blank
or half-drawn page in the emulator.

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
