# Remaining work

What's left after the "every API area" pass (commits 95195c5..06b68e8,
2026-11-02). Status per feature is in [COMPATIBILITY.md](COMPATIBILITY.md);
open bugs go in [KNOWN_ISSUES.md](KNOWN_ISSUES.md). Remove an item when
it's done.

## Testing

- [ ] **Nutrition in the emulator.** Only the overview, logging a food to
  the diary and viewing a diet plan were tried. Still to try against the
  local IronStack (test user `jolla-emulator`):
  - diary: date picker (quick entry, edit, delete, copy a day, save a
    meal as a recipe and previous/next day tried 2026-11-03)
  - foods: food page Nutri-Score and NOVA, deleting your own food
    (creating and editing tried 2026-11-03, every label value sent)
  - recipes: creating one from the Recipes page (ingredients, logging to
    the diary and deleting tried 2026-11-03)
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
- [ ] **New in this pass, on the phone** (emulator-checked against the
  local IronStack 2026-11-03): Progress page, nutrition statistics,
  "Is your current target working?" and observed maintenance, Open Food
  Facts search and barcode, the body tracking reminder. Still to hear on
  real hardware: the stretching timer chimes (the emulator has no audio
  out), also with the screen off.
- [ ] **Dialogs.** A focused text field swallowed the first tap on Save;
  initial focus was removed from every dialog. Confirm on the phone that
  each dialog saves with one tap, also with the keyboard open. (In the
  emulator one tap saves, as long as no "Screenshot captured" banner is
  covering the header; see EMULATOR.md.)

## Features possible now (API supports them)

- [ ] Offline queue for diary, measurements, activities and stretching
  once #31 adds idempotency keys there (today these need a connection).
- [ ] Home screen / cover: show today's calories or stretching streak?
  Open question - decide whether the cover should show anything but a
  workout in progress.

## Waiting on IronStack (issues filed on JonneSaloranta/ironstack)

| Issue | What the app does meanwhile |
|---|---|
| #26 diary date filter | Pages through entries newest first |
| #27 entry nutrition | Computes from today's foods (old days may differ from the web); entries of a deleted recipe aren't counted |
| #28 food search | Fetches the whole food library |
| #29 measurement/activity filters | Fetches everything, groups locally |
| #30 new PRs in set response | Compares `records/` after sync |
| #31 idempotency for more endpoints | Online only for those areas |
| #32 copy program/routine | Copies request by request |
| #33 goals/targets writable | Read-only; set on the web, and a suggested target adjustment is accepted there |
| #34 guided stretching | Plays locally, logs as a quick log; no cool-down suggestion after a workout |
| #35 analytics over time | Progress page and strength trend computed locally |
| #36 translated display names | Ships `content.js` / `content_texts.js` |
| #37 social, coaching, assistant, tutorials | Not in the app |
| #38 built-in recipes not visible | Diet plans show "Built-in recipe" without details |
| #39 null food/recipe crashes | Leaves empty fields out |
| #40 body tracking reminder setting | Own on/off switch in Settings; needs one reading first |
| #41 Open Food Facts import | Searches OFF itself, saves a plain food (no Nutri-Score/NOVA/OFF link) |

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
