# Remaining work

The app uses IronStack 1.30's API for training, body tracking, activities,
stretching and nutrition (2026-11-03). What's left: testing on the phone,
the new social/coaching/assistant API, changes waiting on IronStack, a few
limitations worth knowing, and housekeeping. Status per feature is in
[COMPATIBILITY.md](COMPATIBILITY.md); open bugs go in
[KNOWN_ISSUES.md](KNOWN_ISSUES.md). Remove an item when it's done.

## 1. Testing on the phone

Every section has been tried in the emulator against the local IronStack
(test user `jolla-emulator`), including the light theme, gigantic text and
landscape. Nothing has been tried on real hardware yet.

How: `tools/build.sh aarch64`, copy the RPM to `/tmp` on the phone,
`devel-su rpm -Uvh /tmp/harbour-ironstack-<version>-1.aarch64.rpm` in the
phone's own terminal (EMULATOR.md "Building for a phone"). The phone had
0.3.1 installed on 2026-11-03; 0.4.0 is waiting in its `/tmp`.

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
- [ ] **Offline logging**: with mobile data off, log a diary entry, a body
  weight, an activity and stretching; they wait as "saved on this phone"
  (the diary shows "Not sent yet") and go once the connection is back.
- [ ] **Guided stretching and the cool-down** after a finished workout,
  with the screen off; a session started on the web picked up in the app.
- [ ] **Dialogs save with one tap**, also with the keyboard open and after
  scrolling to the last field. (In the emulator they do; the earlier lost
  tap was the "Screenshot captured" banner, see EMULATOR.md.)
- [ ] **Text sizes and landscape** on the phone's own screen.

## 2. Development possible now

- [ ] **Social, coaching, the AI assistant and guided tours** (IronStack
  #37, in the API since 1.30): friends, requests, blocking, messages and
  groups; asking a trainer, a trainer's clients, importing shared plans;
  the assistant's conversations and proposals; the web's tours. Each is a
  new section, and friends/groups, coaching and the assistant each need an
  API key with their own new permission area (the 403 message already
  names it). Decide which are worth having on the phone first.
- [ ] **Camera barcode scanning** for Open Food Facts. Harbour allows no
  barcode library and the camera needs its own permission, so the number
  is typed today. Possible outside Harbour (OpenRepos) with e.g. ZXing;
  decide together with where the app is published (section 4).
- [ ] **More translations.** Only English and Finnish
  (`translations/`); the web has more. New languages need the `.ts` file
  in `harbour-ironstack.pro` and the built-in content names from
  `tools/content-i18n/generate.py`.
## 3. Waiting on IronStack (issues on JonneSaloranta/ironstack)

#26-#41 were fixed in IronStack 1.30.0 and are used by the app. Still
open (2026-11-03). When one is fixed: make the change below, update
COMPATIBILITY.md and drop the row.

| Issue | Today in the app | When fixed | Where |
|---|---|---|---|
| #42 translated nested names and long texts | `display_name` isn't used; the app ships the web's catalog for every built-in name and text | Use the server's names and texts; drop the generator | `store.js` `contentName`, `texts.js`, `tools/content-i18n/` |
| #43 cool-down suggestion | Ported `suggest_cooldown`; reads every exercise, routine and stretch, finds a done cool-down on the newest page of stretch sessions | Ask the server | `store.js` `suggestCooldown`, `CooldownCard.qml` |
| #44 nutrition statistics and maintenance | Ported from `services.py`, `maintenance.py`, `trends.py`; reads the whole diary | Read them from the API | `nutritionstats.js`, `NutritionStatsPage.qml`, `NutritionPage.qml` |

## 4. Housekeeping

- [ ] **Where it's published**: Harbour, OpenRepos or GitHub. The repo has
  no git remote yet. Harbour rules out camera barcode scanning (section 2).
- [ ] **Release steps**: bump `Version` in `rpm/harbour-ironstack.spec`
  and add a `%changelog` entry for every package that goes to the phone
  (0.4.0 on 2026-11-03), so `rpm -Uvh` upgrades without `--force`; run
  `sfdk -c target=SailfishOS-5.1.0.11-aarch64 check` on the aarch64 RPM
  (without the target it runs the i486 objdump and fails); write release notes once there's a
  public release.
