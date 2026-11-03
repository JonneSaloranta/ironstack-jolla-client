# Remaining work

The app uses all of IronStack 1.30's API (2026-11-03). What's left:
testing on the phone, changes waiting on IronStack, a few limitations
worth knowing, and housekeeping. Status per feature is in
[COMPATIBILITY.md](COMPATIBILITY.md); open bugs go in
[KNOWN_ISSUES.md](KNOWN_ISSUES.md). Remove an item when it's done.

## 1. Testing on the phone

Every section has been tried in the emulator against the local IronStack
(test user `jolla-emulator`), including the light theme, gigantic text and
landscape. On the phone (2026-11-04) so far: the diary with the real
account (which found the proxy link bug fixed in 0.6.1) and the barcode
scanner's viewfinder (upright since 0.6.2).

How: `tools/build.sh aarch64`, copy the RPM to `/tmp` on the phone,
`devel-su rpm -Uvh /tmp/harbour-ironstack-<version>-1.aarch64.rpm` in the
phone's own terminal (EMULATOR.md "Building for a phone"). The phone had
0.6.2 installed on 2026-11-04; 0.6.3 is waiting in its `/tmp`.

- [ ] **Every section with the real account**: training (start, log sets,
  rest timer and its notification with the screen off, finish), programs,
  history, records, exercises, body tracking, activities, stretching,
  nutrition, Progress, settings.
- [ ] **Sound and permissions**: the first launch asks for the new Audio
  permission ("Play and record audio"); the stretching chimes (hold, next
  step, done) are heard, also with the screen off, and stay quiet with
  "Stretching timer sound" off. The emulator has no audio out.
- [ ] **Cover**: today's calories and protein between workouts, updated
  after logging in the diary; "+" opens a quick entry; the workout timer
  and rest actions during a workout.
- [ ] **Open Food Facts through the server**: search by name and by
  barcode, add a product (Nutri-Score and NOVA shown on the food).
- [ ] **Barcode scanning with the camera** (Foods > "Scan a barcode"):
  the viewfinder works on the phone; still to see whether real packages
  (EAN-13, EAN-8, UPC-E) are read, in dim light with the torch and on a
  curved bottle. If nothing is ever read, `VideoOutput.grabToImage` may
  come back empty on the phone - then read the frames with a QVideoProbe
  in C++ instead.
- [ ] **Offline logging**: with mobile data off, log a diary entry, a body
  weight, an activity and stretching; they wait as "saved on this phone"
  (the diary shows "Not sent yet") and go once the connection is back.
- [ ] **Guided stretching and the cool-down** after a finished workout,
  with the screen off; a session started on the web picked up in the app.
- [ ] **Friends, groups, coaching and the assistant** with real accounts;
  the API key needs the "Friends and groups", "Coaching" and "AI
  assistant" areas (a new key - old keys don't get them). Messages
  arriving while a conversation is open; the assistant with a real model.
- [ ] **Dialogs save with one tap**, also with the keyboard open and after
  scrolling to the last field. (In the emulator they do; the earlier lost
  tap was the "Screenshot captured" banner, see EMULATOR.md.)
- [ ] **Text sizes and landscape** on the phone's own screen.

## 2. Development possible now

- [ ] **Swedish, Estonian, Italian and Russian checked by a native
  speaker.** About half of their strings are the web's own translations;
  the rest were written for the app (2026-11-03). New strings: run
  `lupdate` (a build does), then `python3 -I tools/i18n/from-web.py
  ../IronStack sv et it ru` takes what the web has and lists the rest.

## 3. Waiting on IronStack (issues on JonneSaloranta/ironstack)

#26-#41 were fixed in IronStack 1.30.0 and are used by the app. Still
open (2026-11-04). When one is fixed: make the change below, update
COMPATIBILITY.md and drop the row.

| Issue | Today in the app | When fixed | Where |
|---|---|---|---|
| #42 translated nested names and long texts | `display_name` isn't used; the app ships the web's catalog for every built-in name and text | Use the server's names and texts; drop the generator | `store.js` `contentName`, `texts.js`, `tools/content-i18n/` |
| #43 cool-down suggestion | Ported `suggest_cooldown`; reads every exercise, routine and stretch, finds a done cool-down on the newest page of stretch sessions | Ask the server | `store.js` `suggestCooldown`, `CooldownCard.qml` |
| #44 nutrition statistics and maintenance | Ported from `services.py`, `maintenance.py`, `trends.py`; reads the whole diary | Read them from the API | `nutritionstats.js`, `NutritionStatsPage.qml`, `NutritionPage.qml` |
| #45 group unread counts your own message | Reads the thread again after sending to a group | Nothing; drop the extra read | `ChatPage.qml` `send` |
| #46 API program edits don't bump the version | A coach editing a shared program in the app doesn't offer clients an update (on the web it does) | Nothing to change in the app | - |

## 4. Housekeeping

- [ ] **Where it's published**: Harbour, OpenRepos or GitHub. The repo has
  no git remote yet.
- [ ] **Release steps**: bump `Version` in `rpm/harbour-ironstack.spec`
  and add a `%changelog` entry for every package that goes to the phone
  (0.6.3 on 2026-11-04), so `rpm -Uvh` upgrades without `--force`; run
  `sfdk -c target=SailfishOS-5.1.0.11-aarch64 check` on the aarch64 RPM
  (without the target it runs the i486 objdump and fails); write release notes once there's a
  public release.
