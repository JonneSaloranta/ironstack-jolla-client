# Remaining work

The app uses all of IronStack 1.31's API (2026-11-04). What's left:
testing on the phone, changes waiting on IronStack, a few limitations
worth knowing, and housekeeping. Status per feature is in
[COMPATIBILITY.md](COMPATIBILITY.md); open bugs go in
[KNOWN_ISSUES.md](KNOWN_ISSUES.md). Remove an item when it's done.

## 1. Testing on the phone

Every section has been tried in the emulator against the local IronStack
(test user `jolla-emulator`), including the light theme, gigantic text and
landscape. On the phone (2026-11-04) so far: the diary with the real
account (which found the proxy link bug fixed in 0.6.1), the barcode
scanner's viewfinder (upright since 0.6.2), and 0.7.0's changes against
IronStack 1.31.0 - the nutrition dashboard and its observed maintenance,
the statistics page, the cool-down card on a finished workout, built-in
names in Finnish and a group no longer counting your own message as
unread - with no warnings or errors in the app's output.

How: `tools/build.sh aarch64`, copy the RPM to `/tmp` on the phone,
`devel-su rpm -Uvh /tmp/harbour-ironstack-<version>-1.aarch64.rpm` in the
phone's own terminal (EMULATOR.md "Building for a phone"). The phone has
0.7.0 (2026-11-04); 0.8.0 is waiting in its `/tmp`. For the app's
messages, use Settings > App log (0.8.0 on) or start it from the
terminal with `harbour-ironstack 2>&1 | tee /tmp/ironstack.log`.

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
- [ ] **The app log**: Settings > App log at Debug, then Share it by email
  (the emulator has no share targets) and Copy it into another app.
- [ ] **With IronStack's next release** (#47-#51, see section 3): an image
  of your own exercise from the phone's gallery (the first launch asks for
  Pictures and Media index), "This week" on the dashboard, duration
  estimates on programs and the time left in training mode, the trainer
  switches on the coaching page, and a recipe the assistant suggests.

## 2. Development possible now

- [ ] **Swedish, Estonian, Italian and Russian checked by a native
  speaker.** About half of their strings are the web's own translations;
  the rest were written for the app (2026-11-03). New strings: run
  `lupdate` (a build does), then `python3 -I tools/i18n/from-web.py
  ../IronStack sv et it ru` takes what the web has and lists the rest.

## 3. Waiting on IronStack (issues on JonneSaloranta/ironstack)

#26-#46 were fixed in IronStack 1.30.0 and 1.31.0. #47-#51 are fixed on
IronStack's dev branch (2026-11-04, not released yet) and the app already
uses them when the server has them; with a 1.31 server those features
stay hidden. When the release is out:

- [ ] Note its version in COMPATIBILITY.md and README.md in place of "dev
  branch", and try the five against the real server on the phone.
- [ ] Once the app can require that version: drop the 1.31 fallbacks -
  `weekRange` in `DashboardPage.qml`, the 404 messages in
  `ExercisePage.qml` and `SessionController.qml`, and (#47) the app's copy
  of the web's catalog: `Store.contentName`'s fallback, `content.js`,
  `content_texts.js` and `tools/content-i18n/` (old offline caches then
  show English until refreshed).

## 4. Housekeeping

- [ ] **Where it's published**: Harbour, OpenRepos or GitHub. The repo has
  no git remote yet.
- [ ] **Release steps**: bump `Version` in `rpm/harbour-ironstack.spec`
  and add a `%changelog` entry for every package that goes to the phone
  (0.8.0 on 2026-11-04), so `rpm -Uvh` upgrades without `--force`; run
  `sfdk -c target=SailfishOS-5.1.0.11-aarch64 check` on the aarch64 RPM
  (without the target it runs the i486 objdump and fails); write release notes once there's a
  public release.
