# UI redesign: Paper & Petrol

Status: **proposal**. Nothing in this document has been implemented yet. The
crash-shake bug found during the audit is fixed separately (`75006b5`).

The bottom tab system stays. Everything else - colour, type, surfaces, page
layout, overlays, HUD - is open.

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
  pill, no lift, no safe-area inset and no relationship to the content.

## 2. What 2026 UI actually expects

Three primary sources set the direction; the rest is game-specific craft.

**Apple Human Interface Guidelines, Layout (updated 9 September 2026).** Apple's
current guidance is built around **Liquid Glass**: controls are a distinct
translucent material that floats above full-bleed content, with a scroll-edge
effect instead of an opaque bar behind them. It also asks for a clear visual
hierarchy, safe-area respect, Dynamic Type support and progressive disclosure.
The lesson for this game: let the road run under the chrome, make the controls a
separate layer, and never let a control clip at a screen edge.

**Material 3 Expressive (May 2025).** Google's most researched design update -
46 studies, more than 18,000 participants - found that expressive interfaces are
preferred across ages, read as more playful, energetic, creative and friendly,
and let people spot key UI up to **four times faster**. The system adds
motion-physics springs, emphasized variable typography, a 35-shape library and
vibrant, accessible colour schemes. The lesson: expression is not decoration; it
is hierarchy. A game about momentum should feel like it has momentum.

**WCAG 2.2.** Normal text needs 4.5:1 contrast (3:1 for large text); pointer
targets need at least 24x24 CSS px, with platform guidance at 44pt (Apple) and
48dp (Material). Dynamic type and reduced motion are not optional polish.

The synthesis for this game is not "add glass and gradients". It is:

1. **One hero per screen.** A live track map, a car, or a time. Everything else
   is support.
2. **A material hierarchy.** Page -> card -> sheet -> modal, each visibly
   different.
3. **A motion language.** Springs for space, fades for colour, press feedback
   for touch.
4. **A type voice.** A display face for times and titles, a neutral UI face for
   everything else, tabular numerals for clocks.
5. **A restrained palette.** One "go" accent, one "danger" accent, one "daily"
   accent, and a lot of ink.

**What we are deliberately not doing:** purple-blue gradients, neon cyan or
magenta, iridescent "AI glass", glowing borders, floating 3D blobs, generic
dashboard cards. Those are the visual shorthand of 2023-2025 AI product design,
not a racing game. The palette below is warm, printed and matte.

## 3. Three directions

### A. Paper & Petrol (recommended)

A motorsport programme printed on warm paper: bone and cream surfaces, warm ink
type, **vermilion** for go, **ochre** for the daily, **forest** for a PB, and a
**dusty blue** for a ghost. Fine 1px rules, a subtle paper grain, large editorial
numbers, and a dark "smoked glass" HUD that only appears over the road.

Why it fits: the game's road themes are already colourful; a warm neutral menu
lets the road be the star instead of competing with it. Vermilion/ochre/forest
are classic racing-poster colours, not software gradients. It is distinctive
without being loud, and it will still look current in 2028 because it is based on
print, not on a trend cycle.

### B. Night Race

The same palette after dark: warm charcoal, cream text, vermilion accent, muted
sage for a PB. It is the dark variant of A, not a neon nightclub. This is the
safe choice if the menu must stay dark to match the road.

### C. Telemetry

Near-black, monochrome, one muted orange accent, dense data, motorsport HUD.
Minimal and serious. Risk: it can feel sterile for a one-button arcade game, and
it gives the menu little personality.

**Recommendation: A**, with B as the fallback if a light menu feels wrong on a
phone at night. C is the "data nerd" option, not the default.

## 4. Design tokens

These are the values to put in `godot/scripts/theme.gd` (or a new
`ui_tokens.gd`) before any screen is rebuilt. Names are suggestions; keep the
`UiTheme` API stable so `app.gd` does not have to change in the same commit.

### 4.1 Colour

**Paper surfaces (menu, sheets, cards):**

| Token | Hex | Use |
|---|---|---|
| `INK` | `#171512` | primary text, times |
| `INK_DIM` | `#5E5A52` | secondary text |
| `INK_MUTE` | `#6E675C` | hints, labels (4.7:1 on paper) |
| `PAPER` | `#F2EBDD` | page |
| `CARD` | `#FBF6EC` | card |
| `CARD_SUNK` | `#E9DFCE` | inset row / track chip |
| `LINE` | `#D8CEBD` | 1px hairline |
| `VERMILION` | `#B93A1E` | primary action, active tab, danger |
| `VERMILION_BRIGHT` | `#D64B2A` | large graphics only (3.6:1 on paper) |
| `OCHRE` | `#C98A2E` | daily fill (use ink text on it) |
| `OCHRE_TEXT` | `#6E470F` | daily text on paper |
| `FOREST` | `#2F5D46` | PB ahead, success |
| `DUSTY_BLUE` | `#45637F` | ghost, telemetry |
| `BRICK` | `#8A4B3A` | secondary danger text |
| `GOLD` | `#C9A227` | gold medal |
| `SILVER` | `#B9B3A8` | silver medal |
| `BRONZE` | `#A9713F` | bronze medal |

**Smoked HUD (over the road):**

| Token | Hex | Use |
|---|---|---|
| `HUD_BG` | `#1B1814` | chip fill at 82% |
| `HUD_INK` | `#F5EFE3` | time, primary HUD text |
| `HUD_DIM` | `#B8B0A2` | best line, secondary HUD text |
| `HUD_MUTE` | `#8E877B` | labels (4.97:1 on HUD_BG) |
| `HUD_ACCENT` | `#E4572E` | go / active (4.8:1 on HUD_BG) |
| `HUD_GOOD` | `#8FAE97` | ahead (7.3:1) |
| `HUD_BAD` | `#E07A5F` | behind (6.0:1) |

Contrast check (WCAG 2.2): ink 15.4:1 on paper, dim 5.8:1, mute 4.7:1,
vermilion 4.8:1, forest 6.4:1, dusty blue 5.3:1; cream on vermilion 5.3:1; ink
on ochre 6.2:1. `VERMILION_BRIGHT` and `OCHRE` are for fills and large graphics,
not small text. `BRONZE` on `HUD_BG` is 4.3:1, so use it for a medal icon, not a
paragraph.

Do **not** use vermilion for more than one thing at a time. It is the "go"
signal: primary CTA, active tab, behind/danger. PB-ahead uses forest. The daily
uses ochre. The ghost uses dusty blue. Medals use gold/silver/bronze.

### 4.2 Type

| Role | Face | Size / weight | Use |
|---|---|---|---|
| Display | Fraunces 600/700 (or Instrument Serif) | 48 / 40 / 32 | finish time, hero statement, sheet title |
| Title | Inter 650 | 24 / 20 | screen title, card title |
| Body | Inter 450/500 | 15 / 14 | descriptions, rows |
| Label | Inter 600, uppercase, +0.08em | 11 / 12 | eyebrows, mode labels, section headers |
| Mono/time | Inter 600 with tabular figures (`tnum`) | 32 / 24 / 18 | clocks, deltas, metres |

Bundle the fonts under `godot/assets/fonts/` with their OFL licences. Set
`Theme.default_font`; do not rely on the engine default. Use `FontVariation` for
weights if a variable font is used; otherwise ship three static weights.

A serif display is deliberate: it is the strongest anti-AI signal in the plan,
and it fits the "printed programme" idea. If a serif reads wrong on a phone,
swap it for Archivo or another grotesk - but keep the warm palette.

Rules:

- Times are always tabular. A clock that shifts width as it runs looks broken.
- Display type is tight (`-0.02em`); labels are loose (`+0.08em`).
- Never use all-caps for a sentence. Uppercase is for 1-3 word eyebrows only.
- Support a text-scale setting (0.9x, 1.0x, 1.15x, 1.3x). Test 1.3x on the
  narrowest screen.

### 4.3 Space, radius, elevation

- Spacing scale: 4, 8, 12, 16, 20, 24, 32, 40. Page padding 16; card padding
  16; gap between cards 12.
- Radii: hero/sheet 28-32; card 24; button 16; chip 999 (pill); small badge 10.
  Mixing one large radius with one small one is what creates the 2026 shape
  language; using 12 everywhere reads as a bootstrap card.
- Elevation:
  - 0 page: no shadow.
  - 1 card: `0 6 18 rgba(23,21,18,0.10)` + a 1px `LINE` border.
  - 2 sheet: `0 -12 40 rgba(23,21,18,0.16)` + top hairline.
  - 3 modal: same as sheet, with a 62% ink scrim.
- Borders: 1px `LINE`, not 2px saturated navy. The current 2px border is what
  makes every panel look like a dialog.

### 4.4 Material: paper, not glass

The menu is **paper**, not glass. Use `CARD` fills, a 1px `LINE`, a very subtle
paper grain (2-3% opacity, one shared texture), and a soft shadow. The result is
calm and tactile; it does not need a blur.

The **HUD** is the one place for a smoked material: `HUD_BG` at 82% alpha, a 1px
`rgba(245,239,227,0.14)` top highlight, no gradient, no glow. It reads as tinted
glass over the road without the iridescent AI look.

If a real backdrop blur is wanted, make it a desktop-only option at 1/4
resolution and disable it on mobile/web by default. If it costs more than ~2ms,
drop it; the smoked fill already reads.

Implement the paper card and the smoked chip once as a `SurfacePanel` /
`SurfaceCard` control. Do not hand-build a different material in every screen.

### 4.5 Motion

Use Godot `Tween` with spring-like curves. If `TRANS_SPRING` is available in
4.5, use it; otherwise `TRANS_BACK` with a custom curve. All timings go in one
`UiMotion` helper so reduced motion can zero them.

| Interaction | Motion |
|---|---|
| Button press | scale 1.0 -> 0.96 in 90ms, release spring back with a 1.02 overshoot |
| Tab select | active pill morphs 220ms; icon lifts 2px; content cross-fades + 12px slide |
| Sheet open | translate Y from 100% -> 0 with a spatial spring (~320ms); scrim fades 180ms |
| Sheet close | 220ms ease-in; drag follows the finger, release decides |
| Page enter | 180ms fade + 8px rise; no horizontal slide on tab changes |
| PB flash | forest ring pulse 400ms + a small paper-confetti burst; no full-screen flash |
| Crash | vermilion vignette 250ms + shake; reduced motion removes the shake |

Reduced motion: a Settings toggle (already exists) plus an OS preference where
available. When on, replace springs with 120ms fades and remove scale/translate.

### 4.6 Icons

Keep `UiIcon` geometry, but expand it to a consistent 24x24 grid with a 1.75px
stroke, round caps and joins. Add: calendar, trophy, flame, ghost, lock,
chevron, plus, minus, undo, redo, fit, grid, palette, share, copy, check, close,
pause, restart, watch, arrow, speed. The theme font has no icon glyphs; never
use a Unicode character for an icon.

### 4.7 Sound and haptics

- UI tap (8ms haptic), confirm (16ms), error (30ms), tab change (8ms).
- Sounds: a short tick for tabs, a soft thunk for the primary CTA, a chime for a
  PB, a low thud for a crash. Keep them quiet by default; expose a UI volume.
- Haptics and reduced motion already have settings; add a UI sound toggle.

## 5. Screen specs

### 5.1 Shell and bottom tabs (keep the tabs)

- Top bar: 64px, paper, page title 24 display, subtitle 11 uppercase label, left
  slot for back, right slot for settings and an account chip.
- Content: paper page, 16px side padding, 12px gaps, max width 560, scroll with a
  top/bottom edge fade (a 24px gradient to paper) so content does not collide
  with the chrome.
- Bottom tab bar: **72px + safe-area inset**, **ink** material (warm charcoal),
  cream icons, 4 tabs (Garage, Editor, Play, Account), 48px targets, icon 24 +
  label 11. Active tab is a 64x40 vermilion pill with cream icon/label; inactive
  is `HUD_DIM`. Keep Play in the middle. Do not turn Play into a floating action
  button unless the user asks; the request is to keep the tab system as it is.
- The shell background absorbs input (already true); the tab bar must never
  overlap the gesture bar. Use `DisplayServer.get_display_safe_area()` on mobile
  and the web shell's `env(safe-area-inset-bottom)` on web.

### 5.2 Play

The page becomes: hero, mode, tracks, daily, custom, sticky CTA.

1. **Hero card** (16:9 or 4:3): a live top-down mini-map of the selected track,
   drawn by a read-only `TrackPreview`/`TrackMap`. Track number and name top
   left, PB and medal bottom left, a small "world #N" chip top right. A subtle
   animated start dot shows the direction of travel. The card is paper, the road
   lines are ink, the start dot is vermilion.
2. **Mode pill**: Tracks / Endless, 44px, sliding thumb. Keep the existing
   `_set_mode` behaviour; endless hides the track and daily sections.
3. **Track carousel**: horizontal snap cards, 140x110, each with a mini-map,
   number and PB. Selected card has a vermilion ring and lifts 4px. Add a grid
   icon that switches to the existing 5-column number grid for power users. The
   grid is still the fastest way to pick track 27; the carousel is the way to
   sell it.
4. **Daily banner**: a wide ochre card, 96px: calendar icon, "Daily · 21 Nov",
   chips "Track 26" and "No reattach", best/tries, chevron. Ink text on ochre,
   never cream. Tapping opens the daily board sheet (see the daily leaderboard
   plan). A small "Top 3" preview can sit inside if the board is loaded.
5. **My tracks**: horizontal cards plus a "New track" card that opens the
   editor. Keep the existing custom-track picker logic.
6. **Sticky footer** above the tab bar: a 56px vermilion "Race" pill with cream
   text and the track name underneath, a "Ghost: Your best" dusty-blue chip on
   the left and a "More" icon on the right. The CTA stays in the thumb zone even
   when the page scrolls.

### 5.3 Garage

- A large car on a paper spotlight (a warm radial gradient, not a neon glow),
  name and a cosmetic tag, "Random" shuffle.
- Horizontal car carousel with 88x88 thumbnails; selected ring; locked cards
  show a lock and a hint. Keep `verify_cars` (every car has its own sprite).
- If the game has no per-car stats, do not invent them; show the model name and
  a "Sprite · CC0" credit instead. If stats are added later, use three 8px bars
  with a 2px track and a forest fill.

### 5.4 Editor

- The map stays the whole surface. The chrome changes:
  - Top floating paper toolbar: back, undo, redo, fit, grid, colours.
  - Bottom piece tray: horizontally scrolling 56x56 tiles with generated arc
    art, selected tile lifted and vermilion-ringed. Keep one-piece-per-pick.
  - Selected piece sheet: drag handle, angle/radius/length controls, Delete,
    Duplicate, Done. Keep the live slider callback silent (the existing
    `_apply_live` rule); only refresh the menu list on `drag_ended`/commit.
  - Colours sheet: two swatch rows + a gradient preview + Randomize.
  - Sticky bottom bar: "Play" primary, "Save" ghost. Validation errors appear
    as an inline ochre banner, not a modal.
- Do not change `TrackPreview` pan/zoom/pinch/tap behaviour; the verifier pins
  it. Only the surrounding chrome moves.

### 5.5 Account

- Signed out: a paper card with "Sign in" primary and "Create account" ghost;
  email/password fields with floating labels, show/hide, and the keyboard
  scroll behaviour that already exists.
- Signed in: a hero with a monogram avatar in an ink ring, username, "Member
  since", and a stats row (PBs, medals, best distance). Rows for "My runs",
  "Daily history", "Sign out"; a sync chip ("Synced", "Offline", "3 queued").
- Keep the account-name healing and per-account storage rules untouched.

### 5.6 Settings

- Grouped paper cards: Controls (3 keycaps), Audio (3 sliders with value
  bubbles), Feel (haptics, reduced motion, screen shake), Account, About.
- Keycaps: 40x40 rounded squares with the key label; the capture state pulses
  and says "Press a key". Keep the collision refusal.
- Version line at the bottom in mute.

### 5.7 Overlays

Replace centered `PanelContainer` cards with **bottom sheets**:

- 28px top radii, 24px padding, 36x4 drag handle, max 85% height, internal
  scroll, 62% ink scrim.
- Spring up; drag down to dismiss; tap the scrim to dismiss.
- Pause: Resume (primary), Restart, Settings, Quit; a mini track map.
- Finish: 48px time, delta pill, rank, medal, "Race again" primary, "Board" and
  "Watch" ghosts. New PB gets a forest ring and paper confetti.
- Crash: "Crashed", the distance/corner, "Retry" primary, "Menu" ghost;
  vermilion accent.
- Board: title "Daily · 21 Nov", challenge chips, top 50 rows, your row
  highlighted, watch buttons.
- History: grouped by date, PB flags, watch buttons.
- Account form and settings can stay full-screen pages; the daily/board/pause/
  finish/crash sheets are the priority.

### 5.8 HUD

This is where the two reported issues are fixed.

- **Remove the full-width yellow progress bar.** It is redundant: the road is
  the progress bar. If progress is wanted, use a 1px hairline at the very top
  edge with a 4px vermilion car dot at 40% opacity, and make it a Settings
  toggle (default off). Do not use a 7px filled bar.
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
  - Show `PB -0.045s` / `WR +0.120s`, forest when negative, vermilion when
    positive, neutral at `0.000`. If there is no replay (a PB from another
    device, a board row with no steps), hide that chip rather than falling back
    to the countdown.
  - For endless, compare at the same **elapsed time** instead: the reference's
    distance at `t`, so the delta starts at 0 and reflects whether the line is
    ahead of the record at that moment.
  - Implement the curve in `Game` (a `set_pace`/`pace_time_at(s)` pair), not in
    the HUD, so it is testable and the same curve can drive a ghost later.
- HUD layout:
  - Top-left smoked chip: mode label 10 uppercase + time 32 tabular in
    `HUD_INK`.
  - Top-centre: delta pill(s) in `HUD_GOOD`/`HUD_BAD`; no "SPEEDRUN" shout, no
    20px best line.
  - Top-right: pause 44px.
  - Bottom-centre: restart 44px; ghost chip in dusty blue if active.
  - Endless: distance 32 + a small speed tag; delta vs best at the same `t`.
  - All HUD text sits in smoked chips with a 1px top highlight; the road remains
    visible between them. No full-width bars.

## 6. Component and code map

| Area | Change |
|---|---|
| `godot/scripts/theme.gd` | Tokens, fonts, `SurfacePanel`/`SurfaceCard`/`PillButton`/`TabPill`/`KeyCap`/`Banner` variations; replace 2px borders with 1px hairlines; add elevation. |
| `godot/scripts/menu_shell.gd` | 64px top bar, 72px + safe-area tab bar, active pill, edge fades, tab motion. Keep `select()` as the entry point. |
| `godot/scripts/ui_motion.gd` (new) | Press/tab/sheet springs, reduced-motion switch, one place for timings. |
| `godot/scripts/ui_surface.gd` (new) | Paper card and smoked HUD chip, shared grain texture, optional desktop blur. |
| `godot/scripts/ui_icon.gd` | 24px grid, 1.75px stroke, new kinds. |
| `godot/scripts/app.gd` | Split the tab builders into `godot/ui/play_tab.gd`, `garage_tab.gd`, `account_tab.gd`, `settings_tab.gd`; `App` keeps state and signals. This is the right time to do the E1 split. |
| `godot/scripts/track_preview.gd` | Add a read-only mode for the Play hero; do not change editor input. |
| `godot/scripts/render.gd` | `clear_fx()` already added; no physics change. |
| `godot/tools/verify_ui.gd` | 44/48 targets, safe area, dynamic type, sheet fit, tab bar. |
| `godot/tools/verify_theme.gd` (new) | Contrast pairs, token presence, radius/type scale. |
| `godot/tools/verify_hud.gd` | Progress bar removed/optional; delta at `s=0` is 0; position-based ahead/behind; endless at `t`. |
| `godot/README.md`, `AGENTS.md` | Document the new tokens, sheets and HUD delta rule. |

Do not touch `physics/`, `car.gd`, `cfg.gd` or any parity golden for this work.
The UI is presentation only.

## 7. Implementation phases

| Phase | Scope | Effort | Exit criteria |
|---|---|---|---|
| P0 | Tokens, fonts, icons, `UiMotion`, `SurfacePanel`; no layout changes | S | All 16 verifiers green; screenshot baseline saved; contrast pass |
| P1 | Shell: top bar, tab bar, safe area, edge fade, tab motion | M | Bottom tabs unchanged in function; `verify_ui` + `verify_keys` green |
| P2 | Play: hero map, carousel, daily banner, sticky CTA, custom row | L | All controls fit at 320x568 and 420x820; `verify_ui` green |
| P3 | Garage, Account, Settings | M | `verify_cars`, `verify_storage`, `verify_ui` green |
| P4 | Bottom sheets: pause, finish, crash, board, history | M | Sheet fit and drag tests; no clipping |
| P5 | Editor chrome: toolbar, tray, sheet, colours | M | `verify_editor` unchanged and green |
| P6 | HUD: remove progress bar, live pace delta, smoked chips | M | `verify_hud` proves the new delta and no bar |
| P7 | Motion, sound, haptics, reduced motion, dynamic type | S/M | Reduced motion removes springs; 1.3x text fits |
| P8 | Polish, performance, screenshots, docs | S | 60fps menu on a low-end Android; docs updated |

**Sequencing with daily leaderboards:** P0-P1 are independent and should land
first. The daily board backend (see `ROADMAP.md`, C4b) can be built in parallel.
P2 then includes the daily card and board sheet, so the new surface is born in
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
- **Performance:** menu at 60fps on a low-end Android profile; no real-time blur
  on mobile/web; shared materials; draw calls under a budget (measure before and
  after).
- **Regression:** all 16 existing verifiers, `make test`, web export, APK.

## 9. Risks

- **Scope.** This is a full visual overhaul. Phase it; the game stays shippable
  after every phase.
- **Font licensing.** Use OFL fonts and ship the licences. Do not use a system
  font that may not exist on Android/web.
- **Light vs dark.** A paper menu is a real change of mood; B (Night Race) is
  the fallback if playtesters prefer dark. Do not mix the two halfway.
- **Blur cost.** Real backdrop blur can halve the frame rate on a low-end phone.
  Paper and smoked fills are the default; real blur is a desktop-only option.
- **Godot theme limits.** `StyleBoxFlat` has no gradient; use a gradient child
  or a shared shader. Do not build a new material per screen.
- **Editor regression.** `TrackPreview` input is pinned by `verify_editor`; only
  change the chrome around it.
- **Bottom tabs.** Keep the 4-tab system and the `select()` entry point. Do not
  introduce a fifth tab or a floating action button without asking.
- **HUD delta correctness.** The reference curve must be built from the actual
  replay; a final-time subtraction is what caused the current bug. Test at the
  start, at a mid-track split and at the finish.

## 10. Open questions

1. **Direction:** A (Paper & Petrol), B (Night Race) or C (Telemetry)?
2. **Track chooser:** carousel, the existing 5-column grid, or both with a
   toggle? (Recommend both; carousel default.)
3. **Play hero:** live track map, a car render, or both (map on Play, car on
   Garage)? (Recommend map on Play.)
4. **HUD progress:** remove it entirely, or keep an optional 1px hairline?
   (Recommend optional, default off.)
5. **Delta reference:** PB, WR, or both? (Recommend both, each hidden when its
   replay is unavailable.)
6. **Accent:** vermilion, ochre, or ink-only? (Recommend vermilion; ochre is
   reserved for the daily.)
7. **Bottom tab bar:** equal 4 tabs (recommended) or a raised Play tab?
8. **Fonts:** Fraunces + Inter, Instrument Serif + Inter, or Archivo + Inter?
9. **Order:** UI foundation first (recommended) or daily board backend first?
10. **Scope:** do we redesign every screen in one pass, or ship Play + HUD first
    and leave Garage/Account/Settings for a second pass?

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
