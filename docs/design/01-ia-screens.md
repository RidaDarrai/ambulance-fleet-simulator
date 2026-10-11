# Patient / Caller App — Information Architecture & Screen Spec

> **Stage 2 deliverable** · Works from `baseline-report.md` (roles, flows, lifecycle) + `design-tokens.md` v1 (colors, type, spacing, safety tokens).
> Design direction: **HYBRID** — Calm & Clinical default shell; a screen shifts to Mission-Critical theming whenever an active mission exists (per `research/moodboard-directions.html` recommendation).
> Status: **proposed** — open decisions at the end need sign-off before Flutter build starts.

---

## 1. Navigation model

**Bottom tab bar — 4 items, identical for guest and authenticated users** (labels ≤2 words, per IA labeling rules):

| Tab | Guest behavior | Authenticated behavior |
|---|---|---|
| **Map** | Full fleet view, panic trigger | Same + "my unit" pin when a mission is active |
| **Requests** | Active/last request + emergency hotline | Request history incl. attached medical data |
| **Profile** | "You're using the app as a guest" card + Sign in | Medical profile, emergency contacts, sign out |
| **Settings** | Notifications, appearance, accessibility, about | Same |

- **Home = Map tab.** Logo/tab tap returns to the fleet map from anywhere (nav rule: home accessible anywhere).
- **Max 3 taps** to anything: e.g. History → `Requests` tab → tap an entry → detail = 2 taps. Panic = 1 tap from home.
- **Modal vs push:** confirmations, comms, and arming use **sheets/modals** (interrupting flows). Screen-to-screen progress (history → detail, request → mission) uses **push** with a visible back button.
- **Deep links (stable scheme `ambulance://`)**: `/mission/:id`, `/request/:id`, `/request/new`, `/hotline`, `/profile/medical`, `/settings`. Every FCM push deep-links into the matching mission/request screen, not home.
- **Android back:** during an **active mission**, the back button minimizes to the Map (never exits the app, never exits a live mission silently). During **request arming**, back cancels the trigger. Every pushed screen has a back/close in the top-left.
- **Tab badges:** `Requests` shows a subtle badge with the count of your pending + active requests (cleared when the tab is viewed).
- Panic is **not** a nav item — it is a floating action pinned to the Map tab (destructive actions never belong in tab bars).

## 2. IA tree

```
Patient App
├─ /onboarding  ·first-run: welcome → permissions (location, notifications, reduced-motion check)
├─ /fleet  ·Map tab (home)
│   ├─ request arming sheet (panic) ──> /request/confirm ──> /request/queued ──> /mission/:id
│   └─ /hotline (guest fallback, also reachable from arming sheet)
├─ /requests  ·Requests tab
│   └─ /history/:id  ·request/mission detail (resolved view = timeline + outcome)
├─ /mission/:id  ·live tracking (Transiently Mission-Critical themed)
│   ├─ timeline sheet (status phases)
│   └─ comms sheet (voice/chat with crew or dispatcher)
├─ /profile  ·Profile tab (guest card OR medical summary)
│   └─ /profile/medical  ·blood type, allergies, chronic conditions, emergency contacts (auth only)
└─ /settings  ·notifications, appearance (light/dark/system), accessibility (reduced motion), about
```

## 3. Screen register

Anatomy follows tokens: mobile padding 16px / `space.6` vertical, cards `radius.lg` + `shadow.card`, ETA always `type.display.mono` (tabular), status only via `color.status.*`.

### 3.1 `/onboarding` — First run
- **Purpose:** request location + notification permissions; detect reduced-motion preference.
- **Elements:** brand mark (`color.primary`), 3 short value bullets, primary CTA "Continue", quiet "No thanks, I'm just browsing" (belongs to guest flag).
- **States:** permission-denied → explainer card with **Settings deep link** (permission-denied pattern); offline → skip to guest map with `OfflineBanner`.
- **Rules:** never blocks the Map with a hard gate — guest browsing is valid (baseline: guest can view fleet + request).

### 3.2 `/fleet` — Fleet Map (home)
- **Purpose:** see available units near you; trigger a request.
- **Elements:** light desaturated map (`map` layer), available units as calm green dots (`color.status.resolved`/available rule), your location `color.primary` pin; bottom sheet: unit count + avg response ("3 units available · avg response 7 min"), medical-attach chip (auth), **SOS floating button `panic.size` 72px `color.danger`**.
- **States:**
  - *Loading:* skeleton sheet + subtle map placeholder (`surface.muted`), no shimmer text on the map.
  - *Offline:* `OfflineBanner` (pending-amber); SOS still tappable → request is **queued locally** and shown "Waiting for connection" (see 3.4).
  - *Empty:* no units within range → "No units near you right now" + still allow request (it enters FIFO queue; nearest-unit suggestion happens at dispatch time regardless of distance).
  - *Active mission:* sheet collapses to the **Mission-Critical hero** (dark map, status strip, mono ETA) → opens `/mission/:id`.

### 3.3 Panic / request arming (sheet on `/fleet`)
- **Purpose:** one-tap trigger with accidental-trigger safety — trigger fires immediately, 5s **Undo** snackbar ("Request sent · Undo") per undo-over-confirm standard (cost of mistake is low, can be cancelled).
- **Elements:** full-bleed `color.danger.surface` sheet, "Emergency request sent", auto-drafted location line, medical-attach summary (auth), primary "Call dispatcher" + secondary "Cancel request".
- **Rules:** confirm-then-fire is *not* used (baseline says one-tap); undo is the safety net.

### 3.4 `/request/confirm` → `/request/queued`
- **Purpose:** confirm location + (auth) attached medical profile → submit.
- **Elements:** map pin with draggable correction, `medical.surface`/`border` summary card (O+ · allergy · contacts count), primary "Request ambulance".
- **States:**
  - *Error:* e.g. geocoding failure → inline error + Retry (formula: what failed → why → what to do).
  - *Queued:* FIFO position shown with `color.status.pending` (amber) "Position 2 in queue"; nearest-unit suggestion happens at dispatch time (baseline) — show "Checking available units".
  - *Offline:* pending-amber chip "Waiting for connection — request will send automatically".

### 3.5 `/hotline` — Guest fallback
- **Purpose:** guest who needs help without auto-attach taps **Call dispatcher** (native dialer number) + share-location option.
- **Elements:** large `color.primary` call button, "Also send your location to dispatch" toggle.

### 3.6 `/mission/:id` — Live mission tracking (THE core screen, Mission-Critical themed)
- **Purpose:** see unit on route, ETA, contact crew, watch lifecycle.
- **Elements:** dark map (`bg-dark`), status-colored polyline + heading-aware ambulance marker with halo, top **status strip** (4px strip + label per `color.status.*`, e.g. enRoute cyan "EN ROUTE — Unit A-12"), hero **ETA countdown `type.display.mono`**, crew card (crew count, call / chat buttons `color.primary`), "Open timeline" chip.
- **States by lifecycle (section 4)** — loading (mission not yet assigned), reassigned (new unit toast in `color.status.dispatched`), resolved (confetti-free, calm success card + link to history).
- **Back/minimize:** back returns to Map; active mission stays live.

### 3.7 Timeline sheet (from `/mission/:id`)
- **Purpose:** Zomato-style lifecycle progress: `pending → dispatched → enRoute → onScene → transporting → atHospital → resolved`, each step `color.status.*` with timestamps (relative + tap for full time).
- **Empty-ish state:** queued mission shows only past steps up to `dispatched`; greyed upcoming steps.

### 3.8 Comms sheet (from `/mission/:id`)
- **Purpose:** one-tap voice/chat to crew or dispatcher.
- **Elements:** two primary actions (crew / dispatcher), chat thread with `surface` bubbles + timestamps; error state "Call failed — [Retry]" plus "Send message" fallback (network-resilient: chat queues offline).

### 3.9 `/requests` + `/history/:id`
- **Purpose:** active request(s) at top, resolved history below (sorted date desc, changeable).
- **Elements:** list cards with status badge (`color.status.*`), relative timestamps; **empty state** per standard: icon + "No requests yet" + message + primary CTA "View the map"; first-use variant invites the first action.
- Chip per card: "Medical attached" (auth).

### 3.10 `/profile` + `/profile/medical`
- **Purpose:** auth: view/edit medical profile; guest: sign-in card.
- **Elements:** summary tiles (`medical.surface`), edit sheets (blood type segmented control, allergy/chronic condition chips, contact list).
- **Form states:** inline validation on focus-leave; save error → Retry; optimistic-save with offline queue chip.

### 3.11 `/settings`
- **Purpose:** notifications (per-type on/off: dispatch updates, request status, safety), appearance (light/dark/system), accessibility (reduce motion — **disables the panic pulse**, token requirement), emergency-contact quick-call toggle, about.
- **IA groupings:** Account / Notifications / Appearance / Accessibility / About (settings grouping standard).

## 4. Lifecycle → tracking-screen mapping

| Status | Hero color (token) | Tracking screen shows |
|---|---|---|
| pending | `pending` amber | "Checking available units" shimmer; no map hero |
| dispatched | `dispatched` blue | "Unit assigned — starting now"; unit pin appears |
| enRoute | `enRoute` cyan | **ETA countdown**, polyline, crew card |
| onScene | `onScene` violet | "Crew has arrived"; provide-access toggle for crew |
| transporting | `transporting` orange | "En route to [hospital]" + target marker |
| atHospital | `atHospital` teal | "Handover in progress" |
| resolved | `resolved` green | Success card → link to history summary |

Transients: *reassigned* (unit timeout/rejection per baseline) → `dispatched` toast "New unit assigned"; *escalated* → red warning only for critical medical flags.

## 5. Shared cross-cutting states (build once, reuse)

| State | Component & wiring |
|---|---|
| Loading | Skeleton rows (`surface.muted` blocks) — never lorem text |
| Empty | 4-part standard: icon → positive heading → message → CTA (see 3.9) |
| Retryable error | Inline message + **Retry**; formula: happened → why → next |
| Offline | Top `OfflineBanner` (pending-amber); panic queues, chat queues, ETA falls back to "updates paused" |
| Permission denied | Explainer card + **Settings** deep link, never a dead end |
| Reduced motion | `panic.animation` pulse disabled; transitions shorten |
| Dark mode | Token dark variants throughout (`bg-dark`, panels `#1E293B`, status dark hexes) |

## 6. Locked decisions (signed off 2026-10-10)

1. **Panic undo window:** 5s Undo snackbar after trigger.
2. **Emergency contacts:** auto-notified on panic, **on by default**, Settings toggle to disable.
3. **Guest panic:** no phone verification gate — a guest can request directly; hotline is an additional path, not a requirement.
4. **Comms default:** voice-first with automatic chat fallback when a call fails or offline.
5. **Demo scope:** ship **Fleet Map → Panic/Request → Live Mission** first; Timeline, History, Profile, Settings, Onboarding follow in v0.2.

---

*Next stage: per-screen Flutter / Material 3 widget specs starting with `/fleet` + panic arming, then `/mission/:id`.*