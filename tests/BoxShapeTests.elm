module BoxShapeTests exposing
    ( canonicalShapes
    , completeness
    , coverage
    , diagonalCells
    , edgeSanity
    , overlapCoverage
    , spelling
    , stripeEdges
    )

{-| The CAGED box geometry is produced by one derivation, `Main.deriveBox`, from
a tuning's open strings and the scale intervals. These tests pin down that:

1.  the canonical pentatonic and Ionian/Aeolian shapes fall out of the algorithm
    in standard tuning (the algorithm must reproduce the known-good shapes);
2.  every box is well-formed (all six strings, lo ≤ hi) in every preset tuning;
3.  the boxes tile — every scale note on the neck sits inside some box, so every
    rendered note marker has a box behind it;
4.  overlap stripes cover every multi-box region and end on scale notes.

-}

import Dict
import Expect
import Main exposing (ScaleType(..), Tuning, deriveBox, diagonalAnchor, diagonalShapesFor, noteAt, openString, rootSpelling, scaleIntervals, spell, standardTuning, tunings)
import Test exposing (Test, describe, test)



-- SHARED HELPERS


{-| Arbitrary test root; the box geometry is root-independent, so any works. -}
testRoot : Int
testRoot =
    9


octaves : List Int
octaves =
    [ -1, 0, 1 ]


fretboardFrets : List Int
fretboardFrets =
    List.range 0 22


{-| Scales whose boxes go through `deriveBox` (everything except the diagonal
climbing shapes). -}
boxScales : List ScaleType
boxScales =
    [ MinorPent, MajorPent, Ionian, Dorian, Aeolian, Mixolydian, Phrygian, Lydian, Locrian, Blues, HarmonicMinor, MelodicMinor ]


{-| Preset tunings plus a few pathological ones (all strings the same pitch),
which stress the box derivation: the boxes must still contain every scale note. -}
coverageTunings : List Tuning
coverageTunings =
    tunings
        ++ [ { name = "All-B", slug = "B-B-B-B-B-B", strings = [ 11, 11, 11, 11, 11, 11 ] }
           , { name = "All-C", slug = "C-C-C-C-C-C", strings = [ 0, 0, 0, 0, 0, 0 ] }
           ]




scaleNotes : ScaleType -> Int -> List Int
scaleNotes scale root =
    List.map (\i -> modBy 12 (root + i)) (scaleIntervals scale)


{-| Mirror of Main.rootFret: the anchor's fret on the low-E string, which
follows that string's open pitch in any tuning. -}
fRootFor : Tuning -> ScaleType -> Int -> Int
fRootFor tuning scale root =
    let
        lowE =
            openString tuning 6

        minorAnchor =
            modBy 12 (root - lowE)

        majorAnchor =
            modBy 12 (root - 3 - lowE)
    in
    case scale of
        MajorPent ->
            majorAnchor

        Ionian ->
            majorAnchor

        Dorian ->
            majorAnchor

        Mixolydian ->
            majorAnchor

        Phrygian ->
            majorAnchor

        Lydian ->
            majorAnchor

        Locrian ->
            majorAnchor

        DiagonalPent ->
            modBy 12 (root + 3 - lowE)

        DiagonalBlues ->
            modBy 12 (root + 3 - lowE)

        DiagonalMajorPent ->
            minorAnchor

        _ ->
            minorAnchor


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
        HarmonicMinor -> "HarmonicMinor"
        MelodicMinor -> "MelodicMinor"
        DiagonalPent -> "DiagonalPent"
        DiagonalMajorPent -> "DiagonalMajorPent"
        DiagonalBlues -> "DiagonalBlues"



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


{-| The textbook Ionian (major-scale) CAGED boxes (relative to the anchor). -}
ionianReference : List (List ( Int, Int, Int ))
ionianReference =
    [ [ ( 1, 0, 3 ), ( 2, 0, 3 ), ( 3, 0, 4 ), ( 4, 0, 4 ), ( 5, 0, 3 ), ( 6, 0, 3 ) ]
    , [ ( 1, 3, 7 ), ( 2, 3, 7 ), ( 3, 4, 7 ), ( 4, 4, 7 ), ( 5, 3, 7 ), ( 6, 3, 7 ) ]
    , [ ( 1, 5, 8 ), ( 2, 5, 8 ), ( 3, 5, 9 ), ( 4, 5, 9 ), ( 5, 5, 9 ), ( 6, 5, 8 ) ]
    , [ ( 1, 7, 10 ), ( 2, 7, 10 ), ( 3, 7, 11 ), ( 4, 7, 10 ), ( 5, 7, 10 ), ( 6, 7, 10 ) ]
    , [ ( 1, 10, 14 ), ( 2, 10, 13 ), ( 3, 11, 14 ), ( 4, 10, 14 ), ( 5, 10, 14 ), ( 6, 10, 14 ) ]
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
    describe "Every box covers all six strings with lo <= hi, in every tuning"
        (tunings
            |> List.map
                (\tuning ->
                    describe tuning.name
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
                                                                List.map (\( s, _, _ ) -> s) shape == [ 1, 2, 3, 4, 5, 6 ]

                                                            okSpan =
                                                                List.all (\( _, lo, hi ) -> lo <= hi && hi - lo <= 4) shape
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
    test (tuning.name ++ " " ++ scaleName scale) <|
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
                        (List.range 1 6)
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
    test (tuning.name ++ " " ++ scaleName scale) <|
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
    test (tuning.name ++ " " ++ scaleName scale) <|
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
                        (List.range 1 6)
            in
            if List.isEmpty violations then
                Expect.pass

            else
                Expect.fail
                    ("Multi-box positions with no overlap stripe:\n  " ++ String.join "\n  " violations)


overlapCoverage : Test
overlapCoverage =
    describe "Where 2+ boxes overlap, an overlap stripe covers the same position"
        (tunings
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
                                    tuning.name ++ " " ++ scaleName scale ++ " stripe " ++ String.fromInt b1 ++ "-" ++ String.fromInt b2 ++ " S" ++ String.fromInt s
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
                (List.range 1 6)
                |> List.concat
    in
    List.concatMap adjacent [ ( 1, 2 ), ( 2, 3 ), ( 3, 4 ), ( 4, 5 ) ]


stripeEdges : Test
stripeEdges =
    describe "Stripe overlap edges land on scale notes"
        (tunings
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


diagonalRootCells : ScaleType -> ( List Int, List Int ) -> Int -> List Test
diagonalRootCells scale ( lowerDegrees, upperDegrees ) root =
    let
        a =
            diagonalAnchor standardTuning scale root

        noteOf s rel =
            noteAt standardTuning s (a + rel)

        expected degrees =
            List.map (\i -> modBy 12 (root + i)) degrees

        expect label degrees actual =
            test label <|
                \_ -> Expect.equal (expected degrees) actual
    in
    diagonalShapesFor scale
        |> List.concatMap
            (\shape ->
                let
                    tag =
                        scaleName scale
                            ++ " root "
                            ++ String.fromInt root
                            ++ " pattern "
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
                [ expect (tag ++ " lower")
                    lowDeg
                    (List.map (noteOf shape.lower) (List.sort shape.lowerRels))
                , expect (tag ++ " upper")
                    upDeg
                    (List.map (noteOf shape.upper) (List.sort shape.upperRels))
                ]
            )


diagonalCells : Test
diagonalCells =
    describe "Diagonal pentatonic shapes carry the right scale degrees on each string"
        (List.concatMap (diagonalRootCells DiagonalPent ( [ 3, 5, 7 ], [ 10, 0 ] )) (List.range 0 11)
            ++ List.concatMap (diagonalRootCells DiagonalMajorPent ( [ 0, 2, 4 ], [ 7, 9 ] )) (List.range 0 11)
            ++ List.concatMap (diagonalRootCells DiagonalBlues ( [ 3, 5, 6, 7 ], [ 10, 0 ] )) (List.range 0 11)
        )
