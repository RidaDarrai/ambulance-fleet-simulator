# Ambulance Tracking & Dispatch — Design Tokens (v1)

> Single source of truth for the visual language across all four surfaces:
> **Patient app (Flutter)** · **Crew app (Flutter)** · **Dispatcher dashboard (React)** · **Admin panel (React)**.
> Implement this once per stack. Do not hardcode colors / spacing / type in components.

## 1. Mission lifecycle status colors

The status enum is shared end-to-end (`pending → dispatched → enRoute → onScene → transporting → atHospital → resolved`).
These semantic tokens are the ONLY place the status colors live.

| Status | Token | Light (hex) | Dark (hex) | Use |
|---|---|---|---|---|
| pending | `color.status.pending` | `#F59E0B` (amber 500) | `#FBBF24` (amber 400) | Waiting in FIFO queue |
| dispatched | `color.status.dispatched` | `#3B82F6` (blue 500) | `#60A5FA` (blue 400) | Unit assigned, not yet moving |
| enRoute | `color.status.enRoute` | `#06B6D4` (cyan 500) | `#22D3EE` (cyan 400) | Crew heading to patient |
| onScene | `color.status.onScene` | `#8B5CF6` (violet 500) | `#A78BFA` (violet 400) | Crew at patient location |
| transporting | `color.status.transporting` | `#F97316` (orange 500) | `#FB923C` (orange 400) | Patient onboard, heading to hospital |
| atHospital | `color.status.atHospital` | `#14B8A6` (teal 500) | `#2DD4BF` (teal 400) | Unit at hospital, handoff in progress |
| resolved | `color.status.resolved` | `#22C55E` (green 500) | `#4ADE80` (green 400) | Mission complete / unit available again |

Conventions:
- red (`#EF4444` / `#F87171`) is reserved for **danger** only: panic button, critical medical alert, rejected assignment.
- A unit with `status: available` renders using the **success/green** token, not `resolved`.

## 2. Brand palette

| Token | hex | Use |
|---|---|---|
| `color.primary` | `#0EA5E9` (sky 500) | Primary actions, active nav, map markers for own unit |
| `color.primary.foreground` | `#FFFFFF` | Text/icon on primary |
| `color.primary.hover` | `#0284C7` (sky 600) | Primary hover/pressed |
| `color.background` | `#F8FAFC` (slate 50) | App/dashboard background (light) |
| `color.background.dark` | `#0F172A` (slate 900) | Background (dark mode) |
| `color.surface` | `#FFFFFF` | Cards, sheets, dialogs |
| `color.surface.muted` | `#F1F5F9` (slate 100) | Danger-zone rows, secondary fills |
| `color.border` | `#E2E8F0` (slate 200) | Hairlines, dividers |
| `color.text.primary` | `#0F172A` (slate 900) | Headings, primary copy |
| `color.text.secondary` | `#475569` (slate 600) | Body, labels, hints |
| `color.text.muted` | `#94A3B8` (slate 400) | Placeholders, disabled |
| `color.text.inverse` | `#F8FAFC` | Text on dark bg / map overlays |

## 3. Spacing scale (4px base)

```
space.0   = 0
space.1   = 4px
space.2   = 8px
space.3   = 12px
space.4   = 16px
space.6   = 24px
space.8   = 32px
space.12  = 48px
space.16  = 64px
```

Layout defaults:
- Mobile screen padding: `16px` horizontal, `space.6` vertical (bottom safe-area aware).
- Web page gutters: `space.8` on desktop, `space.4` at <768px.
- Card padding: `space.4` (mobile) / `space.6` (web).

## 4. Typography

| Token | Font | Size / Line-height | Weight | Use |
|---|---|---|---|---|
| `type.display` | Inter | 32 / 40 | 700 | Hero numbers, ETA countdown |
| `type.h1` | Inter | 24 / 32 | 700 | Screen titles (mobile) / page titles (web) |
| `type.h2` | Inter | 18 / 28 | 650 | Section headers |
| `type.h3` | Inter | 16 / 24 | 600 | Card titles |
| `type.body` | Inter | 14 / 22 | 400 | Default copy |
| `type.body.small` | Inter | 13 / 20 | 400 | Secondary copy, captions |
| `type.label` | Inter | 12 / 16 | 600 | Form labels, badges, tab labels |
| `type.display.mono` | JetBrains Mono | 32 / 40 | 700 | ETA digits (tabular lining) |
| `type.mono` | JetBrains Mono | 13 / 20 | 400 | IDs, coordinates, timestamps |

Notes:
- Use **tabular-nums / fixed-width digits for all ETA + countdown values** so numbers don't jitter.
- Font stacks: `Inter, -apple-system, "Segoe UI", Roboto, sans-serif`; mono: `"JetBrains Mono", "SF Mono", Consolas, monospace`.

## 5. Radius & shadows

| Token | Value |
|---|---|
| `radius.sm` | 6px (badges, inputs) |
| `radius.md` | 10px (buttons, cards) |
| `radius.lg` | 16px (sheets, dialogs, mobile buttons) |
| `radius.full` | 9999px (panic button, pills, avatars) |
| `shadow.card` | `0 1px 2px rgba(15,23,42,.06), 0 1px 3px rgba(15,23,42,.1)` |
| `shadow.fab` | `0 8px 24px rgba(2,132,199,.35)` (floating panic button) |
| `shadow.mapPanel` | `0 4px 16px rgba(15,23,42,.16)` (map overlays) |

## 6. Danger / safety tokens (panic + medical)

| Token | Value |
|---|---|
| `color.danger` | `#EF4444` |
| `color.danger.hover` | `#DC2626` |
| `color.danger.surface` | `#FEF2F2` (red 50) — panic context bg |
| `color.danger.border` | `#FECACA` (red 200) |
| `panic.size` | 72px tap target (min 64px) |
| `panic.animation` | pulsing ring, 1.6s @ 0% opacity — disabled when `reduced-motion` |
| `medical.surface` | `#EFF6FF` (blue 50) — medical summary card bg |
| `medical.border` | `#DBEAFE` (blue 100) |

## 7. Component-level tokens (shadcn/ui React)

For the Dispatcher/Admin React dashboards map to shadcn CSS variables:
`--primary → color.primary`, `--destructive → color.danger`, `--muted-foreground → color.text.muted`, etc.
Monitor/queue behavior: status badges use `color.status.*`; queue rows are `surface`, selected/mission-active row uses a 2px left border in the mission status color.

## 8. Stack implementation checklist

- [ ] Flutter: single `AppColors`/`AppTheme` (Material 3 `ColorScheme.fromSeed` overridden with these tokens)
- [ ] React: `tokens.css` (CSS variables under `:root` + `[data-theme="dark"]`) consumed by Tailwind config
- [ ] Status colors: import from this file, never re-declared per screen
- [ ] Add `reduced-motion` handling for the panic pulse
- [ ] ETA displays use mono/tabular digits everywhere

---
*Source: Ambulance Tracking & Dispatch Baseline Report (baseline-report.md). Extension: add `color.status.available` if you want it distinct from `resolved`.*