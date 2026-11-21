# UI redesign: Clean

Status: **implemented**. The clean dark system, the Play/Garage layout, the
editor chrome, the bottom sheets and the HUD fixes shipped together. `UiMotion`
and dynamic type are still open. The light variant was tried and rejected: on a
phone it was too bright, so the shipped menu is the dark one.

The bottom tab system stays. The direction below is the shipped one; the
sections that are still a plan are called out in "Implementation status".

The direction is deliberately **clean**: one neutral family, one accent, one
sans-serif, flat surfaces, generous space, no decoration that does not carry
information. The road and the car are the only things that should look like a
game; the menu should look like a well-made tool.

## Implementation status

**Shipped in this pass**

- `godot/scripts/theme.gd` is the clean dark system: graphite page, charcoal
  cards, one hairline, warm off-white ink and one coral accent. The old navy/gold
  palette is gone.
- Inter is bundled under `godot/assets/fonts/` (400/500/600/700, OFL) and is the
  theme's default font. Labels pick a weight from their size
  (`UiTheme.font_for_size`), so a screen has a display/title/body hierarchy.
- The shell is a 56px top bar and a 64px tab bar; the active tab gets a 3px
  accent rule and an accent icon/label.
- The Play tab is a 2-column grid of track cards, each with a real mini-map
  (`TrackMap` builds a `Track` and draws its centreline), the number and the PB.
  The selected card is a charcoal card with a 2px accent border. The daily row is a
  compact card with the action on the right, and a sticky Race footer sits above
  the tab bar so a long grid never buries the action.
- Garage is a 2-column car card grid with the selected car marked by the same
  2px accent border.
- The HUD has no progress bar. PB/WR are live pace deltas measured at the same
  road position (`Game.set_pace` / `pace_time_at`), so they start at `0.000`;
  endless compares distance at the same elapsed time.
- The editor keeps its map-first surface but uses the clean dark chrome.

**Still open**

- `UiMotion` press/tab/sheet timing and reduced-motion animation.
- Dynamic type / 1.3x text-scale checks.
- Account stats and the daily board sheet.

## 1. Why this, why now

The current UI is functional and readable, but it looks like a settings dialog
placed over a game. It has one visual weight: deep-navy panels with a 1-2px
border, the same 12-20px radius, and a warm-gold accent. Nothing tells the eye
what matters first, and nothing carries the speed of the game.

The audit found these concrete issues:

- **One hierarchy.** The page background, cards, sub-cards and buttons are all
  navy rectangles with a hard border. There is no elevation, no material, no
  light source. A hero, a track chip and a danger button read as the same object.
- **No display type.** The whole UI uses the engine's default Open Sans at
  12-44px. Times are not tabular, so digits shift as the clock runs. Section
  labels and values have nearly the same weight.
- **Muted text fails contrast.** `INK_MUTE` (`#6f77a0`) on `SURFACE`
  (`#141a30`) measures **3.95:1**, below WCAG 2.2's 4.5:1 for normal text. It is
  used for 12-14px hints.
- **Touch targets are undersized.** `IconButton` is 40x40; Apple asks for 44pt
  and Material for 48dp. The tab bar is 62px, so its buttons are fine, but the
  top-bar gear, close and back buttons are not.
- **The Play tab is a text stack.** Mode segments, daily card, a 5-column
  number grid, the Play button, ghost row, "More" row and custom-track list.
  It is efficient, but a track has no visual identity and the page has no hero.
- **The HUD shouts and then lies.** A 44px time, a 20px best line, two delta
  chips and a **7px full-width gold progress bar** sit on top of the road. The
  progress bar is the "huge yellow bar" players notice first, and it is not
  needed: the road is the progress bar. The PB/WR delta is computed as
  `elapsed - final_best`, so it starts at about `-10.4s` and counts up to zero.
  It is a countdown to the record, not a live delta. A player cannot tell from
  it whether the first sling was good or bad.
- **No motion language.** Tabs snap, overlays appear, buttons have no press
  feedback. The only motion is the crash shake, the hit flash and the slingshot
  zoom.
- **Overlays are centered cards.** They should be bottom sheets on a phone:
  reachable, dismissible by dragging, and sized to the thumb.
- **The tab bar is a flat rail.** The active tab changes colour, but there is no
  indicator, no safe-area inset and no relationship to the content.

## 2. What "clean" means here

Three sources set the bar; none of them says "add more decoration".

**Apple Human Interface Guidelines, Layout (updated 9 September 2026).** The
current guidance is about hierarchy, safe areas, Dynamic Type, progressive
disclosure and a clear distinction between content and controls. Apple's Liquid
Glass is a material for controls over full-bleed content; the principle is
layering, not iridescence. This game already has full-bleed content (the road),
so the menu should be a calm, opaque layer and the HUD a small translucent one.

**Material 3 Expressive (May 2025).** Google's research (46 studies, 18,000+
participants) found expressive interfaces are preferred across ages and let
people spot key UI up to **four times faster**. The lesson is not "more colour";
it is that **hierarchy, type and motion** are what make an interface feel alive.
A clean interface with one strong accent and one clear action is expressive.

**WCAG 2.2.** Normal text needs 4.5:1 contrast (3:1 for large text); pointer
targets need at least 24x24 CSS px, with platform guidance at 44pt (Apple) and
48dp (Material). Dynamic type and reduced motion are not optional polish.

The rules for this redesign:

1. **One accent.** A signal red for the primary action, the active tab and
   danger. Everything else is ink, paper or a semantic green/red for a delta.
2. **One type family.** Inter for everything; weight and size create hierarchy.
   No serif, no display novelty, no icon font.
3. **Flat surfaces.** Cards are `#FFFFFF` with a 1px `#E4E4E0` border. No
   gradients, no glass, no grain, no glow. A sheet gets a shadow because it
   floats; a card does not.
4. **Space is the decoration.** 20px page padding, 16px card padding, 12px
   gaps, 48px between sections. If a screen feels empty, remove a card rather
   than add a texture.
5. **Motion explains, never performs.** 150-220ms fades and 8px slides; a
   press scales to 0.98. No springs, no confetti, no bouncing.
6. **The game is the colour.** The road themes and car sprites carry the
   personality. The UI stays neutral so they read.

**Not doing:** purple-blue gradients, neon cyan/magenta, iridescent glass,
glowing borders, floating 3D blobs, serif "editorial" headlines, paper grain,
confetti, or a different accent per screen. Those are the visual shorthand of
AI-generated product design, not a racing game.

## 3. Two modes, one system

### A. Clean Light (tried, rejected)

Near-white page, white cards, near-black ink, one signal-red accent. It reads
as a modern app, but on a phone it was too bright next to the game's dark road
themes, and the white sheets dominated the screen.

### B. Clean Dark (shipped)

Graphite page, charcoal cards, warm off-white ink, one coral accent. It matches
the game's dark road themes and the HUD, and it keeps the road the brightest
thing on screen. It is the same layout and type as the light pass, not a second
design.

**Decision: B only.** Do not mix the two halfway (a light page with dark cards,
or a dark page with a white sheet).

## 4. Design tokens

Put these in `godot/scripts/theme.gd` (or a new `ui_tokens.gd`) before any
screen is rebuilt. Keep the `UiTheme` API stable so `app.gd` does not have to
change in the same commit.

### 4.1 Colour

**Clean Dark (shipped):**

| Token | Hex | Use |
|---|---|---|
| `INK` | `#F3F1EA` | primary text, times |
| `INK_DIM` | `#B8B5AC` | secondary text |
| `INK_MUTE` | `#8E8B83` | hints, labels (4.9:1 on sunk) |
| `PAGE` | `#0B0C0E` | page |
| `CARD` | `#141619` | card |
| `CARD_SUNK` | `#1B1E22` | inset row, track chip |
| `LINE` | `#2A2E34` | 1px hairline |
| `ACCENT` | `#FF5A3C` | primary action, active tab |
| `ACCENT_INK` | `#1A0A06` | text on accent (6.2:1) |
| `GOOD` | `#7FD1A3` | ahead, success |
| `BAD` | `#FF9A8C` | behind, error |
| `GOLD` | `#E0BC66` | gold medal |
| `SILVER` | `#C0C0C0` | silver medal |
| `BRONZE` | `#C08A58` | bronze medal |

Contrast check (WCAG 2.2): ink 16.0:1 on a card, dim 8.8:1, mute 5.3:1,
accent 5.9:1 on a card, dark accent text 6.2:1 on the accent, good 10.8:1, bad
9.6:1 on the page. `GOLD` is 10.0:1 on a card, so it is safe for medal text too.

The accent is a **signal**, not a theme: primary CTA, active tab, a crash.
PB-ahead uses `GOOD`; a PB-behind uses `BAD`; medals use gold/silver/bronze. Do
not tint whole cards with the accent.

### 4.2 Type

| Role | Face | Size / weight | Use |
|---|---|---|---|
| Display | Inter 700, tabular figures | 56 / 48 / 32 | finish time, hero number |
| Title | Inter 650 | 24 / 20 | screen title, card title |
| Body | Inter 450/500 | 15 / 14 | descriptions, rows |
| Label | Inter 600, uppercase, +0.06em | 11 / 12 | eyebrows, mode labels, section headers |
| Data | Inter 600, tabular figures | 32 / 24 / 18 | clocks, deltas, metres |

Bundle Inter under `godot/assets/fonts/` with its OFL licence, and set
`Theme.default_font`. Do not rely on the engine default. Ship 400/500/600/700
static weights (or one variable font if `FontVariation` is verified in 4.5).

Rules:

- Times are always tabular. A clock that shifts width as it runs looks broken.
- Display type is tight (`-0.02em`); labels are loose (`+0.06em`).
- Never use all-caps for a sentence. Uppercase is for 1-3 word eyebrows only.
- Support a text-scale setting (0.9x, 1.0x, 1.15x, 1.3x). Test 1.3x on the
  narrowest screen.

### 4.3 Space, radius, elevation

- Spacing scale: 4, 8, 12, 16, 20, 24, 32, 48. Page padding 20; card padding
  16; gap between cards 12; section gap 48.
- Radii: sheet 24; card 20; button 14; chip 999 (pill); small badge 10. Do not
  use a different radius on every control; three sizes is enough.
- Elevation:
  - 0 page: no shadow.
  - 1 card: 1px `LINE`, no shadow.
  - 2 sheet: `0 -12 40 rgba(17,17,17,0.16)` + top hairline.
  - 3 modal: same as sheet, with a 62% ink scrim.
- Borders: 1px, `LINE`. The current 2px saturated navy border is what makes
  every panel look like a dialog.

### 4.4 Material

There is no glass in the menu. Cards are flat `CARD` with a 1px `LINE`; sheets
are flat `CARD` with a shadow. The HUD has no panel: its text sits directly over
the road with a soft shadow. The only translucent surface is the overlay scrim.

If a real backdrop blur is wanted later, make it a desktop-only option and
disable it on mobile/web by default. It is not part of this plan.

### 4.5 Motion

Use Godot `Tween` with `TRANS_CUBIC`/`EASE_OUT`. All timings go in one
`UiMotion` helper so reduced motion can zero them.

| Interaction | Motion |
|---|---|
| Button press | scale 1.0 -> 0.98 in 90ms, back in 150ms |
| Tab select | content cross-fade 160ms; active indicator slides 180ms |
| Sheet open | translate Y 100% -> 0 in 220ms; scrim fades 160ms |
| Sheet close | 180ms ease-in; drag follows the finger |
| Page enter | 160ms fade + 8px rise |
| PB | a single accent ring pulse 300ms; no confetti |
| Crash | a 200ms red vignette + shake; reduced motion removes the shake |

Reduced motion: a Settings toggle (already exists) plus an OS preference where
available. When on, use 100ms fades and no scale/translate.

### 4.6 Icons

Keep `UiIcon` geometry, but expand it to a consistent 24x24 grid with a 1.75px
stroke, round caps and joins. Add: calendar, trophy, flame, ghost, lock,
chevron, plus, minus, undo, redo, fit, grid, palette, share, copy, check, close,
pause, restart, watch, arrow, speed. The theme font has no icon glyphs; never
use a Unicode character for an icon.

### 4.7 Sound and haptics

- UI tap (8ms haptic), confirm (16ms), error (30ms), tab change (8ms).
- Sounds: a short tick for tabs, a soft thunk for the primary CTA, a chime for a
  PB, a low thud for a crash. Quiet by default; expose a UI volume.
- Haptics and reduced motion already have settings; add a UI sound toggle.

## 5. Screen specs

### 5.1 Shell and bottom tabs (keep the tabs)

- Top bar: 56px, `CARD` or `PAGE`, 1px bottom `LINE`, page title 24 display,
  subtitle 11 label, left slot for back, right slot for settings/account.
- Content: `PAGE`, 20px side padding, max width 560, 12px card gaps, 48px
  section gaps. Scrolls under the top bar with a 16px edge fade.
- Bottom tab bar: **64px + safe-area inset**, `CARD` with a 1px top `LINE`,
  4 tabs (Garage, Editor, Play, Account), 48px targets, icon 24 + label 11.
  Active tab: accent icon/label plus a **3px accent bar** at the top of the tab.
  Inactive: `INK_MUTE`. Keep Play in the middle; no floating action button.
- The shell background absorbs input (already true); the tab bar must never
  overlap the gesture bar. Use `DisplayServer.get_display_safe_area()` on mobile
  and the web shell's `env(safe-area-inset-bottom)` on web.

### 5.2 Play

A clean vertical page, not a dashboard:

1. **Mode segmented control**: Tracks / Endless, 40px, `CARD_SUNK` track,
   `CARD` selected segment, 1px `LINE`. Keep `_set_mode` behaviour; endless
   hides the track and daily sections.
2. **Track grid**: 2 columns of `CARD` track cards, each with a small ink
   mini-map (read-only `TrackPreview`), the track number, and the PB. Selected
   card has a 2px `ACCENT` border, not a fill. 13 tracks = 7 rows, scrollable;
   this is more visual than the 5-column number grid and still compact. Keep a
   small "list/grid" icon if the player wants the old number grid.
3. **Daily row**: one `CARD` row, 72px: calendar icon, "Daily · 21 Nov", the
   track/modifier as secondary text, the best on the right, a chevron. No
   gradient, no banner. Tapping opens the daily board sheet.
4. **My tracks**: one row of compact cards plus a "New track" card; keep the
   existing custom-track picker logic.
5. **Sticky footer** above the tab bar: a 52px `ACCENT` "Race" button, full
   width, with the selected track name in `INK_DIM` above it. A small "Ghost:
   Your best" toggle sits to the left of the button or in a secondary row.

### 5.3 Garage

- A 2-column grid of `CARD` car cards: sprite, name, a small "Selected" or
  "Locked" label. Selected card has a 2px `ACCENT` border. No carousel, no
  spotlight, no turntable.
- A "Random" text button in the section header. Keep `verify_cars`.
- Do not invent stats. If stats are added later, use three 6px bars with a 2px
  `CARD_SUNK` track and an `INK` fill; the accent is for selection, not data.

### 5.4 Editor

- The map stays the whole surface. The chrome is flat:
  - Top toolbar: `CARD`, 1px bottom `LINE`, back, undo, redo, fit, grid,
    colours. 44px icon buttons.
  - Bottom piece tray: `CARD`, 1px top `LINE`, horizontally scrolling 56x56
    tiles with generated arc art. Selected tile: 2px `ACCENT` border.
  - Selected piece sheet: flat bottom sheet, drag handle, angle/radius/length
    controls, Delete, Duplicate, Done. Keep the live slider callback silent
    (the existing `_apply_live` rule); only refresh the menu list on
    `drag_ended`/commit.
  - Colours sheet: two swatch rows + a preview + Randomize.
  - Sticky bottom bar: "Play" primary, "Save" ghost. Validation errors appear
    as inline `BAD` text, not a modal.
- Do not change `TrackPreview` pan/zoom/pinch/tap behaviour; the verifier pins
  it. Only the surrounding chrome moves.

### 5.5 Account

- Signed out: a `CARD` with "Sign in" primary and "Create account" ghost;
  email/password fields with labels above, show/hide, and the keyboard scroll
  behaviour that already exists.
- Signed in: a `CARD` with a monogram avatar (ink on `CARD_SUNK`), username,
  "Member since", and a stats row (PBs, medals, best distance). List rows for
  "My runs", "Daily history", "Sign out"; a sync label ("Synced", "Offline",
  "3 queued").
- Keep the account-name healing and per-account storage rules untouched.

### 5.6 Settings

- One list, grouped by section headers: Controls (3 keycaps), Audio (3 sliders
  with value labels), Feel (haptics, reduced motion, screen shake), Account,
  About.
- Rows are 56px, separated by 1px `LINE`, no nested cards. Keycaps are 40x40
  `CARD_SUNK` squares; the capture state says "Press a key". Keep the collision
  refusal.
- Version line at the bottom in `INK_MUTE`.

### 5.7 Overlays

Replace centered `PanelContainer` cards with **bottom sheets**:

- 24px top radii, 20px padding, 36x4 drag handle, max 85% height, internal
  scroll, 62% ink scrim.
- 220ms up; drag down to dismiss; tap the scrim to dismiss.
- Pause: Resume (primary), Restart, Settings, Quit.
- Finish: 48px time, delta, rank, medal, "Race again" primary, "Board" and
  "Watch" ghosts. A new PB gets a single accent ring, no confetti.
- Crash: "Crashed", the distance/corner, "Retry" primary, "Menu" ghost.
- Board: title "Daily · 21 Nov", challenge line, top 50 rows, your row
  highlighted, watch buttons.
- History: grouped by date, PB flags, watch buttons.
- Account form and settings can stay full-screen pages; the daily/board/pause/
  finish/crash sheets are the priority.

### 5.8 HUD

This is where the two reported issues are fixed.

- **Remove the full-width yellow progress bar.** It is redundant: the road is
  the progress bar. If progress is wanted, use a 1px `DARK_LINE` hairline at the
  very top edge with a 4px accent dot, and make it a Settings toggle (default
  off). Do not use a 7px filled bar.
- **Live delta, not a countdown.** The current delta is
  `elapsed - final_best`, so it starts at `-10.4s` and rises to 0. Replace it
  with a **pace delta at the same road position**:
  - Precompute a reference curve `s -> time` from the PB replay (local
    `Storage.get_replay`) and/or the WR replay (the board row's `steps`).
  - At each tick, `delta = player.time - reference.time_at(player.car.s)`.
  - At the start, `s = 0` and both times are 0, so the delta reads `0.000`.
  - If the player is slower to the first sling, at the same `s` the reference
    time is lower, so the delta goes positive (behind). If the player is faster,
    it goes negative (ahead).
  - Show `PB -0.045s` / `WR +0.120s`, `DARK_GOOD` when negative, `DARK_BAD`
    when positive, `DARK_DIM` at `0.000`. If there is no replay (a PB from
    another device, a board row with no steps), hide that chip rather than
    falling back to the countdown.
  - For endless, compare at the same **elapsed time**: the reference's distance
    at `t`, so the delta starts at 0 and reflects whether the line is ahead of
    the record at that moment.
  - Implement the curve in `Game` (a `set_pace`/`pace_time_at(s)` pair), not in
    the HUD, so it is testable and the same curve can drive a ghost later.
- HUD layout:
  - Top-left: mode label 10 uppercase + time 32 tabular, `DARK_INK`, with a
    soft text shadow so it reads on a light road.
  - Top-centre: delta text, no chip if the road is clean; use a 1px top
    highlight only when a chip is needed.
  - Top-right: pause 44px.
  - Bottom-centre: restart 44px.
  - Endless: distance 32 + a small speed label; delta vs best at the same `t`.
  - No boxes around every label. The HUD should be three small text clusters,
    not a dashboard.

## 6. Component and code map

| Area | Change |
|---|---|
| `godot/scripts/theme.gd` | Tokens, Inter, `Card`/`PillButton`/`TabButton`/`KeyCap`/`Row` variations; 1px hairlines; flat cards; sheet shadow. |
| `godot/scripts/menu_shell.gd` | 56px top bar, 64px + safe-area tab bar, 3px active indicator, edge fade, tab motion. Keep `select()` as the entry point. |
| `godot/scripts/ui_motion.gd` (new) | Press/tab/sheet timings, reduced-motion switch. |
| `godot/scripts/ui_icon.gd` | 24px grid, 1.75px stroke, new kinds. |
| `godot/scripts/app.gd` | Split the tab builders into `godot/ui/play_tab.gd`, `garage_tab.gd`, `account_tab.gd`, `settings_tab.gd`; `App` keeps state and signals. This is the right time to do the E1 split. |
| `godot/scripts/track_preview.gd` | Add a read-only mode for the Play track cards; do not change editor input. |
| `godot/scripts/render.gd` | `clear_fx()` already added; no physics change. |
| `godot/tools/verify_ui.gd` | 44/48 targets, safe area, dynamic type, sheet fit, tab bar. |
| `godot/tools/verify_theme.gd` (new) | Contrast pairs, token presence, radius/type scale. |
| `godot/tools/verify_hud.gd` | Progress bar removed/optional; delta at `s=0` is 0; position-based ahead/behind; endless at `t`. |
| `godot/README.md`, `AGENTS.md` | Document the tokens, sheets and HUD delta rule. |

Do not touch `physics/`, `car.gd`, `cfg.gd` or any parity golden for this work.
The UI is presentation only.

## 7. Implementation phases

| Phase | Scope | Effort | Exit criteria |
|---|---|---|---|
| P0 | Tokens, Inter, icons, `UiMotion`; no layout changes | S | All 16 verifiers green; screenshot baseline; contrast pass |
| P1 | Shell: top bar, tab bar, safe area, active indicator | M | Bottom tabs unchanged in function; `verify_ui` + `verify_keys` green |
| P2 | Play: mode control, 2-column track cards, daily row, sticky CTA | L | All controls fit at 320x568 and 420x820; `verify_ui` green |
| P3 | Garage, Account, Settings | M | `verify_cars`, `verify_storage`, `verify_ui` green |
| P4 | Bottom sheets: pause, finish, crash, board, history | M | Sheet fit and drag tests; no clipping |
| P5 | Editor chrome: toolbar, tray, sheet, colours | M | `verify_editor` unchanged and green |
| P6 | HUD: remove progress bar, live pace delta, text-only clusters | M | `verify_hud` proves the new delta and no bar |
| P7 | Motion, sound, haptics, reduced motion, dynamic type | S/M | Reduced motion removes scale/translate; 1.3x text fits |
| P8 | Polish, performance, screenshots, docs | S | 60fps menu on a low-end Android; docs updated |

**Sequencing with daily leaderboards:** P0-P1 are independent and should land
first. The daily board backend (see `ROADMAP.md`, C4b) can be built in parallel.
P2 then includes the daily row and board sheet, so the new surface is born in
the new system rather than rebuilt twice.

## 8. Verification

- **Contrast:** a new `verify_theme.gd` computes WCAG ratios for every
  foreground/background pair actually used. Fail under 4.5:1 for normal text and
  3:1 for large text.
- **Targets:** `verify_ui` walks every Button/LineEdit and asserts at least
  44x44 (48x48 for primary actions), including the top-bar icons and tab bar.
- **Fit:** the existing viewport matrix plus 320x568 and 360x640; no control may
  leave the viewport; sheets must scroll.
- **Safe area:** simulate a 24px bottom inset and assert the tab bar and CTA sit
  above it.
- **Dynamic type:** run the menu at 1.3x and assert no clipping.
- **HUD:** at `s=0`, both deltas read `0.000` (or `--`); at a known `s`, a
  reference run that is 0.2s slower reads `+0.200`; the progress bar is gone.
- **Performance:** menu at 60fps on a low-end Android profile; flat cards only;
  shared materials; draw calls under a budget (measure before and after).
- **Regression:** all 16 existing verifiers, `make test`, web export, APK.

## 9. Risks

- **Scope.** This is a full visual overhaul. Phase it; the game stays shippable
  after every phase.
- **Font licensing.** Inter is OFL; ship the licence. Do not use a system font
  that may not exist on Android/web.
- **Light vs dark.** The shipped menu is dark. Do not add a light setting without
  a new review; the white pass was rejected as too bright on a phone.
- **Godot theme limits.** `StyleBoxFlat` can do flat cards and hairlines; it
  cannot do gradients. This plan does not need gradients.
- **Editor regression.** `TrackPreview` input is pinned by `verify_editor`; only
  change the chrome around it.
- **Bottom tabs.** Keep the 4-tab system and the `select()` entry point. Do not
  introduce a fifth tab or a floating action button without asking.
- **HUD delta correctness.** The reference curve must be built from the actual
  replay; a final-time subtraction is what caused the current bug. Test at the
  start, at a mid-track split and at the finish.

## 10. Open questions

1. **Mode:** Clean Dark (shipped). A light setting is not planned.
2. **Track chooser:** 2-column cards (recommended), the existing 5-column
   number grid, or both with a toggle?
3. **Play hero:** a track card grid, one large live map, or both?
4. **HUD progress:** remove it entirely, or keep an optional 1px hairline?
   (Recommend optional, default off.)
5. **Delta reference:** PB, WR, or both? (Recommend both, each hidden when its
   replay is unavailable.)
6. **Accent:** signal red (recommended), ink-only, or a muted green?
7. **Bottom tab bar:** 3px top indicator (recommended) or a filled active tab?
8. **Scope:** every screen in one pass, or Play + HUD first and leave Garage/
   Account/Settings for a second pass?

## 11. References

- Apple Human Interface Guidelines, Layout (updated 9 September 2026):
  <https://developer.apple.com/design/human-interface-guidelines/layout/>
- Apple Human Interface Guidelines, Materials:
  <https://developer.apple.com/design/human-interface-guidelines/materials>
- Apple Human Interface Guidelines, Motion:
  <https://developer.apple.com/design/human-interface-guidelines/motion>
- Apple Human Interface Guidelines, Typography:
  <https://developer.apple.com/design/human-interface-guidelines/typography>
- Material 3 Expressive (13 May 2025):
  <https://m3.material.io/blog/building-with-m3-expressive>
- Material 3 navigation bar:
  <https://m3.material.io/components/navigation-bar/guidelines>
- WCAG 2.2, Contrast (Minimum):
  <https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html>
- WCAG 2.2, Target Size (Minimum):
  <https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html>
- Game UI Database (reference gallery): <https://www.gameuidatabase.com/>
- Interface In Game (reference gallery): <https://interfaceingame.com/>
