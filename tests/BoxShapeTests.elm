module BoxShapeTests exposing
    ( canonicalShapes
    , completeness
    , coverage
    , diagonalCells
    , edgeSanity
    , overlapCoverage
    , spelling
    , stringCounts
    , stripeEdges
    , triadShapes
    )

{-| The CAGED box geometry is produced by one derivation, `Main.deriveBox`, from
a tuning's open strings and the scale intervals. These tests pin down that:

1.  the canonical pentatonic and Ionian/Aeolian shapes fall out of the algorithm
    in standard tuning (the algorithm must reproduce the known-good shapes);
2.  every box is well-formed (every string, lo ≤ hi) in every preset tuning, at
    any number of strings;
3.  the boxes tile — every scale note on the neck sits inside some box, so every
    rendered note marker has a box behind it;
4.  overlap stripes cover every multi-box region and end on scale notes.

-}

import Dict
import Expect
import Main exposing (ScaleType(..), StringSet(..), Tuning, anchorOpen, deriveBox, diagonalAnchor, diagonalShapesFor, fourthsFor, midiAt, nextLowString, noteAt, openAbs, openString, resizeTuning, rootSpelling, scaleIntervals, spell, standardFor, standardTuning, stringCount, thirdsFor, triadVoicingsFor, tuningFromSlug, tunings, tuningsFor)
import Test exposing (Test, describe, test)



-- SHARED HELPERS


{-| Arbitrary test root; the box geometry is root-independent, so any works. -}
testRoot : Int
testRoot =
    9


octaves : List Int
octaves =
    [ -2, -1, 0, 1, 2 ]


fretboardFrets : List Int
fretboardFrets =
    List.range 0 22


{-| Scales whose boxes go through `deriveBox` (everything except the diagonal
climbing shapes). -}
boxScales : List ScaleType
boxScales =
    [ MajorPent, MinorPent, Ionian, Aeolian, Dorian, Mixolydian, Phrygian, Lydian, Locrian, Blues, HarmonicMajor, HarmonicMinor, MelodicMajor, MelodicMinor, BebopDominant, BebopMajor, BebopMinor ]
        -- Scales edited on the neck: one note added, one taken away, and a
        -- sparse one built up from a blank neck, whose third flips it major.
        ++ [ Custom MinorPent [ 0, 2, 3, 5, 7, 10 ]
           , Custom Ionian [ 0, 2, 4, 5, 7, 9 ]
           , Custom Blank [ 0, 4, 9 ]
           , Custom DiagonalMajor [ 0, 2, 4, 5, 7, 9 ]
           ]


{-| The string counts the geometry is exercised at: from one string to a dozen,
past the seven and eight a guitar has, with the odd and even ones either side
of each pair-of-strings boundary the diagonal shapes care about. -}
stringCountsUnderTest : List Int
stringCountsUnderTest =
    [ 1, 2, 3, 4, 5, 7, 8, 9, 12 ]


{-| Every preset on offer: the six-string ones, and what each other count
offers (standard, the named seven- and eight-string tunings, all fourths and
all major thirds). -}
presetTunings : List Tuning
presetTunings =
    tunings ++ List.concatMap tuningsFor stringCountsUnderTest


{-| Preset tunings plus a few pathological ones (all strings the same pitch),
which stress the box derivation: the boxes must still contain every scale note. -}
coverageTunings : List Tuning
coverageTunings =
    presetTunings
        ++ [ { name = "All-B", slug = "B-B-B-B-B-B", strings = [ 11, 11, 11, 11, 11, 11 ] }
           , { name = "All-C", slug = "C-C-C-C-C-C", strings = [ 0, 0, 0, 0, 0, 0 ] }
           , { name = "All-E (1)", slug = "E", strings = [ 4 ] }
           , { name = "All-E (8)", slug = "E-E-E-E-E-E-E-E", strings = [ 4, 4, 4, 4, 4, 4, 4, 4 ] }
           ]




{-| A tuning's name and how many strings it has: "Standard" alone is ambiguous
once there are tunings of every length. -}
tuningLabel : Tuning -> String
tuningLabel tuning =
    tuning.name ++ " (" ++ String.fromInt (stringCount tuning) ++ ")"


scaleNotes : ScaleType -> Int -> List Int
scaleNotes scale root =
    List.map (\i -> modBy 12 (root + i)) (scaleIntervals scale)


{-| Mirror of Main.rootFret: the anchor's fret on the low-E string, which
follows that string's open pitch in any tuning. -}
fRootFor : Tuning -> ScaleType -> Int -> Int
fRootFor tuning scale root =
    let
        lowE =
            anchorOpen tuning
    in
    case scale of
        DiagonalPent ->
            modBy 12 (root + 3 - lowE)

        DiagonalBlues ->
            modBy 12 (root + 3 - lowE)

        DiagonalMajorPent ->
            modBy 12 (root - lowE)

        DiagonalMajor ->
            modBy 12 (root - 3 - lowE)

        DiagonalMinor ->
            modBy 12 (root - lowE)

        _ ->
            modBy 12 (root - offsetFor scale - lowE)


{-| Semitones from box 1's anchor up to the root: the modes anchor on their
parent major scale's relative minor. -}
offsetFor : ScaleType -> Int
offsetFor scale =
    case scale of
        MajorPent -> 3
        Ionian -> 3
        Dorian -> 5
        Phrygian -> 7
        Lydian -> 8
        Mixolydian -> 10
        Locrian -> 2
        HarmonicMajor -> 3
        MelodicMajor -> 3
        BebopDominant -> 10
        BebopMajor -> 3
        BebopMinor -> 5
        DiagonalMajor -> 3
        Custom base intervals ->
            -- An edited scale keeps its preset's anchor while it keeps the
            -- preset's third, and anchors as plain minor or major once the
            -- third has changed.
            let
                third ivs =
                    case ( List.member 3 ivs, List.member 4 ivs ) of
                        ( True, False ) -> Just 3
                        ( False, True ) -> Just 4
                        _ -> Nothing
            in
            case third intervals of
                Nothing ->
                    offsetFor base

                Just t ->
                    if third (scaleIntervals base) == Just t then
                        offsetFor base

                    else if t == 3 then
                        0

                    else
                        3
        _ -> 0


rangeOnString : List ( Int, Int, Int ) -> Int -> Maybe ( Int, Int )
rangeOnString shape s =
    shape
        |> List.filter (\( s2, _, _ ) -> s2 == s)
        |> List.head
        |> Maybe.map (\( _, lo, hi ) -> ( lo, hi ))


scaleName : ScaleType -> String
scaleName scale =
    case scale of
        Ionian -> "Ionian"
        Dorian -> "Dorian"
        Aeolian -> "Aeolian"
        MinorPent -> "MinorPent"
        MajorPent -> "MajorPent"
        Mixolydian -> "Mixolydian"
        Phrygian -> "Phrygian"
        Lydian -> "Lydian"
        Locrian -> "Locrian"
        Blues -> "Blues"
        HarmonicMajor -> "HarmonicMajor"
        HarmonicMinor -> "HarmonicMinor"
        MelodicMajor -> "MelodicMajor"
        MelodicMinor -> "MelodicMinor"
        BebopDominant -> "BebopDominant"
        BebopMajor -> "BebopMajor"
        BebopMinor -> "BebopMinor"
        ChromaticMinor -> "ChromaticMinor"
        Blank -> "Blank"
        ChromaticMajor -> "ChromaticMajor"
        TriadMajor -> "TriadMajor"
        TriadMinor -> "TriadMinor"
        TriadDim -> "TriadDim"
        TriadAug -> "TriadAug"
        DiagonalPent -> "DiagonalPent"
        DiagonalMajorPent -> "DiagonalMajorPent"
        DiagonalBlues -> "DiagonalBlues"
        DiagonalMajor -> "DiagonalMajor"
        DiagonalMinor -> "DiagonalMinor"
        Custom base intervals -> scaleName base ++ "+" ++ String.join "," (List.map String.fromInt intervals)



-- 1. CANONICAL SHAPES FALL OUT OF THE ALGORITHM


{-| The textbook minor-pentatonic CAGED boxes (relative to the anchor). -}
pentReference : List (List ( Int, Int, Int ))
pentReference =
    [ [ ( 1, 0, 3 ), ( 2, 0, 3 ), ( 3, 0, 2 ), ( 4, 0, 2 ), ( 5, 0, 2 ), ( 6, 0, 3 ) ]
    , [ ( 1, 3, 5 ), ( 2, 3, 5 ), ( 3, 2, 4 ), ( 4, 2, 5 ), ( 5, 2, 5 ), ( 6, 3, 5 ) ]
    , [ ( 1, 5, 7 ), ( 2, 5, 8 ), ( 3, 4, 7 ), ( 4, 5, 7 ), ( 5, 5, 7 ), ( 6, 5, 7 ) ]
    , [ ( 1, 7, 10 ), ( 2, 8, 10 ), ( 3, 7, 9 ), ( 4, 7, 9 ), ( 5, 7, 10 ), ( 6, 7, 10 ) ]
    , [ ( 1, 10, 12 ), ( 2, 10, 12 ), ( 3, 9, 12 ), ( 4, 9, 12 ), ( 5, 10, 12 ), ( 6, 10, 12 ) ]
    ]


{-| The textbook Ionian (major-scale) CAGED boxes (relative to the anchor).

These are the five standard major-scale positions: each one sits on the *same*
five-fret window as the pentatonic box of the same number (see `pentReference`),
with the two extra degrees filling in. Transcribed from a published A-major
position chart, so this is the spec `deriveBox` has to reproduce. -}
ionianReference : List (List ( Int, Int, Int ))
ionianReference =
    [ [ ( 1, 0, 3 ), ( 2, 0, 3 ), ( 3, -1, 2 ), ( 4, 0, 2 ), ( 5, 0, 3 ), ( 6, 0, 3 ) ]
    , [ ( 1, 2, 5 ), ( 2, 3, 5 ), ( 3, 2, 5 ), ( 4, 2, 5 ), ( 5, 2, 5 ), ( 6, 2, 5 ) ]
    , [ ( 1, 5, 8 ), ( 2, 5, 8 ), ( 3, 4, 7 ), ( 4, 4, 7 ), ( 5, 5, 7 ), ( 6, 5, 8 ) ]
    , [ ( 1, 7, 10 ), ( 2, 7, 10 ), ( 3, 7, 9 ), ( 4, 7, 10 ), ( 5, 7, 10 ), ( 6, 7, 10 ) ]
    , [ ( 1, 10, 12 ), ( 2, 10, 13 ), ( 3, 9, 12 ), ( 4, 9, 12 ), ( 5, 9, 12 ), ( 6, 10, 12 ) ]
    ]


reproduces : String -> ScaleType -> List (List ( Int, Int, Int )) -> Test
reproduces name scale reference =
    describe name
        (List.map2
            (\b expected ->
                test (name ++ " box " ++ String.fromInt b) <|
                    \_ -> Expect.equal expected (deriveBox standardTuning scale b)
            )
            [ 1, 2, 3, 4, 5 ]
            reference
        )


canonicalShapes : Test
canonicalShapes =
    describe "Standard-tuning shapes fall out of deriveBox"
        [ reproduces "Minor pentatonic = canonical CAGED" MinorPent pentReference
        , reproduces "Major pentatonic = same shapes (relative minor)" MajorPent pentReference
        , reproduces "Ionian = canonical major-scale CAGED" Ionian ionianReference
        , reproduces "Aeolian = same shapes as Ionian (relative minor)" Aeolian ionianReference
        ]



-- 2. EVERY BOX IS WELL-FORMED IN EVERY TUNING


edgeSanity : Test
edgeSanity =
    describe "Every box covers every string with lo <= hi, in every tuning"
        (presetTunings
            |> List.map
                (\tuning ->
                    describe (tuningLabel tuning)
                        (boxScales
                            |> List.concatMap
                                (\scale ->
                                    [ 1, 2, 3, 4, 5 ]
                                        |> List.map
                                            (\b ->
                                                test (scaleName scale ++ " box " ++ String.fromInt b) <|
                                                    \_ ->
                                                        let
                                                            shape =
                                                                deriveBox tuning scale b

                                                            okStrings =
                                                                List.map (\( s, _, _ ) -> s) shape == List.range 1 (stringCount tuning)

                                                            -- A compact five-fret position is the goal, but a
                                                            -- box must hold the whole scale, and one or two
                                                            -- strings cannot do that in five frets: there the
                                                            -- window grows (`deriveBox`).
                                                            okSpan =
                                                                List.all
                                                                    (\( _, lo, hi ) ->
                                                                        lo <= hi && (stringCount tuning < 3 || hi - lo <= 4)
                                                                    )
                                                                    shape
                                                        in
                                                        if okStrings && okSpan then
                                                            Expect.pass

                                                        else
                                                            Expect.fail ("Malformed box: " ++ Debug.toString shape)
                                            )
                                )
                        )
                )
        )



-- 3. THE BOXES TILE: every scale note on the neck sits inside some box


coveredBy : Tuning -> ScaleType -> Int -> Int -> Bool
coveredBy tuning scale s f =
    let
        anchor =
            fRootFor tuning scale testRoot
    in
    [ 1, 2, 3, 4, 5 ]
        |> List.any
            (\b ->
                case rangeOnString (deriveBox tuning scale b) s of
                    Just ( lo, hi ) ->
                        octaves
                            |> List.any
                                (\o ->
                                    let
                                        sh =
                                            anchor + 12 * o
                                    in
                                    lo + sh <= f && f <= hi + sh
                                )

                    Nothing ->
                        False
            )


coverageFor : Tuning -> ScaleType -> Test
coverageFor tuning scale =
    test (tuningLabel tuning ++ " " ++ scaleName scale) <|
        \_ ->
            let
                notes =
                    scaleNotes scale testRoot

                violations =
                    List.concatMap
                        (\s ->
                            List.filterMap
                                (\f ->
                                    if List.member (noteAt tuning s f) notes && not (coveredBy tuning scale s f) then
                                        Just ("S" ++ String.fromInt s ++ " fret " ++ String.fromInt f)

                                    else
                                        Nothing
                                )
                                fretboardFrets
                        )
                        (List.range 1 (stringCount tuning))
            in
            if List.isEmpty violations then
                Expect.pass

            else
                Expect.fail
                    ("Scale notes with no box behind them:\n  " ++ String.join "\n  " violations)


coverage : Test
coverage =
    describe "Every scale note on the neck sits inside a box (boxes tile)"
        (coverageTunings
            |> List.concatMap (\tuning -> List.map (coverageFor tuning) boxScales)
        )



-- 3b. THE HARD REQUIREMENT: every box contains the COMPLETE scale (all degrees),
-- so each box is a self-contained position you can play the whole scale in.


boxDegrees : Tuning -> ScaleType -> Int -> List Int
boxDegrees tuning scale b =
    let
        anchor =
            fRootFor tuning scale testRoot

        notes =
            scaleNotes scale testRoot
    in
    deriveBox tuning scale b
        |> List.concatMap
            (\( s, lo, hi ) ->
                List.range (lo + anchor) (hi + anchor)
                    |> List.map (noteAt tuning s)
                    |> List.filter (\n -> List.member n notes)
            )


completenessFor : Tuning -> ScaleType -> Test
completenessFor tuning scale =
    test (tuningLabel tuning ++ " " ++ scaleName scale) <|
        \_ ->
            let
                notes =
                    scaleNotes scale testRoot

                missing b =
                    let
                        present =
                            boxDegrees tuning scale b
                    in
                    notes
                        |> List.filter (\n -> not (List.member n present))
                        |> List.map (\n -> "box " ++ String.fromInt b ++ " missing pitch " ++ String.fromInt n)

                violations =
                    List.concatMap missing [ 1, 2, 3, 4, 5 ]
            in
            if List.isEmpty violations then
                Expect.pass

            else
                Expect.fail
                    ("Boxes that do not contain the whole scale:\n  " ++ String.join "\n  " violations)


completeness : Test
completeness =
    describe "Every box contains the complete scale (all degrees), in every tuning"
        (coverageTunings
            |> List.concatMap (\tuning -> List.map (completenessFor tuning) boxScales)
        )



-- 4. OVERLAP STRIPES (7-note modes): cover every multi-box region, end on notes


solidCount : Tuning -> ScaleType -> Int -> Int -> Int
solidCount tuning scale s f =
    let
        anchor =
            fRootFor tuning scale testRoot
    in
    [ 1, 2, 3, 4, 5 ]
        |> List.concatMap
            (\b ->
                case rangeOnString (deriveBox tuning scale b) s of
                    Just ( lo, hi ) ->
                        List.filter (\o -> lo + anchor + 12 * o <= f && f <= hi + anchor + 12 * o) octaves

                    Nothing ->
                        []
            )
        |> List.length


stripeCount : Tuning -> ScaleType -> Int -> Int -> Int
stripeCount tuning scale s f =
    let
        anchor =
            fRootFor tuning scale testRoot

        adjCovers ( b1, b2 ) o =
            case ( rangeOnString (deriveBox tuning scale b1) s, rangeOnString (deriveBox tuning scale b2) s ) of
                ( Just ( lo1, hi1 ), Just ( lo2, hi2 ) ) ->
                    let
                        sh =
                            anchor + 12 * o

                        ovlpLo =
                            max lo1 lo2 + sh

                        ovlpHi =
                            min hi1 hi2 + sh
                    in
                    ovlpHi >= ovlpLo && ovlpLo <= f && f <= ovlpHi

                _ ->
                    False

        wrapCovers o =
            case ( rangeOnString (deriveBox tuning scale 5) s, rangeOnString (deriveBox tuning scale 1) s ) of
                ( Just ( lo5, hi5 ), Just ( lo1, hi1 ) ) ->
                    let
                        ovlpLo =
                            max (lo5 + anchor + 12 * o) (lo1 + anchor + 12 * (o + 1))

                        ovlpHi =
                            min (hi5 + anchor + 12 * o) (hi1 + anchor + 12 * (o + 1))
                    in
                    ovlpHi >= ovlpLo && ovlpLo <= f && f <= ovlpHi

                _ ->
                    False

        adj =
            [ ( 1, 2 ), ( 2, 3 ), ( 3, 4 ), ( 4, 5 ) ]
                |> List.concatMap (\pair -> List.filter (adjCovers pair) octaves)
                |> List.length

        wrap =
            List.filter wrapCovers octaves |> List.length
    in
    adj + wrap


overlapCoverageFor : Tuning -> ScaleType -> Test
overlapCoverageFor tuning scale =
    test (tuningLabel tuning ++ " " ++ scaleName scale) <|
        \_ ->
            let
                violations =
                    List.concatMap
                        (\s ->
                            List.filterMap
                                (\f ->
                                    if solidCount tuning scale s f > 1 && stripeCount tuning scale s f == 0 then
                                        Just ("S" ++ String.fromInt s ++ " fret " ++ String.fromInt f)

                                    else
                                        Nothing
                                )
                                fretboardFrets
                        )
                        (List.range 1 (stringCount tuning))
            in
            if List.isEmpty violations then
                Expect.pass

            else
                Expect.fail
                    ("Multi-box positions with no overlap stripe:\n  " ++ String.join "\n  " violations)


overlapCoverage : Test
overlapCoverage =
    describe "Where 2+ boxes overlap, an overlap stripe covers the same position"
        (presetTunings
            |> List.concatMap (\tuning -> List.map (overlapCoverageFor tuning) boxScales)
        )


stripeEdgeOnNote : Tuning -> ScaleType -> String -> Int -> Int -> Test
stripeEdgeOnNote tuning scale label s relFret =
    test label <|
        \_ ->
            let
                anchor =
                    fRootFor tuning scale testRoot

                note =
                    noteAt tuning s (anchor + relFret)
            in
            if List.member note (scaleNotes scale testRoot) then
                Expect.pass

            else
                Expect.fail (label ++ " edge is not a scale note")


stripeEdgesFor : Tuning -> ScaleType -> List Test
stripeEdgesFor tuning scale =
    let
        adjacent ( b1, b2 ) =
            List.filterMap
                (\s ->
                    case ( rangeOnString (deriveBox tuning scale b1) s, rangeOnString (deriveBox tuning scale b2) s ) of
                        ( Just ( lo1, hi1 ), Just ( lo2, hi2 ) ) ->
                            let
                                lo =
                                    max lo1 lo2

                                hi =
                                    min hi1 hi2

                                tag =
                                    tuningLabel tuning ++ " " ++ scaleName scale ++ " stripe " ++ String.fromInt b1 ++ "-" ++ String.fromInt b2 ++ " S" ++ String.fromInt s
                            in
                            if hi >= lo then
                                Just
                                    [ stripeEdgeOnNote tuning scale (tag ++ " lo") s lo
                                    , stripeEdgeOnNote tuning scale (tag ++ " hi") s hi
                                    ]

                            else
                                Nothing

                        _ ->
                            Nothing
                )
                (List.range 1 (stringCount tuning))
                |> List.concat
    in
    List.concatMap adjacent [ ( 1, 2 ), ( 2, 3 ), ( 3, 4 ), ( 4, 5 ) ]


stripeEdges : Test
stripeEdges =
    describe "Stripe overlap edges land on scale notes"
        (presetTunings
            |> List.concatMap (\tuning -> List.concatMap (stripeEdgesFor tuning) boxScales)
        )



-- ENHARMONIC SPELLING (unchanged)


letters : List String -> List Char
letters =
    List.filterMap (String.uncons >> Maybe.map Tuple.first)


accidentalCount : List String -> Int
accidentalCount =
    List.map
        (\s ->
            String.toList s
                |> List.filter (\c -> c == '\u{266F}' || c == '\u{266D}' || c == 'x')
                |> List.length
        )
        >> List.sum


diatonicModes : List ScaleType
diatonicModes =
    [ Ionian, Dorian, Aeolian, Mixolydian, Phrygian, Lydian, Locrian, HarmonicMinor, MelodicMinor ]


spelling : Test
spelling =
    describe "enharmonic spelling"
        [ test "C major = C D E F G A B" <|
            \_ ->
                Expect.equal
                    [ "C", "D", "E", "F", "G", "A", "B" ]
                    (spell 0 Ionian)
        , test "F major uses B\u{266D}, not A\u{266F}" <|
            \_ ->
                Expect.equal
                    [ "F", "G", "A", "B\u{266D}", "C", "D", "E" ]
                    (spell 5 Ionian)
        , test "pitch class 8 major spells as A\u{266D} (4 flats), not G\u{266F} (no double-sharps)" <|
            \_ ->
                Expect.equal
                    [ "A\u{266D}", "B\u{266D}", "C", "D\u{266D}", "E\u{266D}", "F", "G" ]
                    (spell 8 Ionian)
        , test "pitch class 6 major breaks the tie toward F\u{266F} (sharps)" <|
            \_ ->
                Expect.equal "F\u{266F}" (rootSpelling Ionian 6)
        , test "the major-scale root picker matches the conventional key names" <|
            \_ ->
                Expect.equal
                    [ "C", "D\u{266D}", "D", "E\u{266D}", "E", "F", "F\u{266F}", "G", "A\u{266D}", "A", "B\u{266D}", "B" ]
                    (List.map (rootSpelling Ionian) (List.range 0 11))
        , describe "every 7-note diatonic mode uses each letter A\u{2013}G exactly once, from every root" <|
            List.map
                (\( root, scale ) ->
                    test (String.fromInt root ++ " " ++ Debug.toString scale) <|
                        \_ ->
                            Expect.equal
                                7
                                (letters (spell root scale)
                                    |> List.map (\c -> ( c, () ))
                                    |> Dict.fromList
                                    |> Dict.size
                                )
                )
                (List.concatMap
                    (\root -> List.map (\scale -> ( root, scale )) diatonicModes)
                    (List.range 0 11)
                )
        , describe "no diatonic-mode key needs more than 7 accidentals (proper enharmonic choice)" <|
            List.map
                (\( root, scale ) ->
                    test (String.fromInt root ++ " " ++ Debug.toString scale) <|
                        \_ ->
                            Expect.atMost 7 (accidentalCount (spell root scale))
                )
                (List.concatMap
                    (\root -> List.map (\scale -> ( root, scale )) diatonicModes)
                    (List.range 0 11)
                )
        ]



-- DIAGONAL PENTATONIC (unchanged): shapes carry the right degrees per string


diagonalRootCells : Int -> ScaleType -> ( List Int, List Int ) -> Int -> List Test
diagonalRootCells strings scale ( lowerDegrees, upperDegrees ) root =
    let
        tuning =
            standardFor strings

        a =
            diagonalAnchor tuning scale root

        noteOf s rel =
            noteAt tuning s (a + rel)

        expected degrees =
            List.map (\i -> modBy 12 (root + i)) degrees

        expect label degrees actual =
            test label <|
                \_ -> Expect.equal (expected degrees) actual
    in
    diagonalShapesFor strings scale
        |> List.concatMap
            (\shape ->
                let
                    tag =
                        scaleName scale
                            ++ " root "
                            ++ String.fromInt root
                            ++ " ("
                            ++ String.fromInt strings
                            ++ " strings) pattern "
                            ++ String.fromInt shape.color
                            ++ " strings "
                            ++ String.fromInt shape.lower
                            ++ "/"
                            ++ String.fromInt shape.upper

                    ( lowDeg, upDeg ) =
                        if shape.color == 2 then
                            ( upperDegrees, lowerDegrees )

                        else
                            ( lowerDegrees, upperDegrees )
                in
                -- A half pair at the bottom of an odd-stringed neck has no
                -- lower string, so there is nothing to say about it.
                (if List.isEmpty shape.lowerRels then
                    []

                 else
                    [ expect (tag ++ " lower")
                        lowDeg
                        (List.map (noteOf shape.lower) (List.sort shape.lowerRels))
                    ]
                )
                    ++ [ expect (tag ++ " upper")
                            upDeg
                            (List.map (noteOf shape.upper) (List.sort shape.upperRels))
                       ]
            )


{-| Whatever the string count, every string that exists carries the whole scale
across the two patterns, and no shape reaches for a string that does not. -}
diagonalStrings : Int -> ScaleType -> Test
diagonalStrings strings scale =
    test (scaleName scale ++ " on " ++ String.fromInt strings ++ " strings") <|
        \_ ->
            let
                tuning =
                    standardFor strings

                shapes =
                    diagonalShapesFor strings scale

                pitchClasses s =
                    shapes
                        |> List.concatMap
                            (\shape ->
                                (if shape.lower == s then
                                    shape.lowerRels

                                 else
                                    []
                                )
                                    ++ (if shape.upper == s then
                                            shape.upperRels

                                        else
                                            []
                                       )
                            )
                        |> List.map (\rel -> modBy 12 (noteAt tuning s (diagonalAnchor tuning scale testRoot + rel) - testRoot))
                        |> List.sort
                        |> dedupe

                reaching =
                    shapes
                        |> List.concatMap
                            (\shape ->
                                (if List.isEmpty shape.lowerRels then
                                    []

                                 else
                                    [ shape.lower ]
                                )
                                    ++ [ shape.upper ]
                            )
                        |> List.filter (\s -> s < 1 || s > strings)
            in
            Expect.equal
                ( [], List.repeat strings (List.sort (scaleIntervals scale)) )
                ( reaching, List.map pitchClasses (List.range 1 strings) )


dedupe : List Int -> List Int
dedupe xs =
    case xs of
        a :: b :: rest ->
            if a == b then
                dedupe (b :: rest)

            else
                a :: dedupe (b :: rest)

        _ ->
            xs


diagonalCells : Test
diagonalCells =
    describe "Diagonal shapes carry the right scale degrees on each string"
        (List.concatMap
            (\strings ->
                let
                    roots =
                        if strings == 6 then
                            List.range 0 11

                        else
                            [ 0, 4, 9 ]
                in
                List.concatMap (diagonalRootCells strings DiagonalPent ( [ 3, 5, 7 ], [ 10, 0 ] )) roots
                    ++ List.concatMap (diagonalRootCells strings DiagonalMajorPent ( [ 0, 2, 4 ], [ 7, 9 ] )) roots
                    ++ List.concatMap (diagonalRootCells strings DiagonalBlues ( [ 3, 5, 6, 7 ], [ 10, 0 ] )) roots
                    ++ List.concatMap (diagonalRootCells strings DiagonalMajor ( [ 9, 11, 0, 2 ], [ 4, 5, 7 ] )) roots
                    ++ List.concatMap (diagonalRootCells strings DiagonalMinor ( [ 0, 2, 3, 5 ], [ 7, 8, 10 ] )) roots
            )
            (6 :: stringCountsUnderTest)
            ++ List.concatMap
                (\strings ->
                    List.map (diagonalStrings strings) [ DiagonalPent, DiagonalMajorPent, DiagonalBlues, DiagonalMajor, DiagonalMinor ]
                )
                (6 :: stringCountsUnderTest)
        )



-- TRIADS: close-position voicings across three adjacent strings


{-| The defining property of a close-position voicing: the three notes ascend,
each less than an octave above the one below it. -}
closePosition : Tuning -> { a | notes : List ( Int, Int ) } -> Bool
closePosition tuning v =
    let
        pitches =
            v.notes
                |> List.reverse
                |> List.map (\( s, f ) -> openAbs tuning s + f)
    in
    List.map2 (\lo hi -> hi > lo && hi < lo + 12) pitches (List.drop 1 pitches)
        |> List.all identity


triadQualities : List ScaleType
triadQualities =
    [ TriadMajor, TriadMinor, TriadDim, TriadAug ]


{-| Every invariant a close-position voicing must satisfy, for one tuning and
quality: it sits on the three strings of its set, inside the neck, carries all
three chord tones (one each, never a doubled degree), and its `inversion` names
the degree actually in the bass. -}
triadInvariants : Tuning -> ScaleType -> Int -> Test
triadInvariants tuning scale top =
    let
        voicings =
            triadVoicingsFor tuning scale testRoot (StringTrio top)

        tag =
            scaleName scale ++ " / " ++ tuningLabel tuning ++ " / strings " ++ String.fromInt top

        degreesOf v =
            v.notes
                |> List.map (\( s, f ) -> modBy 12 (noteAt tuning s f - testRoot))
                |> List.sort

        bassDegree v =
            v.notes
                |> List.reverse
                |> List.head
                |> Maybe.map (\( s, f ) -> modBy 12 (noteAt tuning s f - testRoot))
                |> Maybe.withDefault -1

        expectedInversion v =
            List.head (List.filter (\( _, d ) -> d == bassDegree v) (List.indexedMap Tuple.pair (List.sort (scaleIntervals scale))))
                |> Maybe.map Tuple.first
                |> Maybe.withDefault -1
    in
    describe tag
        [ test "every set produces voicings" <|
            \_ ->
                -- Only for real tunings: strings an exact octave apart (the
                -- pathological ones) have no close-position triad at all,
                -- since the next degree up always lands past the octave.
                if List.member tuning presetTunings then
                    Expect.greaterThan 0 (List.length voicings)

                else
                    Expect.pass
        , test "each voicing sits on the set's three strings, inside the neck" <|
            \_ ->
                Expect.equalLists []
                    (List.filter
                        (\v ->
                            List.map Tuple.first v.notes
                                /= [ top, top + 1, top + 2 ]
                                || List.any (\( _, f ) -> f < 0 || f > 22) v.notes
                        )
                        voicings
                    )
        , test "each voicing carries all three chord tones, one each" <|
            \_ ->
                Expect.equalLists []
                    (List.filter (\v -> degreesOf v /= List.sort (scaleIntervals scale)) voicings)
        , test "each voicing is in close position: every note within an octave above the one below" <|
            \_ ->
                Expect.equalLists []
                    (List.filter (\v -> not (closePosition tuning v)) voicings)
        , test "the inversion names the degree in the bass" <|
            \_ ->
                Expect.equalLists []
                    (List.filter (\v -> v.inversion /= expectedInversion v) voicings)
        ]


{-| The C major triad on strings 2-3-4 in standard tuning: the textbook
shapes — first inversion at the nut (x x 2 0 1 x), second inversion at 5
(x x 5 5 5 x), root position at 8-10 (x x 10 9 8 x), then the octave repeat.
Pins the derivation to what a triad chart actually shows. -}
canonicalTriads : Test
canonicalTriads =
    let
        actual =
            triadVoicingsFor standardTuning TriadMajor 0 (StringTrio 2)
                |> List.map (\v -> ( v.inversion, List.map Tuple.second v.notes ))
    in
    test "C major triad on strings 2-3-4 (standard tuning) is the canonical shape set" <|
        \_ ->
            Expect.equalLists
                [ ( 1, [ 1, 0, 2 ] )
                , ( 2, [ 5, 5, 5 ] )
                , ( 0, [ 8, 9, 10 ] )
                , ( 1, [ 13, 12, 14 ] )
                , ( 2, [ 17, 17, 17 ] )
                , ( 0, [ 20, 21, 22 ] )
                ]
                actual


triadShapes : Test
triadShapes =
    describe "Triad voicings"
        (canonicalTriads
            :: List.concatMap
                (\tuning ->
                    List.concatMap
                        (\scale -> List.map (triadInvariants tuning scale) (List.range 1 (stringCount tuning - 2)))
                        triadQualities
                )
                coverageTunings
        )



-- STRING COUNTS: any number of strings, from one up


{-| The tuning a count change lands on, as its low-to-high note list (written
the way a player reads a tuning), so the expectations below read like the
tunings they describe. -}
lowToHigh : Tuning -> List Int
lowToHigh tuning =
    List.reverse tuning.strings


stringCounts : Test
stringCounts =
    let
        dropD =
            { name = "Drop D", slug = "drop-d", strings = [ 4, 11, 7, 2, 9, 2 ] }

        custom =
            resizeTuning 6 { name = "Custom", slug = "E-B-G-D-A-D", strings = [ 4, 11, 7, 2, 9, 2 ] }
    in
    describe "Any number of strings"
        [ describe "standard tuning carries on in fourths below the low E"
            [ test "six strings is the standard tuning it always was" <|
                \_ -> Expect.equal standardTuning (standardFor 6)
            , test "seven strings add a low B, eight a low F\u{266F}" <|
                \_ ->
                    Expect.equal
                        [ [ 11, 4, 9, 2, 7, 11, 4 ], [ 6, 11, 4, 9, 2, 7, 11, 4 ] ]
                        [ lowToHigh (standardFor 7), lowToHigh (standardFor 8) ]
            , test "fewer than six drop strings from the low end, so the top strings stay put" <|
                \_ ->
                    Expect.equal
                        [ [ 4 ], [ 11, 4 ], [ 7, 11, 4 ], [ 2, 7, 11, 4 ], [ 9, 2, 7, 11, 4 ] ]
                        (List.map (standardFor >> lowToHigh) [ 1, 2, 3, 4, 5 ])
            , test "the string count is the length of the tuning" <|
                \_ ->
                    Expect.equal (List.range 1 12) (List.map (standardFor >> stringCount) (List.range 1 12))
            ]
        , describe "adding and removing strings"
            [ test "standard grows a B and then an F\u{266F}, and is Standard at every count" <|
                \_ ->
                    Expect.equal
                        [ standardFor 7, standardFor 8 ]
                        [ resizeTuning 7 standardTuning, resizeTuning 8 (resizeTuning 7 standardTuning) ]
            , test "taking a string away from a longer standard lands back on standard, bare slug and all" <|
                \_ ->
                    Expect.equal standardTuning (resizeTuning 6 (standardFor 8))
            , test "all fourths and all major thirds keep going in fourths and in thirds" <|
                \_ ->
                    Expect.equal
                        [ fourthsFor 7, fourthsFor 9, thirdsFor 7, thirdsFor 10 ]
                        [ resizeTuning 7 (fourthsFor 6)
                        , resizeTuning 9 (fourthsFor 6)
                        , resizeTuning 7 (thirdsFor 6)
                        , resizeTuning 10 (thirdsFor 6)
                        ]
            , test "a fifth at the bottom (Drop D) grows a fourth, not a fifth, and is Custom" <|
                \_ ->
                    let
                        grown =
                            resizeTuning 7 dropD
                    in
                    Expect.equal ( [ 9, 2, 9, 2, 7, 11, 4 ], "Custom" ) ( lowToHigh grown, grown.name )
            , test "a Custom tuning stays Custom, even when it grows into a preset's notes" <|
                \_ ->
                    Expect.equal "Custom" (resizeTuning 7 (resizeTuning 6 custom)).name
            , test "the next string is a step further down" <|
                \_ ->
                    Expect.equal
                        [ 11, 11, 11, 7 ]
                        [ nextLowString [ 4, 11, 7, 2, 9, 4 ]
                        , nextLowString [ 4 ]
                        , nextLowString [ 11, 4 ]
                        , nextLowString [ 4, 8, 0 ]
                        ]
            , test "never fewer than one string, and the top string is what is left" <|
                \_ ->
                    Expect.equal
                        [ [ 4 ], [ 4 ], [ 4 ] ]
                        (List.map (\n -> lowToHigh (resizeTuning n standardTuning)) [ 1, 0, -5 ])
            ]
        , describe "a tuning's link says how many strings it has"
            [ test "every preset's slug finds that preset again" <|
                \_ ->
                    Expect.equalLists []
                        (List.filter (\t -> tuningFromSlug t.slug /= Just t) presetTunings)
            , test "a typed-in tuning of any length is Custom and round-trips" <|
                \_ ->
                    Expect.equal
                        (Just [ 4, 11, 7, 2, 9, 4, 11, 6 ])
                        (tuningFromSlug "E-B-G-D-A-E-B-Fs" |> Maybe.map .strings)
            , test "a custom tuning's own slug finds it again" <|
                \_ ->
                    Expect.equal (Just custom) (tuningFromSlug custom.slug)
            , test "nonsense is not a tuning" <|
                \_ ->
                    Expect.equal
                        [ Nothing, Nothing, Nothing, Nothing, Nothing ]
                        (List.map tuningFromSlug [ "", "nonsense", "E-x", "standard-0", "standard-99999" ])
            ]
        , describe "a longer neck keeps the six-string boxes on its top six strings"
            (List.concatMap
                (\strings ->
                    List.map
                        (\scale ->
                            test (scaleName scale ++ " on " ++ String.fromInt strings ++ " strings") <|
                                \_ ->
                                    Expect.equal
                                        (List.map (\b -> deriveBox standardTuning scale b) [ 1, 2, 3, 4, 5 ])
                                        (List.map
                                            (\b -> List.filter (\( s, _, _ ) -> s <= 6) (deriveBox (standardFor strings) scale b))
                                            [ 1, 2, 3, 4, 5 ]
                                        )
                        )
                        boxScales
                )
                [ 7, 8, 12 ]
            )
        , describe "strings five apart show the same notes in every box"
            (List.concatMap
                (\tuning ->
                    List.map
                        (\scale ->
                            test (tuningLabel tuning ++ " " ++ scaleName scale) <|
                                \_ ->
                                    let
                                        anchor =
                                            fRootFor tuning scale testRoot

                                        notesOn b s =
                                            case rangeOnString (deriveBox tuning scale b) s of
                                                Just ( lo, hi ) ->
                                                    List.range lo hi
                                                        |> List.map (\rel -> noteAt tuning s (anchor + rel))
                                                        |> List.filter (\n -> List.member n (scaleNotes scale testRoot))
                                                        |> List.sort

                                                Nothing ->
                                                    []

                                        mismatches =
                                            List.concatMap
                                                (\b ->
                                                    List.range 1 (stringCount tuning - 5)
                                                        |> List.filter (\s -> notesOn b s /= notesOn b (s + 5))
                                                        |> List.map (\s -> "box " ++ String.fromInt b ++ " strings " ++ String.fromInt s ++ " and " ++ String.fromInt (s + 5))
                                                )
                                                [ 1, 2, 3, 4, 5 ]
                                    in
                                    Expect.equalLists [] mismatches
                        )
                        boxScales
                )
                (List.filter (\t -> stringCount t >= 6) coverageTunings)
            )
        , describe "the anchor is the low E, or where it would be"
            [ test "standard tuning of any length anchors on E" <|
                \_ -> Expect.equal (List.repeat 12 4) (List.map (standardFor >> anchorOpen) (List.range 1 12))
            , test "with six strings or more it is the sixth string itself" <|
                \_ ->
                    Expect.equalLists []
                        (List.filter (\t -> stringCount t >= 6 && anchorOpen t /= openString t 6) presetTunings)
            ]
        , describe "every string sounds below the one above it"
            [ test "the open strings of every preset descend from the high string" <|
                \_ ->
                    Expect.equalLists []
                        (List.filter
                            (\t ->
                                let
                                    pitches =
                                        List.map (\s -> midiAt t s 0) (List.range 1 (stringCount t))
                                in
                                List.map2 (>) pitches (List.drop 1 pitches) |> List.all identity |> not
                            )
                            presetTunings)
            , test "standard tuning sounds E4 B3 G3 D3 A2 E2, then B1 and F\u{266F}1" <|
                \_ ->
                    Expect.equal
                        [ 64, 59, 55, 50, 45, 40, 35, 30 ]
                        (List.map (\s -> midiAt (standardFor 8) s 0) (List.range 1 8))
            ]
        ]
