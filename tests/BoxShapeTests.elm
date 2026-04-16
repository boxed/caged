module BoxShapeTests exposing (overlapCoverage, stripeEdges, suite)

{-| Validates that every box-shape edge (the per-string `lo` and `hi`
relative-fret values returned by `majorBoxShape`) actually falls on a note
that's part of the scale. If a box's lo/hi extends to a fret with no scale
note on that string, the polygon would render with empty space at its edge.
-}

import Expect
import Main exposing (ScaleType(..), majorBoxShape, noteAt, scaleIntervals)
import Test exposing (Test, describe, test)


{-| All modes whose box rendering goes through `majorBoxShape`. -}
modesWithMajorShapes : List ScaleType
modesWithMajorShapes =
    [ Ionian, Dorian, Aeolian ]


{-| Pick A (=9) as the test root for every scale. Choice is arbitrary; the
edge-validity check is anchor-relative, so any root would work. -}
testRoot : Int
testRoot =
    9


fRootFor : ScaleType -> Int -> Int
fRootFor scale root =
    case scale of
        MinorPent ->
            modBy 12 (root - 4)

        MajorPent ->
            modBy 12 (root - 7)

        Ionian ->
            modBy 12 (root - 7)

        Dorian ->
            modBy 12 (root - 7)

        Aeolian ->
            modBy 12 (root - 4)


scaleNotes : ScaleType -> Int -> List Int
scaleNotes scale root =
    scaleIntervals scale
        |> List.map (\i -> modBy 12 (root + i))


scaleName : ScaleType -> String
scaleName scale =
    case scale of
        Ionian ->
            "Ionian"

        Dorian ->
            "Dorian"

        Aeolian ->
            "Aeolian"

        MinorPent ->
            "MinorPent"

        MajorPent ->
            "MajorPent"


{-| Test one (scale, box, string, edge label, fRel) combination. Pass if
the note at fRoot+fRel on the given string is in the scale. -}
edgeOnScaleNote : ScaleType -> Int -> Int -> Int -> String -> Int -> Test
edgeOnScaleNote scale root b s edgeLabel fRel =
    let
        absFret =
            fRootFor scale root + fRel

        note =
            noteAt s absFret

        notes =
            scaleNotes scale root

        label =
            scaleName scale
                ++ " box "
                ++ String.fromInt b
                ++ ", S"
                ++ String.fromInt s
                ++ " "
                ++ edgeLabel
                ++ "="
                ++ String.fromInt fRel
    in
    test label <|
        \_ ->
            if List.member note notes then
                Expect.pass

            else
                Expect.fail
                    ("Edge fRel "
                        ++ String.fromInt fRel
                        ++ " (abs fret "
                        ++ String.fromInt absFret
                        ++ ", pitch class "
                        ++ String.fromInt note
                        ++ ") is not in the scale "
                        ++ scaleName scale
                        ++ " (root "
                        ++ String.fromInt root
                        ++ "). Polygon would render with an empty edge."
                    )


testsForBox : ScaleType -> Int -> List Test
testsForBox scale b =
    majorBoxShape scale b
        |> List.concatMap
            (\( s, lo, hi ) ->
                [ edgeOnScaleNote scale testRoot b s "lo" lo
                , edgeOnScaleNote scale testRoot b s "hi" hi
                ]
            )


testsForScale : ScaleType -> Test
testsForScale scale =
    describe (scaleName scale)
        (List.concatMap (testsForBox scale) [ 1, 2, 3, 4, 5 ])


suite : Test
suite =
    describe "Box shape edges land on scale notes"
        (List.map testsForScale modesWithMajorShapes)



-- Coverage test: where 2+ solid boxes cover a position, an overlap
-- stripe must cover it too (with non-zero width on that string).


fretboardFrets : List Int
fretboardFrets =
    List.range 0 22


octaves : List Int
octaves =
    [ -1, 0, 1 ]


rangeOnString : List ( Int, Int, Int ) -> Int -> Maybe ( Int, Int )
rangeOnString shape s =
    shape
        |> List.filter (\( s2, _, _ ) -> s2 == s)
        |> List.head
        |> Maybe.map (\( _, lo, hi ) -> ( lo, hi ))


solidBoxCount : ScaleType -> Int -> Int -> Int -> Int
solidBoxCount scale root s f =
    let
        fRoot =
            fRootFor scale root
    in
    [ 1, 2, 3, 4, 5 ]
        |> List.concatMap
            (\b ->
                case rangeOnString (majorBoxShape scale b) s of
                    Just ( lo, hi ) ->
                        octaves
                            |> List.filter
                                (\o ->
                                    let
                                        shift =
                                            fRoot + 12 * o
                                    in
                                    lo + shift <= f && f <= hi + shift
                                )

                    Nothing ->
                        []
            )
        |> List.length


overlapStripeCount : ScaleType -> Int -> Int -> Int -> Int
overlapStripeCount scale root s f =
    let
        fRoot =
            fRootFor scale root

        adjacent =
            [ ( 1, 2 ), ( 2, 3 ), ( 3, 4 ), ( 4, 5 ) ]

        adjCovers ( b1, b2 ) o =
            case ( rangeOnString (majorBoxShape scale b1) s, rangeOnString (majorBoxShape scale b2) s ) of
                ( Just ( lo1, hi1 ), Just ( lo2, hi2 ) ) ->
                    let
                        shift =
                            fRoot + 12 * o

                        ovlpLo =
                            max lo1 lo2 + shift

                        ovlpHi =
                            min hi1 hi2 + shift
                    in
                    ovlpHi >= ovlpLo && ovlpLo <= f && f <= ovlpHi

                _ ->
                    False

        wrapCovers o =
            case ( rangeOnString (majorBoxShape scale 5) s, rangeOnString (majorBoxShape scale 1) s ) of
                ( Just ( lo5, hi5 ), Just ( lo1, hi1 ) ) ->
                    let
                        shift5 =
                            fRoot + 12 * o

                        shift1 =
                            fRoot + 12 * (o + 1)

                        ovlpLo =
                            max (lo5 + shift5) (lo1 + shift1)

                        ovlpHi =
                            min (hi5 + shift5) (hi1 + shift1)
                    in
                    ovlpHi >= ovlpLo && ovlpLo <= f && f <= ovlpHi

                _ ->
                    False

        adjCount =
            adjacent
                |> List.concatMap (\pair -> List.filter (adjCovers pair) octaves)
                |> List.length

        wrapCount =
            octaves
                |> List.filter wrapCovers
                |> List.length
    in
    adjCount + wrapCount


coverageForScale : ScaleType -> Test
coverageForScale scale =
    test ("Solid overlaps covered by stripe in " ++ scaleName scale) <|
        \_ ->
            let
                violations =
                    List.concatMap
                        (\s ->
                            List.filterMap
                                (\f ->
                                    let
                                        solids =
                                            solidBoxCount scale testRoot s f

                                        stripes =
                                            overlapStripeCount scale testRoot s f
                                    in
                                    if solids > 1 && stripes == 0 then
                                        Just
                                            ("S"
                                                ++ String.fromInt s
                                                ++ " fret "
                                                ++ String.fromInt f
                                                ++ " covered by "
                                                ++ String.fromInt solids
                                                ++ " solid boxes, no overlap stripe"
                                            )

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
                    ("Found "
                        ++ String.fromInt (List.length violations)
                        ++ " positions where solid boxes overlap without a stripe:\n  "
                        ++ String.join "\n  " violations
                    )


overlapCoverage : Test
overlapCoverage =
    describe "Where 2+ solid boxes overlap, an overlap stripe must cover the same position"
        (List.map coverageForScale modesWithMajorShapes)



-- Stripe-edge test: every per-string lo/hi value of every stripe overlap
-- polygon must be a scale note on its string. polygonPoints widens edges
-- by half a fret in either direction, so this check ensures the rendered
-- polygon ends "between two bands, underneath a note".


stripeEdgeTest : ScaleType -> String -> Int -> Int -> ( () -> Expect.Expectation )
stripeEdgeTest scale label s fRel =
    \_ ->
        let
            absFret =
                fRootFor scale testRoot + fRel

            note =
                noteAt s absFret

            notes =
                scaleNotes scale testRoot
        in
        if List.member note notes then
            Expect.pass

        else
            Expect.fail
                (label
                    ++ " edge fRel "
                    ++ String.fromInt fRel
                    ++ " (abs "
                    ++ String.fromInt absFret
                    ++ ", pitch class "
                    ++ String.fromInt note
                    ++ ") is not a scale note"
                )


adjacentStripeEdges : ScaleType -> ( Int, Int ) -> List Test
adjacentStripeEdges scale ( b1, b2 ) =
    List.map2 Tuple.pair (majorBoxShape scale b1) (majorBoxShape scale b2)
        |> List.concatMap
            (\( ( s, lo1, hi1 ), ( _, lo2, hi2 ) ) ->
                let
                    ovlpLo =
                        max lo1 lo2

                    ovlpHi =
                        min hi1 hi2

                    label =
                        scaleName scale
                            ++ " stripe "
                            ++ String.fromInt b1
                            ++ "-"
                            ++ String.fromInt b2
                            ++ " S"
                            ++ String.fromInt s
                in
                if ovlpHi >= ovlpLo then
                    [ test (label ++ " lo") (stripeEdgeTest scale (label ++ " lo") s ovlpLo)
                    , test (label ++ " hi") (stripeEdgeTest scale (label ++ " hi") s ovlpHi)
                    ]

                else
                    []
            )


wrapStripeEdges : ScaleType -> List Test
wrapStripeEdges scale =
    List.map2 Tuple.pair (majorBoxShape scale 5) (majorBoxShape scale 1)
        |> List.concatMap
            (\( ( s, lo5, hi5 ), ( _, lo1, hi1 ) ) ->
                let
                    -- Box 5 at octave N, box 1 at octave N+1. Relative to
                    -- a single F_root, box 1's positions sit 12 frets up.
                    ovlpLo =
                        max lo5 (lo1 + 12)

                    ovlpHi =
                        min hi5 (hi1 + 12)

                    label =
                        scaleName scale
                            ++ " wrap stripe 5-1 S"
                            ++ String.fromInt s
                in
                if ovlpHi >= ovlpLo then
                    [ test (label ++ " lo") (stripeEdgeTest scale (label ++ " lo") s ovlpLo)
                    , test (label ++ " hi") (stripeEdgeTest scale (label ++ " hi") s ovlpHi)
                    ]

                else
                    []
            )


stripeEdgesForScale : ScaleType -> Test
stripeEdgesForScale scale =
    describe (scaleName scale)
        (List.concatMap (adjacentStripeEdges scale) [ ( 1, 2 ), ( 2, 3 ), ( 3, 4 ), ( 4, 5 ) ]
            ++ wrapStripeEdges scale
        )


stripeEdges : Test
stripeEdges =
    describe "Stripe overlap edges land on scale notes (so polygons end at fret lines underneath notes)"
        (List.map stripeEdgesForScale modesWithMajorShapes)
