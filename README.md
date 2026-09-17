# Swapnio

**Swapnio is a skill-swapping platform: teach what you know, learn what you want — no money involved.**

Users build a skill passport (what they offer / want to learn), discover people with complementary
skills, match with a swipe, chat, schedule a *swap session*, complete it, and rate each other.
Reputation is earned — ratings only unlock after a session both people actually showed up to.

> Flutter app built with the standard `flutter` toolchain against the Material widget layer
> (`package:flutter/material.dart`). Verified with **Flutter 3.32.8 / Dart 3.8.1**.

---

## What works today

Everything in this section is implemented and building. Known gaps are listed separately below — the
split is deliberate, so nobody has to guess which parts are real.

### Accounts & onboarding
- **Email/password auth** and **Google Sign-In** (Firebase Auth)
- Animated splash screen, then auth-state routing → onboarding → main app
- **4-step onboarding wizard**: identity → skills taught/wanted → experience level → resume/photo upload
- **Skill autocomplete** while typing, backed by the skill catalog (see *Matching* below)

### Discovery & matching
- **Home feed**: search, skill-category filters (whole-word matching), paginated infinite scroll,
  per-user match score, collapsing header
- **Swipe deck**: drag physics with rotation/overlays, like / pass / favourite / rewind, haptics
- **Weighted match algorithm** (`lib/services/match_service.dart`) scoring, in order of weight:
  what they teach that you want (×3), what you teach that they want (×2 — reciprocal interest),
  overlapping availability, and a small rating tie-breaker — normalised to a 0–100% score
- **"Why this match"** breakdown on each card: the exact skills and shared availability behind the score
- **"Likes you" badge**: live count of people who already liked you, so interest is discoverable
  without swiping past them by chance
- **"It's a Match!"** dialog when both sides liked each other
- Deck excludes: people you already requested, people you already chat with, blocked users, banned accounts

### Skill catalog (matching accuracy)
- Merges **admin-curated skills** with **skill names already used across real profiles**, so
  suggestions work from day one without pre-seeding
- **Case/whitespace canonicalisation** — "python", "Python" and " Python " stop being three
  different skills that silently fail to match
- **Synonym aliases** — admins map e.g. `JavaScript → [JS, ECMAScript]`; typing an alias resolves
  to the canonical skill

### Requests, chat & swap sessions
- **Requests / Chats / Sessions** tabs
- Accepting a request creates the chat room and clears the reverse request (mutual likes don't leave
  a phantom request behind)
- **Real-time chat**: date dividers, delivery ticks, copy-on-long-press, failed-send retry banner
- **Swap sessions**: propose with date/time, skills, **meeting link** (Meet/Zoom/Jitsi — no video SDK
  bundled by design) and an **agenda** → accept/decline → reschedule → complete
- **Outcome capture on completion**: session notes + "we covered what we planned", persisted and
  shown on the session card — this is what turns a *match* into a provable *outcome*
- **Session reminders**: push ~1 hour before an accepted session (scheduled Cloud Function)

### Trust, safety & reliability
- **No-show tracking**: a missed session is attributed server-side to whoever *didn't* report it
- **No-show enforcement** (a real gate, not a warning): once you have ≥3 resolved sessions and your
  show-up rate falls below 50%, Firestore itself refuses to create new sessions. New accounts always
  pass, and recovery is automatic — attending sessions pulls the ratio back
- Surfaced in three places: an explanation *before* booking, a banner on your own Activity tab, and a
  **show-up rate badge** on other people's profiles so you can judge before agreeing to meet
- **Ratings are earned**: only accepted after a completed swap, one per rater per session, with
  **structured feedback tags** (Punctual, Clear teacher, Patient…) alongside stars
- **Block / report** users; feeds filter blocks in both directions
- **Privacy settings that actually apply**: `profileVisibility` (public / matches-only / private),
  plus per-field control over skills, availability and email on your public profile
- Firestore + Storage security rules enforce all of the above server-side

### Gamification & progress
- Points, levels and badges, awarded **server-side only** (a client can't award itself points)
- Milestone badges at 1 / 5 / 10 / 25 completed swaps, plus first-message and profile-completion bonuses
- **Activity tab** on your profile: points, level, badges, recent sessions, recent reviews, and a
  top-5 leaderboard
- Per-skill progress tracking (sessions completed, streaks) recorded from real swap completions

### Community & admin
- **Forum** with posts and replies, **scoped by skill** (filter chips + skill tag per post)
- **Admin dashboard** (gated on `users/{uid}.isAdmin`): live user list with search, stats overview,
  curated skills CRUD with aliases, and a moderation queue to dismiss reports or suspend accounts
- **Analytics dashboard**, admin-only

### Platform & polish
- **Sahara design system** — EB Garamond + Manrope, warm palette, soft shadows
- **Dark mode**, persisted per user, applied across the main screens
- Collapsing headers on Home / Profile / Admin
- Notification bell + badge, notifications page, **FCM push** for requests, matches, sessions and reminders
- **Crashlytics + Performance Monitoring**, with Flutter framework errors and uncaught async errors routed to Crashlytics
- **Offline-capable Firestore** (persistence enabled, unlimited cache)

---

## Tech stack

| Layer | Choice |
| --- | --- |
| UI | Flutter 3.32.8 (Material), `google_fonts`, `curved_navigation_bar`, `shimmer`, `cached_network_image`, `flutter_rating_bar`, `flutter_svg` |
| State | `provider` — `AppState`, `UserDataProvider`, plus per-feature providers |
| Backend | Firebase: Auth, Cloud Firestore, Storage, Cloud Messaging, Cloud Functions (Node 20, 2nd gen) |
| Monitoring | Firebase Crashlytics, Firebase Performance Monitoring |
| Tooling | `flutter analyze`, `flutter test`, CI in `.github/workflows/ci.yml` |

## Cloud Functions

All six are deployed and run with admin privileges (they write data a client is not allowed to write —
e.g. the *other* participant's points or no-show record).

| Function | Trigger | Does |
| --- | --- | --- |
| `pushOnNotification` | `notifications/{id}` created | Sends FCM to the recipient's devices, prunes dead tokens |
| `badgeOnCompletedSwap` | `swaps/{id}` → `completed` | +25 points to both, milestone badges (1/5/10/25) |
| `badgeOnFirstMessage` | first chat message created | One-time +5 points and `first_message` badge |
| `badgeOnProfileComplete` | `users/{id}` becomes complete | One-time +10 points and `profile_complete` badge |
| `trackSessionReliability` | `swaps/{id}` status change | Records attendance / attributes no-shows |
| `sessionReminders` | every 15 min (Cloud Scheduler) | Notifies both participants ~1h before a session |

## Data model

Firestore collections (all governed by `firestore.rules`):

```
users/{uid}                     profile, skills, availability, privacy map,
                                isAdmin, rating, sessionsAttended, noShowCount
  settings/{doc}                notification preferences (owner-only)
swipeRequests/{id}              a like awaiting acceptance
chatRooms/{id}                  participants, last message, unread counts
  messages/{id}                 chat messages (text / system / rating)
swaps/{id}                      swap sessions: skills, schedule, meeting link,
                                agenda, status, notes, outcome
ratings/{id}                    earned ratings: stars, review, feedback tags, swapId
gamification/{uid}              points, level, badges (server-written only)
progress/{uid}                  per-skill sessions, streaks
skills/{id}                     admin-curated skills + aliases
forum_posts/{id}                community posts, replies, optional skillName
favorites/ notifications/ blocks/ reports/ analytics/ activityLogs/
```

## Project structure

```
lib/
  main.dart                 entry, Firebase + Crashlytics init, providers, routing
  theme.dart                Sahara light/dark themes
  firebase_options.dart     platform Firebase options
  models/                   UserModel, NotificationModel
  providers/                AppState (auth, profile, notifications, theme), UserDataProvider
  services/                 match, skill catalog, swap sessions, safety, notifications
  ui/                       shared widgets (safety sheet, skill suggestion chips)
  Screen/Auth|User|Admin/   screens
  features/                 gamification, progress, forum, analytics, verification
functions/index.js          Cloud Functions
firestore.rules             security model (incl. no-show enforcement)
firestore.indexes.json      composite indexes
storage.rules               Cloud Storage rules
```

## Getting started

```bash
flutter pub get
flutter run
```

### Toolchain notes (Windows)

Gradle 8.12 (pinned by Flutter 3.32.8) does **not** support Java 25 — install JDK 21 and point
`JAVA_HOME` at it before building Android:

```powershell
$env:JAVA_HOME='C:\path\to\jdk-21'
flutter build apk --release
```

`android/gradle.properties` caps the Gradle JVM at 2 GB. Raise it only if you have the headroom —
over-provisioning here causes the daemon to be killed on machines with limited free RAM.

Desktop builds need **Developer Mode** for plugin symlinks (`start ms-settings:developers`);
Android builds don't.

### Firebase setup

The app currently points at the legacy project **`hotelbooking-f6a24`** (see `.firebaserc` and
`lib/firebase_options.dart`) — see *Known gaps*. Android is registered as `com.swapnio.app`.

Deploy the backend before onboarding real users:

```bash
firebase login
firebase deploy --only firestore:rules,firestore:indexes,storage
firebase deploy --only functions
```

Cloud Functions require the **Blaze** plan (Cloud Scheduler, Eventarc, Pub/Sub). `firebase.json`
defines emulator ports (Firestore 8080, Auth 9099, Storage 9199) for local rule testing via
`firebase emulators:start`.

Google Sign-In requires your signing certificate's SHA-1 to be registered against the Android app:

```bash
firebase apps:android:sha:create <APP_ID> <SHA1>
```

## Testing

```bash
flutter analyze     # 0 errors expected
flutter test        # unit + widget tests (test/models, test/features, widget_test)
```

---

## Known gaps / roadmap

**Blocking a store release**
1. **Release signing is not set up** — release builds are still signed with the *debug* keystore
   (`signingConfig = signingConfigs.getByName("debug")`). Google Play rejects debug-signed uploads,
   and the debug key is a well-known shared key. Generate a keystore, add `key.properties`, and wire
   up a real `signingConfigs.release` before any upload.
2. Play Store listing: needs an `.aab` (not `.apk`), privacy policy URL, content rating, and assets.
3. Still on the shared legacy Firebase project `hotelbooking-f6a24` — a dedicated Swapnio project
   (`flutterfire configure`) is wanted before real users.

**Partially built**
4. **Analytics logging is never called** — `AnalyticsProvider.logEvent()` has no call sites, so the
   admin Analytics dashboard will be empty until events are actually emitted.
5. **Quiz scores are never populated** — `progress` tracks `avgQuizScore`, but no quiz feature exists.
6. **Phone verification is display-only** — status is shown; there is no OTP flow.
7. Firebase options are configured for **Android only**; iOS/web/desktop need `flutterfire configure`.
8. Admin: no audit log for moderation actions, and stats fetch the full `users` collection unpaginated.

**Product roadmap**
9. Matchmaking v2: timezone-aware availability, proficiency levels, saved filter presets.
10. Auto-match on mutual likes (skip the manual accept step entirely).
11. Typing indicators / read receipts (would suit Realtime Database's presence primitives).
12. Group/cohort sessions; forum threads that convert into sessions.
13. Monetisation: intentionally not built. The core barter loop stays free; the likely paths are paid
    expert sessions with a take rate, a Pro tier, and institutional licensing.

## License

GNU Affero General Public License v3.0 — see [`LICENSE`](LICENSE).
Copyright (C) 2026 Arnab Das and Manab Kumar Barman.
