# Remaining work

What's left after the "every API area" pass (commits 95195c5..06b68e8,
2026-11-02). Status per feature is in [COMPATIBILITY.md](COMPATIBILITY.md);
open bugs go in [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Remove an item when
it's done.

## Testing

- [ ] **Nutrition in the emulator.** Only the overview, logging a food to
  the diary and viewing a diet plan were tried. Still to try against the
  local IronStack (test user `jolla-emulator`):
  - diary: quick entry (calories estimated from macros when empty), edit,
    delete, copy a day, save a meal as a recipe, previous/next day, date
    picker
  - foods: food page (label, Nutri-Score, NOVA), create, edit and delete
    your own food (`FoodEditDialog` reads its nutrient fields through a
    Repeater - check every value is sent)
  - recipes: create, add/edit/remove ingredients, log to diary, delete
  - goal and profile page; editing the profile (needs a profile made by
    the web's nutrition onboarding first)
  - diet plans: create (diet builder), activate/deactivate, log for a date,
    rename, delete; shopping list, trips, shopping days, ticking items
  - calculators: every calculator, metric and imperial
- [ ] **Everything on the phone.** Build aarch64 in
  `~/Projektit/build-ironstack-aarch64`, copy the RPM to `/tmp` on the
  phone, install with `devel-su rpm -Uvh` (needs the user's terminal), go
  through every section with the user's real account, larger text sizes
  and landscape.
- [ ] **Dialogs.** A focused text field swallowed the first tap on Save;
  initial focus was removed from every dialog. Confirm on the phone that
  each dialog saves with one tap.

## Features possible now (API supports them)

- [ ] Nutrition stats (the web's `stats` page: averages, macro split
  over time) - worked out from diary entries, slow without #26.
- [ ] Observed maintenance and the "is your target working?" suggestion
  on the nutrition overview - computable from diary and body weight, but
  the web's algorithm (`apps/nutrition/maintenance.py`,
  `suggestions.py`) would need porting.
- [ ] Open Food Facts: search and barcode import done by the app itself,
  then `POST foods/` (the API has no import, see COMPATIBILITY.md).
- [ ] Training analytics like the web's: weekly volume, muscle group
  volume, PR history - from completed sessions until #35.
- [ ] Body tracking reminder (14 days without a reading) - the on/off
  setting isn't in the API profile.
- [ ] Stretching: timer sound, cool-down suggestion after a workout
  (needs #34 for `after_workout`).
- [ ] Offline queue for diary, measurements, activities and stretching
  once #31 adds idempotency keys there (today these need a connection).
- [ ] Home screen / cover: show today's calories or stretching streak?

## Waiting on IronStack (issues filed on JonneSaloranta/ironstack)

| Issue | What the app does meanwhile |
|---|---|
| #26 diary date filter | Pages through entries newest first |
| #27 entry nutrition | Computes from today's foods (old days may differ from the web) |
| #28 food search | Fetches the whole food library |
| #29 measurement/activity filters | Fetches everything, groups locally |
| #30 new PRs in set response | Compares `records/` after sync |
| #31 idempotency for more endpoints | Online only for those areas |
| #32 copy program/routine | Copies request by request |
| #33 goals/targets writable | Read-only; set on the web |
| #34 guided stretching | Plays locally, logs as a quick log |
| #35 analytics over time | Strength trend computed locally |
| #36 translated display names | Ships `content.js` / `content_texts.js` |
| #37 social, coaching, assistant, tutorials | Not in the app |
| #38 built-in recipes not visible | Diet plans show "Built-in recipe" without details |
| #39 null food/recipe crashes | Leaves empty fields out |

When one is fixed: update the app, regenerate `content.js` if relevant
(`python3 -I tools/content-i18n/generate.py ../IronStack`), and update
COMPATIBILITY.md.

## Housekeeping

- [ ] The repo root holds in-tree i486 build output (`*.o`, `Makefile`,
  `moc_*`); ignored by git but easy to mix up with the aarch64 build.
- [ ] The app has no git remote - decide where it's published (Harbour,
  OpenRepos, GitHub) and add `sfdk check` to the release steps.
- [ ] Version is still 0.1.0; bump and write release notes before the
  phone becomes the daily driver.
