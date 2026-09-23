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
elm make src/Main.elm --optimize --output=elm.js   # compile
elm-test                                          # run tests (~5300 tests)
```

`--optimize` is not optional: `elm.js` is the artifact the site serves, so the
committed build has to be the release build. Without it the shipped file keeps
full record field names and skips Elm's dead-code elimination and unboxing.
`--optimize` also refuses to compile any `Debug.*` call, which is the check you
want on a file that goes straight to production.

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
`HarmonicMajor`/`HarmonicMinor` (major with ♭6 / minor with a raised 7th),
`MelodicMajor`/`MelodicMinor` (major with ♭6 ♭7 / minor with a raised 6th and
7th), three diagonal climbing variants
(`DiagonalPent`/`DiagonalMajorPent`/`DiagonalBlues`), the two all-notes
maps `ChromaticMinor`/`ChromaticMajor`, the empty `Blank` neck, and the four triads
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

`Blank` (the **None** button in the All notes group, slug `blank`) is the same
bare neck with no markers at all — for printing empty necks to practice on. It
has no intervals, so nothing is drawn; it is folded into `isChromatic` so it
inherits the no-boxes path, and the heading drops the root ("Blank neck") and
the legend drops the tones row.

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
7. Add a button to the right `pickerGroup` in `viewControls`, plus title and
   interval labels in the view.
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
  - Major-flavored (MajorPent, Ionian, Dorian, Mixolydian, Harmonic/Melodic
    major, …): `(R − 3 − openLowE) mod 12` — relative minor on low E
    (= `R − 7` standard).
- **Note roles** (`noteRole`): Root / Third / Fifth / Other. Scale-wide, not
  per-box. 3rd = interval 3 (minor) or 4 (major). 5th = interval 7 always.
- **Naming and order**: a button says only what its picker group does not
  already say — the **Pentatonic** group's buttons read "Major" and "Minor",
  not "Major pentatonic". Ionian and Aeolian are labeled **Major (Ionian)** and
  **Minor (Aeolian)** — the common name first, the mode name in parentheses.
  Every major/minor pair is listed major-first, in the buttons, in the
  `ScaleType` constructors and in every `case` over them (major/minor
  pentatonic, Ionian/Aeolian, harmonic, melodic, the all-notes maps, the
  diagonals).

## Tunings

The selector offers preset tunings (Standard, Drop D, Eb/D Standard, Drop C,
C# Standard (Iommi), DADGAD, Open G/D/E) **plus arbitrary custom tunings**
via per-string ▲/▼ steppers (shown only after pressing **Custom**). A custom
tuning round-trips through the URL as six dash-joined note slugs
(`?tuning=D-A-G-D-A-D`); presets use their slug. A note-encoded slug always
stays "Custom" so `Nav.replaceUrl` re-firing `UrlChanged` can't collapse it
back to a preset.

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

A lasso is a **pill** (`triadCapsule`): one round-capped, round-joined stroke
threaded through the three note centers, so every note sits in a rounded end or
elbow of an even-width shape. The outline is that pill minus the same pill
inset by `triadLassoInset`, which leaves an even ring. It is drawn as a **masked
rect**, not the obvious wide-stroke + background-stroke pair, because that pair
would paint over what sits under the lasso: the inlay dots, and the rings of any
lasso it crosses in the all-sets view.

The interior is the same pill stroked in an **opaque** blend of its color with
`--bg` (`inversionFill`, `triadFillPct`), the way the overlap stripes pre-blend
theirs. Translucent fills stacked their tints wherever pills crossed, into
colors that no longer said which inversion they belonged to. Opaque means a
pill hides what it covers, so two things follow: the pills are painted
**largest first** (small ones stay on top, where they would otherwise be
swallowed by the sets around them), with every fill down before any ring so no
ring is painted over; and `viewFretboard` draws the whole neck — inlay dots,
fret lines, nut and strings — *before* the lassos in triad mode, so a pill
reads as one solid shape rather than something with the fretboard grid ruled
across it.

**Every string set gets its own width** (`triadSizeStep`, radii 5px apart), so
where sets pile onto the same note their lassos nest instead of coinciding. The
sizes are interleaved, not handed out in string order: a set overlaps its
neighbor on two strings but the set beyond that on only one, so 2-3-4 is
smallest, then 4-5-6, then 1-2-3, then 3-4-5 — two steps between every pair
sharing two strings, and at most three sets meet on any one string.

The smallest size is the floor, and it is set by the **root markers**: a 28px
square rounded 3 reaches 18.6px from the note center, not the 14px of the
circles. Sizing to the circles is what let the roots poke out of an earlier
pass. The largest is the ceiling — beyond it a pill swallows the neighboring
strings whole.

### Neck heading

`viewScaleTitle` puts the scale name and its notes on one line, the notes muted
(`--text-2`) beside the name, and each note's scale degree stacked underneath
it rather than trailing in brackets (`noteChip`). That is one line of vertical
space instead of two, which matters once the page is a stack of necks, and it
lines the degrees up into their own row you can read across. The modes with no
degree list — the all-notes maps, and the triads' string-set label — put a
muted `aside` in the same place instead.

The two blocks are **built to the same height**: 22px at line-height 1.2 for
the name, 13px over 10px at 1.15 for a note above its degree, both 26.4px. So
the row centers rather than baselines them, which lines their tops and bottoms
up and makes the pair read as one band instead of a title with something
hanging off it. Change one size and the other has to move with it.

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

In triad mode 1 and 4 both move ahead of the regions — the whole neck is drawn
first and the opaque pills sit on top of it (see **Triad lassos**).
6. Fret numbers + inlay dots below fretboard.

Polygon edges land at fret-center positions (beneath notes), not at fret
lines. Pinch overlaps (single shared fret) collapse to zero width and are
visually invisible — accepted trade-off for consistent edge alignment.

## Toolbar

The control panel is ordered by **how often you reach for a thing**. The scale
groups and the root are a list you pick from every time you set a neck up, so
they stay open. Tuning and the highlight window you set once and then play, so
each folds down to a single button that says where it stands and gets out of
the way. That is most of the panel's height back, and on a phone it is the
difference between the neck being on screen and not.

- **The scale picker is one radio group of 23 options**, broken into the
  families a player would look in: Pentatonic, Modes, Harmonic, Melodic,
  Diagonal, Triads, All notes. Each is a `pickerGroup` — an uppercase caption
  riding with its own buttons rather than sitting in a column — and the groups
  flow and wrap between themselves inside a `controlBlock`. Since the caption
  carries the context, the buttons inside it can just say "Major", which is
  what gets the whole picker into two lines instead of four long rows.
- **`controlBlock` is capped at `totalWidth`**, the neck's width. Without the
  cap the flex row would lay every group on one line and drag the page out to
  match, because the body sizes itself to its widest row. With it, the neck is
  what sets the page width — which the old 14-button scale row did not allow:
  it was wider than the neck and every screen paid for it.
- **Tuning** is a disclosure: the button reads `Standard tuning ▾`, opens the
  list of presets when pressed, and closes again as soon as you pick one.
  **Custom** is the exception — `SetTuning` leaves the list open for it, because
  the per-string steppers it reveals are the thing you opened the list for. A
  custom tuning has no name worth reading, so the button spells out its six
  notes instead (`tuningLabel`), written low string to high the way a tuning is
  normally written down.
- **Highlight shapes** and **Highlight string** are plain on/off toggles:
  pressing one switches it on at `defaultFocus` / `defaultStringFocus` and
  reveals its steppers; pressing it again puts them away. The caret on the
  tuning button is what separates those from it — one opens a list, the others
  are on or off. Both steppers are the same `stepper`, which takes its label
  already rendered because a string reads as `6 (E)`, not as a bare number.
- `tuningOpen` is on the model but deliberately **not** in the URL: it is the
  state of a drawer, not of the diagram, and a shared link should not reopen
  someone else's drawer.
- There is no label column any more. Every caption rides with the buttons it
  names, so rows start at the left edge and a row can hold several groups.

## Highlight shapes

The **Highlight shapes** button sets a fret window — `Frets 4 – 8` — and
everything that does not fall in it is drawn gray. It is `focus : Maybe Focus` on the model,
a pair of inclusive fret numbers, and like the tuning it belongs to the hand
rather than to one neck: one window applies to every neck at once. That is the
whole point. Practicing a C–Am–G–F progression between frets 4 and 8 lights up
box 1, box 1, box 3 and box 4, one per neck, and fades everything else.

- **`focusedShapes`** is the single rule: of all the drawn instances of a
  shape, the ones with the most frets inside the window stay in color. It
  returns a `Maybe` because "no window set" and "window that lit nothing" have
  to render differently — `Nothing` mutes nothing at all. Ties all stay lit; a
  window as wide as one position picks out exactly one shape, and a wider one
  legitimately holds two.
- It is keyed by whatever identifies an instance, so the same function serves
  the CAGED boxes (keyed by box number and octave, spans from `boxSpan`) and
  the diagonal climbing shapes (keyed by shape index and octave, spans from
  `diagonalSpan`). `isMuted` turns the result into a per-shape bool.
- **Triads use containment instead**, not "overlaps most": a voicing is in
  position when you can reach all three notes without moving your hand. A lasso
  poking out of the window is one you cannot play there, whichever way it leans.
- Muted shapes swap their color for `--box-off` (`boxFill`) or `--inv-off`
  (`inversionColor`/`inversionFill`), both chroma 0 at roughly the lightness of
  the color they replace, so a muted box still reads as a box.
- **Overlap stripes mute per side.** The band where an in-position box meets an
  out-of-position one is half color, half gray, because that is what it is.
  So a stripe pattern is minted for each of the four muting combinations
  (`stripeMutings`) and the id says which (`stripeId`, e.g. `ovlp-1-2m`) — four
  patterns per pair instead of one.
- The **Highlight shapes** button switches the window on and off; the fret
  steppers only exist while it is on. The legend grows a gray chip reading
  "outside frets 4–8" to say what the gray means. `clampFocus` keeps the window on the neck
  and the right way round, clamping the low end against the high end rather
  than swapping past it, so a stepper pushed too far just stops.

## Highlight string

The **Highlight string** button picks one string — `String 6 (E)` — and every
note *off* it is drawn faded. It is `stringFocus : Maybe Int` on the model, a
string number 1–6, and like the fret window it belongs to the hand rather than
to one neck: one string applies to every neck at once. The two are independent
and compose — one box, one string — which is the pair you want when you are
learning a position string by string.

- It fades the **note markers only**, and by opacity (`offStringOpacity`,
  applied to the whole marker group in `offString`) rather than by swapping in
  a gray. The boxes and lassos are fret-position shapes and have nothing to say
  about strings, so they are left alone; and the notes fade rather than vanish
  because where the note you want sits relative to its neighbors is half of
  what you are looking at.
- The highlighted string's own line is drawn heavier and in `--string-on`
  (`drawStrings`, which takes the `Board` for this). That says which string is
  live on the stretches of neck that carry no notes. In triad mode the strings
  go under the opaque pills, so a lasso covers it — the same trade-off the
  inlay dots already make.
- The stepper names the string's open note as well as its number
  (`stringLabel`), since in a custom tuning the number alone does not say what
  you are on. **▲ moves toward string 1**, the one drawn at the top of the
  neck. `clampString` holds it to 1–6.
- The legend grows a faded note chip (`legendFade`, at the same
  `offStringOpacity`) reading "off string 6 (E)".

## Print

`index.html` has a `@media print` block for printing sheets of necks. Anything
you click carries the `no-print` class (the control panel, the drag handle, ×,
Add neck, the page header with Keep screen on) and is hidden, as is the
"Blank neck" heading — a printed blank neck needs no caption. `neck-row` drops the active accent and
drag tint (with `!important`, since Elm styles inline) and keeps a neck from
splitting across pages. Print forces the light scheme and a pure white page (`--bg`, `--surface`, and
the `html`/`body` background).

## Monochrome

The **Monochrome** button (`mono` on the model, `&mono=1` in the URL) swaps
every color on the necks for black-and-white dither textures, for a printer with
no color. It has to be a switch: browsers never match `@media (monochrome)` in
print, and a Black & white print setting only turns the finished page gray. It
is on screen as well, so what you see is what prints.

- **`ditherCells`** holds the five textures, on a 4×4 grid of `ditherPixel`
  squares: scattered dots, horizontal lines, rising diagonals, vertical lines,
  falling diagonals. They differ in *structure*, not only density, so
  neighboring boxes stay apart in gray. Boxes 1–3 are also the three triad
  inversions, which is why those three are the least alike.
- `ditherPatternDefs` mints them per neck (`n0-dither-3`) and `regionPaint` is
  the one place a box's paint is chosen: color at an opacity, or a texture at
  full strength (it is mostly holes, so the neck shows through).
- **No overlap stripes** in monochrome. The textures are transparent, so
  where two boxes overlap both textures show, and that already reads as the
  pair.
- A **muted** shape (outside the highlight window) is left unpainted, since
  any gray would read as one more texture. The legend shows it as an empty
  outlined chip (`legendBlank`).
- Triad pills stay opaque: `triadFill` strokes the page color, then the
  inversion's texture over it. The rings are plain ink (`ringColor`), gray
  when muted.
- The all-notes markers drop their pitch hues for `--note-bg`, and "hue = note"
  goes from the heading and the legend.

## Two columns

The **Two columns** button (`twoColumns`, `&cols=2`) lays the neck list out as
a two-column grid pinned to one neck's width (`totalWidth`), so each neck
renders at half size and a printed page holds twice as many. With it off, the
list has no grid styles, so the one-column layout is unchanged. A drag moves
a neck two slots per row, so it stays in its column.

## Dark mode

All colors go through CSS custom properties with `light-dark()` in
`index.html`. Box colors for dark mode use `oklch()` with high chroma
so they read well after the 0.45/0.55 opacity blend. Stripe patterns
pre-blend with `color-mix(in srgb, var(--box-N) 55%, var(--bg) 45%)`
for opaque rendering.

## The neck list

The page draws a **list of necks**, not one fretboard. A `Neck` is a root, a
scale and (triads only) a string set; `Model` holds `necks : List Neck` plus
`active`, the index the control panel edits. Tuning is *not* per neck — it is a
property of the instrument, so it stays on the model and every neck shares it.

This replaced an earlier "Multiple roots" checkbox that turned the root buttons
into a multi-select. That could only ever draw one scale at a time, so you
could not put A minor pentatonic above C major; per-neck scales are the whole
point of the list.

- **`Board`** is what the drawing code takes: a neck plus the tuning plus an
  `id`. Every render function reads its root/scale/stringSet/tuning off a
  `Board`, never off the model, which is what lets one page draw many necks.
  `boardAt` pairs neck `i` with the tuning; `activeBoard` is the one the
  controls are pointed at, and it feeds the legend and (single-neck only) the
  title above the controls.
- **`board.id`** namespaces the SVG ids a neck mints — the `ovlp-*` stripe
  patterns and the `triad-lasso-*` masks. Ids are document-global, so without
  a prefix a `url(#…)` would resolve to whichever neck rendered first and every
  later neck would wear the first one's patterns. The prefix is the neck's
  **index** (`n0-`), not its root, because two necks may now share a root (the
  same key in two different modes).
- Every control edits the active neck through `mapActive`. **Add neck**
  duplicates the active neck and selects the copy, so you reshape it with the
  ordinary root and scale buttons. **×** removes one; `RemoveNeck` refuses the
  last one, so the list is never empty and the buttons always have something
  to edit.
- With a single neck the list furniture disappears entirely — no handle, no ×,
  no active accent, title above the controls — so the page looks exactly as it
  did before there was a list.

### Reordering

Each neck has a grip handle on its left. Dragging uses **pointer events**, not
HTML5 drag and drop, which does not fire for touch at all — and this is a chart
you reorder on the tablet propped up in front of you.

- `DragStart` reads `clientY` **and the row height**, decoded straight off the
  DOM as `currentTarget.parentElement.offsetHeight`, because Elm cannot measure
  the page and a drag has to know how far one slot is. The row carries its gap
  as `padding-bottom` rather than a margin so `offsetHeight` is the full pitch.
- `DragMove` recomputes the target slot from the distance dragged **since the
  grab**, never since the last move, so previewing the reorder cannot feed back
  into the arithmetic and make the neck chase the finger.
- The list renders in the previewed order (`orderedNecks`) while a drag is
  live, so the neck travels with the pointer; `DragEnd` commits it and `active`
  follows the neck that moved. `displayIndexOf`/`committedIndexOf` map between
  the screen slot and the slot in `model.necks`, so a click on a previewed row
  still names the right neck.
- Touch pointers are implicitly captured by the handle, so its own
  `pointermove` is enough there. A mouse is not captured and walks straight off
  the handle, so `subscriptions` watches the document's `mousemove`/`mouseup`
  while a drag is live. Both paths feed the same messages; on a mouse they
  double up harmlessly, since `DragMove` is idempotent. The handle needs
  `touch-action: none` or the browser claims the gesture for scrolling and no
  `pointermove` ever arrives.

## URL state

`Browser.application` syncs the whole neck list and the tuning to query params.
`Nav.replaceUrl` (not push) on each change, from a single `sync` helper, so the
address bar is always a link to exactly what is on screen.

- **One neck** writes the URL it always wrote — `?root=A&scale=dorian`,
  `?root=C&scale=triad-major&strings=2-3-4` — so every link ever shared of a
  single fretboard still reads the way it did.
- **Several** write `?necks=A.minor-pent,C.ionian,E.triad-major.2-3-4`: one
  neck per comma, `root.scale` with the string set appended in the triad modes
  that have one. `&active=N` rides along when the active neck is not the first.
- `&tuning=` is appended in both forms, omitted for Standard. Sharp notes use
  `Cs`, `Ds`, etc. to avoid URL-encoding `#`.
- `&focus=4-8` carries the highlight window, omitted when it is off. It is
  clamped on the way in, so a hand-edited or stale window cannot land off the
  neck or inside out.
- `&string=6` carries the highlighted string, omitted when it is off, and
  clamped to 1–6 on the way in for the same reason.
- `&mono=1` and `&cols=2` carry the Monochrome and Two columns switches,
  omitted when off.
- The old `?roots=C-E-G` multi-root param is still **parsed** (a list of roots
  all sharing the one `scale`) so links from that version keep working. It is
  never written any more; the next change rewrites the URL in the new form.

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
