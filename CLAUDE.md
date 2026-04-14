# caged — guitar fretboard visualizer

Interactive Elm app that renders the pentatonic scale across a 22-fret guitar
neck, with the five "boxes" colored to match `fretboard-reference.jpeg`.
Live site: https://boxed.github.io/caged/

## Stack

- **Elm 0.19.1** (single-module app in `src/Main.elm`, ~700 lines).
- No bundler, no npm. `index.html` loads the compiled `elm.js` directly.
- Hosted on **GitHub Pages** from `main` branch, root path.

## Build

```sh
elm make src/Main.elm --output=elm.js
```

`elm.js` **is committed** — Pages has no build step, so the compiled artifact
must be part of the repo. After any change to `src/Main.elm`, recompile and
commit both files together.

## File layout

- `src/Main.elm` — the whole app: model, music theory, SVG rendering.
- `index.html` — host page; loads `elm.js`.
- `elm.json` — Elm dependencies.
- `elm.js` — compiled output (committed).
- `fretboard-reference.jpeg` — the original reference image the visualization
  is modeled after.
- `README.md` — user-facing docs.

## Music theory model (the non-obvious bits)

- **String numbering**: S1 = high E (top of diagram), S6 = low E (bottom) —
  matches the reference image orientation.
- **Notes** are represented as `Int` pitch classes 0–11 (C=0). Scale
  intervals: minor pent `[0, 3, 5, 7, 10]`, major pent `[0, 2, 4, 7, 9]`.
- **rootFret** is the anchor fret on the low-E string:
  - Minor of R → `(R - 4) mod 12`
  - Major of R → `(R - 7) mod 12` (i.e. the *relative minor* R−3 anchors the
    shape; major pent reuses its relative minor's boxes, same notes, just a
    different root highlighted).
- **Box shapes** are hardcoded in `boxShape` as per-string `(lower, upper)`
  relative frets. The B-string shift (major-third tuning gap between G and B)
  is baked into these numbers — don't try to derive the shapes on the fly.
- **Box assignment** for a given scale note = the box where that note serves
  as the *lower* of the two notes on its string. This gives every note
  exactly one primary box / color (see `boxOf`). Adjacent boxes share an edge
  (upper of box N on a string = lower of box N+1 on that string).
- **Note roles** (`noteRole`): Root / Third / Fifth / Other. The 3rd is
  interval 3 for minor pent, 4 for major pent; the 5th is interval 7 in
  both. These are scale-wide roles, not per-box — the same pitch class
  always gets the same marker, regardless of which box it falls in.

## Rendering

All drawn in a single SVG (`viewFretboard`):
1. Box polygons (translucent, drawn first, one polygon per box per octave
   within the `[-1, 0, 1]` octave window — filtered by `inRange`).
2. Frets, nut, strings, dot markers.
3. Note circles/squares on top, styled by `NoteRole`.
4. Fret numbers below the neck (frets 3/5/7/9/12/15/17/19/21 highlighted).

Layout constants are at the top of the "LAYOUT" section — adjust
`fretWidth`, `stringSpacing`, `nutWidth`, etc. to rescale.

## Deployment

- Repo: https://github.com/boxed/caged
- Pages source: `main` branch, root path (legacy Pages build, no Actions).
- Every push to `main` triggers a Pages rebuild within ~1 minute.
