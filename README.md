# Swapnio

**Swapnio is a skill-swapping platform: teach what you know, learn what you want — no money involved.**

Users build a skill passport (what they offer / want to learn), discover people with complementary
skills, match with a swipe, chat, schedule a *swap session*, complete it, and rate each other. Swap
sessions and completed swaps unlock reputation, which keeps ratings meaningful.

> The Flutter app targets the **Flutter Material** widget layer shipped inside the Flutter SDK
> (`package:flutter/material.dart` with `WidgetsFlutterBinding`/`runApp`), so it is built with the
> standard `flutter` toolchain (verified with Flutter 3.32.8).

## Features

**Core loop**
- Email/password auth (Firebase Auth) + profile setup (skills offered/wanted, availability)
- Home feed with skill-category filters, search and paginated infinite scroll
- Swipe deck with drag physics, match score (your wanted ∩ their offered), haptics, undo
- **"It's a Match!"** dialog when both users liked each other
- Requests + real-time chat (date dividers, delivery ticks, retry on failure)
- **Swap sessions**: propose date/time + what you teach/learn → accept → complete (+25 points each)
- **Earned reputation**: ratings are only accepted after a completed swap session

**Trust & safety**
- Block / report users; feeds filter blocks in both directions and pending likes are cleared
- Admin moderation queue: review reports, dismiss or suspend accounts
- Firestore + Storage security rules enforce all of the above server-side
- Admin-only screens (curated skills, analytics, moderation)

**Polish**
- Sahara design system (EB Garamond + Manrope, warm palette, soft shadows, shared tab theme)
- **Dark mode** with a Light/Dark toggle persisted per user
- Notification bell + badge, notifications page, FCM push plumbing
- Offline-capable Firestore (persistence enabled)

## Tech stack

| Layer | Choice |
| --- | --- |
| UI | Flutter 3.32.8 (Material widget layer), `google_fonts`, `curved_navigation_bar`, `shimmer`, `cached_network_image`, `flutter_rating_bar`, `flutter_svg` |
| State | `provider` (`AppState`, `UserDataProvider`, feature providers) |
| Backend | Firebase: Auth, Cloud Firestore, Cloud Storage, Cloud Messaging, Cloud Functions (Node 20) |
| Tooling | `flutter analyze` + `flutter test`, CI in `.github/workflows/ci.yml` |

## Project structure

```
lib/
  main.dart                 entry point, providers, theme mode
  theme.dart                AppTheme: light/dark Sahara themes, shared tab theme, tokens
  firebase_options.dart     platform Firebase options (see "Firebase setup")
  models/                   UserModel, NotificationModel
  providers/                AppState (auth, profile, notifications, appearance)
  services/                 SafetyService (block/report), SwapSessionService, NotificationService
  ui/                       shared widgets (safety sheet)
  Screen/Auth|User|Admin/   screens
  features/                 gamification, progress, forum, analytics, verification routes
firestore.rules             Firestore security model
firestore.indexes.json      composite indexes
storage.rules               Cloud Storage rules
functions/                  Cloud Functions (push notifications, completion badge)
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

Plugin symlinks on Windows require **Developer Mode** (`start ms-settings:developers`) for *desktop*
builds; Android builds work without it.

### Firebase setup

The repository currently points at the legacy project `hotelbooking-f6a24` (see `.firebaserc` and
`lib/firebase_options.dart`). Once the dedicated Swapnio project exists, run:

```bash
flutterfire configure     # regenerates lib/firebase_options.dart
```

Deploy the security model and indexes **before** onboarding real users:

```bash
firebase login
firebase deploy --only firestore:rules,firestore:indexes,storage
firebase deploy --only functions     # push notifications + completion badge
```

`firebase.json` also defines emulator ports (Firestore 8080, Auth 9099, Storage 9199) so the rules can
be exercised locally with `firebase emulators:start`.

## Testing

```bash
flutter analyze     # 0 errors expected
flutter test        # unit + widget tests
```

## Known gaps / roadmap

1. Switch to the dedicated Swapnio Firebase project (`flutterfire configure`) and update `google-services.json`.
2. Remove the remaining `untitled` identifiers (Android namespace / bundle id) when creating the store listing.
3. Replace remaining hard-coded surface colours so dark mode is pixel-perfect on every screen.
4. Matchmaking v2 (availability/timezone/language overlap) and search v2 (fuzzy + saved filters).
5. Admin analytics charts + CSV export; gamification wired to every real event; leaderboards.
6. Release signing config, app icon/splash generation, Play Store listing, crash reporting.
7. Rating distribution, endorsements, skill verification badges, invites/referrals.

## License

GNU Affero General Public License v3.0 — see [`LICENSE`](LICENSE).
Copyright (C) 2026 Arnab Das and Manab Kumar Barman.