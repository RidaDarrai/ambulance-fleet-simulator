# M3 Test Scenarios — Live tracking & contact

Manual QA checklist for features added in milestone 3 (commits `M3:*`).
Automated coverage that already exists: `apps/patient_app/test/routing_test.dart`
(straight-line math), plus per-app `flutter analyze` / `flutter test` / dashboard
`npm run build` (see 8. Regression gate).

## 0. Setup (preconditions)

1. Deployed Firebase project `ambulance-dispatch-sim` (rules current).
2. Accounts signed in (or ready): dispatcher web (`dispatcher@sim.local` /
   `dispatch1234`), crew app (`crew@sim.local` / `crew12345`), patient app
   (guest is fine), admin web (`admin@sim.local` / `admin1234`).
3. Run apps: patient + crew via `flutter run -d edge`, dashboard via `npm run dev`.
4. GPS simulator available: `npm run gps -- AMB-01` (project root).
5. Optional debug view of RTDB: Firebase console → Realtime Database → `positions`.

---

## 1. GPS simulator (`scripts/gps-sim.mjs`)

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| 1.1 | Single position write | `node scripts/gps-sim.mjs AMB-01` (v1 behavior via any run) | Position for AMB-01 appears under `positions/<id>` with `lat/lng/speed/updatedAt` |
| 1.2 | Unknown ambulance | `node scripts/gps-sim.mjs AMB-99` | Exits non-zero, message `Ambulance not found`, no RTDB write |
| 1.3 | Resolve by plate and by id | Run once with `AMB-01`, once with the raw doc id | Both work identically |
| 1.4 | Manual target mode | `npm run gps -- AMB-01 --to <lat> <lng> --speed 5000` | Moves toward target, prints `HOLD` + `target reached` on arrival, exits |
| 1.5 | Mission-aware mode (no `--to`) | Assign AMB-01 to a request; run `npm run gps -- AMB-01 --ticks 3` | Log shows current mission status (e.g. `[assigned\|]`), position moves toward patient |
| 1.6 | Status transitions rebuild route | With sim running at normal speed: crew presses *Start (en route)* → *Arrived on scene* → picks hospital → *Start transport* | Sim log status key changes; after `transporting` the unit heads to the selected hospital; at `onScene`/`atHospital` it holds (speed 0) |
| 1.7 | Mission resolved | Crew completes mission while sim running | Sim keeps holding at last position (status `resolved` → no target) |
| 1.8 | Missing args | `node scripts/gps-sim.mjs` | Usage message, exit code 1 |

## 2. Live positions (all maps)

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| 2.1 | Patient fleet map live | Start sim for one ambulance → patient app → Fleet Map tab | That marker is blue (live) at sim position; others blue-grey at base |
| 2.2 | Base fallback | Stop sim, delete `positions/<id>` in console | Marker snaps back to the ambulance's base coordinates |
| 2.3 | Crew ops map | Run sim for the crew's own ambulance → crew app | Own blue marker follows the sim; map stays centered on base (no jitter) |
| 2.4 | Dispatcher map | Sim running → dispatcher page | Fleet markers on the Leaflet map move at sim pace |
| 2.5 | Multiple ambulances | Run sims for 2 ambulances simultaneously | Both move independently everywhere |
| 2.6 | RTDB denied read (negative) | Temporarily revoke `positions` read rule → reload dashboard | Red `Load error: positions: permission_denied` banner inside the queue pane; layout (queue+map) still intact; restore rule afterwards |

## 3. Route polyline + ETA (patient)

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| 3.1 | Polyline appears | Create request, dispatcher assigns, crew accepts → patient tracking view | Indigo route line drawn from ambulance to patient (OSRM road geometry, not straight) |
| 3.2 | ETA chip | Same as 3.1 while status is assigned/accepted/enRoute | Status card shows `ETA ~N min` alongside the status label |
| 3.3 | ETA shrinks | Sim running; watch tracking view | ETA decreases as ambulance moves; polyline re-shapes when it moves >50 m (refetch throttled to ≥3 s) |
| 3.4 | ETA hidden off-phase | Crew presses *Arrived on scene* | `ETA` chip disappears (status no longer in assigned/accepted/enRoute) |
| 3.5 | OSRM fallback | Disconnect network (or block `router.project-osrm.org`), reopen tracking view | Straight-line polyline still drawn, ETA estimated at 40 km/h, no crash |
| 3.6 | No ambulance yet | Status `requested` (before assign) | No polyline, no ETA, patient marker only |

## 4. Dispatcher active-mission view

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| 4.1 | Select active mission | Click a row under *Active missions* | Row highlights; map pans/zooms to the patient; detail panel replaces the request panel |
| 4.2 | Detail content | Select an active mission | Shows status chip, ambulance plate, patient coordinates, full timeline (7 steps) |
| 4.3 | Timeline fills live | While watching, crew advances status | Corresponding timeline step gains green dot + HH:MM timestamp; current step is blue |
| 4.4 | Live route + ETA on map | Select active mission with sim running | Blue polyline ambulance→patient; `ETA ~N min · X.X km` line in panel; both refresh as ambulance moves |
| 4.5 | Switch selection | Click queue request → back to active mission | Assign panel and detail panel switch correctly; map re-pans; stale ETA resets |
| 4.6 | Resolved leaves active list | Crew completes mission | Mission disappears from *Active missions*; if it was selected, panel falls back cleanly |
| 4.7 | Timeline for late stages | Select mission in `transporting`/`atHospital` | Timeline shows completed steps up to current; ETA line hidden (no longer en route to patient) |

## 5. Chat (patient ↔ dispatcher ↔ crew)

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| 5.1 | Patient → dispatcher | Patient tracking → *Chat* → send message | Message appears instantly on dispatcher panel for that mission (role `Patient`, right-aligned for patient) |
| 5.2 | Dispatcher → patient | Reply from dispatcher detail panel | Appears in patient bottom sheet live (role `Dispatch`) |
| 5.3 | Crew participates | Crew mission screen → *Messages* card → send | Visible in both patient sheet and dispatcher panel (role `Crew`) |
| 5.4 | Unread badge | With sheet closed, receive 2 messages → do not open | Badge shows `2` on patient chat button; opening sheet then closing clears it |
| 5.5 | Badge accuracy | Send own message while sheet closed | Badge does not count your own pending send incorrectly (count reflects total) |
| 5.6 | Empty state | Open chat on a fresh mission | "No messages yet" (patient: "say hello", dispatcher: same idea) |
| 5.7 | Whitespace message | Send only spaces | Nothing is written to Firestore |
| 5.8 | History + order | Send 5 messages, reopen | Newest at bottom (patient/dispatcher), oldest→newest ordering correct; last 100 kept |
| 5.9 | Persistence | Reload dashboard mid-conversation | All messages still present after reconnect |

## 6. Voice links (`tel:`)

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| 6.1 | Patient calls dispatch | Patient tracking → *Call* | Native dialer opens prefilled with `+212522000000` (web: prompt/opens `tel:` handler) |
| 6.2 | Crew calls dispatch | Crew ops screen → *Dispatch* button | Dialer opens with the hotline |
| 6.3 | Callback number capture | Panic dialog → enter `0612345678` → SEND | Mission doc contains `patientPhone: "0612345678"` |
| 6.4 | Callback optional | Panic dialog → leave blank → SEND | Mission doc has **no** `patientPhone` field; no call link shown to dispatcher |
| 6.5 | Dispatcher calls patient | With `patientPhone` present, dispatcher selects the queued request | *Call 0612345678* link visible; clicking opens dialer/tab with number |
| 6.6 | Android visibility | Build crew/patient APK on Android 11+ | DIAL intent works (manifest `<queries>` entry present); no `ActivityNotFound` crash |

## 7. Cross-app edge cases

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| 7.1 | Reject returns to queue | Crew rejects an assigned request | Mission back to `requested`, `ambulanceId` null, appears in dispatcher queue again; sim holds (no target) |
| 7.2 | Reassign after reject | Dispatcher assigns a different ambulance | New crew sees incoming banner; patient sees correct live marker (route rebuilds) |
| 7.3 | Guest vs profile patient | Run one mission as guest, one logged-in with medical profile | Dispatcher sees "Guest caller" vs blood/allergies/conditions; chat works both ways |
| 7.4 | Two tabs same role | Two dispatcher tabs open | Assign from tab A reflects live in tab B (Firestore snapshot) |
| 7.5 | Sim during `requested` | Run sim while mission unassigned | Position holds at base (mission-aware mode has no target) |

## 8. Regression gate (run before calling M3 "done")

```powershell
# Dashboard
cd apps/dashboard; npm run build          # must exit 0

# Patient app
cd apps/patient_app; flutter analyze; flutter test   # 0 issues, 3 tests

# Crew app
cd apps/crew_app; flutter analyze; flutter test      # 0 issues, 1 test

# Full demo lifecycle (manual)
# panic → queue → suggest → assign → accept → enRoute → onScene
# → hospital → transporting → atHospital → resolved
# Verify at each step: patient status chip, dispatcher timeline,
# crew button, sim route target, chat availability.
```

**Known environment quirks during testing**
- OneDrive may lock `build\unit_test_assets` → delete manually and rerun `flutter test`.
- Emulator keyboard can't type `@` → use `flutter run -d edge` instead.
- New shells need `$env:Path = "$env:USERPROFILE\flutter\bin;$env:Path"` (PATH not persisted).
