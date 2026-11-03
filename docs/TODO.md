# Remaining work

Everything the API offers is in the app (0.3.1, 2026-11-03). What's left:
testing on the phone, changes waiting on IronStack, a few limitations
worth knowing, and housekeeping. Status per feature is in
[COMPATIBILITY.md](COMPATIBILITY.md); open bugs go in
[KNOWN_ISSUES.md](KNOWN_ISSUES.md). Remove an item when it's done.

## 1. Testing on the phone

Every section has been tried in the emulator against the local IronStack
(test user `jolla-emulator`), including the light theme, gigantic text and
landscape. Nothing has been tried on real hardware yet.

How: `tools/build.sh aarch64`, copy the RPM to `/tmp` on the phone,
`devel-su rpm -Uvh /tmp/harbour-ironstack-<version>-1.aarch64.rpm` in the
phone's own terminal (EMULATOR.md "Building for a phone"). The phone had
0.1.0 installed on 2026-11-03; 0.3.1 is waiting in its `/tmp`.

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
- [ ] **Open Food Facts on mobile data**: search by name and by barcode,
  add a product, the per-minute limits.
- [ ] **Dialogs save with one tap**, also with the keyboard open and after
  scrolling to the last field. (In the emulator they do; the earlier lost
  tap was the "Screenshot captured" banner, see EMULATOR.md.)
- [ ] **Text sizes and landscape** on the phone's own screen.

## 2. Development possible now

- [ ] **Offline queue for more areas** once IronStack #31 adds
  idempotency keys to `diary-entries/`, `measurements/`, `activities/`
  and `stretch-sessions/`. Today only sets and finishing a workout are
  queued (`SyncQueue`, used from `SessionController.qml`); the rest needs
  a connection. Without the keys a retry after a lost response could log
  twice, so don't queue them before #31.
- [ ] **Camera barcode scanning** for Open Food Facts. Harbour allows no
  barcode library and the camera needs its own permission, so the number
  is typed today. Possible outside Harbour (OpenRepos) with e.g. ZXing;
  decide together with where the app is published (section 4).
- [ ] **More translations.** Only English and Finnish
  (`translations/`); the web has more. New languages need the `.ts` file
  in `harbour-ironstack.pro` and the built-in content names from
  `tools/content-i18n/generate.py`.
- [ ] **Stale shopping-list ticks.** Ticks are kept per plan and trip in
  the settings cache (`shopping/<plan>/<trip>`); a deleted plan's ticks
  stay until logout. Harmless and small; clean up when a plan is deleted
  if it ever matters.

## 3. Waiting on IronStack (issues on JonneSaloranta/ironstack)

Nothing here is fixed yet (checked 2026-11-03). When one is: make the
change below, regenerate `content.js` if relevant
(`python3 -I tools/content-i18n/generate.py ../IronStack`), update
COMPATIBILITY.md and drop the row.

| Issue | Today in the app | When fixed | Where |
|---|---|---|---|
| #26 diary date filter | Pages through all entries newest first; statistics read the whole diary | Ask for the day or range only | `nutrition.js` `entriesFor`, `nutritionstats.js` `entriesSince`, `NutritionStatsPage.qml` |
| #27 entry nutrition | Works an entry out from today's food/recipe (old days may differ from the web); built-in and deleted recipes can't be counted | Use the entry's own nutrition; drop "Built-in or deleted recipe", `isKnown` and the "? kcal" headings | `nutrition.js` `forEntry`/`isKnown`/`daySummary`, `DiaryPage.qml`, `nutritionstats.js` |
| #28 food search | Fetches the whole food library and searches it locally | Search on the server | `FoodsPage.qml`, `nutrition.js` `ensure` |
| #29 measurement/activity filters | Fetches every reading and activity, groups them locally | Filter by type and date | `MeasurementsPage.qml`, `ActivitiesPage.qml`, `DashboardPage.qml`, `nutritionstats.js` `bodyWeightSince` |
| #30 new PRs in the set response | Compares `records/` before and after a sync | Read the new records from the reply | `harbour-ironstack.qml` |
| #31 idempotency for more endpoints | Diary, measurements, activities, stretching online only | Queue them like sets (section 2) | `SyncQueue`, the pages that `POST` them |
| #32 copy a program or routine | Copies request by request, removes a half-made copy | One request | `store.js` `copyProgram`/`copyRoutine` |
| #33 goals and targets writable | Read-only; "Is your current target working?" sends you to the web | Accept a suggested target in the app; edit goals | `NutritionPage.qml`, `NutritionGoalsPage.qml` |
| #34 guided stretching | Played on the phone, logged as a quick log; no cool-down suggestion after a workout | Use the server's session; suggest a cool-down after a workout like the web | `StretchPlayerPage.qml`, `TrainingPage.qml` |
| #35 analytics over time | Progress page and strength trend worked out from completed sessions | Read them from the API | `progress.js`, `ProgressPage.qml`, `ExerciseProgressPage.qml` |
| #36 translated display names | Ships the web's translations in `content.js` / `content_texts.js` | Use the server's names; drop the generator | `store.js` `contentName`, `texts.js`, `tools/content-i18n/` |
| #37 social, coaching, assistant, tutorials | Not in the app | New sections | - |
| #38 built-in recipes not visible | Diet plans show "Built-in recipe" without details; the diary can't count or copy their entries | Show the recipe; count and copy its entries | `DietPlanPage.qml`, `DiaryPage.qml`, `nutrition.js` |
| #39 null food/recipe crashes | Leaves the unused field out of the body | Nothing needed; the workaround can stay | `nutrition.js` `entryBody`, `DiaryEntryDialog.qml` |
| #40 body tracking reminder setting, join date | Own switch in Settings; the reminder needs one reading first | Use the profile's setting; remind new users from their join date | `SettingsPage.qml`, `DashboardPage.qml`, `progress.js` `needsBodyReminder` |
| #41 Open Food Facts import | Searches OFF itself and saves a plain food (no Nutri-Score, NOVA or OFF link, so the web can't refresh it) | Import through the API; drop the app's OFF client | `OpenFoodFactsPage.qml`, `openfoodfacts.js`, `ApiClient::openFoodFacts` |

## 4. Housekeeping

- [ ] **Where it's published**: Harbour, OpenRepos or GitHub. The repo has
  no git remote yet. Harbour rules out camera barcode scanning (section 2).
- [ ] **Release steps**: bump `Version` in `rpm/harbour-ironstack.spec`
  and add a `%changelog` entry for every package that goes to the phone
  (0.3.1 on 2026-11-03), so `rpm -Uvh` upgrades without `--force`; run
  `sfdk check` on the aarch64 RPM; write release notes once there's a
  public release.
- [ ] **`sfdk check` warning**: "unstripped-binary-or-object
  /usr/bin/harbour-ironstack". Harbour accepts it; stripping the binary in
  the spec's `%install` would clear it.
