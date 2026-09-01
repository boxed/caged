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
elm-test                                 # run tests (~5300 tests)
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

Scale types: the two pentatonics, the seven diatonic modes, `Blues`,
`HarmonicMinor`, `MelodicMinor`, three diagonal climbing variants
(`DiagonalPent`/`DiagonalMajorPent`/`DiagonalBlues`), the two all-notes
maps `ChromaticMinor`/`ChromaticMajor`, and the four triads
`TriadMajor`/`TriadMinor`/`TriadDim`/`TriadAug`.

`ChromaticMinor` and `ChromaticMajor` (the **All notes (minor)** / **All notes
(major)** buttons, slugs `all-notes-minor` / `all-notes-major`) are deliberately
*not* scales — they are a plain note map of the whole neck. Their intervals are
all twelve pitch classes, so every fret carries a marker. The two differ only in
which chord tones get marked, and `isChromatic` covers every case they share.
The bare `all-notes` slug still parses, mapping to `ChromaticMinor`, so old
links keep working (`Nav.replaceUrl` then rewrites it). Consequences threaded
through the code:

- `drawBoxRegions` returns `[]` for them — with all 12 degrees present a CAGED
  box would swallow the neck, so no box polygons or overlap stripes are drawn.
  They are therefore excluded from `boxScales` in the tests.
- `noteRole` short-circuits to intervals measured from the chosen root: root,
  the 5th (7, the same either way), and the third/seventh the *mode* names —
  `chromaticThird`/`chromaticSeventh` give 3/10 for minor and 4/11 for major.
  With no scale there is nothing to pick which third is the diatonic one, which
  is exactly why the choice is split across two modes.
- Every marker is filled with its pitch-class color (`pitchColor`, the `--pc-*`
  vars). Hues follow the circle of fifths, so a semitone step is half the wheel
  away (adjacent frets never look alike) and the naturals land in the warm half,
  the accidentals in the cool half. Markers are drawn by `chromaticMarker`;
  the label uses `--note-text` on every fill.
- `rootSpelling` and `spelledName` short-circuit to `noteName` — all twelve
  pitch classes are present, so there is no key signature to spell against and
  the conventional sharp names are used on both the fretboard and root buttons.
- The legend drops the box swatches and shows pitch-gradient chips for
  Root / ♭3 or 3rd / 5th / ♭7 or 7th / other plus a "hue = note" note.

Adding a new mode no longer needs per-mode box tables — `deriveBox` generates
the shapes from the intervals. It requires:
1. Add constructor to `ScaleType`.
2. Add intervals to `scaleIntervals`.
3. Add `rootFret` case (`majorAnchor` for major-flavored, `minorAnchor` for
   minor-flavored — these already fold in the tuning's low-E open pitch).
4. Add `majorFlavored` case (True iff box 1 anchors on the relative minor —
   matches the `majorAnchor` choice in step 3).
5. Add `thirdInterval`/`seventhInterval` cases in `noteRole` (and a
   `fifthInterval` case if the 5th is not 7 semitones).
6. Add `scaleDegrees` case (for enharmonic spelling) and a `scaleSlug` /
   `scaleFromSlug` pair for the URL.
7. Add button, title, and interval labels in the view.
8. Add to `boxScales` in `tests/BoxShapeTests.elm` and to its `scaleName`.
9. Run `elm-test` — `coverage` checks every scale note sits in a box and
   `edgeSanity` checks every box is well-formed in every tuning.

## Triads

The four triad modes (**Triads** row, slugs `triad-major` / `triad-minor` /
`triad-dim` / `triad-aug`) are chords, not scales: three intervals, and the
grouping that matters is the *voicing*, not the position. So `drawBoxRegions`
hands them to `drawTriadLassos` instead of the CAGED machinery, and they are
excluded from `boxScales` in the tests. They are the only modes where the 5th
is not 7 semitones, hence `fifthInterval` (6 for dim, 8 for aug), read by
`noteRole`.

- **`triadVoicingsFor tuning scale root stringSet`** is the single source of
  truth for the shapes — the triad's `deriveBox`. For each three-string set it
  walks up the neck: take a chord tone on the lowest string, then on each
  higher string take the *next degree* above the note below it, inside the
  octave. Insisting on the next **degree** (not merely the next chord tone) is
  what keeps a voicing in close position: near the nut the note it wants can
  sit below fret 0, and then that voicing correctly does not exist there
  instead of doubling a degree.
- Voicings are read by **pitch**, not pitch class, via `openAbs` — a tuning
  stores only pitch classes, so the span between adjacent strings is taken as
  the smallest ascending interval that fits (a unison reads as an octave).
  That keeps the six strings strictly ascending in any custom tuning. Strings
  an exact octave apart (the pathological test tunings) have no close-position
  triad at all, which is correct.
- **Inversion is the index of the bass note's degree** in the sorted intervals
  — 0 root position, 1 first, 2 second — and picks the lasso's color
  (`inversionColor`, the `--inv-*` vars: the box 1–3 hues, saturated, since a
  3px ring needs more punch than a 55%-opacity fill).
- **`StringSet`** (`AllStrings` or `StringTrio t`, `t` = the set's highest
  string) is model state, shown as the **Strings** row and carried in the URL
  as `?strings=2-3-4` — only in triad modes, so every other mode keeps the URL
  it had.

## Music theory model

- **Notes**: `Int` pitch classes 0–11 (C=0).
- **String numbering**: S1 = high E (top), S6 = low E (bottom).
- **Tuning**: `{ name, slug, strings }` where `strings` is the six open-string
  pitch classes (S1→S6). `openString tuning s` indexes it; `noteAt tuning s f`
  is the pitch class at a fret. Standard tuning = `[4,11,7,2,9,4]`.
- **rootFret** anchors boxes on the low-E string, following its open pitch:
  - Minor-flavored (MinorPent, Aeolian, Blues, Harmonic/Melodic minor):
    `(R − openLowE) mod 12` — root on low E (= `R − 4` in standard tuning).
  - Major-flavored (MajorPent, Ionian, Dorian, Mixolydian, …):
    `(R − 3 − openLowE) mod 12` — relative minor on low E (= `R − 7` standard).
- **Note roles** (`noteRole`): Root / Third / Fifth / Other. Scale-wide, not
  per-box. 3rd = interval 3 (minor) or 4 (major). 5th = interval 7 always.

## Tunings

The selector offers preset tunings (Standard, Drop D, Eb/D Standard, Drop C,
DADGAD, Open G/D/E) **plus arbitrary custom tunings** via per-string ▲/▼
steppers (shown only after pressing **Custom**). A custom tuning round-trips
through the URL as six dash-joined note slugs (`?tuning=D-A-G-D-A-D`); presets
use their slug. A note-encoded slug always stays "Custom" so `Nav.replaceUrl`
re-firing `UrlChanged` can't collapse it back to a preset.

## Box shapes — one derivation (`deriveBox`)

`deriveBox tuning scale b` is the **single source of truth** for all CAGED box
geometry — no per-mode or per-tuning tables. A box is a *playing position* that
**must contain the complete scale** (every degree, somewhere across its strings)
so you can play the whole scale within it — that is the hard requirement.
Ergonomics (a compact fret window) is secondary and yields when it conflicts.
It works for any tuning because it reads the actual open-string pitches rather
than offsetting a standard-tuning shape.

- **Anchors**: the 5 boxes sit on the minor-pentatonic degrees of the low string
  relative to `rootFret` — `pentAnchor` = `[0,3,5,7,10]`.
- **Window** (`boxWindow`): base window `[A−1, A+3]` for *every* scale — a
  compact 5-fret CAGED position. Seven-note modes use the same window as the
  pentatonic, so mode box N and pentatonic box N are the same hand position;
  the two extra degrees fill in inside the window instead of pushing the
  position up the neck. (An earlier `[A, A+4]` for 7-note scales put boxes 1,
  2, 3 and 5 a fret too high versus published major-scale position charts.)
- **Completeness growth**: the box's upper bound grows past the base window until
  every scale degree is present. For every ordinary tuning the base window is
  already complete, so nothing grows; only degenerate tunings (e.g. all six
  strings the same pitch — where a compact box *cannot* hold all degrees) force
  wider, heavily-overlapping boxes. Guarded by the `completeness` test.
- **Membership** (`anchorScaleSet`): a note at relative fret `off` on string `s`
  is in the box iff `(open s − open 6 + off) mod 12` is a scale degree. Major-
  flavored scales (`majorFlavored`) rotate the intervals up a minor third because
  box 1 anchors on the relative minor. The root cancels, so shapes are
  root-independent.
- **Reproduces the canon**: in standard tuning this yields the exact textbook
  pentatonic and Ionian/Aeolian shapes — locked by the `canonicalShapes` test.
  Dorian/Lydian/Locrian etc. are now the algorithm's consistent CAGED shapes
  (they used to be hand-tuned / imported and differed slightly).
- **Overlaps**: wherever adjacent box windows overlap, the shared band is drawn
  as diagonal two-color stripes (`drawOverlapStripe`), plus the 5→1 octave wrap
  (`drawWrapOverlap`). This is computed for *every* non-diagonal scale, since
  `deriveBox` can produce real overlaps in any tuning (e.g. pentatonic in Open
  G). In standard tuning pentatonic boxes only touch, so those overlaps collapse
  to invisible zero-width pinches. Solid fill (`boxFillOpacity`) and the stripe
  pre-blend (`boxBlendPct`) share one ratio so a stripe reads like the solids
  around it.
- **Diagonal scales** are a separate climbing-shape system (`DiagShape`,
  `drawDiagonalShape`) and still use the pitch-preserving `boxShift` offset,
  since those are fixed shapes meant to be slid.

## Rendering

### Triad lassos

A lasso is a bead around each of the three notes joined by a ribbon along their
centers (`triadBody`), so the shape hugs the markers at any angle — a plain
wide stroke let the square root markers poke out of diagonal runs. **Every string set gets its own size** (`triadSizeStep`, 6px apart), so where
sets pile onto the same note their lassos nest instead of coinciding. The sizes
are interleaved, not handed out in string order: a set overlaps its neighbor on
two strings but the set beyond that on only one, so 2-3-4 is smallest, then
4-5-6, then 1-2-3, then 3-4-5 — two steps between every pair sharing two
strings. The smallest size is the floor (it must clear the 28px note markers),
the largest the ceiling (beyond it a bead swallows the neighboring strings).

The wash is dropped in the **all-sets** view: four tints over the same notes is
noise, so there the lassos are outline-only, like the reference chart. With one
set selected the wash stays, reading the enclosed area at a glance. The outline
is that shape minus the same shape inset by `triadLassoInset`, which gives an
even ring. It is drawn as a **masked rect**, not the obvious wide-stroke +
background-stroke pair, because that pair would paint over what sits under the
lasso: the inlay dots, and the rings of any lasso it crosses in the
all-string-sets view. The wash inside is a `Svg.g` with a group `opacity` so
bead and ribbon do not double up where they overlap.

### Draw order

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

`Browser.application` syncs root + scale + tuning (+ string set, triads only)
to query params: `?root=A&scale=dorian&tuning=drop-d`, or
`?root=C&scale=triad-major&strings=2-3-4`. Sharp notes use `Cs`, `Ds`, etc. to avoid
URL-encoding `#`. The `tuning` param is omitted for Standard. `Nav.replaceUrl`
(not push) on each change.

## Ports (Wake Lock)

`port module Main` exposes `requestWakeLock`, `releaseWakeLock` (outgoing)
and `wakeLockChanged` (incoming). `index.html` wires these to
`navigator.wakeLock` with auto-reacquire on `visibilitychange`.

## Tests (`tests/BoxShapeTests.elm`)

Test suites (~7600 tests total):

1. **`canonicalShapes`** — `deriveBox` in standard tuning reproduces the textbook
   pentatonic and Ionian/Aeolian CAGED shapes exactly. This is the spec: the
   clean algorithm must yield the known-good shapes.
2. **`completeness`** — the hard requirement: every box contains the complete
   scale (all degrees), for every tuning including pathological ones (all six
   strings the same pitch). Guards that no box is ever missing a scale degree.
3. **`coverage`** — for every tuning and scale, every scale note on the neck
   sits inside some box, so every rendered note marker has a box behind it
   (guards that the boxes tile).
4. **`edgeSanity`** — every box covers all 6 strings with lo ≤ hi, in every
   tuning.
5. **`overlapCoverage`** — for every non-diagonal scale, wherever 2+ boxes
   overlap an overlap stripe covers the same position, in every tuning.
6. **`stripeEdges`** — stripe overlap edges land on scale notes.
7. **`diagonalCells`** — the diagonal climbing shapes carry the right scale
   degrees on each string.
8. **`triadShapes`** — every triad voicing sits on its set's three strings and
   inside the neck, carries all three chord tones with none doubled, is in
   close position (each note under an octave above the one below), and its
   `inversion` names the degree actually in the bass — for every tuning and all
   four qualities. Plus `canonicalTriads`: C major on strings 2-3-4 in standard
   tuning is the textbook set (x x 2 0 1 x, x x 5 5 5 x, x x 10 9 8 x, then the
   octave repeat).

## Deployment

- Repo: https://github.com/boxed/caged
- Pages source: `main` branch, root path (legacy Pages build, no Actions).
- Every push to `main` triggers a Pages rebuild within ~1 minute.
- Elm replaces the `#app` div on init, so CSS targeting `#app` doesn't work.
  Use inline styles from Elm instead.
- iOS safe-area insets handled via `viewport-fit=cover` + `env()` padding on
  `<body>`.
