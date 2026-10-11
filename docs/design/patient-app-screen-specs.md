# Patient/Caller App — Screen Specifications (Step 3)

> Direction: **Hybrid** — *Calm & Clinical* at rest (light `#F8FAFC`), *Mission-Critical* during an active mission
> (dark `#0F172A` HUD, full-strength status colors). All values come from `design-tokens.md`. No invented tokens.

---

## 0. Global conventions (apply to every screen)

| Concern | Rule |
|---|---|
| Theme switch | Idle screens = light. Automatic switch to dark mission theme when `incident.status ∈ {dispatched, enRoute, onScene, transporting}`; back to light at `resolved`. Not a user setting. |
| Skeletons | Any load >400 ms → content-shaped skeleton + shimmer (never a bare spinner on content screens). |
| Motion | Transitions ≤300 ms; panic pulse (`panic.animation` 1.6 s) is **disabled under reduced-motion**. |
| Digits | All ETA/countdown/distance use `type.display.mono` / `type.mono`, `fontVariantNumeric: tabular`. |
| Status color | Only from `color.status.*`; each status chip pairs color **with** an icon + word (never color alone). |
| Red | `color.danger` reserved for panic, critical medical alert, cancel/reject. |
| Touch targets | ≥44 pt (iOS) — panic = `panic.size` 72 px. |
| Safe areas | 16 px horizontal padding, `space.6` (24 px) vertical, bottom safe-area aware. |
| Offline | Global top banner + queued writes; never a dead-end screen. |

---

## 1. Splash & first-run onboarding

**Purpose:** 10-second comprehension of value; get to the fleet map fast. Shown only on first launch (after that: splash ≤400 ms → map).

**Key elements:** App mark + name; 3 carousel pages max, one concept each, `PageView` with dot indicator and **Skip** always visible; progress label "1 of 3"; primary button "Get started", secondary text "Skip".
Pages: ① *See ambulances near you, live* (map illustration) ② *One tap to request help* (panic illustration) ③ *Save medical info so crews see it sooner* (profile illustration).

**States:** loading (logo + 400 ms skeleton of page 1) · empty (n/a) · error (onboarding content is bundled — n/a; if remote config fails, fall back to bundled copy, log, never block) · offline (works fully offline — bundled) · permission-denied (n/a here; requested in §2).

**Gestures:** horizontal swipe between pages; Skip; Android back = Skip.

**Microcopy:** "Skip" · "Get started" · "You can change this later in Settings."
Error fallback: "We couldn't load the latest info. Showing the basics."

**Tokens:** `color.background`, `color.surface`, `color.primary`, `color.primary.foreground`, `type.h1`, `type.body`, `type.label`, `space.4/6/8`, `radius.lg`, `shadow.card`.

---

## 2. Pre-permission explainers (location · notifications)

**Purpose:** Explain *why* before the OS dialog; raise grant rate; always give a recovery path.

**Key elements:** Bottom sheet, icon, title, 1-line reason, primary "Allow location" / "Not now", link "Why we ask".
- **Location:** asked when the Map first renders → "While using" only.
- **Notifications:** asked **after the first request is placed**, never at launch.

**States:** loading (n/a) · empty (n/a) · error (n/a) · offline (n/a) · **permission-denied:** show persistent non-blocking chip on Map "Location off — showing last known area" + row "Enable in Settings › App › Location" (deep-link `app-settings:`).

**Gestures:** drag-down dismiss; tap outside dismiss (both preserve "ask again later" ability).

**Microcopy:** "Share your location so we can send the nearest ambulance." / "Turn on location" / "Not now" ·
Notifications: "Get told the moment a crew is assigned." / "Allow notifications" / "Maybe later".
Denied: "Location is off. Turn it on in Settings so we can find you."

**Tokens:** `color.surface`, `color.border`, `color.primary`, `color.text.primary/secondary/muted`, `type.h2`, `type.body`, `space.4`, `radius.lg`, `shadow.mapPanel`, `space.3` icon gaps.

---

## 3. Fleet map (home)

**Purpose:** See available ambulances in real time; the app's launch screen for all users.

**Key elements:**
- Full-bleed map (light/desaturated in idle theme) with unit markers filled by unit status (`available` → success green; `enRoute` etc. → their token).
- Draggable bottom sheet (peek ¼, half ½, expanded ¾): title "6 ambulances near you", **horizontal unit cards** (unit ID, plate, distance, status chip) or empty-state block.
- Top: location search/center button (right), offline banner slot (top).
- **Panic FAB** (72 px, `shadow.fab`, pulsing ring) bottom-right above sheet + **Call dispatcher** outlined button (`tel:` link) in sheet header.
- Active-mission banner (if any) pinned above sheet — 1 tap resumes tracking.

**States:** loading → map tiles skeleton + 2–3 shimmer unit cards · empty → "No ambulances available nearby. Call the dispatcher instead." + `Call dispatcher` button (positive framing, never a bare blank map) · error → inline sheet message "Couldn't load fleet. Check your connection and try again." + **Retry** · offline → top banner "No connection — showing last known positions (2 min old)", markers desaturated + hollow ring, panic still enabled (request queued) · permission-denied → map centered on last known/default city + chip "Location off" + "Open Settings".

**Gestures:** pan/zoom map; drag sheet (snap points); tap marker → unit sheet (§4); tap sheet header → expand; swipe down sheet → collapse; pull-down on map → refresh; long-press pin → "Set this as my location" (logged-in).

**Microcopy:** "6 ambulances near you" · "Updated 2s ago" · "Call dispatcher" · "Request help" (FAB label for a11y) · Empty: "No ambulances nearby right now." · Error: "We couldn't load the fleet. Pull down to try again."

**Tokens:** `color.background`, `color.primary` (markers, my-location), `color.status.*` (marker fills, chips), `color.surface`, `color.border`, `type.h2` (sheet title), `type.body.small`, `type.mono` (IDs, coords), `space.4`, `radius.lg` (sheet), `radius.md` (cards), `shadow.card`, `shadow.mapPanel`, `shadow.fab`, `panic.size`, `panic.animation`.

---

## 4. Unit detail sheet

**Purpose:** Confidence before requesting: who's nearest, how far, how fast they move.

**Key elements:** Unit avatar/plate, status chip + word, distance & ETA (`type.mono`), crew/paged info (if public), vehicle type chip, primary button **"Request this unit"** (logged-in) / **"Request help"** (guest), secondary **"Call dispatcher"**.

**States:** loading (skeleton rows) · empty (unit went unavailable → auto-dismiss with snackbar "Unit A-12 is no longer available. Showing the next nearest.") · error → "Couldn't get live details." + Retry · offline → last-known values + "2 min old" label · permission-denied (n/a).

**Gestures:** tap outside/drag down to dismiss; swipe horizontally on card → next unit; tap Request → §5.

**Microcopy:** "1.2 km · ETA 4 min" · "Available now" · "Request help".

**Tokens:** `color.surface`, `color.border`, `color.status.*`, `color.primary`, `type.h3`, `type.body.small`, `type.mono`, `space.4`, `radius.md`, `shadow.mapPanel`.

---

## 5. Panic request flow (guest lite / logged-in full)

**Purpose:** Create the incident in ≤2 taps with minimum friction.

**Key elements (single screen, stacked steps):**
1. **Location confirm** — pin on mini-map + reverse-geocoded address + "Edit pin" (drag).
2. **Who needs help** — guest: `Name`, `Phone` (tel keyboard) · logged-in: shows "Using your saved details" chip.
3. **What's happening** (optional, ≤5 chips: "Unconscious", "Chest pain", "Breathing", "Injury", "Other") + free-text (optional).
4. **Attach medical profile** toggle (logged-in, default ON, `medical.surface` preview of blood type/allergies).
5. Full-width danger button **"Send request"** (72 px, `shadow.fab`); secondary text "Call dispatcher instead".

**States:** loading (button shows inline progress, label "Sending…", inputs disabled but visible) · empty (validation: required fields empty) · error (submit failed) · offline (request queued: banner "No connection — we'll send your request as soon as you're back online." + button becomes "Save request") · permission-denied (location denied → manual address field appears, flow still completes).

**Gestures:** drag pin to adjust; tap chips to toggle; Submit; swipe-back preserves entered data.

**Microcopy:** "Where should we send help?" · "Add pin" · "This request will include your medical profile." (privacy transparency) · Validation: "Enter a phone number so the crew can reach you." · Error: "We couldn't send your request. Check your connection and tap Send request again." · Offline: "Your request is saved and will send automatically."

**Tokens:** `color.danger`, `color.danger.hover`, `color.danger.surface`, `color.danger.border`, `medical.surface`, `medical.border`, `color.surface`, `color.border`, `type.h1`, `type.body`, `type.label`, `space.4/6`, `radius.lg`, `shadow.fab`, `panic.size`.

---

## 6. Waiting for dispatch (status: `pending`)

**Purpose:** Reduce anxiety while the request sits in the FIFO queue; prove the system is alive.

**Key elements:** Status band in `color.status.pending` (amber) with icon + "In the queue"; **queue position** ("Position 2 of 5") and **elapsed timer** (`type.display.mono`); live map with your pin pulsing; card "A dispatcher is reviewing your request"; actions: **Call dispatcher** (primary outline) and **Cancel request** (danger text, confirm dialog); note "Keep this screen open".

**States:** loading (immediately after submit → optimistic "Request sent" + skeleton) · empty (n/a) · error (write rejected: full-width danger card "Request failed — dispatcher never received it." + **Try again** + **Call**) · offline (queued + banner "Waiting for connection…" + queued icon on status band) · permission-denied (n/a).

**Gestures:** pull-to-refresh; tap Call; tap Cancel → confirm dialog (Cancel left, "Cancel request" right in red); Android back → minimizes to banner, doesn't cancel.

**Microcopy:** "Your request is in the queue" · "Position 2 of 5" · "Dispatcher reviewing" · Cancel dialog: title "Cancel this request?" body "A crew has not been assigned yet. If you still need help, you'll have to send a new request." buttons "Keep request" / "Cancel request".

**Tokens:** `color.status.pending`, `color.danger`, `color.danger.surface`, `color.surface`, `color.border`, `type.display.mono` (timer), `type.h2`, `type.body`, `type.mono` (request ID `INC-4471`), `space.4`, `radius.md`, `shadow.card`.

---

## 7. Live mission tracking (dispatched → enRoute → onScene → transporting → atHospital)

**Purpose:** The core screen: where the crew is, when they arrive, how to reach them.

**Key elements (dark mission theme):**
- Map with **route polyline** in the current status color, glowing ambulance marker, your pin; dark basemap.
- **Status band** (full-width, status color + icon + word): "Dispatched" → "En route" → "Arriving soon" → "On scene" → "Transporting to St. Mary's".
- **ETA hero** `type.display.mono` 32/40 tabular (`04:12`) + sublabel "Unit A-12 · 1.2 km".
- **Timeline stepper** (vertical, 5 dots) with completed/active/pending states — active dot = status color.
- **Crew card:** unit ID, plate, crew name, actions **Call** / **Chat** (one-tap to crew & dispatcher).
- **Medical attached confirmation** chip (logged-in): "Medical profile sent ✓".
- Persistent **Call dispatcher** + **Cancel request** (danger, confirm) in sheet.

**States:** loading (skeleton ETA + shimmer card while first GPS ping arrives, ≤2 s) · empty (n/a — a mission always has data) · error ("Couldn't update the crew position. Last update 40 s ago." + Retry) · offline (banner "Offline — last position 40 s ago", polyline frozen at last ping, ETA replaced by "—" with label "ETA unavailable offline", comms buttons disabled with tooltip, **Cancel disabled** but "Call dispatcher" switches to `tel:` which still works) · permission-denied (n/a — map works without own-location permission; your pin hidden with note "Your location is off — the crew has your saved address").

**Gestures:** pan/zoom; drag sheet (peek/half/full) — map re-frames when sheet snaps; tap Call/Chat; swipe timeline rows → jump map to that status timestamp (history); Android back → minimize to banner.

**Microcopy:** "Unit A-12 is on the way" · "Arriving in 04:12" · "Stay where you are — the crew can see your pin." · "Medical profile sent to the crew" · Delay: "The crew is taking longer than expected. A dispatcher has been notified." · Offline: "You're offline. We'll reconnect automatically."

**Tokens:** full status set (`color.status.dispatched/enRoute/onScene/transporting/atHospital`), `color.background.dark`, `color.text.inverse`, `color.text.muted`, `color.primary`, `color.danger`, `type.display.mono`, `type.h2`, `type.body`, `type.label`, `type.mono`, `space.4`, `radius.md/lg`, `shadow.mapPanel`, `shadow.fab`.

---

## 8. Mission summary (resolved)

**Purpose:** Closure + reassurance + a nudge to keep the profile updated.

**Key elements:** Success check (status `resolved` green), "Help arrived at 14:32"; recap card (unit, crew, total time `type.display.mono`, timestamps per status); **"How was the response?"** 1–5 rating (optional); button **"Done"** → Map; link "Update your medical profile".

**States:** loading (skeleton) · empty (n/a) · error (summary failed → still show mission resolved banner + "Details unavailable" + Retry) · offline (shows cached summary, "Saved on this device") · permission-denied (n/a).

**Gestures:** tap Done (pops to root), tap rating, tap profile link.

**Microcopy:** "Help arrived at 14:32" · "Total time 11 min" · "Rate the response (optional)" · "Done".

**Tokens:** `color.status.resolved`, `color.surface`, `color.primary`, `medical.surface` (profile nudge card), `type.h1`, `type.display.mono`, `type.body`, `space.4/6`, `radius.md`, `shadow.card`.

---

## 9. Missions list (logged-in)

**Purpose:** One place for active + past missions; entry point to detail.

**Key elements:** Pinned **active mission row** (2 px left border in mission status color, live ETA chip) above segmented control **Active | History**; history rows: status chip + incident ID (`type.mono`) + relative time ("2 hours ago", full timestamp on tap) + hospital/crew; skeleton loading; pagination on scroll.

**States:** loading (3 skeleton rows, shimmer) · empty → illustration + heading "No missions yet" + message "Requests you send will appear here with their status and crew details." + action **"Back to map"** · error → "We couldn't load your missions." + **Retry** · offline → cached list + "Showing saved missions" banner · permission-denied (n/a).

**Gestures:** tap row → detail; swipe row → Share/ Delete? (**no** — mission records are non-destructive: swipe disabled, keep it simple); pull-to-refresh; segmented switch.

**Microcopy:** relative times; empty-state as above; error as above.

**Tokens:** `color.status.*` (chips + 2 px left border per token §7), `color.surface`, `color.border`, `type.h3`, `type.body.small`, `type.mono`, `space.3/4`, `radius.md`, `shadow.card`.

---

## 10. Mission detail

**Purpose:** Audit trail of a past mission — timestamps, crew, outcome.

**Key elements:** Header (incident ID, status chip, created time); **timeline** of all 7 statuses with mono timestamps; route snapshot (static map image, polyline in final status color); crew/vehicle/hospital card; attached-medical indicator; "Report an issue" link.

**States:** loading (skeleton timeline) · empty (n/a — reached only from a row) · error → "Mission details couldn't be loaded." + Retry · offline → cached · permission-denied (n/a).

**Gestures:** back; tap map snapshot → expand full-screen; tap hospital → open in Maps app (external deep link).

**Microcopy:** "Created 14:21" · "Assigned to Unit A-12" · "Handed off at St. Mary's 14:32".

**Tokens:** `color.status.*`, `color.surface`, `color.border`, `color.text.secondary`, `type.h1`, `type.h3`, `type.body`, `type.mono` (all timestamps), `space.4`, `radius.md`, `shadow.card`.

---

## 11. Medical profile + section editors

**Purpose:** Store what crews need: blood type, critical allergies, chronic conditions, emergency contacts — auto-attached to requests.

**Key elements:** Summary card (`medical.surface`/`medical.border`) with 4 rows: **Blood type** · **Allergies** · **Chronic conditions** · **Emergency contacts** — each row shows value or "Not added" + chevron; "Last updated 3 days ago" (`type.mono`); lock/privacy line "Shared only when you send a request"; banner nudge for incompleteness "Add your blood type — crews use it first" with action.
Editors: one grouped form per section, visible labels above fields, ≤6 fields, save button fixed bottom; allergy input offers chip suggestions + free text; blood type = single-select list (smart default empty, no pre-ticked).

**States:** loading (skeleton summary rows) · empty → first-use empty state: icon + "Add your medical info" + "Crews see this the moment you request help." + **Add blood type** (primary action) · error → "We couldn't save your changes. Your entries are kept on this device — tap Save again." + inline retry (never wipe the form) · offline → edits queue locally, row shows "Pending sync" chip · permission-denied (n/a).

**Gestures:** tap row → editor push; swipe back preserves unsaved input (dialog "Discard changes?" if dirty); autosave after 800 ms idle for long text.

**Microcopy:** "Not added" · "Shared only when you send a request" · Validation: "Pick the blood type from the list." · Save: "Saved ✓" (snackbar 2 s).

**Tokens:** `medical.surface`, `medical.border`, `color.surface`, `color.border`, `color.primary`, `color.text.secondary/muted`, `type.h2`, `type.h3`, `type.body`, `type.label`, `type.mono`, `space.4`, `radius.md`, `radius.sm` (inputs), `shadow.card`.

---

## 12. Emergency contacts

**Purpose:** Who the crew calls when the patient can't.

**Key elements:** List of contacts (avatar, name, relationship, `tel:` button); **Add contact** primary button; max 5 (helper text when reaching limit); per-row overflow → Edit / Remove (confirm dialog).

**States:** loading (2 skeleton rows) · empty → icon + "No emergency contacts yet" + "Add someone we should call if you can't answer." + **Add contact** · error (load) → "We couldn't load your contacts." + Retry; save error → keep input, "Try again" · offline (queued, "Pending sync") · permission-denied (n/a).

**Gestures:** tap row → edit; tap phone icon → dial immediately; add → form push; remove → confirm dialog.

**Microcopy:** Remove dialog: "Remove Sarah?" / "She will no longer be called during an emergency." / "Remove" (red) · Fields: "Full name", "Relationship", "Phone number".

**Tokens:** `color.surface`, `color.border`, `color.danger` (confirm only), `color.primary`, `type.h3`, `type.body`, `type.label`, `space.4`, `radius.md`, `shadow.card`.

---

## 13. Sign in / Create account

**Purpose:** Convert contextually without blocking value.

**Key elements:** Value card on top ("Save medical info so crews see it sooner"); form: phone (primary, tel keyboard) + OTP 6-digit step (auto-advance, paste support), or email+password on create; **"Continue as guest"** always visible; privacy policy link inline near the submit button; "Step 1 of 2" indicator on create.

**States:** loading (button progress) · empty (validation) · error (wrong code: "That code doesn't match. Try again or request a new one."; server: "We couldn't sign you in. Check your connection and try again.") · offline → "You're offline. Connect to sign in — you can keep using the app as a guest." · permission-denied (n/a).

**Gestures:** OTP auto-focus next box; resend countdown (30 s); back → returns to the screen that prompted sign-in (destination preserved).

**Microcopy:** "Send code" · "Send a new code in 0:28" · "Continue as guest" · "We'll only use your number to identify your requests." (consent line, no pre-ticked boxes).

**Tokens:** `color.primary`, `color.primary.hover`, `color.surface`, `color.border`, `color.text.primary/secondary/muted`, `type.h1`, `type.body`, `type.label`, `radius.sm` (inputs), `radius.lg` (buttons), `space.3/4`, `shadow.card`.

---

## 14. Help / FAQ + dispatcher hotline

**Purpose:** Answer without leaving the app; always a human path.

**Key elements:** Prominent **Call dispatcher** card (`tel:`) with number shown; accordion FAQ (5–7 items: "How fast will an ambulance arrive?", "Can I request without an account?", "What info does the crew see?", "How do I cancel?"); "How dispatch works" 4-step graphic; links: Privacy policy, Terms, About.

**States:** loading (accordion skeleton) · empty → "No help topics yet" + Call dispatcher · error → topics bundled fallback + note "Showing saved help content." · offline (fully usable — content bundled; call button still works) · permission-denied (n/a).

**Gestures:** tap to expand/collapse (one open at a time); tap call → system dialer confirm; share help link.

**Microcopy:** "Call dispatcher" · "Available 24/7" · "Tap to call" · FAQ answers ≤2 sentences, plain language.

**Tokens:** `color.primary`, `color.surface`, `color.surface.muted`, `color.border`, `type.h2`, `type.h3`, `type.body`, `space.4`, `radius.md`, `shadow.card`.

---

## 15. Notifications settings

**Purpose:** Per-type control; never one master switch that kills mission alerts.

**Key elements:** Grouped switches: **Mission updates** (on, locked — helper "Required so you know when a crew is assigned"), **Crew messages** (on), **Arrival alerts** (on), **Tips & product news** (off, opt-in only); quiet-hours row (default: respect OS Focus/DND); link "Open system settings" if OS-denied; note about badge accuracy.

**States:** loading (skeleton switches) · empty (n/a) · error → toggle reverts + snackbar "Couldn't save that change. Try again." · offline → change applied locally with "Pending sync" chip, flushed on reconnect · permission-denied → banner "Notifications are off for this app. Turn them on in Settings to get crew alerts." + **Open Settings**.

**Gestures:** switch toggles (immediate optimistic update); tap row label → expands detail.

**Microcopy:** "Mission updates can't be turned off in-app while you have an active request." · "We'll never send marketing without your opt-in."

**Tokens:** `color.primary` (switch on), `color.surface.muted` (locked row), `color.border`, `color.text.secondary`, `type.h3`, `type.body`, `type.label`, `space.4`, `radius.md`.

---

## 16. Privacy & permissions · Appearance · About

**Purpose:** GDPR-grade control, grouped by theme (Account / Notifications / Privacy / Appearance / About).

**Key elements:**
- **Privacy & permissions:** location mode ("While using" active + explanation), "Download your data" (JSON export), "Delete account and all data" (danger, type-to-confirm), consent toggles (analytics off by default), privacy policy link.
- **Appearance:** System / Light / Dark (note: mission screens always use the mission theme).
- **About:** version (`type.mono`), licenses, terms, help, "Replay onboarding".

**States:** loading (section skeletons) · empty (n/a) · error → "Couldn't apply that change." + Retry · offline (all local; export queued with "Export will start when you're back online.") · permission-denied → for location row show state chip "Denied" + "Open Settings".

**Gestures:** toggles; segmented theme picker; destructive flows behind confirm dialogs.

**Microcopy:** Delete dialog: "Delete your account?" / "This permanently removes your profile, medical info and mission history. This can't be undone." / "Delete" (red, right) / "Cancel" (left) · "Your medical profile is encrypted and shared only with the crew assigned to your request."

**Tokens:** `color.surface`, `color.surface.muted`, `color.border`, `color.danger` / `danger.hover`, `color.text.primary/secondary/muted`, `type.h3`, `type.body`, `type.label`, `type.mono`, `space.4`, `radius.md`.

---

## 17. Cross-cutting states (global components)

| Component | Spec | Tokens |
|---|---|---|
| **Offline banner** | Top, non-blocking, `surface.muted` + wifi-off icon: "No connection — working offline". Auto-dismiss on reconnect with "Back online". | `color.surface.muted`, `color.border`, `type.label`, `space.2/3`, `radius.sm` |
| **Permission-denied chip** | Inline chip on map/profile rows with recovery link "Open Settings". | `color.text.secondary`, `color.border`, `type.label` |
| **Skeleton** | Content-shaped, 3 rows max, shimmer 1.2 s, used 400 ms–3 s. | `color.surface.muted`, `radius.md` |
| **Error card (recoverable)** | "What happened + why + what to do" + **Retry** button. | `color.danger.surface`, `color.danger.border`, `color.danger`, `type.body`, `radius.md` |
| **Full-screen error (blocking)** | Illustration, message, **Retry** + **Call dispatcher** (never lose the emergency path). | `color.background`, `color.primary`, `color.danger` |
| **Empty state** | Icon/illustration + heading + 1-line message + primary action (4 parts, every empty screen). | `color.surface`, `type.h3`, `type.body`, `color.primary` |
| **Snackbar/undo** | 5 s, with Undo for cancellable actions (e.g., "Contact removed · Undo"). | `color.text.inverse` on `color.background.dark`, `radius.md` |
| **Confirm dialog** | Title = action ("Cancel request?"), body = consequence, verb-matched red button on right, Cancel left. | `color.surface`, `radius.lg`, `color.danger`, `type.h3`, `type.body` |
| **Active mission banner** | Persistent on all tabs: status color dot + "Unit A-12 · 04:12" + chevron; 1 tap resumes. | `color.status.*`, `color.surface`, `shadow.mapPanel`, `type.label`, `type.mono` |
