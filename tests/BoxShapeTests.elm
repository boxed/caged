module BoxShapeTests exposing (suite)

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
