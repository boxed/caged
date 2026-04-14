module Main exposing (main)

import Browser
import Html exposing (Html, button, div, h1, p, span, text)
import Html.Attributes exposing (style)
import Html.Events exposing (onClick)
import Svg
import Svg.Attributes as SA



-- MODEL


type alias Model =
    { root : Int
    , scale : ScaleType
    }


type ScaleType
    = MinorPent
    | MajorPent
    | Ionian




type Msg
    = SetRoot Int
    | SetScale ScaleType


init : Model
init =
    { root = 9, scale = MinorPent }



-- UPDATE


update : Msg -> Model -> Model
update msg model =
    case msg of
        SetRoot n ->
            { model | root = modBy 12 n }

        SetScale s ->
            { model | scale = s }



-- MUSIC THEORY


noteName : Int -> String
noteName n =
    case modBy 12 n of
        0 -> "C"
        1 -> "C\u{266F}"
        2 -> "D"
        3 -> "D\u{266F}"
        4 -> "E"
        5 -> "F"
        6 -> "F\u{266F}"
        7 -> "G"
        8 -> "G\u{266F}"
        9 -> "A"
        10 -> "A\u{266F}"
        11 -> "B"
        _ -> ""


{-| String 1 is the high E (top of diagram), string 6 is the low E (bottom).
Returns the open-string pitch class (C=0).
-}
openString : Int -> Int
openString s =
    case s of
        1 -> 4
        2 -> 11
        3 -> 7
        4 -> 2
        5 -> 9
        6 -> 4
        _ -> 0


noteAt : Int -> Int -> Int
noteAt s f =
    modBy 12 (openString s + f)


scaleIntervals : ScaleType -> List Int
scaleIntervals st =
    case st of
        MinorPent ->
            [ 0, 3, 5, 7, 10 ]

        MajorPent ->
            [ 0, 2, 4, 7, 9 ]

        Ionian ->
            [ 0, 2, 4, 5, 7, 9, 11 ]


scaleNotes : Model -> List Int
scaleNotes model =
    List.map (\i -> modBy 12 (model.root + i)) (scaleIntervals model.scale)


isInScale : Model -> Int -> Bool
isInScale model n =
    List.member (modBy 12 n) (scaleNotes model)


{-| The "shape anchor" fret on the low-E string.
Minor pent of R → R's fret on low E.
Major pent of R → relative minor (R - 3)'s fret on low E.
-}
rootFret : Model -> Int
rootFret model =
    case model.scale of
        MinorPent ->
            modBy 12 (model.root - 4)

        MajorPent ->
            modBy 12 (model.root - 7)

        Ionian ->
            modBy 12 (model.root - 7)


{-| Returns which box (1-5) a note belongs to, based on its relative
fret (mod 12) from the shape anchor. The box is the one where this
position serves as the *lower* of the two notes on its string.
-}
boxOf : Int -> Int -> Maybe Int
boxOf s fRel =
    case ( s, fRel ) of
        ( 1, 0 ) -> Just 1
        ( 1, 3 ) -> Just 2
        ( 1, 5 ) -> Just 3
        ( 1, 7 ) -> Just 4
        ( 1, 10 ) -> Just 5
        ( 2, 0 ) -> Just 1
        ( 2, 3 ) -> Just 2
        ( 2, 5 ) -> Just 3
        ( 2, 8 ) -> Just 4
        ( 2, 10 ) -> Just 5
        ( 3, 0 ) -> Just 1
        ( 3, 2 ) -> Just 2
        ( 3, 4 ) -> Just 3
        ( 3, 7 ) -> Just 4
        ( 3, 9 ) -> Just 5
        ( 4, 0 ) -> Just 1
        ( 4, 2 ) -> Just 2
        ( 4, 5 ) -> Just 3
        ( 4, 7 ) -> Just 4
        ( 4, 9 ) -> Just 5
        ( 5, 0 ) -> Just 1
        ( 5, 2 ) -> Just 2
        ( 5, 5 ) -> Just 3
        ( 5, 7 ) -> Just 4
        ( 5, 10 ) -> Just 5
        ( 6, 0 ) -> Just 1
        ( 6, 3 ) -> Just 2
        ( 6, 5 ) -> Just 3
        ( 6, 7 ) -> Just 4
        ( 6, 10 ) -> Just 5
        _ -> Nothing


positionBox : Model -> Int -> Int -> Maybe Int
positionBox model s f =
    if isInScale model (noteAt s f) then
        let
            fRel =
                modBy 12 (f - rootFret model)
        in
        case model.scale of
            Ionian -> ionianBoxOf s fRel
            _ -> boxOf s fRel

    else
        Nothing


{-| Box mapping for Ionian: pentatonic notes reuse `boxOf`, the two extra
scale tones per string are placed in whichever pentatonic box their fret
range already contains. Derived with F_root shifted to match MajorPent. -}
ionianBoxOf : Int -> Int -> Maybe Int
ionianBoxOf s fRel =
    case boxOf s fRel of
        Just b ->
            Just b

        Nothing ->
            case ( s, fRel ) of
                ( 1, 2 ) -> Just 1
                ( 1, 8 ) -> Just 4
                ( 2, 1 ) -> Just 1
                ( 2, 7 ) -> Just 3
                ( 3, 5 ) -> Just 3
                ( 3, 11 ) -> Just 5
                ( 4, 4 ) -> Just 2
                ( 4, 10 ) -> Just 5
                ( 5, 3 ) -> Just 2
                ( 5, 9 ) -> Just 4
                ( 6, 2 ) -> Just 1
                ( 6, 8 ) -> Just 4
                _ -> Nothing


type NoteRole
    = Root
    | Third
    | Fifth
    | Other


noteRole : Model -> Int -> NoteRole
noteRole model n =
    let
        interval =
            modBy 12 (n - model.root)

        thirdInterval =
            case model.scale of
                MinorPent -> 3
                MajorPent -> 4
                Ionian -> 4
    in
    if interval == 0 then
        Root

    else if interval == thirdInterval then
        Third

    else if interval == 7 then
        Fifth

    else
        Other


{-| Relative-fret pattern of each box per string: (lower, upper).
These are the two scale notes of that box on that string,
where "upper" of box N equals "lower" of box N+1.
-}
boxShape : Int -> List ( Int, Int, Int )
boxShape b =
    case b of
        1 ->
            [ ( 1, 0, 3 ), ( 2, 0, 3 ), ( 3, 0, 2 ), ( 4, 0, 2 ), ( 5, 0, 2 ), ( 6, 0, 3 ) ]

        2 ->
            [ ( 1, 3, 5 ), ( 2, 3, 5 ), ( 3, 2, 4 ), ( 4, 2, 5 ), ( 5, 2, 5 ), ( 6, 3, 5 ) ]

        3 ->
            [ ( 1, 5, 7 ), ( 2, 5, 8 ), ( 3, 4, 7 ), ( 4, 5, 7 ), ( 5, 5, 7 ), ( 6, 5, 7 ) ]

        4 ->
            [ ( 1, 7, 10 ), ( 2, 8, 10 ), ( 3, 7, 9 ), ( 4, 7, 9 ), ( 5, 7, 10 ), ( 6, 7, 10 ) ]

        5 ->
            [ ( 1, 10, 12 ), ( 2, 10, 12 ), ( 3, 9, 12 ), ( 4, 9, 12 ), ( 5, 10, 12 ), ( 6, 10, 12 ) ]

        _ ->
            []


boxColor : Int -> String
boxColor b =
    case b of
        1 -> "var(--box-1)"
        2 -> "var(--box-2)"
        3 -> "var(--box-3)"
        4 -> "var(--box-4)"
        5 -> "var(--box-5)"
        _ -> "var(--surface-bd)"



-- LAYOUT


numFrets : Int
numFrets =
    22


nutWidth : Float
nutWidth = 70


fretWidth : Float
fretWidth = 58


stringSpacing : Float
stringSpacing = 36


topMargin : Float
topMargin = 30


leftMargin : Float
leftMargin = 18


rightMargin : Float
rightMargin = 18


fretboardHeight : Float
fretboardHeight =
    stringSpacing * 5


totalWidth : Float
totalWidth =
    leftMargin + nutWidth + fretWidth * toFloat numFrets + rightMargin


totalHeight : Float
totalHeight =
    topMargin + fretboardHeight + 80


noteX : Int -> Float
noteX f =
    if f == 0 then
        leftMargin + nutWidth * 0.5

    else
        leftMargin + nutWidth + fretWidth * (toFloat f - 0.5)


fretLineX : Int -> Float
fretLineX f =
    leftMargin + nutWidth + fretWidth * toFloat f


stringY : Int -> Float
stringY s =
    topMargin + stringSpacing * toFloat (s - 1)



-- VIEW


view : Model -> Html Msg
view model =
    div [ style "margin" "1rem 0.5rem" ]
        [ h1 [ style "margin" "0 0 6px" ] [ text "Guitar Fretboard Visualizer" ]
        , viewScaleTitle model
        , viewControls model
        , viewFretboard model
        , viewLegend model
        ]


viewScaleTitle : Model -> Html Msg
viewScaleTitle model =
    let
        scaleName =
            noteName model.root
                ++ " "
                ++ (case model.scale of
                        MinorPent -> "Minor Pentatonic"
                        MajorPent -> "Major Pentatonic"
                        Ionian -> "Ionian (Major)"
                   )

        intervalLabels =
            case model.scale of
                MinorPent -> [ "R", "♭3", "4", "5", "♭7" ]
                MajorPent -> [ "R", "2", "3", "5", "6" ]
                Ionian -> [ "R", "2", "3", "4", "5", "6", "7" ]

        notePairs =
            List.map2
                (\i lbl ->
                    noteName (modBy 12 (model.root + i)) ++ " (" ++ lbl ++ ")"
                )
                (scaleIntervals model.scale)
                intervalLabels
    in
    div [ style "margin-bottom" "14px" ]
        [ div
            [ style "font-size" "20px"
            , style "font-weight" "600"
            ]
            [ text scaleName ]
        , div
            [ style "color" "var(--text-2)"
            , style "font-size" "14px"
            , style "margin-top" "2px"
            ]
            [ text ("Notes: " ++ String.join "  ·  " notePairs) ]
        ]


viewControls : Model -> Html Msg
viewControls model =
    div [ style "margin-bottom" "18px" ]
        [ div [ style "margin-bottom" "8px" ]
            [ label "Root" , noteButtonRow model ]
        , div []
            [ label "Scale"
            , scaleButton model MinorPent "Minor Pent"
            , scaleButton model MajorPent "Major Pent"
            , scaleButton model Ionian "Ionian"
            ]
        ]


label : String -> Html Msg
label s =
    span
        [ style "display" "inline-block"
        , style "width" "60px"
        , style "font-size" "13px"
        , style "color" "var(--text-2)"
        , style "font-weight" "600"
        , style "text-transform" "uppercase"
        , style "letter-spacing" "0.05em"
        ]
        [ text s ]


noteButtonRow : Model -> Html Msg
noteButtonRow model =
    span [] (List.map (rootButton model) (List.range 0 11))


rootButton : Model -> Int -> Html Msg
rootButton model n =
    let
        active =
            modBy 12 model.root == n
    in
    button
        ([ onClick (SetRoot n)
         , style "min-width" "44px"
         ]
            ++ buttonBaseStyle active
        )
        [ text (noteName n) ]


scaleButton : Model -> ScaleType -> String -> Html Msg
scaleButton model st lbl =
    button
        ([ onClick (SetScale st)
         , style "min-width" "80px"
         ]
            ++ buttonBaseStyle (model.scale == st)
        )
        [ text lbl ]


buttonBaseStyle : Bool -> List (Html.Attribute Msg)
buttonBaseStyle active =
    [ style "padding" "6px 12px"
    , style "margin" "0 4px 0 0"
    , style "border" "1px solid var(--btn-bd)"
    , style "border-radius" "6px"
    , style "cursor" "pointer"
    , style "font-size" "14px"
    , style "font-family" "inherit"
    , style "background"
        (if active then
            "var(--btn-on-bg)"

         else
            "var(--btn-bg)"
        )
    , style "color"
        (if active then
            "var(--btn-on-text)"

         else
            "var(--btn-text)"
        )
    , style "font-weight"
        (if active then
            "600"

         else
            "500"
        )
    ]


viewFretboard : Model -> Html Msg
viewFretboard model =
    Svg.svg
        [ SA.viewBox ("0 0 " ++ String.fromFloat totalWidth ++ " " ++ String.fromFloat totalHeight)
        , SA.width (String.fromFloat totalWidth)
        , SA.style "max-width: 100%; height: auto;"
        ]
        (List.concat
            [ drawFretMarkers
            , drawBoxRegions model
            , drawFretLines
            , drawStrings
            , drawNotes model
            , drawFretNumbers
            , drawInlayDots
            ]
        )



-- BOX POLYGONS


drawBoxRegions : Model -> List (Svg.Svg Msg)
drawBoxRegions model =
    let
        octaves =
            [ -1, 0, 1 ]
    in
    List.concatMap
        (\b -> List.filterMap (drawOneBox model b) octaves)
        [ 1, 2, 3, 4, 5 ]


drawOneBox : Model -> Int -> Int -> Maybe (Svg.Svg Msg)
drawOneBox model b octave =
    let
        fRoot =
            rootFret model

        shift =
            fRoot + 12 * octave

        positions =
            List.map
                (\( s, lo, hi ) -> ( s, lo + shift, hi + shift ))
                (boxShape b)

        inRange =
            List.any
                (\( _, lo, hi ) ->
                    (lo >= 0 && lo <= numFrets) || (hi >= 0 && hi <= numFrets)
                )
                positions
    in
    if inRange then
        Just
            (Svg.polygon
                [ SA.points (polygonPoints positions)
                , SA.fill (boxColor b)
                , SA.fillOpacity "0.45"
                , SA.stroke (boxColor b)
                , SA.strokeOpacity "0.85"
                , SA.strokeWidth "1"
                , SA.strokeLinejoin "round"
                ]
                []
            )

    else
        Nothing


polygonPoints : List ( Int, Int, Int ) -> String
polygonPoints positions =
    let
        pad =
            stringSpacing * 0.55

        byString s =
            positions
                |> List.filter (\( str, _, _ ) -> str == s)
                |> List.head
                |> Maybe.withDefault ( s, 0, 0 )

        ( _, lo1, hi1 ) = byString 1
        ( _, lo2, hi2 ) = byString 2
        ( _, lo3, hi3 ) = byString 3
        ( _, lo4, hi4 ) = byString 4
        ( _, lo5, hi5 ) = byString 5
        ( _, lo6, hi6 ) = byString 6

        yMid sa sb =
            (stringY sa + stringY sb) / 2

        verts =
            [ ( fretCenterX lo1, stringY 1 - pad )
            , ( fretCenterX hi1, stringY 1 - pad )
            , ( fretCenterX hi1, yMid 1 2 )
            , ( fretCenterX hi2, yMid 1 2 )
            , ( fretCenterX hi2, yMid 2 3 )
            , ( fretCenterX hi3, yMid 2 3 )
            , ( fretCenterX hi3, yMid 3 4 )
            , ( fretCenterX hi4, yMid 3 4 )
            , ( fretCenterX hi4, yMid 4 5 )
            , ( fretCenterX hi5, yMid 4 5 )
            , ( fretCenterX hi5, yMid 5 6 )
            , ( fretCenterX hi6, yMid 5 6 )
            , ( fretCenterX hi6, stringY 6 + pad )
            , ( fretCenterX lo6, stringY 6 + pad )
            , ( fretCenterX lo6, yMid 5 6 )
            , ( fretCenterX lo5, yMid 5 6 )
            , ( fretCenterX lo5, yMid 4 5 )
            , ( fretCenterX lo4, yMid 4 5 )
            , ( fretCenterX lo4, yMid 3 4 )
            , ( fretCenterX lo3, yMid 3 4 )
            , ( fretCenterX lo3, yMid 2 3 )
            , ( fretCenterX lo2, yMid 2 3 )
            , ( fretCenterX lo2, yMid 1 2 )
            , ( fretCenterX lo1, yMid 1 2 )
            ]
    in
    verts
        |> List.map (\( x, y ) -> String.fromFloat x ++ "," ++ String.fromFloat y)
        |> String.join " "


fretCenterX : Int -> Float
fretCenterX f =
    -- noteX handles fret 0 specially; here we always use the "between lines" center
    if f <= 0 then
        leftMargin + nutWidth + fretWidth * (toFloat f - 0.5)

    else
        leftMargin + nutWidth + fretWidth * (toFloat f - 0.5)



-- FRETBOARD STRUCTURE


drawFretLines : List (Svg.Svg Msg)
drawFretLines =
    let
        top = topMargin - 4
        bot = topMargin + fretboardHeight + 4

        nut =
            Svg.line
                [ SA.x1 (String.fromFloat (leftMargin + nutWidth))
                , SA.x2 (String.fromFloat (leftMargin + nutWidth))
                , SA.y1 (String.fromFloat top)
                , SA.y2 (String.fromFloat bot)
                , SA.stroke "var(--nut)"
                , SA.strokeWidth "5"
                , SA.strokeLinecap "round"
                ]
                []

        fretLine f =
            Svg.line
                [ SA.x1 (String.fromFloat (fretLineX f))
                , SA.x2 (String.fromFloat (fretLineX f))
                , SA.y1 (String.fromFloat top)
                , SA.y2 (String.fromFloat bot)
                , SA.stroke "var(--fret-line)"
                , SA.strokeWidth "1.3"
                ]
                []
    in
    nut :: List.map fretLine (List.range 1 numFrets)


drawStrings : List (Svg.Svg Msg)
drawStrings =
    let
        leftX =
            leftMargin

        rightX =
            leftMargin + nutWidth + fretWidth * toFloat numFrets

        drawLine s =
            Svg.line
                [ SA.x1 (String.fromFloat leftX)
                , SA.x2 (String.fromFloat rightX)
                , SA.y1 (String.fromFloat (stringY s))
                , SA.y2 (String.fromFloat (stringY s))
                , SA.stroke "var(--string)"
                , SA.strokeWidth "1"
                ]
                []
    in
    List.map drawLine (List.range 1 6)


drawFretMarkers : List (Svg.Svg Msg)
drawFretMarkers =
    let
        singles = [ 3, 5, 7, 9, 15, 17, 19, 21 ]
        doubles = [ 12 ]
        midY = topMargin + stringSpacing * 2.5

        dot f dy =
            Svg.circle
                [ SA.cx (String.fromFloat (noteX f))
                , SA.cy (String.fromFloat (midY + dy))
                , SA.r "5"
                , SA.fill "var(--inlay-board)"
                ]
                []
    in
    List.map (\f -> dot f 0) singles
        ++ List.concatMap (\f -> [ dot f -stringSpacing, dot f stringSpacing ]) doubles



-- NOTES


drawNotes : Model -> List (Svg.Svg Msg)
drawNotes model =
    let
        forString s =
            List.filterMap (drawNoteAt model s) (List.range 0 numFrets)
    in
    List.concatMap forString (List.range 1 6)


drawNoteAt : Model -> Int -> Int -> Maybe (Svg.Svg Msg)
drawNoteAt model s f =
    case positionBox model s f of
        Just _ ->
            let
                n = noteAt s f
                role = noteRole model n
                cx = noteX f
                cy = stringY s

                background =
                    case role of
                        Root ->
                            Svg.rect
                                [ SA.x (String.fromFloat (cx - 14))
                                , SA.y (String.fromFloat (cy - 14))
                                , SA.width "28"
                                , SA.height "28"
                                , SA.rx "3"
                                , SA.fill "var(--root-bg)"
                                , SA.stroke "var(--root-bg)"
                                , SA.strokeWidth "1"
                                ]
                                []

                        Third ->
                            Svg.circle
                                [ SA.cx (String.fromFloat cx)
                                , SA.cy (String.fromFloat cy)
                                , SA.r "14"
                                , SA.fill "var(--note-bg)"
                                , SA.stroke "var(--chord-bd)"
                                , SA.strokeWidth "1.8"
                                , SA.strokeDasharray "4 3"
                                ]
                                []

                        Fifth ->
                            Svg.circle
                                [ SA.cx (String.fromFloat cx)
                                , SA.cy (String.fromFloat cy)
                                , SA.r "14"
                                , SA.fill "var(--note-bg)"
                                , SA.stroke "var(--chord-bd)"
                                , SA.strokeWidth "1.8"
                                , SA.strokeLinecap "round"
                                , SA.strokeDasharray "0.1 4"
                                ]
                                []

                        Other ->
                            Svg.circle
                                [ SA.cx (String.fromFloat cx)
                                , SA.cy (String.fromFloat cy)
                                , SA.r "14"
                                , SA.fill "var(--note-bg)"
                                , SA.stroke "var(--note-bd)"
                                , SA.strokeWidth "1.3"
                                ]
                                []

                textColor =
                    case role of
                        Root -> "var(--root-text)"
                        Third -> "var(--note-text)"
                        Fifth -> "var(--note-text)"
                        Other -> "var(--note-text)"

                labelNode =
                    Svg.text_
                        [ SA.x (String.fromFloat cx)
                        , SA.y (String.fromFloat (cy + 4))
                        , SA.textAnchor "middle"
                        , SA.fontSize "13"
                        , SA.fontWeight "700"
                        , SA.fontFamily "-apple-system, Helvetica, Arial, sans-serif"
                        , SA.fill textColor
                        ]
                        [ Svg.text (noteName n) ]
            in
            Just (Svg.g [] [ background, labelNode ])

        Nothing ->
            Nothing



-- FRET NUMBER LABELS


drawFretNumbers : List (Svg.Svg Msg)
drawFretNumbers =
    let
        y =
            topMargin + fretboardHeight + 38

        highlighted =
            [ 3, 5, 7, 9, 12, 15, 17, 19, 21 ]

        labelFor f =
            let
                txt =
                    if f == 0 then
                        "Open"

                    else
                        String.fromInt f

                isHi = List.member f highlighted

                bg =
                    if isHi then
                        [ Svg.rect
                            [ SA.x (String.fromFloat (noteX f - 13))
                            , SA.y (String.fromFloat (y - 14))
                            , SA.width "26"
                            , SA.height "19"
                            , SA.rx "3"
                            , SA.fill "var(--fret-num-bg)"
                            ]
                            []
                        ]

                    else
                        []

                openTriangle =
                    if f == 0 then
                        [ Svg.polygon
                            [ SA.points
                                (String.fromFloat (noteX f - 5)
                                    ++ ","
                                    ++ String.fromFloat (y - 18)
                                    ++ " "
                                    ++ String.fromFloat (noteX f + 5)
                                    ++ ","
                                    ++ String.fromFloat (y - 18)
                                    ++ " "
                                    ++ String.fromFloat (noteX f)
                                    ++ ","
                                    ++ String.fromFloat (y - 24)
                                )
                            , SA.fill "var(--triangle)"
                            ]
                            []
                        ]

                    else
                        []

                lbl =
                    Svg.text_
                        [ SA.x (String.fromFloat (noteX f))
                        , SA.y (String.fromFloat y)
                        , SA.textAnchor "middle"
                        , SA.fontSize "13"
                        , SA.fontFamily "-apple-system, Helvetica, Arial, sans-serif"
                        , SA.fill "var(--fret-num)"
                        ]
                        [ Svg.text txt ]
            in
            bg ++ openTriangle ++ [ lbl ]
    in
    List.concatMap labelFor (List.range 0 numFrets)



-- INLAY DOT ROW (below fret numbers)


drawInlayDots : List (Svg.Svg Msg)
drawInlayDots =
    let
        singles = [ 3, 5, 7, 9, 15, 17, 19, 21 ]
        doubles = [ 12 ]
        y = topMargin + fretboardHeight + 60

        dot f dx =
            Svg.circle
                [ SA.cx (String.fromFloat (noteX f + dx))
                , SA.cy (String.fromFloat y)
                , SA.r "5"
                , SA.fill "var(--inlay-below)"
                ]
                []
    in
    List.map (\f -> dot f 0) singles
        ++ List.concatMap (\f -> [ dot f -7, dot f 7 ]) doubles



-- LEGEND


viewLegend : Model -> Html Msg
viewLegend _ =
    div
        [ style "margin-top" "16px"
        , style "font-size" "13px"
        , style "color" "var(--text-2)"
        , style "display" "flex"
        , style "gap" "18px"
        , style "flex-wrap" "wrap"
        , style "align-items" "center"
        ]
        (legendText "Boxes:"
            :: List.map legendSwatch [ ( 1, "1" ), ( 2, "2" ), ( 3, "3" ), ( 4, "4" ), ( 5, "5" ) ]
            ++ [ legendText "Tones:"
               , legendMarker "square-dark" "Root"
               , legendMarker "circle-dashed" "3rd"
               , legendMarker "circle-dotted" "5th"
               , legendMarker "circle-plain" "other"
               ]
        )


legendText : String -> Html Msg
legendText s =
    span [ style "font-weight" "600", style "color" "var(--text-strong)" ] [ text s ]


legendSwatch : ( Int, String ) -> Html Msg
legendSwatch ( b, lbl ) =
    span
        [ style "display" "inline-flex"
        , style "align-items" "center"
        , style "gap" "6px"
        ]
        [ span
            [ style "display" "inline-block"
            , style "width" "16px"
            , style "height" "16px"
            , style "background" (boxColor b)
            , style "border" ("1px solid " ++ boxColor b)
            , style "border-radius" "3px"
            , style "opacity" "0.75"
            ]
            []
        , text lbl
        ]


legendMarker : String -> String -> Html Msg
legendMarker kind lbl =
    let
        common =
            [ style "display" "inline-block"
            , style "width" "16px"
            , style "height" "16px"
            , style "box-sizing" "border-box"
            ]

        marker =
            case kind of
                "square-dark" ->
                    span
                        (common
                            ++ [ style "background" "var(--root-bg)"
                               , style "border-radius" "2px"
                               ]
                        )
                        []

                "circle-dashed" ->
                    span
                        (common
                            ++ [ style "background" "var(--note-bg)"
                               , style "border" "1.8px dashed var(--chord-bd)"
                               , style "border-radius" "50%"
                               ]
                        )
                        []

                "circle-dotted" ->
                    span
                        (common
                            ++ [ style "background" "var(--note-bg)"
                               , style "border" "1.8px dotted var(--chord-bd)"
                               , style "border-radius" "50%"
                               ]
                        )
                        []

                _ ->
                    span
                        (common
                            ++ [ style "background" "var(--note-bg)"
                               , style "border" "1px solid var(--note-bd)"
                               , style "border-radius" "50%"
                               ]
                        )
                        []
    in
    span
        [ style "display" "inline-flex"
        , style "align-items" "center"
        , style "gap" "6px"
        ]
        [ marker, text lbl ]



-- MAIN


main : Program () Model Msg
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }
