# Firebase backend handoff — Patient app

> Audience: an AI coding session (or developer) tasked with wiring the real
> Firebase backend to the finished Flutter UI. Read this file first, then the
> files it points to. Do **not** redesign the UI — it is approved and frozen.

## 1. Context

The Patient/Caller app for the Ambulance Tracking & Dispatch project was
designed and built UI-first (5-step gated workflow). All 17 screens are
implemented as a **demo app with no backend**: every screen reads from and
writes to `lib/core/app_state.dart` (a `ChangeNotifier` with in-memory demo
data). Your job is to replace the demo data with real Firebase data **without
touching the screens' visual design**.

Source-of-truth docs (read in this order):

1. `baseline-report.md` — product spec (status lifecycle, roles, rules)
2. `design-tokens.md` — the design system (do not add new colors/type)
3. `docs/patient-app-screen-specs.md` — per-screen behavior, states, microcopy
4. `docs/patient-app-ia.md` — navigation/IA (approved)

## 2. Architecture contract (the seam)

**`AppState` is the single integration seam.** Every screen does:

```dart
ListenableBuilder(listenable: state, builder: (context, _) => ...)
```

and calls methods like `state.sendRequest()`, `state.signIn()`,
`state.updateMedicalProfile()`. The UI already implements loading / empty /
error / offline / permission-denied states for each screen — those states are
driven by fields on `AppState`.

**Recommended approach — repository behind `AppState`:**

```
screens ──> AppState (ChangeNotifier, keeps its current public API)
                │
                ▼
        AppRepository (abstract)
           ├── DemoRepository   (current in-memory logic — keep it working)
           └── FirebaseRepository (new)
```

- Extract the demo logic out of `AppState` into `DemoRepository`, keeping the
  exact same method signatures.
- Implement `FirebaseRepository` with the same signatures.
- `AppState` becomes a thin adapter: it calls the repository and mirrors the
  results into the same public fields, then `notifyListeners()`.
- Keep a runtime switch (default: demo) so the UI walkthroughs and Settings
  "State (demo)" toggles keep working for design review.
- Alternative (smaller diff, acceptable): keep `AppState` as-is and
  progressively replace the bodies of its methods with Firestore/Auth calls
  plus snapshot subscriptions that update the same fields. Do this only if it
  stays readable.

**Rule: screens may be edited only to (a) consume streams already surfaced by
`AppState`, or (b) fix compile errors caused by signature changes. No layout,
color, spacing, or copy changes.**

## 3. Data model (proposed — adapt to what already exists in your project)

You mentioned you already built a Firebase backend that "mostly works". Map
your existing schema onto these fields; where they differ, prefer keeping the
UI contract (below) and adapt on the repository side.

```
users/{uid}
  phone, displayName?, createdAt

users/{uid}/medical/{docId}              # single doc, docId = "self"
  bloodType: string|null        # null → MedicalCard renders "Not set"
  allergies: string[]
  conditions: string[]
  contacts: [{name, phone, relation}]    # max 5 (UI enforces)

units/{unitId}
  callsign, status: 'available'|'enRoute'|'onScene'|'transporting'|'offDuty'
  location: GeoPoint, hospital: string
  # `available` maps to success-green in the UI; red is danger-only

incidents/{incidentId}
  patientId: uid|null          # null = guest
  patientPhone: string
  contactNumber: string
  location: GeoPoint
  status: 'pending'|'dispatched'|'enRoute'|'onScene'|'transporting'
          |'atHospital'|'resolved'|'cancelled'
  statusTimes: {status: Timestamp}   # UI renders per-status mono timestamps
  unitId, unitCallsign         # snapshot at assignment time
  etaSeconds: number|null      # drives the mono ETA hero
  medicalAttached: bool
  createdAt, updatedAt
```

### Status lifecycle (must be enforced server-side)

`pending → dispatched → enRoute → onScene → transporting → atHospital → resolved`
(`cancelled` allowed any time before crew arrival — UI already has the
confirm dialog).

Enforce with a Firestore **security rule** and/or a **Cloud Function
`onIncidentWrite`** that rejects invalid transitions (client sets `status`,
function validates against the current value and reverts/logs violations).
The UI switches theme on status: dark mission HUD for
`dispatched…atHospital`, calm light at `pending` and `resolved`.

## 4. Firebase pieces → where they plug into the UI

| Firebase | UI integration point |
|---|---|
| **Auth (phone)** | `sign_in_screen.dart` — demo accepts code `123456`. Wire `verifyPhoneNumber` → OTP step; map `invalid-verification-code` → "That code doesn't match…" state, keep the 30 s resend countdown, keep "Continue as guest". |
| **Firestore incidents** | `request_flow.dart` "Send request" → create `incidents` doc; `mission_screen.dart` streams the doc (status band, ETA, timeline dots, `statusTimes`); `missions_screen.dart`/`mission_detail_screen.dart` query history by `patientId`. |
| **Firestore units** | `fleet_screen.dart` — live markers + unit sheet; subscribe to `units` where status ≠ offDuty. |
| **FCM** | `main.dart` already has the auto-open hook: a data message with `type: 'dispatched'` + `incidentId` opens `MissionScreen`. Send data messages (not notification messages) from Functions so the app handles them in-background/foreground alike. |
| **geolocator** | Real device location replaces the demo `userLocation`; keep the primer flow (`permission_primer.dart` shows first, then the OS dialog). |
| **Cloud Functions** | Dispatch matching (nearest available unit), status transitions, FCM fan-out to patient + unit, `requestAmbulance` callable (creates incident, triggers matching). |
| **Firestore rules** | Patients read/write only their own incidents & medical docs; `units` readable by authenticated+guest patients; status transitions server-only after `dispatched`. |
| **Crashlytics/Analytics** | Optional; analytics is **opt-in off by default** in the UI (§16 Settings). |

### Offline & resilience (UI states already exist — map them)

- `AppState.offline` → real connectivity (e.g. `connectivity_plus`).
- Incident create while offline → the UI already shows "Save request" /
  queued state (§6); implement write-behind queue or Firestore's offline
  persistence and surface `pending` status.
- Medical profile save failure → UI keeps the form and shows the error (§11);
  wire `FirebaseException` to that path (Settings has "Simulate save failure"
  for the demo repo).

## 5. Step-by-step plan (batches with verification gates)

Work in small batches; after each one run:

```
flutter analyze
flutter build web --no-tree-shake-icons --no-wasm-dry-run
```

and report what changed before moving on.

1. **Scaffold** — `flutterfire configure` (or wire your existing project's
   `firebase_options.dart`), add `firebase_core`, `firebase_auth`,
   `cloud_firestore`, `firebase_messaging`, `firebase_analytics` to
   `pubspec.yaml`. App must still run fully in demo mode.
2. **Repository seam** — extract `DemoRepository`, define `AppRepository`,
   add the runtime switch. Zero behavior change; verify all screens still
   work in demo mode.
3. **Auth** — phone OTP in `SignInScreen`; `AppState.isAuthenticated` from
   `authStateChanges`; guest remains fully functional.
4. **Incidents write path** — `RequestFlowScreen` creates a real doc;
   queue when offline.
5. **Live mission** — `MissionScreen` streams the incident; server-side
   status transitions; `statusTimes` filled by the function; ETA from unit
   location.
6. **Fleet** — `units` collection live on the map + unit detail sheet.
7. **History** — `MissionsScreen`/`MissionDetailScreen` query + realtime
   updates.
8. **Medical profile** — Firestore CRUD under `users/{uid}/medical`, attach
   snapshot to incident on request (`medicalAttached`).
9. **FCM** — Functions send data messages; verify foreground handling and the
   background auto-open path in `main.dart`.
10. **Rules + indexes + cleanup** — deploy rules, composite indexes for the
    history queries, remove/flag dead demo code (keep `DemoRepository`).

## 6. Ground rules

- Flutter 3.47.x / Dart 3.13.x; `flutter_map` ^7.0.2 (note: no
  `screenPointToLatLng`; the request-flow pin drag uses manual Web-Mercator
  math — don't "fix" it).
- Tokens live in `lib/core/tokens.dart` and mirror `design-tokens.md` — no
  new colors, type sizes, or spacing values.
- Status colors: red = danger only; `available`/`resolved` = success green.
- Every user-visible string is specified in `docs/patient-app-screen-specs.md`
  — reuse it verbatim.
- Commit per batch with a descriptive message; run the analyze + build gate
  every batch.
