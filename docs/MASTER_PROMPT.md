# MASTER PROMPT — DrD: Production Hardening + PWA Conversion

> This is the self-directed brief that drives the work in this branch.
> It was written after a full read of the codebase, not from assumptions.

---

## 0. Context

**DrD** (`medical_appointment_app`) is a Flutter app whose product promise is:
*a patient books a specific time slot with a doctor so nobody sits in a waiting
room for three hours.* Everything in this brief is judged against that promise.

Current state: Flutter 3.x app, Firebase (Auth + Firestore) backend, Arabic-first
RTL UI, ~13k lines of Dart across 30 screens/providers, plus a stale Supabase
schema, an unused Clean-Architecture `domain/` layer, and ~40 one-off Python
patch scripts committed at the repo root.

---

## 1. Non-negotiable outcomes

1. **The app must not double-book a slot.** Not "usually". Not "if the UI
   refreshes". Enforced at the database level so two phones tapping Confirm in
   the same second cannot both win.
2. **Patient data must not be world-readable.** This app stores names, phone
   numbers, birth dates, symptoms, and doctor health ratings. That is medical
   data.
3. **It must be a real, installable PWA** — passes an install prompt, works
   offline for already-seen content, has a correct manifest and icon set, and
   updates cleanly when a new version ships.
4. **It must still build for Android and iOS**, because the App Store does not
   accept PWAs and the Play Store only accepts them via a wrapper. The web build
   is an *addition*, not a replacement.
5. **Nothing may regress.** `flutter analyze` must be clean, and the critical
   logic must be covered by tests that did not exist before.

---

## 2. Review findings to fix (discovered by reading the code)

### CRITICAL — blocks shipping

| # | Finding | Location |
|---|---|---|
| C1 | Booking writes with `collection('appointments').add({...})` — no transaction, no uniqueness. Two concurrent confirms both succeed. This defeats the entire product. | `patient_booking_screen.dart:866` |
| C2 | No `firestore.rules` and no `firebase.json` exist in the repo. The database is running on whatever was clicked in the console — almost certainly test mode. | repo root |
| C3 | `DefaultFirebaseOptions.currentPlatform` hardcodes `return android;` and only Android config exists. There is no `authDomain`. **Firebase Auth cannot work on web.** PWA is impossible until this is fixed. | `firebase_options.dart` |
| C4 | Login resolves phone→email by querying `users` *before* authenticating. This requires public read on every user document: emails, phones, birth dates, roles. | `firebase_auth_service.dart` `login()` |
| C5 | `web/manifest.json` and `web/index.html` are untouched Flutter defaults — `"A new Flutter project"`, `medical_appointment_app`, `#0175C2`, `lang` unset, no RTL. Not installable as a credible app. | `web/` |
| C6 | `pubspec.yaml` pins `intl: ^0.19.0`, which cannot resolve against current `flutter_localizations`. **The project does not `pub get` on modern Flutter.** | `pubspec.yaml` |

### HIGH — correctness and data integrity

| # | Finding |
|---|---|
| H1 | `updatePatientProfile()` mutates the in-memory map and calls `notifyListeners()` but **never writes to Firestore**. The user's edit silently disappears on next login. |
| H2 | Appointment status is a free-form string with seven spellings in circulation: `Booked`, `Scheduled`, `upcoming`, `pending`, `Completed`, `Cancelled`, `PendingConfirmation`. Every screen re-implements the matching by hand. |
| H3 | Time is parsed and formatted at least four different ways (`HH:mm`, `HH:mm:ss`, `hh:mm AM/PM`, and a bespoke parser in the Cloud Function). All are timezone-naive. |
| H4 | `checkSession()` awaits `authStateChanges().first`, which can hang forever, and login state is derived only from a local field — so a web reload logs the user out. |
| H5 | `TimeSlotGenerator` (`core/utils/`) is dead: the booking screen ships its own inline slot logic instead. Two sources of truth, one unused. |
| H6 | The entire `domain/` layer (entities, repositories, 8 use cases) and `appointment_provider` are never wired into the app. The README advertises an architecture that isn't running. |
| H7 | Working-day matching does `entry.key.contains(DateFormat('EEEE','ar').format(date))` — locale-string matching as a data key. |
| H8 | No tests exist. No `test/` directory at all. |

### MEDIUM — hygiene, performance, maintainability

| # | Finding |
|---|---|
| M1 | ~40 one-off Python patch scripts (`fix_*.py`, `apply_*.py`, `update_analytics2.py`…) committed at the repo root, plus `doctor_analytics_screen.dart.bak` inside `lib/`. |
| M2 | Six dead Dart files: `home_screen_simple`, `login_screen_simple`, `simple_auth_service`, `local_auth_service`, `auth_service`, `firebase_phone_auth`. |
| M3 | 51 `print()` calls ship to production — visible in the browser console on web. |
| M4 | 471 hardcoded `Colors.*` references, no theme layer, no dark mode (despite `values-night/` existing). |
| M5 | `supabase/schema.sql` documents a Postgres backend the app abandoned for Firestore. README describes Supabase too. |
| M6 | Doctor list is fetched with a full unfiltered collection read on every screen open; no caching, no pagination. |

---

## 3. Work plan

### Phase A — Make it build and stop the bleeding
- Fix `intl` constraint; refresh `flutter_lints`; confirm `pub get` + `analyze`.
- Delete the 40 Python scripts, the `.bak`, and the six dead Dart files.
- Delete the stale Supabase schema; rewrite the README to describe reality.

### Phase B — Correctness core
- `AppointmentStatus`: one canonical enum + a tolerant parser that maps every
  legacy spelling onto it, so existing Firestore documents keep working.
- `AppointmentSlot` / deterministic slot IDs: `{doctorId}_{yyyy-MM-dd}_{HH:mm}`.
- Rewrite booking to `runTransaction` against that deterministic document ID.
  Existence check and write happen atomically. Add a second guard: one active
  appointment per patient per doctor per day.
- Restore `TimeSlotGenerator` as the single slot authority and delete the
  inline duplicate.
- Fix `updatePatientProfile` to persist, and make session restore reliable.

### Phase C — Security
- Author `firestore.rules` from scratch: patients read/write only their own
  documents; doctors read only appointments assigned to them; **the slot
  uniqueness rule is enforced server-side**; notifications are readable only by
  their addressee.
- Add a `phone_index` collection holding only `{phone → uid, email}` so login
  no longer needs public read on `users`.
- Add `firestore.indexes.json` for the composite queries the app already runs.
- Add `firebase.json` wiring hosting + rules + indexes.

### Phase D — PWA
- Real `manifest.json`: `id`, `scope`, `start_url`, `display_override`,
  `lang: ar`, `dir: rtl`, categories, shortcuts, screenshots, maskable icons.
- Rewrite `index.html`: `lang="ar" dir="rtl"`, real title/description,
  `theme-color` for light and dark, Apple PWA meta, and an Arabic branded
  loading screen so the boot is not a white void.
- Service worker layer: offline fallback page, and an update flow that tells
  the user in Arabic that a new version is ready instead of silently caching
  stale code forever.
- Web Firebase config with `authDomain` so Auth actually works.

### Phase E — Store readiness + quality gate
- Verify the Android release path and document signing.
- Tests for slot generation, status parsing, phone normalization, and the
  booking ID scheme.
- CI: analyze + test + build web on every push.
- Deployment guide covering web hosting, Play Store (TWA and native), and
  App Store — including the honest constraint that Apple will not accept a PWA.

---

## 4. Rules of engagement

- **Do not break existing Firestore data.** Legacy status strings and legacy
  appointment documents must keep working. Migration is tolerant, not
  destructive.
- **Arabic first.** Every user-facing string added must be Arabic, RTL-correct.
- **No new dependencies unless they earn their place.**
- **Report honestly.** If something cannot be verified in this environment
  (device testing, real Firebase deploy), say so rather than implying it passed.
