# Standalone mode

The app can be used without an IronStack server: "Use without a server"
on the login page. Everything is then kept on the phone, and later it can
be moved to a server in one go. Done so far: training. Still to come,
each as its own release: body tracking, activities and stretching; then
nutrition; then the transfer to a server.

## How it works

The pages don't know which mode they're in. They call
`api.request(method, path, body, callback)` as always:

- **ApiClient** (`src/apiclient.cpp`): while `settings.standalone` is
  on, `request()`, `send()` and `upload()` go to a JavaScript handler.
  - The answer comes on the next turn of the event loop, like a network
    reply.
  - The sync queue goes the same way, so its signals and the
    personal-record notification work unchanged.
  - An uploaded image is kept in the app's data directory.
  - `requestWith()` and `requestTo()` always use the network: logging in,
    and the transfer.
- **The local backend** (`qml/js/local/`, registered by
  `qml/components/LocalBackend.qml`) answers with IronStack's API: the same
  paths, status codes and body shapes, including pagination.
  - **`router.js`**: matches the path to a handler. Sections not in
    standalone mode yet answer empty lists. Anything else answers 404,
    "Not available without a server".
  - **Handlers**, ported from IronStack's services with the same rules:

    | Module | Covers |
    |---|---|
    | `exercises.js` | exercises, last performance |
    | `programs.js` | programs, workouts, prescriptions, copies, up next, duration estimates |
    | `sessions.js` | sessions, performed exercises, sets |
    | `records.js` | personal records |
    | `progression.js` | the weight suggestion's seven methods, with the web's wording |
    | `analytics.js` | summary, weekly and muscle-group volume, exercise trend, achievements |
    | `profile.js` | the profile |

  - **`db.js`**: SQLite through QtQuick.LocalStorage.
    - Every row keeps its API object as JSON. The columns beside it are
      only what's filtered, sorted or added up.
    - Built-in rows keep ids below 100001; the user's own count up from it.
    - The schema has migrations (`MIGRATIONS`).
- **Built-in content** - exercises with images, program templates,
  stretches, foods and recipes - is `qml/data/seed.json`, made by
  `tools/standalone/generate_seed.py`. A new version is brought in when
  the app starts. A built-in row IronStack has dropped stays, inactive,
  because history may refer to it.

### Differences from the server

- **Duration estimates** always use IronStack's default formula
  (marked "rough"). The server learns its timings from every user's sets,
  and there's only one user here.
- **Achievements** are the phone's own user only.
- **Built-in names** come translated from the app's own catalog
  (`content.js`): the backend doesn't send `display_*` twins.

### What needs a server

`qml/js/features.js` lists what only works with a server: friends and
groups, coaching, the AI assistant, the guide, "Recently active" and food
search. It also lists the sections not in this mode yet.

- In standalone mode these are shown dimmed, saying what they need.
  Tapping one opens `ServerFeaturePage`, which tells what it does.
- With Settings' "Show what needs a server" off, they're hidden.
- Settings also backs up everything on the phone as one JSON file.

## Updating the built-in content

```bash
python3 -I tools/standalone/generate_seed.py ../IronStack \
    --server http://localhost:8000 --key-file /tmp/ironstack-dev/key
```

- **Inputs:** IronStack's seed migrations and `seed_data` say *which*
  rows are built in (read with `ast`, never run). The server's API gives
  their content, so later edits to seeded rows are in. Use a server
  running the same IronStack version, logged in as a test user.
- **Stable ids:** ids live in `tools/standalone/seed_ids.json` and are
  never reused. Commit it along with `qml/data/`.

## Moving the data to a server (to come)

A one-time transfer through the same API. Planned steps:

1. Log in to the server.
2. Match built-in rows by their English name.
3. Send the user's own exercises and programs, then the sessions in time
   order with their sets.
4. Save a map of local to server ids, so an interrupted transfer
   resumes. Resent writes reuse their `Idempotency-Key`.
5. Compare counts and records at the end.
6. Switch the app to the server.

It needs IronStack to accept a session's real start and end times
(JonneSaloranta/ironstack#52). Until then, every transferred workout
would land on the transfer day.

## Tests

| Test | Covers |
|---|---|
| `tests/qml/tst_local_db.qml` | schema, ids, seed updates |
| `tests/qml/tst_local_training.qml` | the training endpoints through `Router.handle` (records, suggestions, up next, analytics, pagination) |
| `tests/qml/tst_local_perf.qml` | five years of sets (30 000) |
| `tests/qml/tst_features.qml` | dimmed or hidden |
| `tests/cpp/tst_apiclient.cpp` (`standalone*`) | the routing |
