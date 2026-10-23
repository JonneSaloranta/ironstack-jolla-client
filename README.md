# IronStack for Sailfish OS

Native Sailfish OS client (`harbour-ironstack`) for a self-hosted
[IronStack](https://github.com/JonneSaloranta/ironstack) instance. Silica
QML UI, a small C++ layer for networking and settings. Talks to IronStack's
REST API (`/api/v1/`) with a per-user API key.

## Features (0.1)

- Connect with a server address and API key
- Dashboard: last 7 days, workout in progress, recent PRs
- Programs and workouts, start a session from a workout or freeform
- Training mode: one exercise at a time, big +/- steppers, one tap to log
  a set, prefilled from the previous set, last time or the program target;
  moves on to the next exercise by itself, swipe to go anywhere
- Works without a connection: sets and finishing a workout are saved on
  the phone and sent when the server can be reached; a workout in
  progress can be opened and continued offline
- Full view of a session for corrections: edit and delete sets, add
  exercises, finish or abandon
- Rest timer with a notification, also with the screen off
- History and personal records
- Cover shows the workout in progress and its duration
- Metric or imperial display, following the IronStack profile setting

## API key

Create one in IronStack under Profile > API keys with:

| Context | Permissions |
|---|---|
| profile, exercises, programs, records, analytics | Read |
| workouts | Create, Read, Update, Delete |

## Building

Requires the [Sailfish SDK](https://docs.sailfishos.org/Tools/Sailfish_SDK/).

```bash
sfdk config target=SailfishOS-<version>-i486     # emulator
sfdk build
sfdk config device="Sailfish OS Emulator <version>"
sfdk deploy --sdk

sfdk -c target=SailfishOS-<version>-aarch64 build  # phone
sfdk check RPMS/*.rpm                             # Harbour validation
```

See [docs/EMULATOR.md](docs/EMULATOR.md) for setting up and using the
emulator to try the app, including connecting it to a local IronStack.

## Tests

Headless QML tests run inside the SDK build engine; see
[docs/TESTING.md](docs/TESTING.md).

## Server-side gaps

Features that need IronStack API changes are tracked as issues labelled
[`mobile-client`](https://github.com/JonneSaloranta/ironstack/issues?q=label%3Amobile-client)
in the IronStack repository.

## License

AGPL-3.0, same as IronStack.
