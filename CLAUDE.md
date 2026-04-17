# caged — guitar fretboard visualizer

Interactive Elm app that renders pentatonic and diatonic scales across a
22-fret guitar neck with colored box shapes and overlap stripes.
Live site: https://boxed.github.io/caged/

## Stack

- **Elm 0.19.1** — `port module` in `src/Main.elm` (~1400 lines).
  Uses `Browser.application` (not sandbox) for URL-based state.
- **elm-test** — `elm-explorations/test` for box-shape validation.
- No bundler, no npm. `index.html` loads the compiled `elm.js` directly.
- Hosted on **GitHub Pages** from `main` branch, root path.

## Build & test

```sh
elm make src/Main.elm --output=elm.js   # compile
elm-test                                 # run tests (363 tests)
```

`elm.js` **is committed** — Pages has no build step, so the compiled artifact
must be part of the repo. After any change to `src/Main.elm`, recompile and
commit both files together.

## File layout

- `src/Main.elm` — the whole app: model, music theory, SVG rendering, ports.
- `tests/BoxShapeTests.elm` — tests that box shape edges land on scale notes,
  stripe edges land on scale notes, and overlap stripes cover all multi-box
  overlap regions.
- `index.html` — host page; loads `elm.js`, wires Wake Lock ports.
- `elm.json` — Elm dependencies (including test deps).
- `elm.js` — compiled output (committed).
- `fretboard-reference.jpeg` — the original reference image.
- `README.md` — user-facing docs.

## Scales and modes

Five scale types: `MinorPent`, `MajorPent`, `Ionian`, `Dorian`, `Aeolian`.

Adding a new mode of the major scale requires:
1. Add constructor to `ScaleType`.
2. Add intervals to `scaleIntervals`.
3. Add `rootFret` case (R−7 for major-flavored, R−4 for minor-flavored).
4. Add `thirdInterval` case in `noteRole` (3 for minor 3rd, 4 for major 3rd).
5. Add to `usesMajorBoxShapes` (True for 7-note modes).
6. If the mode's interval pattern differs from ionian/dorian on specific
   strings, add a dedicated box shape function and dispatch in `majorBoxShape`.
7. Add button, title, and interval labels in the view.
8. Run `elm-test` — the edge tests will catch any shape where lo/hi extends
   to a non-scale-note fret.

## Music theory model

- **Notes**: `Int` pitch classes 0–11 (C=0).
- **String numbering**: S1 = high E (top), S6 = low E (bottom).
- **rootFret** anchors boxes on the low-E string:
  - MinorPent, Aeolian: `(R − 4) mod 12` — root on low E.
  - MajorPent, Ionian, Dorian: `(R − 7) mod 12` — relative minor on low E.
- **Note roles** (`noteRole`): Root / Third / Fifth / Other. Scale-wide, not
  per-box. 3rd = interval 3 (minor) or 4 (major). 5th = interval 7 always.

## Box shapes — two systems

### Pentatonic boxes (`boxShape`)
- 5 non-overlapping boxes, 2 notes per string, clean partition.
- Used for MinorPent and MajorPent.
- Each note belongs to exactly one box via `boxOf`.

### Major-scale-mode boxes (`majorBoxShape`)
- Mode-specific shapes dispatched by `ScaleType`:
  - **Ionian/Aeolian** use `ionianBoxShape` — wider boxes derived from
    standard major-scale CAGED positions.
  - **Dorian** uses `dorianBoxShape` — derived from Dean Arnold's dorian
    patterns (https://www.deanarnoldguitar.com/post/dorian-scale-patterns-for-guitar).
- Adjacent boxes overlap (shared boundary notes). Overlaps are rendered as
  diagonal stripe patterns; non-overlap regions are solid fills.
- Box shapes differ between modes because each mode's intervals place notes
  at different frets — a shape derived for ionian will have empty extensions
  when applied to dorian (and vice versa). The test suite catches this.
- The 5→1 wrap overlap (box 5 of one octave overlapping box 1 of the next)
  is handled separately in `drawWrapOverlap`.

## Rendering

SVG draw order (later = on top):
1. Fret markers (inlay dots on neck — drawn first so box tints blend over them).
2. Solid box polygons (5 boxes × octaves). For major-scale modes, later boxes
   paint over earlier in shared regions.
3. Overlap stripe polygons (adjacent pairs + wrap). Drawn with opaque
   pre-blended colors (`color-mix`) so they fully cover underlying solids
   without alpha contamination.
4. Fret lines, nut, strings.
5. Note markers (circles/squares by role).
6. Fret numbers + inlay dots below fretboard.

Polygon edges land at fret-center positions (beneath notes), not at fret
lines. Pinch overlaps (single shared fret) collapse to zero width and are
visually invisible — accepted trade-off for consistent edge alignment.

## Dark mode

All colors go through CSS custom properties with `light-dark()` in
`index.html`. Box colors for dark mode use `oklch()` with high chroma
so they read well after the 0.45/0.55 opacity blend. Stripe patterns
pre-blend with `color-mix(in srgb, var(--box-N) 55%, var(--bg) 45%)`
for opaque rendering.

## URL state

`Browser.application` syncs root + scale to query params:
`?root=A&scale=dorian`. Sharp notes use `Cs`, `Ds`, etc. to avoid
URL-encoding `#`. `Nav.replaceUrl` (not push) on each change.

## Ports (Wake Lock)

`port module Main` exposes `requestWakeLock`, `releaseWakeLock` (outgoing)
and `wakeLockChanged` (incoming). `index.html` wires these to
`navigator.wakeLock` with auto-reacquire on `visibilitychange`.

## Tests (`tests/BoxShapeTests.elm`)

Three test suites (363 tests total):

1. **`suite`** — for every (mode, box, string) the per-string `lo` and `hi`
   f_rel values land on actual scale notes. Catches shape definitions that
   extend to non-scale frets.
2. **`overlapCoverage`** — for every (string, fret) on the fretboard, if 2+
   solid boxes cover it, an overlap stripe must also cover it.
3. **`stripeEdges`** — for every stripe overlap polygon (adjacent + wrap),
   the per-string lo/hi values are scale notes.

## Deployment

- Repo: https://github.com/boxed/caged
- Pages source: `main` branch, root path (legacy Pages build, no Actions).
- Every push to `main` triggers a Pages rebuild within ~1 minute.
- Elm replaces the `#app` div on init, so CSS targeting `#app` doesn't work.
  Use inline styles from Elm instead.
- iOS safe-area insets handled via `viewport-fit=cover` + `env()` padding on
  `<body>`.
