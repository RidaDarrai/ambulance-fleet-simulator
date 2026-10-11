# Patient/Caller App — Information Architecture (Step 2)

> Flutter · Material 3 · built on `baseline-report.md` + `design-tokens.md`
> Rules applied: 3-tap rule, max 2 hierarchy levels, ≤5 bottom tabs, modal-vs-push discipline, contextual permissions.

## 1. Navigation model

| Layer | Choice |
|---|---|
| Top-level | **3 tabs** — `Map` · `Missions` · `Profile` (guest sees `Map` · `Help` · `Profile`) |
| Panic button | **FAB on Map, never a tab** (bottom tab bars must not host destructive actions) |
| Drill-down | Push stack (screen has back/close top-left) |
| Quick tasks | Bottom sheets (unit detail, location confirm, quick actions) |
| Interruptive | Dialogs only for destructive confirm (cancel mission, delete account) + pre-permission explainers |
| Deep links | `ambulance://map?unit={id}` · `ambulance://mission/{incidentId}` · FCM lands on the exact mission screen |
| Back behavior | Sheets → dismiss; pushed screens → pop; mission active → back keeps a persistent banner on Map (never loses the mission) |

## 2. Guest screen map

```
Splash ─ (first run only) ─> Onboarding (3 steps, Skip always visible)
        └─> Pre-permission explainers (location, notifications) ─> system dialogs
                                      │
                                      ▼
                        ┌───────── MAP (tab 1) ─────────┐
                        │ full-bleed fleet map          │
                        │ • unit markers (status color) │
                        │ • bottom sheet: nearest units │
                        │ • [Call dispatcher] hotline   │
                        │ • PANIC FAB  ──────────┐      │
                        └────────┬───────────────┼──────┘
                       tap unit  │               │ tap (1)
                                 ▼               ▼
                    Unit detail sheet      Panic request flow
                    (1 tap from map)       1. Location confirm sheet
                                           2. Guest details (name, phone*)
                                           3. Send → Waiting in queue
                                                    │
                                                    ▼
                                    ┌──── LIVE MISSION TRACKING ────┐
                                    │ map + polyline + ETA countdown │
                                    │ status timeline (enum)         │
                                    │ call / chat crew + dispatcher   │
                                    │ [Cancel request] (confirm)      │
                                    └───────────────┬─────────────────┘
                                                    ▼
                                            Mission summary (resolved)
        ┌────────── HELP (tab 2) ──────────┐   ┌────── PROFILE (tab 3) ──────┐
        │ FAQ / how dispatch works         │   │ Sign in / Create account    │
        │ Call dispatcher (tel: deep link) │   │ Why save a medical profile  │
        │ Privacy policy · Terms · About   │   │ App settings (theme, lang)  │
        └──────────────────────────────────┘   └─────────────────────────────┘
```

**Guest does NOT see:** Missions tab (history is account-bound), Medical profile editor.
Sign-in entry points are contextual, not a wall: after first request, and inside Profile.

## 3. Logged-in screen map

```
MAP (tab 1)  = fleet map + panic FAB + active-mission banner (if any)
   ├─ Unit detail sheet
   ├─ Panic request flow → Waiting → LIVE MISSION TRACKING → Summary
   └─ (from banner) resume mission in 1 tap

MISSIONS (tab 2)
   ├─ Active mission (pinned, colored left border = mission status)
   ├─ History list (status chip + relative time, tap → detail)
   └─ Mission detail / summary (timeline, crew, timestamps)

PROFILE (tab 3)
   ├─ Account header (name, phone, avatar)
   ├─ Medical profile ── Blood type · Allergies · Chronic conditions
   │        └─> Edit forms (one grouped form per section)
   ├─ Emergency contacts ── add / edit / remove (confirm dialog)
   ├─ Notifications ── per-type toggles: mission updates (on, locked),
   │                   crew messages (on), tips (opt-in)
   ├─ Privacy & permissions ── location mode, data export, delete account
   ├─ Appearance / Language
   └─ About ── version, privacy policy, terms, help
```

## 4. 3-tap verification

| Content | Path | Taps |
|---|---|---|
| Request an ambulance (guest) | Map → Panic FAB → Send | **2** |
| Request (logged-in) | Map → Panic FAB → Send | **2** |
| Nearest unit + ETA | Map → tap marker | **1** |
| Active mission status | any tab → banner / Missions | **1–2** |
| Medical profile | Profile → Medical profile | **2** |
| Edit allergies | Profile → Medical profile → Allergies | **3** |
| Emergency contact | Profile → Emergency contacts | **2** |
| Call dispatcher | Map → Call dispatcher | **1** |
| Past mission detail | Missions → mission | **2** |
| Notification settings | Profile → Notifications | **2** |
| Cancel mission (deep) | Map → banner → Cancel → confirm | **3** |

## 5. Screen inventory (spec'd in Step 3)

| # | Screen | Guest | Logged-in |
|---|---|---|---|
| 1 | Splash / first-run onboarding (3 steps) | ✓ | ✓ |
| 2 | Pre-permission explainers (location, notifications) | ✓ | ✓ |
| 3 | Fleet map (home) | ✓ | ✓ |
| 4 | Unit detail sheet | ✓ | ✓ |
| 5 | Panic request flow (location → details → send) | ✓ (lite) | ✓ (profile auto-attached) |
| 6 | Waiting for dispatch (queue position, countdown) | ✓ | ✓ |
| 7 | Live mission tracking (map + ETA + timeline + comms) | ✓ | ✓ |
| 8 | Mission summary / resolved | ✓ | ✓ |
| 9 | Missions list (active + history) | — | ✓ |
| 10 | Mission detail (timeline, timestamps) | — | ✓ |
| 11 | Medical profile + section editors | — | ✓ |
| 12 | Emergency contacts | — | ✓ |
| 13 | Sign in / Create account | ✓ | — |
| 14 | Help / FAQ + hotline | ✓ | ✓ |
| 15 | Notifications settings | — | ✓ |
| 16 | Privacy & permissions, Appearance, About | partial | ✓ |
| 17 | Offline / permission-denied overlays (cross-cutting states) | ✓ | ✓ |

## 6. IA decisions & rationale

- **Panic is an action, not a place.** It lives as a persistent FAB on the map (1 tap from launch) — tab bars are for destinations.
- **2 hierarchy levels max:** tabs → screens → sheets. No nested menus; Medical profile sections are flat cards, not a tree.
- **Guest → account conversion is contextual** (after first request, when attaching a medical profile would have helped), never before the guest can see the fleet — value first (ux-help-onboarding).
- **Permissions in sequence, at moment of use:** location before the map renders, notifications only after the first request is placed (ux-notifications, ux-safety-privacy).
- **Mission never gets lost:** back from tracking keeps a persistent banner + Missions tab pin (ux-navigation back-stack rule).
- **Offline is a layer, not a screen:** global banner + cached map + queued request writes (ux-network).
