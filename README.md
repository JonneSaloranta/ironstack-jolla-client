# IronStack for Sailfish OS

Native Sailfish OS client (`harbour-ironstack`) for a self-hosted
[IronStack](https://github.com/JonneSaloranta/ironstack) instance. Silica
QML UI, a small C++ layer for networking and settings. Talks to IronStack's
REST API (`/api/v1/`) with a per-user API key; needs IronStack 1.31.0 or
later. Exercise images, "this week", duration estimates and the trainer
switches need IronStack's next release (its dev branch today).

## Features (0.1)

- Connect with a server address and API key
- Dashboard: workout in progress or up next, this week or the last 7
  days, recent PRs, achievements
- Programs and workouts with how long each takes, start a session from a
  workout or freeform; your own exercises with images from the gallery
- Training mode: one exercise at a time, big +/- steppers, one tap to log
  a set, prefilled from the previous set, last time or the program target;
  moves on to the next exercise by itself, swipe to go anywhere; the time
  left beside the time spent
- Works without a connection: sets, finishing a workout, diary entries,
  body measurements, activities and stretching are saved on the phone and
  sent when the server can be reached; a workout in progress can be opened
  and continued offline
- Smart weight suggestion and last time's sets for each exercise, as on
  the web
- In English, Finnish, Swedish, Estonian, Italian and Russian - the web's
  languages
- Built-in exercise, program and workout names in the phone's language,
  with the same translations as the web
- Full view of a session for corrections: edit and delete sets, add
  exercises, finish or abandon
- Rest timer with a notification, also with the screen off
- History and personal records; a Progress page like the web's (volume
  per week and muscle group, records, body measurement changes)
- Nutrition: food diary, foods (also from Open Food Facts by name or
  barcode, through the server; the barcode also with the camera), recipes, diet plans, goals, statistics,
  observed maintenance and whether your calorie target is working, with
  the suggested adjustment one tap away
- Body measurements with a reminder after 14 days, activities, and
  stretching with a guided, chiming timer; a cool-down suggested after a
  workout
- Friends, groups and messages; coaching (ask a trainer, shared plans,
  a trainer's clients, becoming a trainer); the AI assistant, which can
  also suggest recipes; the web's guided tours as a
  guide
- Cover shows the workout in progress and its duration; otherwise today's
  calories and protein against the target, with a quick entry action
- Metric or imperial display, following the IronStack profile setting
- An app log (Settings > Troubleshooting) to copy or share when something
  goes wrong, from errors only up to every request

## API key

Create one in IronStack under Profile > API keys with:

| Context | Permissions | Used for |
|---|---|---|
| profile | Read, Update | Units, settings |
| exercises | Create, Read, Update, Delete | Exercise library, your own exercises |
| programs | Create, Read, Update, Delete | Programs, up next, editing your programs |
| workouts | Create, Read, Update, Delete | Logging workouts |
| records, analytics | Read | Records, stats, achievements |
| measurements | Create, Read, Update, Delete | Body measurements |
| activities | Create, Read, Update, Delete | Activities |
| nutrition | Create, Read, Update, Delete | Food diary, foods, recipes, diet plans |
| stretching | Create, Read, Update, Delete | Stretching |

A key can leave out the parts you don't use; the app then tells you which
permission a section needs instead of showing it.

## Building

Requires the [Sailfish SDK](https://docs.sailfishos.org/Tools/Sailfish_SDK/).

```bash
tools/build.sh             # emulator: ../build-ironstack-i486/RPMS/
tools/emulator/emu.sh deploy
tools/build.sh aarch64     # phone: ../build-ironstack-aarch64/RPMS/
```

See [docs/EMULATOR.md](docs/EMULATOR.md) for setting up and using the
emulator to try the app, including connecting it to a local IronStack.

## Tests

Headless QML tests run inside the SDK build engine; see
[docs/TESTING.md](docs/TESTING.md).

## Remaining work

See [docs/TODO.md](docs/TODO.md) and [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

## Server-side gaps

Features that need IronStack API changes are tracked as issues labelled
[`mobile-client`](https://github.com/JonneSaloranta/ironstack/issues?q=label%3Amobile-client)
in the IronStack repository.

## License

AGPL-3.0, same as IronStack.
