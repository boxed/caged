port module Practice exposing
    ( Model
    , Msg
    , init
    , isPlaying
    , subscriptions
    , update
    , view
    )

{-| The **Practice** panel: a backing band to solo over. You write (or are dealt)
a chord chart, the band loops it, and a strip of all twelve notes shows which
ones fit the chord being played right now. With **Listen** on, the microphone
is pitch-tracked and a note outside the key flashes the chart red.

Everything but the sound is here: the chart, the presets, the chart writer, the
key the chart is in, the Roman numerals, what each note means over each chord,
the keyboard shortcuts and the view. `band.js` only makes the sound and
listens, because Elm cannot reach Web Audio or the microphone. It talks to it
through two ports: `bandOut` sends it the band state (on every change, so a
chord edited while the band plays is heard on the next bar) and play / stop /
listen / unlisten; `bandIn` brings back the beat being heard, whether the band
is playing, and every note the microphone settles on.

The chart is remembered in the browser (`band.js` writes what `encodeSave`
gives it to localStorage), not in the URL: the URL belongs to the fretboard.

-}

import Array exposing (Array)
import Browser.Events
import Dict exposing (Dict)
import Html exposing (Html, button, div, input, option, span, text)
import Html.Attributes as A exposing (attribute, style)
import Html.Events exposing (onClick, onInput)
import Json.Decode as D
import Json.Encode as E
import Process
import Random
import Set
import Svg
import Svg.Attributes as SA
import Task


port bandOut : E.Value -> Cmd msg


port bandIn : (D.Value -> msg) -> Sub msg



-- CHORDS


type Quality
    = QMaj
    | QMin
    | Q7
    | QMin7
    | QMaj7
    | Q6
    | QMin6
    | Q9
    | Q13
    | Q7s9
    | Q7b9
    | QDim7


type Family
    = MajFam
    | MinFam
    | DomFam
    | DimFam


{-| `id` is what `band.js` and the saved chart call it; `label` is what goes
after the root (`A7♯9`); `name` is the caption in the editor; `basic` types
show without opening **More chord types**; `tones` are the voicing's notes
above the root, which with the root and fifth make the chord's tones. -}
type alias QualInfo =
    { id : String
    , label : String
    , name : String
    , basic : Bool
    , fam : Family
    , tones : List Int
    }


qualities : List Quality
qualities =
    [ QMaj, QMin, Q7, QMin7, QMaj7, Q6, QMin6, Q9, Q13, Q7s9, Q7b9, QDim7 ]


qualInfo : Quality -> QualInfo
qualInfo q =
    case q of
        QMaj ->
            QualInfo "maj" "" "major" True MajFam [ 0, 4, 7 ]

        QMin ->
            QualInfo "m" "m" "minor" True MinFam [ 0, 3, 7 ]

        Q7 ->
            QualInfo "7" "7" "seventh" True DomFam [ 0, 4, 10 ]

        QMin7 ->
            QualInfo "m7" "m7" "minor seventh" False MinFam [ 3, 10, 14 ]

        QMaj7 ->
            QualInfo "maj7" "maj7" "major seventh" False MajFam [ 4, 7, 11 ]

        Q6 ->
            QualInfo "6" "6" "sixth" False MajFam [ 4, 7, 9 ]

        QMin6 ->
            QualInfo "m6" "m6" "minor sixth" False MinFam [ 3, 7, 9 ]

        Q9 ->
            QualInfo "9" "9" "ninth" False DomFam [ 4, 10, 14 ]

        Q13 ->
            QualInfo "13" "13" "thirteenth" False DomFam [ 4, 9, 10, 14 ]

        Q7s9 ->
            QualInfo "7#9" "7♯9" "sharp nine" False DomFam [ 4, 10, 15 ]

        Q7b9 ->
            QualInfo "7b9" "7♭9" "flat nine" False DomFam [ 4, 10, 13 ]

        QDim7 ->
            QualInfo "dim7" "°7" "diminished" False DimFam [ 0, 3, 6, 9 ]


qualFromId : String -> Maybe Quality
qualFromId id =
    List.filter (\q -> (qualInfo q).id == id) qualities |> List.head


fam : Quality -> Family
fam q =
    (qualInfo q).fam


type alias Bar =
    { root : Int, q : Quality }


noteNames : Array String
noteNames =
    Array.fromList [ "C", "D♭", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B" ]


noteName : Int -> String
noteName pc =
    Array.get (modBy 12 pc) noteNames |> Maybe.withDefault "?"


chordName : Bar -> String
chordName bar =
    noteName bar.root ++ (qualInfo bar.q).label


{-| While **More chord types** is shut, anything the panel writes uses only
major, minor and seventh chords. -}
simplify : Bool -> List Bar -> List Bar
simplify moreOpen bars =
    if moreOpen then
        bars

    else
        List.map (\b -> { b | q = basicFor (fam b.q) }) bars


basicFor : Family -> Quality
basicFor f =
    case f of
        MajFam ->
            QMaj

        MinFam ->
            QMin

        _ ->
            Q7



-- STYLES AND PRESETS


type Style
    = Shuffle
    | Modern
    | Ballad


styles : List Style
styles =
    [ Modern, Shuffle, Ballad ]


type alias StyleInfo =
    { id : String, name : String, short : String, bpm : Int, feel : Int, hint : String }


styleInfo : Style -> StyleInfo
styleInfo s =
    case s of
        Shuffle ->
            StyleInfo "shuffle" "Old-school shuffle" "Shuffle" 112 80 "Ride, boogie bass, electric piano"

        Modern ->
            StyleInfo "modern" "Modern blues rock" "Modern" 100 8 "Straight eighths, hi-hat, strummed acoustic guitar"

        Ballad ->
            StyleInfo "ballad" "Slow ballad" "Ballad" 50 100 "Slow triplet feel, piano triplets over organ, no guitar"


styleFromId : String -> Maybe Style
styleFromId id =
    List.filter (\s -> (styleInfo s).id == id) styles |> List.head


type alias Preset =
    { id : String, name : String, bars : List ( Int, Quality ) }


{-| Degrees are semitones above the key. -}
presets : List Preset
presets =
    let
        sevenths =
            List.map (\d -> ( d, Q7 ))
    in
    [ Preset "twelve" "12-bar blues" (sevenths [ 0, 0, 0, 0, 5, 5, 0, 0, 7, 5, 0, 7 ])
    , Preset "quick" "quick-change blues" (sevenths [ 0, 5, 0, 0, 5, 5, 0, 0, 7, 5, 0, 7 ])
    , Preset "soul"
        "soul blues"
        [ ( 0, Q7 ), ( 5, Q7 ), ( 0, Q7 ), ( 9, QMin7 ), ( 5, Q7 ), ( 2, QMin7 ), ( 0, Q7 ), ( 4, QMin7 ), ( 2, QMin7 ), ( 7, Q7 ), ( 0, Q7 ), ( 7, Q7 ) ]
    , Preset "jazz"
        "jazz blues"
        [ ( 0, Q7 ), ( 5, Q7 ), ( 0, Q7 ), ( 0, Q7 ), ( 5, Q7 ), ( 6, QDim7 ), ( 0, Q7 ), ( 9, Q7 ), ( 2, QMin7 ), ( 7, Q7 ), ( 0, Q7 ), ( 7, Q7 ) ]
    , Preset "slow"
        "slow blues"
        [ ( 0, Q9 ), ( 5, Q9 ), ( 0, Q9 ), ( 0, Q7 ), ( 5, Q9 ), ( 5, Q9 ), ( 0, Q7 ), ( 4, QMin7 ), ( 2, QMin7 ), ( 7, Q9 ), ( 0, Q7 ), ( 7, Q7s9 ) ]
    , Preset "minor"
        "minor blues"
        [ ( 0, QMin7 ), ( 0, QMin7 ), ( 0, QMin7 ), ( 0, QMin7 ), ( 5, QMin7 ), ( 5, QMin7 ), ( 0, QMin7 ), ( 0, QMin7 ), ( 8, Q7 ), ( 7, Q7 ), ( 0, QMin7 ), ( 7, Q7 ) ]
    , Preset "rock"
        "blues rock"
        [ ( 0, QMaj ), ( 0, QMaj ), ( 5, QMaj ), ( 7, QMaj ), ( 0, QMaj ), ( 9, QMin ), ( 5, QMaj ), ( 7, QMaj ) ]
    , Preset "ballad" "pop ballad" [ ( 0, QMaj ), ( 9, QMin ), ( 7, QMaj ), ( 5, QMaj ) ]
    , Preset "eight" "8-bar blues" (sevenths [ 0, 7, 5, 5, 0, 7, 0, 0 ])
    ]


presetById : String -> Maybe Preset
presetById id =
    List.filter (\p -> p.id == id) presets |> List.head


{-| Where the chart came from. A preset follows the key by being rebuilt in it;
a chart of your own or a made-up one follows it by being transposed. -}
type Source
    = FromPreset String
    | Custom
    | Generated


barsFromPreset : Bool -> String -> Int -> List Bar
barsFromPreset moreOpen id key =
    presetById id
        |> Maybe.map (.bars >> List.map (\( d, q ) -> { root = modBy 12 (key + d), q = q }))
        |> Maybe.withDefault []
        |> simplify moreOpen


minBars : Int
minBars =
    1


maxBars : Int
maxBars =
    16



-- CHART WRITER


{-| The chords a made-up chart may use, by degree. `quals` are the qualities
by richness tier: plain triads, sevenths, extended. The entries are listed
roughly in order of how much they belong in a blues; `next` is where each
likes to go. -}
type alias Palette =
    { chords : Array { deg : Int, quals : List (List Quality) }
    , next : Dict Int (List Int)
    }


majorPalette : Palette
majorPalette =
    { chords =
        Array.fromList
            [ { deg = 0, quals = [ [ QMaj ], [ Q7, Q6 ], [ Q9, Q9, Q13 ] ] } -- I
            , { deg = 5, quals = [ [ QMaj ], [ Q7 ], [ Q9, QMaj7 ] ] } -- IV
            , { deg = 7, quals = [ [ QMaj ], [ Q7 ], [ Q9, Q7s9, Q13 ] ] } -- V
            , { deg = 9, quals = [ [ QMin ], [ QMin7 ], [ QMin7, QMin6 ] ] } -- vi
            , { deg = 2, quals = [ [ QMin ], [ QMin7 ], [ QMin7 ] ] } -- ii
            , { deg = 10, quals = [ [ QMaj ], [ Q7 ], [ Q9 ] ] } -- ♭VII
            , { deg = 4, quals = [ [ QMin ], [ QMin7 ], [ QMin7 ] ] } -- iii
            , { deg = 6, quals = [ [ QDim7 ], [ QDim7 ], [ QDim7 ] ] } -- ♯iv dim
            , { deg = 8, quals = [ [ QMaj ], [ Q7 ], [ QMaj7 ] ] } -- ♭VI
            , { deg = 3, quals = [ [ QMaj ], [ Q7 ], [ QMaj7 ] ] } -- ♭III
            , { deg = 2, quals = [ [ QMaj ], [ Q7 ], [ Q9 ] ] } -- II
            , { deg = 5, quals = [ [ QMin ], [ QMin7 ], [ QMin6 ] ] } -- iv
            ]
    , next =
        Dict.fromList
            [ ( 0, [ 1, 2, 3, 4, 5, 7, 9 ] )
            , ( 1, [ 0, 2, 7, 11, 5 ] )
            , ( 2, [ 0, 3, 1, 8 ] )
            , ( 3, [ 4, 1, 2, 6 ] )
            , ( 4, [ 2, 0, 6, 1 ] )
            , ( 5, [ 1, 0, 8 ] )
            , ( 6, [ 3, 4, 1 ] )
            , ( 7, [ 0, 2 ] )
            , ( 8, [ 2, 5, 0 ] )
            , ( 9, [ 1, 0 ] )
            , ( 10, [ 2, 4 ] )
            , ( 11, [ 0, 2 ] )
            ]
    }


minorPalette : Palette
minorPalette =
    { chords =
        Array.fromList
            [ { deg = 0, quals = [ [ QMin ], [ QMin7 ], [ QMin7, QMin6 ] ] } -- i
            , { deg = 5, quals = [ [ QMin ], [ QMin7 ], [ QMin7 ] ] } -- iv
            , { deg = 7, quals = [ [ QMaj ], [ Q7 ], [ Q7s9, Q7b9 ] ] } -- V
            , { deg = 8, quals = [ [ QMaj ], [ Q7 ], [ QMaj7 ] ] } -- ♭VI
            , { deg = 10, quals = [ [ QMaj ], [ Q7 ], [ Q9 ] ] } -- ♭VII
            , { deg = 3, quals = [ [ QMaj ], [ Q6 ], [ QMaj7 ] ] } -- ♭III
            , { deg = 7, quals = [ [ QMin ], [ QMin7 ], [ QMin7 ] ] } -- v
            , { deg = 2, quals = [ [ QDim7 ], [ QDim7 ], [ QDim7 ] ] } -- ii dim
            , { deg = 5, quals = [ [ QMaj ], [ Q7 ], [ Q9 ] ] } -- IV
            ]
    , next =
        Dict.fromList
            [ ( 0, [ 1, 2, 4, 3, 5, 8 ] )
            , ( 1, [ 0, 2, 3, 4 ] )
            , ( 2, [ 0, 1, 3 ] )
            , ( 3, [ 2, 4, 0 ] )
            , ( 4, [ 0, 3, 5, 1 ] )
            , ( 5, [ 3, 4, 1 ] )
            , ( 6, [ 3, 1, 0 ] )
            , ( 7, [ 2, 0 ] )
            , ( 8, [ 0, 2, 4 ] )
            ]
    }


maxVariety : Int -> Int
maxVariety n =
    min n (Array.length majorPalette.chords)


{-| How plain or rich a made-up chart leans, per style: the chance of triads
and of sevenths (the rest are extended chords). -}
richness : Style -> ( Float, Float )
richness s =
    case s of
        Modern ->
            ( 0.45, 0.4 )

        Shuffle ->
            ( 0.15, 0.5 )

        Ballad ->
            ( 0.8, 0.2 )


roll : Random.Seed -> ( Float, Random.Seed )
roll =
    Random.step (Random.float 0 1)


pickFrom : List a -> a -> Random.Seed -> ( a, Random.Seed )
pickFrom list fallback seed =
    let
        ( r, s ) =
            roll seed
    in
    ( getAt (floor (r * toFloat (List.length list))) list |> Maybe.withDefault fallback, s )


{-| Like `pickFrom`, but favoring the front of the list. -}
leanFrom : List a -> a -> Random.Seed -> ( a, Random.Seed )
leanFrom list fallback seed =
    let
        ( r, s ) =
            roll seed

        n =
            List.length list
    in
    ( getAt (min (n - 1) (floor ((r ^ 1.8) * toFloat n))) list |> Maybe.withDefault fallback, s )


{-| Writes a chart of `n` bars that uses `k` different chords in `key`. Home is
always in the set and the rest is a draw that leans toward the front of the
palette. Each chord keeps one quality for the whole chart, around a shared
richness level. The last bar is fixed to resolve home: from V if the set has
it, else from the chart's second chord. Phrases like to start at home, and a
chord may hold for a bar or two when there is room. -}
writeChart : Int -> Int -> Int -> Style -> Random.Seed -> ( List Bar, Random.Seed )
writeChart n k0 key style seed0 =
    let
        k =
            clamp 1 (maxVariety n) k0

        ( rMinor, s1 ) =
            roll seed0

        pal =
            if rMinor < 0.25 && k <= Array.length minorPalette.chords then
                minorPalette

            else
                majorPalette

        chordAt i =
            Array.get i pal.chords |> Maybe.withDefault { deg = 0, quals = [ [ QMaj ] ] }

        ( scored, s2 ) =
            List.foldl
                (\i ( acc, s ) ->
                    let
                        ( r, s_ ) =
                            roll s
                    in
                    ( ( i, toFloat i + r * 4.5 ) :: acc, s_ )
                )
                ( [], s1 )
                (List.range 1 (Array.length pal.chords - 1))

        chosen =
            0 :: List.take (k - 1) (List.sortBy Tuple.second scored |> List.map Tuple.first)

        inSet c =
            List.member c chosen

        ( plain, sevenths ) =
            richness style

        ( rBase, s3 ) =
            roll s2

        base =
            if rBase < plain then
                0

            else if rBase < plain + sevenths then
                1

            else
                2

        ( quality, s4 ) =
            List.foldl
                (\i ( d, s ) ->
                    let
                        ( ra, sa ) =
                            roll s

                        ( rb, sb ) =
                            roll sa

                        shift =
                            if ra < 0.25 then
                                if rb < 0.5 then
                                    -1

                                else
                                    1

                            else
                                0

                        options =
                            getAt (clamp 0 2 (base + shift)) (chordAt i).quals |> Maybe.withDefault [ QMaj ]

                        ( q, sc ) =
                            pickFrom options QMaj sb
                    in
                    ( Dict.insert i q d, sc )
                )
                ( Dict.empty, s3 )
                chosen

        ratio =
            toFloat n / toFloat k

        holdChance =
            if ratio >= 3 then
                0.35

            else if ratio >= 2 then
                0.15

            else
                0

        lastFixed =
            if n >= 2 && k >= 2 then
                Just
                    (if inSet 2 then
                        2

                     else
                        getAt 1 chosen |> Maybe.withDefault 0
                    )

            else
                Nothing

        fixed =
            if lastFixed == Nothing then
                0

            else
                1

        fill i ( seq, used, s ) =
            if i >= n - fixed then
                ( seq, used, s )

            else
                let
                    prev =
                        Array.get (i - 1) seq |> Maybe.withDefault 0

                    run =
                        i >= 2 && Array.get (i - 2) seq == Just prev

                    unused =
                        List.filter (\c -> not (Set.member c used)) chosen

                    left =
                        n - i - fixed

                    -- don't pile up on the turnaround chord
                    turnaround c =
                        lastFixed /= Nothing && i == n - 2 && Just c == lastFixed

                    ( next, s_ ) =
                        if not (List.isEmpty unused) && List.length unused >= left then
                            pickFrom unused prev s

                        else
                            let
                                ( ra, sa ) =
                                    roll s

                                ( rb, sb ) =
                                    roll sa

                                ( rc, sc ) =
                                    roll sb
                            in
                            if modBy 4 i == 0 && n >= 8 && prev /= 0 && ra < 0.6 then
                                ( 0, sa )

                            else if not run && not (turnaround prev) && rb < holdChance then
                                ( prev, sb )

                            else
                                let
                                    wants =
                                        Dict.get prev pal.next
                                            |> Maybe.withDefault []
                                            |> List.filter (\c -> inSet c && c /= prev && not (turnaround c))

                                    fresh =
                                        List.filter (\c -> not (Set.member c used)) wants

                                    fallback =
                                        List.filter (\c -> c /= prev && not (turnaround c)) chosen
                                in
                                case ( fresh, wants, fallback ) of
                                    ( f :: _, _, _ ) ->
                                        if rc < 0.6 then
                                            ( f, sc )

                                        else
                                            leanFrom wants prev sc

                                    ( [], _ :: _, _ ) ->
                                        leanFrom wants prev sc

                                    ( [], [], _ :: _ ) ->
                                        pickFrom fallback prev sc

                                    _ ->
                                        ( prev, sc )
                in
                fill (i + 1) ( Array.push next seq, Set.insert next used, s_ )

        ( body, _, s5 ) =
            fill 1 ( Array.fromList [ 0 ], Set.singleton 0 |> insertMaybe lastFixed, s4 )

        withLast =
            case lastFixed of
                Just lf ->
                    Array.push lf body

                Nothing ->
                    body

        -- anything still unused replaces an interior bar that repeats a neighbor
        ( final, s6 ) =
            List.foldl
                (\c ( seq, s ) ->
                    let
                        len =
                            Array.length seq

                        repeats i =
                            Array.get i seq == Array.get (i - 1) seq || Array.get i seq == Array.get (i + 1) seq
                    in
                    case List.filter repeats (List.range 1 (len - 2)) of
                        spot :: _ ->
                            ( Array.set spot c seq, s )

                        [] ->
                            let
                                ( r, s_ ) =
                                    roll s
                            in
                            ( Array.set (max 1 (floor (r * toFloat (len - 1)))) c seq, s_ )
                )
                ( withLast, s5 )
                (List.filter (\c -> not (List.member c (Array.toList withLast))) chosen)
    in
    ( Array.toList final
        |> List.map
            (\i ->
                { root = modBy 12 (key + (chordAt i).deg)
                , q = Dict.get i quality |> Maybe.withDefault QMaj
                }
            )
    , s6
    )


insertMaybe : Maybe Int -> Set.Set Int -> Set.Set Int
insertMaybe m set =
    case m of
        Just x ->
            Set.insert x set

        Nothing ->
            set


distinctChords : List Bar -> Int
distinctChords bars =
    List.map (\b -> ( b.root, (qualInfo b.q).id )) bars |> Set.fromList |> Set.size



-- KEY


{-| How well a chart sits in a key: chords built on the major scale count
fully, blues dominants on I, IV and V count too, and the first bar landing on
the tonic tips it. -}
keyFit : List Bar -> Int -> Float
keyFit bars k =
    List.indexedMap
        (\i b ->
            let
                d =
                    modBy 12 (b.root - k)

                f =
                    fam b.q

                chord =
                    if (f == MajFam || f == DomFam) && List.member d [ 0, 5, 7 ] then
                        2

                    else if f == MinFam && List.member d [ 2, 4, 9 ] then
                        2

                    else if f == DimFam && d == 11 then
                        2

                    else if f == MinFam && d == 0 then
                        1.5

                    else
                        0
            in
            chord
                + (if i == 0 && d == 0 then
                    1.5

                   else
                    0
                  )
        )
        bars
        |> List.sum


{-| After a hand edit, follow the chart to the key it is really in, so the
Roman numerals read right (C Am G F gives I vi V IV). The chords stay put; only
the key label moves. -}
followKey : Model -> Model
followKey model =
    let
        best =
            List.foldl
                (\k ( bk, bs ) ->
                    let
                        sc =
                            keyFit model.bars k
                    in
                    if sc > bs then
                        ( k, sc )

                    else
                        ( bk, bs )
                )
                ( model.key, keyFit model.bars model.key )
                (List.range 0 11)
    in
    { model | key = Tuple.first best }


degreeNumerals : Array String
degreeNumerals =
    Array.fromList [ "I", "♭II", "II", "♭III", "III", "IV", "♯IV", "V", "♭VI", "VI", "♭VII", "VII" ]


{-| The chord's Roman numeral in the key: upper case for major and dominant
chords, lower case for minor and diminished, so C Am G F in C is I vi V IV,
and A7 in C is VI7. -}
numeral : Int -> Bar -> String
numeral key bar =
    let
        info =
            qualInfo bar.q

        rn =
            Array.get (modBy 12 (bar.root - key)) degreeNumerals |> Maybe.withDefault "?"
    in
    case info.fam of
        DimFam ->
            String.toLower rn ++ "°7"

        MinFam ->
            String.toLower rn ++ String.dropLeft 1 info.label

        _ ->
            rn ++ info.label



-- WHAT EACH NOTE IS


type Role
    = ChordTone
    | InKey
    | BlueNote
    | Outside


{-| What each chord tone is called within its chord. -}
toneName : Family -> Int -> String
toneName f d =
    let
        names =
            case f of
                MajFam ->
                    [ ( 0, "R" ), ( 4, "3" ), ( 7, "5" ), ( 11, "7" ), ( 9, "6" ), ( 2, "9" ) ]

                DomFam ->
                    [ ( 0, "R" ), ( 4, "3" ), ( 7, "5" ), ( 10, "♭7" ), ( 2, "9" ), ( 9, "13" ), ( 3, "♯9" ), ( 1, "♭9" ) ]

                MinFam ->
                    [ ( 0, "R" ), ( 3, "♭3" ), ( 7, "5" ), ( 10, "♭7" ), ( 9, "6" ), ( 2, "9" ) ]

                DimFam ->
                    [ ( 0, "R" ), ( 3, "♭3" ), ( 6, "♭5" ), ( 9, "°7" ) ]
    in
    Dict.fromList names |> Dict.get d |> Maybe.withDefault ""


{-| The chord's tones by pitch class, each with its name in the chord. The
voicings can leave out the root and fifth, so those are added. -}
chordTones : Bar -> Dict Int String
chordTones bar =
    let
        info =
            qualInfo bar.q

        offsets =
            0
                :: (if info.fam == DimFam then
                        []

                    else
                        [ 7 ]
                   )
                ++ List.map (modBy 12) info.tones
    in
    offsets
        |> List.map (\d -> ( modBy 12 (bar.root + d), toneName info.fam d ))
        |> Dict.fromList


keyDegrees : Array String
keyDegrees =
    Array.fromList [ "1", "♭2", "2", "♭3", "3", "4", "♭5", "5", "♭6", "6", "♭7", "7" ]


{-| The bar the notes strip is about: the one the band is playing, or the one
being edited while it is stopped. -}
currentIndex : Model -> Int
currentIndex model =
    case ( model.playing, model.playhead ) of
        ( True, Just ph ) ->
            modBy (max 1 (List.length model.bars)) ph.bar

        _ ->
            model.selected


currentBar : Model -> Bar
currentBar model =
    getAt (currentIndex model) model.bars |> Maybe.withDefault { root = model.key, q = Q7 }


{-| A note is a chord tone, in the key's scale, a blue note (not in the
ballad), or outside. A chart with a minor chord on the tonic is in a minor
key, whose scale carries both sixth and seventh, raised and not. -}
roleOf : Model -> Int -> Role
roleOf model pc =
    let
        k =
            model.key

        minorKey =
            List.any (\b -> b.root == k && fam b.q == MinFam) model.bars

        degree =
            modBy 12 (pc - k)

        scale =
            if minorKey then
                [ 0, 2, 3, 5, 7, 8, 10, 11 ]

            else
                [ 0, 2, 4, 5, 7, 9, 11 ]

        blue =
            if model.style == Ballad then
                []

            else if minorKey then
                [ 6 ]

            else
                [ 3, 6, 10 ]
    in
    if Dict.member pc (chordTones (currentBar model)) then
        ChordTone

    else if List.member degree scale then
        InKey

    else if List.member degree blue then
        BlueNote

    else
        Outside



-- MODEL


type alias Mix =
    { drums : Int, bass : Int, keys : Int, guitar : Int, master : Int }


type Channel
    = Drums
    | Bass
    | Keys
    | Guitar
    | Master


channels : List ( Channel, String )
channels =
    [ ( Drums, "Drums" ), ( Bass, "Bass" ), ( Keys, "Keys" ), ( Guitar, "Guitar" ), ( Master, "Master" ) ]


level : Channel -> Mix -> Int
level c mix =
    case c of
        Drums ->
            mix.drums

        Bass ->
            mix.bass

        Keys ->
            mix.keys

        Guitar ->
            mix.guitar

        Master ->
            mix.master


setLevel : Channel -> Int -> Mix -> Mix
setLevel c v mix =
    case c of
        Drums ->
            { mix | drums = v }

        Bass ->
            { mix | bass = v }

        Keys ->
            { mix | keys = v }

        Guitar ->
            { mix | guitar = v }

        Master ->
            { mix | master = v }


type alias Playhead =
    { bar : Int, beat : Int }


type alias Model =
    { style : Style
    , bpm : Int
    , feel : Int
    , key : Int
    , source : Source
    , bars : List Bar
    , selected : Int
    , moreOpen : Bool
    , mix : Mix

    -- what band.js last reported: whether it plays, and the beat it is on
    -- (`bar` counts up from the count-in, the chart's bar is it mod length)
    , playing : Bool
    , playhead : Maybe Playhead

    -- the microphone
    , listening : Bool
    , earMessage : String
    , heard : Maybe Int

    -- a wrong note keeps the chart red a moment after it stops
    , missHold : Bool
    , missToken : Int
    , seed : Random.Seed
    }


isPlaying : Model -> Bool
isPlaying =
    .playing


{-| `seed` seeds the chart writer; `saved` is what `encodeSave` left in the
browser last time, or null. -}
init : Int -> D.Value -> Model
init seed saved =
    let
        fresh =
            { style = Ballad
            , bpm = (styleInfo Ballad).bpm
            , feel = (styleInfo Ballad).feel
            , key = 0
            , source = FromPreset "ballad"
            , bars = barsFromPreset False "ballad" 0
            , selected = 0
            , moreOpen = False
            , mix = { drums = 80, bass = 90, keys = 55, guitar = 75, master = 90 }
            , playing = False
            , playhead = Nothing
            , listening = False
            , earMessage = ""
            , heard = Nothing
            , missHold = False
            , missToken = 0
            , seed = Random.initialSeed seed
            }
    in
    case D.decodeValue savedDecoder saved of
        Ok s ->
            applySaved s fresh |> openMoreIfNeeded

        Err _ ->
            fresh



-- SAVED CHART


type alias Saved =
    { style : Maybe String
    , bpm : Maybe Int
    , feel : Maybe Int
    , key : Maybe String
    , prog : Maybe String
    , chords : Maybe (List String)
    }


savedDecoder : D.Decoder Saved
savedDecoder =
    D.map6 Saved
        (D.maybe (D.field "style" D.string))
        (D.maybe (D.field "bpm" D.int))
        (D.maybe (D.field "feel" D.int))
        (D.maybe (D.field "key" D.string))
        (D.maybe (D.field "prog" D.string))
        (D.maybe (D.field "chords" (D.list D.string)))


{-| ASCII note names for storage, as everywhere caged writes a slug. -}
slugKeys : List String
slugKeys =
    [ "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" ]


keyFromSlug : String -> Maybe Int
keyFromSlug s =
    List.indexedMap Tuple.pair slugKeys
        |> List.filter (\( _, n ) -> n == s)
        |> List.head
        |> Maybe.map Tuple.first


chordCode : Bar -> String
chordCode b =
    (getAt b.root slugKeys |> Maybe.withDefault "C")
        ++ (if b.q == QMaj then
                ""

            else
                (qualInfo b.q).id
           )


parseChord : String -> Maybe Bar
parseChord code =
    let
        rootLen =
            if String.slice 1 2 code == "b" then
                2

            else
                1
    in
    Maybe.map2 Bar
        (keyFromSlug (String.left rootLen code))
        (case String.dropLeft rootLen code of
            "" ->
                Just QMaj

            id ->
                qualFromId id
        )


applySaved : Saved -> Model -> Model
applySaved s model =
    let
        style =
            s.style |> Maybe.andThen styleFromId |> Maybe.withDefault model.style

        info =
            styleInfo style

        key =
            s.key |> Maybe.andThen keyFromSlug |> Maybe.withDefault model.key

        chords =
            s.chords |> Maybe.withDefault [] |> List.map parseChord

        withChart m =
            if
                not (List.isEmpty chords)
                    && List.length chords
                    <= maxBars
                    && List.all ((/=) Nothing) chords
            then
                { m | source = Custom, bars = List.filterMap identity chords }

            else
                case s.prog |> Maybe.andThen presetById of
                    Just p ->
                        { m | source = FromPreset p.id, bars = barsFromPreset m.moreOpen p.id key }

                    Nothing ->
                        m
    in
    withChart
        { model
            | style = style
            , bpm = s.bpm |> Maybe.map (clamp 40 200) |> Maybe.withDefault info.bpm
            , feel =
                case ( style, s.feel ) of
                    ( Ballad, _ ) ->
                        info.feel

                    ( _, Just f ) ->
                        clamp 0 100 f

                    _ ->
                        info.feel
            , key = key
        }


encodeSave : Model -> E.Value
encodeSave model =
    E.object
        ([ ( "style", E.string (styleInfo model.style).id )
         , ( "bpm", E.int model.bpm )
         , ( "feel", E.int model.feel )
         , ( "key", E.string (getAt model.key slugKeys |> Maybe.withDefault "A") )
         ]
            ++ (case model.source of
                    FromPreset id ->
                        [ ( "prog", E.string id ) ]

                    _ ->
                        [ ( "chords", E.list (chordCode >> E.string) model.bars ) ]
               )
        )


{-| What band.js needs to play: the chart and how to play it. -}
encodeBand : Model -> E.Value
encodeBand model =
    let
        fader c =
            E.float (toFloat (level c model.mix) / 100)
    in
    E.object
        [ ( "style", E.string (styleInfo model.style).id )
        , ( "bpm", E.int model.bpm )
        , ( "feel", E.int model.feel )
        , ( "bars"
          , E.list
                (\b -> E.object [ ( "root", E.int b.root ), ( "q", E.string (qualInfo b.q).id ) ])
                model.bars
          )
        , ( "mix"
          , E.object
                [ ( "drums", fader Drums )
                , ( "bass", fader Bass )
                , ( "keys", fader Keys )
                , ( "guitar", fader Guitar )
                , ( "master", fader Master )
                ]
          )
        ]


command : String -> List ( String, E.Value ) -> Cmd msg
command kind fields =
    bandOut (E.object (( "type", E.string kind ) :: fields))



-- UPDATE


type Msg
    = TogglePlay
    | SetStyle Style
    | SetBpm String
    | SetFeel String
    | SetKey String
    | SetPreset String
    | SetCount Int
    | Generate Int
    | Select Int
    | Step Int
    | SetRoot Int
    | NudgeRoot Int
    | SetQuality Quality
    | NudgeQuality Int
    | FlipMinor
    | ToggleMore
    | SetMix Channel String
    | ToggleListen
    | FromBand D.Value
    | MissExpired Int


{-| Every change that reaches the band is sent to it at once (so it is heard
on the next beat) and saved. -}
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        ( next, cmd ) =
            step msg model
                |> Tuple.mapFirst openMoreIfNeeded

        heardBy m =
            ( m.style, ( m.bpm, m.feel, m.key ), ( m.source, m.bars, m.mix ) )
    in
    if heardBy next /= heardBy model then
        ( next
        , Cmd.batch
            [ cmd
            , command "state" [ ( "band", encodeBand next ), ( "save", encodeSave next ) ]
            ]
        )

    else
        ( next, cmd )


{-| A chord type beyond the basic three, selected, opens the rest of them. -}
openMoreIfNeeded : Model -> Model
openMoreIfNeeded model =
    if (qualInfo (currentBarAt model.selected model).q).basic then
        model

    else
        { model | moreOpen = True }


currentBarAt : Int -> Model -> Bar
currentBarAt i model =
    getAt i model.bars |> Maybe.withDefault { root = model.key, q = QMaj }


step : Msg -> Model -> ( Model, Cmd Msg )
step msg model =
    let
        selectedBar =
            currentBarAt model.selected model
    in
    case msg of
        TogglePlay ->
            ( model
            , if model.playing then
                command "stop" []

              else
                command "play" [ ( "band", encodeBand model ) ]
            )

        SetStyle s ->
            ( { model | style = s, bpm = (styleInfo s).bpm, feel = (styleInfo s).feel }, Cmd.none )

        SetBpm v ->
            ( { model | bpm = String.toInt v |> Maybe.withDefault model.bpm |> clamp 40 200 }, Cmd.none )

        SetFeel v ->
            ( { model | feel = String.toInt v |> Maybe.withDefault model.feel |> clamp 0 100 }, Cmd.none )

        SetKey v ->
            case String.toInt v of
                Just k ->
                    ( setKey (modBy 12 k) model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        SetPreset id ->
            case presetById id of
                Just _ ->
                    ( clampSelected
                        { model
                            | source = FromPreset id
                            , bars = barsFromPreset model.moreOpen id model.key
                        }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        SetCount n ->
            ( setCount n model, Cmd.none )

        Generate k ->
            ( generate (List.length model.bars) k model, Cmd.none )

        Select i ->
            ( clampSelected { model | selected = i }, Cmd.none )

        Step d ->
            ( clampSelected { model | selected = model.selected + d }, Cmd.none )

        SetRoot r ->
            ( setChord { selectedBar | root = modBy 12 r } model, Cmd.none )

        NudgeRoot d ->
            ( setChord { selectedBar | root = modBy 12 (selectedBar.root + d) } model, Cmd.none )

        SetQuality q ->
            ( setChord { selectedBar | q = q } model, Cmd.none )

        NudgeQuality d ->
            -- step through the chord types on offer: the basic three, or all of them when open
            let
                offered =
                    List.filter (\t -> model.moreOpen || (qualInfo t).basic) qualities

                idx =
                    case indexOf selectedBar.q offered of
                        Just i ->
                            i

                        Nothing ->
                            if d > 0 then
                                -1

                            else
                                0

                q =
                    getAt (modBy (List.length offered) (idx + d)) offered |> Maybe.withDefault selectedBar.q
            in
            ( setChord { selectedBar | q = q } model, Cmd.none )

        FlipMinor ->
            -- between major and minor, keeping a seventh or sixth where it can
            let
                q =
                    case selectedBar.q of
                        QMin ->
                            QMaj

                        QMin7 ->
                            Q7

                        QMin6 ->
                            Q6

                        Q6 ->
                            if model.moreOpen then
                                QMin6

                            else
                                QMin

                        other ->
                            if List.member other [ Q7, Q9, Q13, Q7s9, Q7b9, QMaj7 ] && model.moreOpen then
                                QMin7

                            else
                                QMin
            in
            ( setChord { selectedBar | q = q } model, Cmd.none )

        ToggleMore ->
            ( { model | moreOpen = not model.moreOpen }, Cmd.none )

        SetMix c v ->
            ( { model | mix = setLevel c (String.toInt v |> Maybe.withDefault 0 |> clamp 0 100) model.mix }, Cmd.none )

        ToggleListen ->
            ( { model | earMessage = "" }
            , command
                (if model.listening then
                    "unlisten"

                 else
                    "listen"
                )
                []
            )

        FromBand value ->
            fromBand value model

        MissExpired token ->
            if token == model.missToken then
                ( { model | missHold = False }, Cmd.none )

            else
                ( model, Cmd.none )


fromBand : D.Value -> Model -> ( Model, Cmd Msg )
fromBand value model =
    let
        field name dec =
            D.decodeValue (D.field name dec) value
    in
    case field "type" D.string of
        Ok "playing" ->
            ( { model | playing = field "on" D.bool |> Result.withDefault False, playhead = Nothing }, Cmd.none )

        Ok "beat" ->
            case ( field "bar" D.int, field "beat" D.int ) of
                ( Ok bar, Ok beat ) ->
                    ( { model | playhead = Just { bar = bar, beat = beat } }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        Ok "ear" ->
            ( { model
                | listening = field "on" D.bool |> Result.withDefault False
                , earMessage = field "message" D.string |> Result.withDefault ""
              }
            , Cmd.none
            )

        Ok "heard" ->
            let
                heard =
                    field "pc" D.int
                        |> Result.toMaybe
                        |> Maybe.andThen
                            (\pc ->
                                if pc < 0 then
                                    Nothing

                                else
                                    Just pc
                            )

                wasOut =
                    Maybe.map (roleOf model) model.heard == Just Outside

                isOut =
                    Maybe.map (roleOf model) heard == Just Outside
            in
            if wasOut && not isOut then
                -- the wrong note stopped: keep the flash a moment, so a quick one still shows
                ( { model | heard = heard, missHold = True, missToken = model.missToken + 1 }
                , Process.sleep 150 |> Task.perform (\_ -> MissExpired (model.missToken + 1))
                )

            else
                ( { model | heard = heard }, Cmd.none )

        _ ->
            ( model, Cmd.none )


clampSelected : Model -> Model
clampSelected model =
    { model | selected = clamp 0 (List.length model.bars - 1) model.selected }


setChord : Bar -> Model -> Model
setChord bar model =
    followKey { model | bars = setAt model.selected bar model.bars, source = Custom }


setCount : Int -> Model -> Model
setCount n0 model =
    let
        n =
            clamp minBars maxBars n0

        last =
            List.reverse model.bars |> List.head |> Maybe.withDefault { root = model.key, q = Q7 }
    in
    if model.source == Generated then
        generate n (distinctChords model.bars) model

    else
        clampSelected
            { model
                | bars = List.take n (model.bars ++ List.repeat (n - List.length model.bars) last)
                , source = Custom
            }


generate : Int -> Int -> Model -> Model
generate n k model =
    let
        ( bars, seed ) =
            writeChart n k model.key model.style model.seed
    in
    clampSelected { model | source = Generated, bars = simplify model.moreOpen bars, seed = seed }


setKey : Int -> Model -> Model
setKey k model =
    case model.source of
        FromPreset id ->
            { model | key = k, bars = barsFromPreset model.moreOpen id k }

        _ ->
            { model
                | key = k
                , bars =
                    model.bars
                        |> List.map (\b -> { b | root = modBy 12 (b.root + k - model.key) })
                        |> simplify model.moreOpen
            }



-- SUBSCRIPTIONS


{-| The keyboard is the panel's only while it is open. -}
subscriptions : Bool -> Model -> Sub Msg
subscriptions open _ =
    Sub.batch
        [ bandIn FromBand
        , if open then
            Browser.Events.onKeyDown keyDecoder

          else
            Sub.none
        ]


{-| Space plays and stops; ← → move between bars; ↑ ↓ change the note, with
Shift the chord type; A–G name the note; M flips major and minor. Keys typed
into a form control are theirs. -}
keyDecoder : D.Decoder Msg
keyDecoder =
    D.map6
        (\key shift meta ctrl alt tag ->
            if meta || ctrl || alt || List.member tag [ "INPUT", "SELECT", "TEXTAREA" ] then
                Nothing

            else
                case key of
                    " " ->
                        Just TogglePlay

                    "ArrowRight" ->
                        Just (Step 1)

                    "ArrowLeft" ->
                        Just (Step -1)

                    "ArrowUp" ->
                        Just
                            (if shift then
                                NudgeQuality 1

                             else
                                NudgeRoot 1
                            )

                    "ArrowDown" ->
                        Just
                            (if shift then
                                NudgeQuality -1

                             else
                                NudgeRoot -1
                            )

                    _ ->
                        case String.toUpper key of
                            "M" ->
                                Just FlipMinor

                            letter ->
                                letterPitch letter |> Maybe.map SetRoot
        )
        (D.field "key" D.string)
        (D.field "shiftKey" D.bool)
        (D.field "metaKey" D.bool)
        (D.field "ctrlKey" D.bool)
        (D.field "altKey" D.bool)
        (D.oneOf [ D.at [ "target", "tagName" ] D.string, D.succeed "" ])
        |> D.andThen (Maybe.map D.succeed >> Maybe.withDefault (D.fail "not ours"))


letterPitch : String -> Maybe Int
letterPitch letter =
    Dict.fromList [ ( "C", 0 ), ( "D", 2 ), ( "E", 4 ), ( "F", 5 ), ( "G", 7 ), ( "A", 9 ), ( "B", 11 ) ]
        |> Dict.get letter



-- VIEW


{-| The panel, capped at `maxWidth` (the neck's width) like the other
drawers. -}
view : Float -> Model -> Html Msg
view maxWidth model =
    div
        [ A.class "no-print practice-panel"
        , style "background" "var(--surface)"
        , style "border" "1px solid var(--surface-bd)"
        , style "border-radius" "10px"
        , style "padding" "10px 12px 12px"
        , style "margin-bottom" "10px"
        , style "max-width" (String.fromFloat maxWidth ++ "px")
        , style "box-sizing" "border-box"
        , style "display" "grid"
        , style "gap" "10px"
        ]
        [ transport model
        , controls model
        , chart model
        , div [ style "display" "flex", style "flex-wrap" "wrap", style "gap" "10px" ]
            [ editor model, mixer model ]
        ]


transport : Model -> Html Msg
transport model =
    div [ style "display" "flex", style "align-items" "center", style "gap" "12px", style "flex-wrap" "wrap" ]
        [ playButton model
        , span [ style "display" "inline-flex", style "align-items" "center", style "gap" "8px", style "font-size" "14px" ]
            [ span
                [ style "width" "10px"
                , style "height" "10px"
                , style "border-radius" "50%"
                , style "background"
                    (if model.playing then
                        "var(--btn-on-bg)"

                     else
                        "var(--surface-bd)"
                    )
                ]
                []
            , span [ style "color" "var(--text-2)", style "font-variant-numeric" "tabular-nums" ] (status model)
            ]
        , span [ style "flex" "1" ] []
        , if String.isEmpty model.earMessage then
            text ""

          else
            span [ style "font-size" "13px", style "color" "var(--text-2)" ] [ text model.earMessage ]
        , heardNote model
        , button
            ([ onClick ToggleListen
             , A.title "Listen through the microphone and flash red on notes outside the key"
             , attribute "aria-pressed" (boolString model.listening)
             ]
                ++ btn model.listening
            )
            [ text
                (if model.listening then
                    "Listening"

                 else
                    "Listen"
                )
            ]
        ]


status : Model -> List (Html Msg)
status model =
    case ( model.playing, model.playhead ) of
        ( False, _ ) ->
            [ text "Ready" ]

        ( True, Nothing ) ->
            [ text "Counting in" ]

        ( True, Just ph ) ->
            [ text "Bar "
            , strong (String.fromInt (currentIndex model + 1))
            , text " · beat "
            , strong (String.fromInt (ph.beat + 1))
            , text " · "
            , strong (chordName (currentBar model))
            ]


strong : String -> Html msg
strong s =
    span [ style "color" "var(--text)", style "font-weight" "600" ] [ text s ]


heardNote : Model -> Html Msg
heardNote model =
    case ( model.listening, model.heard ) of
        ( True, Just pc ) ->
            span
                [ style "font-size" "22px"
                , style "font-weight" "600"
                , style "min-width" "2.2ch"
                , style "text-align" "center"
                , style "color"
                    (case roleOf model pc of
                        ChordTone ->
                            "var(--hit)"

                        Outside ->
                            "var(--miss)"

                        _ ->
                            "var(--text)"
                    )
                ]
                [ text (noteName pc) ]

        ( True, Nothing ) ->
            span [ style "min-width" "2.2ch" ] []

        _ ->
            text ""


playButton : Model -> Html Msg
playButton model =
    button
        [ onClick TogglePlay
        , attribute "aria-label"
            (if model.playing then
                "Stop"

             else
                "Play"
            )
        , style "width" "44px"
        , style "height" "44px"
        , style "border-radius" "50%"
        , style "border" "0"
        , style "cursor" "pointer"
        , style "display" "grid"
        , style "place-items" "center"
        , style "background" "var(--btn-on-bg)"
        , style "color" "var(--btn-on-text)"
        , style "box-shadow"
            (if model.playing then
                "0 0 0 3px var(--surface), 0 0 0 5px var(--btn-on-bg)"

             else
                "none"
            )
        ]
        [ Svg.svg [ SA.viewBox "0 0 24 24", SA.width "20", SA.height "20", SA.fill "currentColor" ]
            [ if model.playing then
                Svg.rect [ SA.x "5", SA.y "5", SA.width "14", SA.height "14", SA.rx "1.5" ] []

              else
                Svg.path [ SA.d "M7 4v16l13-8z" ] []
            ]
        ]


controls : Model -> Html Msg
controls model =
    let
        variety =
            distinctChords model.bars

        n =
            List.length model.bars
    in
    div [ style "display" "flex", style "flex-wrap" "wrap", style "gap" "8px" ]
        [ card "Style"
            [ div [ style "display" "flex", style "flex-wrap" "wrap", style "row-gap" "4px" ]
                (List.map
                    (\s -> button (onClick (SetStyle s) :: btn (s == model.style)) [ text (styleInfo s).name ])
                    styles
                )
            , div [ style "font-size" "12px", style "color" "var(--text-2)", style "margin-top" "5px" ]
                [ text (styleInfo model.style).hint ]
            ]
        , card "Tempo"
            [ div [ style "font-size" "18px", style "font-weight" "600", style "font-variant-numeric" "tabular-nums" ]
                [ text (String.fromInt model.bpm)
                , span [ style "font-size" "12px", style "color" "var(--text-2)", style "font-weight" "500" ] [ text " bpm" ]
                ]
            , slider 40 200 model.bpm SetBpm False
            ]
        , card "Feel"
            [ div [ style "font-size" "13px", style "margin-bottom" "2px" ] [ text (feelName model) ]
            , slider 0 100 model.feel SetFeel (model.style == Ballad)
            , div
                [ style "display" "flex"
                , style "justify-content" "space-between"
                , style "font-size" "11px"
                , style "color" "var(--text-2)"
                ]
                [ span [] [ text "Straight" ], span [] [ text "Shuffle" ] ]
            ]
        , card "Key"
            [ dropdown SetKey
                (String.fromInt model.key)
                (List.map (\pc -> ( String.fromInt pc, noteName pc )) (List.range 0 11))
            ]
        , card "Progression"
            [ dropdown SetPreset
                (case model.source of
                    FromPreset id ->
                        id

                    Custom ->
                        "custom"

                    Generated ->
                        "generated"
                )
                (List.map (\p -> ( p.id, capitalize p.name )) presets
                    ++ (case model.source of
                            Custom ->
                                [ ( "custom", "Custom" ) ]

                            Generated ->
                                [ ( "generated", "Made up" ) ]

                            FromPreset _ ->
                                []
                       )
                )
            ]
        , card "Bars"
            [ stepper "One bar fewer" "One bar more" n (n > minBars) (n < maxBars) (SetCount (n - 1)) (SetCount (n + 1)) ]
        , card "Different chords"
            [ stepper "One chord type fewer"
                "One chord type more"
                variety
                (variety > 1)
                (variety < maxVariety n)
                (Generate (variety - 1))
                (Generate (variety + 1))
            , button (onClick (Generate variety) :: btn False ++ [ style "margin-top" "5px" ])
                [ text "Write me a new chart" ]
            ]
        ]


feelName : Model -> String
feelName model =
    if model.style == Ballad then
        "Triplets"

    else if model.feel < 20 then
        "Straight 8ths"

    else if model.feel < 60 then
        "Light swing"

    else
        "Shuffle"


chart : Model -> Html Msg
chart model =
    let
        miss =
            model.missHold
                || (model.listening && Maybe.map (roleOf model) model.heard == Just Outside)

        title =
            noteName model.key
                ++ " "
                ++ (case model.source of
                        FromPreset id ->
                            presetById id |> Maybe.map .name |> Maybe.withDefault "blues"

                        _ ->
                            "blues"
                   )

        n =
            List.length model.bars
    in
    div
        [ attribute "aria-label" "Chord chart"
        , style "background" "var(--group-bg)"
        , style "border-radius" "8px"
        , style "padding" "8px 10px 10px"
        , style "box-shadow"
            (if miss then
                "0 0 0 3px var(--miss)"

             else
                "none"
            )
        , style "transition" "box-shadow 0.12s"
        ]
        [ div
            [ style "display" "flex"
            , style "justify-content" "space-between"
            , style "align-items" "baseline"
            , style "flex-wrap" "wrap"
            , style "gap" "4px 16px"
            , style "margin-bottom" "8px"
            ]
            [ span [ style "font-size" "18px", style "font-weight" "600" ] [ text title ]
            , span [ style "display" "flex", style "gap" "14px", style "font-size" "13px", style "color" "var(--text-2)" ]
                (List.map (\s -> span [] [ text s ])
                [ ((if model.style == Ballad then
                        "♩. = "

                      else
                        "♩ = "
                     )
                        ++ String.fromInt model.bpm
                    )
                , (styleInfo model.style).short
                , feelName model
                , (String.fromInt n
                        ++ (if n == 1 then
                                " bar"

                            else
                                " bars"
                           )
                    )
                ])
            ]
        , div
            [ attribute "role" "list"
            , style "display" "grid"
            , style "grid-template-columns" "repeat(4, minmax(0, 1fr))"
            , style "gap" "6px"
            ]
            (List.indexedMap (barView model) model.bars)
        , notesStrip model
        ]


barView : Model -> Int -> Bar -> Html Msg
barView model i bar =
    let
        current =
            model.playing && model.playhead /= Nothing && currentIndex model == i

        selected =
            i == model.selected

        beat =
            Maybe.map .beat model.playhead |> Maybe.withDefault -1

        info =
            qualInfo bar.q
    in
    button
        [ onClick (Select i)
        , attribute "role" "listitem"
        , attribute "aria-pressed" (boolString selected)
        , attribute "aria-label"
            ("Bar " ++ String.fromInt (i + 1) ++ ": " ++ noteName bar.root ++ " " ++ info.name ++ ", " ++ numeral model.key bar)
        , style "display" "grid"
        , style "gap" "4px"
        , style "justify-items" "start"
        , style "text-align" "left"
        , style "padding" "6px 9px 7px"
        , style "border" "1px solid var(--btn-bd)"
        , style "border-radius" "6px"
        , style "cursor" "pointer"
        , style "font-family" "inherit"
        , style "min-width" "0"

        -- the bar being edited is a selected button, like every other one on the page
        , style "background"
            (if selected then
                "var(--btn-on-bg)"

             else
                "var(--btn-bg)"
            )
        , style "color"
            (if selected then
                "var(--btn-on-text)"

             else
                "var(--btn-text)"
            )

        -- the bar the band is on gets a ring around it, clear of the button
        , style "box-shadow"
            (if current then
                "0 0 0 2px var(--group-bg), 0 0 0 4px var(--btn-on-bg)"

             else
                "none"
            )
        ]
        [ span [ style "font-size" "12px", style "opacity" "0.7", style "white-space" "nowrap" ] [ text (numeral model.key bar) ]
        , span [ style "font-size" "24px", style "font-weight" "600", style "line-height" "1", style "white-space" "nowrap" ]
            [ text (noteName bar.root)
            , span [ style "font-size" "14px", style "vertical-align" "0.5em", style "font-weight" "500" ] [ text info.label ]
            ]
        , span [ style "display" "flex", style "gap" "5px" ]
            (List.map
                (\k ->
                    span
                        [ style "width" "7px"
                        , style "height" "7px"
                        , style "border-radius" "50%"
                        , style "border" "1.5px solid currentColor"
                        , style "opacity"
                            (if current && k <= beat then
                                "1"

                             else
                                "0.45"
                            )
                        , style "background"
                            (if current && k <= beat then
                                "currentColor"

                             else
                                "transparent"
                            )
                        ]
                        []
                )
                (List.range 0 3)
            )
        ]


{-| All twelve notes from the key up, each marked with what it is over the
chord being played: a chord tone, in the key, a blue note, or outside. -}
notesStrip : Model -> Html Msg
notesStrip model =
    let
        bar =
            currentBar model

        tones =
            chordTones bar

        legendChip extra label =
            span [ style "display" "inline-flex", style "align-items" "center", style "gap" "4px" ]
                [ span
                    ([ style "width" "10px"
                     , style "height" "10px"
                     , style "border-radius" "2px"
                     , style "border" "1px solid var(--note-bd)"
                     , style "background" "var(--note-bg)"
                     ]
                        ++ extra
                    )
                    []
                , text label
                ]
    in
    div [ style "margin-top" "10px" ]
        [ div
            [ style "display" "flex"
            , style "justify-content" "space-between"
            , style "align-items" "baseline"
            , style "flex-wrap" "wrap"
            , style "gap" "4px 14px"
            , style "margin-bottom" "6px"
            , style "font-size" "12px"
            , style "color" "var(--text-2)"
            ]
            [ span [] [ text "Notes over ", strong (chordName bar) ]
            , span [ style "display" "flex", style "gap" "12px", style "flex-wrap" "wrap" ]
                [ legendChip [ style "background" "var(--root-bg)", style "border-color" "var(--root-bg)" ] "Chord root"
                , legendChip [ style "border" "2px solid var(--chord-bd)" ] "Chord tone"
                , legendChip [] "In the key"
                , legendChip [ style "border-style" "dashed" ] "Blue note"
                , legendChip [ style "border-style" "dotted", style "opacity" "0.45", style "background" "transparent" ] "Outside"
                ]
            ]
        , div
            [ attribute "role" "list"
            , attribute "aria-label" "Notes for the current chord"
            , style "display" "grid"
            , style "grid-template-columns" "repeat(12, minmax(0, 1fr))"
            , style "gap" "4px"
            ]
            (List.map (noteCell model tones) (List.range 0 11))
        ]


noteCell : Model -> Dict Int String -> Int -> Html Msg
noteCell model tones d =
    let
        pc =
            modBy 12 (model.key + d)

        role =
            roleOf model pc

        heard =
            model.listening && model.heard == Just pc

        chordRoot =
            role == ChordTone && pc == (currentBar model).root

        ( label, roleStyles ) =
            case role of
                ChordTone ->
                    if chordRoot then
                        ( "chord root"
                        , [ style "background" "var(--root-bg)"
                          , style "border-color" "var(--root-bg)"
                          , style "color" "var(--root-text)"
                          ]
                        )

                    else
                        ( "chord tone", [ style "border" "2px solid var(--chord-bd)", style "padding" "3px 0 4px" ] )

                InKey ->
                    ( "in the key", [] )

                BlueNote ->
                    ( "blue note", [ style "border-style" "dashed" ] )

                Outside ->
                    ( "outside"
                    , [ style "border-style" "dotted"
                      , style "background" "transparent"
                      , style "opacity"
                            (if heard then
                                "1"

                             else
                                "0.4"
                            )
                      ]
                    )

        ring =
            if not heard then
                []

            else
                case role of
                    ChordTone ->
                        [ style "box-shadow" "0 0 0 3px var(--hit)" ]

                    Outside ->
                        [ style "box-shadow" "0 0 0 3px var(--miss)"
                        , style "background" "color-mix(in srgb, var(--miss) 25%, var(--note-bg))"
                        ]

                    _ ->
                        [ style "box-shadow" "0 0 0 3px var(--text)" ]
    in
    div
        ([ attribute "role" "listitem"
         , attribute "aria-label" (noteName pc ++ ", " ++ label)
         , style "text-align" "center"
         , style "padding" "4px 0 5px"
         , style "border-radius" "4px"
         , style "border" "1px solid var(--note-bd)"
         , style "background" "var(--note-bg)"
         , style "color" "var(--note-text)"
         , style "min-width" "0"
         , style "transition" "background 0.12s, box-shadow 0.08s, opacity 0.12s"
         ]
            ++ roleStyles
            ++ ring
        )
        [ div [ style "font-size" "10px", style "font-weight" "600", style "height" "12px", style "line-height" "12px" ]
            [ text (Dict.get pc tones |> Maybe.withDefault "") ]
        , div [ style "font-size" "17px", style "font-weight" "600", style "line-height" "1.2" ] [ text (noteName pc) ]
        , div [ style "font-size" "10px", style "opacity" "0.65" ]
            [ text (Array.get d keyDegrees |> Maybe.withDefault "") ]
        ]


editor : Model -> Html Msg
editor model =
    let
        bar =
            currentBarAt model.selected model

        qualButton q =
            let
                info =
                    qualInfo q

                on =
                    q == bar.q
            in
            button
                (onClick (SetQuality q)
                    :: btn on
                    ++ [ style "display" "inline-grid", style "justify-items" "start", style "gap" "2px", style "margin-bottom" "4px" ]
                )
                [ span [ style "font-size" "15px" ]
                    [ text (noteName bar.root)
                    , span [ style "font-size" "10px", style "vertical-align" "0.5em" ] [ text info.label ]
                    ]
                , span [ style "font-size" "11px", style "opacity" "0.7" ] [ text info.name ]
                ]
    in
    div [ style "flex" "1 1 420px", style "min-width" "0" ]
        [ card ("Editing bar " ++ String.fromInt (model.selected + 1) ++ " · " ++ chordName bar ++ " · " ++ numeral model.key bar)
            [ div [ style "font-size" "12px", style "color" "var(--text-2)", style "margin-bottom" "8px", style "line-height" "1.5" ]
                [ text "Click a bar to change its chord. ← → move between bars, ↑ ↓ change the note, with Shift the chord type. A–G name the note, M flips major and minor, Space plays and stops." ]
            , caption "Note"
            , div [ style "display" "flex", style "flex-wrap" "wrap", style "row-gap" "4px", style "margin-bottom" "8px" ]
                (List.map (\pc -> button (onClick (SetRoot pc) :: btn (pc == bar.root) ++ [ style "min-width" "40px" ]) [ text (noteName pc) ])
                    (List.range 0 11)
                )
            , caption "Chord"
            , div [ style "display" "flex", style "flex-wrap" "wrap" ]
                (List.map qualButton (List.filter (qualInfo >> .basic) qualities))
            , button
                [ onClick ToggleMore
                , attribute "aria-expanded" (boolString model.moreOpen)
                , A.title "While this is shut, new charts use only major, minor and seventh chords"
                , style "border" "0"
                , style "background" "none"
                , style "padding" "4px 0"
                , style "cursor" "pointer"
                , style "font" "inherit"
                , style "font-size" "13px"
                , style "color" "var(--text-2)"
                , style "text-decoration" "underline"
                ]
                [ text
                    (if model.moreOpen then
                        "Fewer chord types ▴"

                     else
                        "More chord types ▾"
                    )
                ]
            , if model.moreOpen then
                div [ style "display" "flex", style "flex-wrap" "wrap", style "margin-top" "4px" ]
                    (List.map qualButton (List.filter (qualInfo >> .basic >> not) qualities))

              else
                text ""
            ]
        ]


mixer : Model -> Html Msg
mixer model =
    div [ style "flex" "0 1 260px", style "min-width" "200px" ]
        [ card "Band"
            (List.map
                (\( c, name ) ->
                    div
                        [ style "display" "grid"
                        , style "grid-template-columns" "56px 1fr"
                        , style "align-items" "center"
                        , style "gap" "8px"
                        ]
                        [ span [ style "font-size" "12px", style "color" "var(--text-2)" ] [ text name ]
                        , slider 0 100 (level c model.mix) (SetMix c) False
                        ]
                )
                channels
            )
        ]



-- VIEW HELPERS


{-| A tinted card with its name on top, like the scale picker's families. -}
card : String -> List (Html msg) -> Html msg
card name children =
    div
        [ style "background" "var(--group-bg)"
        , style "border-radius" "8px"
        , style "padding" "6px 8px 8px"
        , style "min-width" "0"
        ]
        (caption name :: children)


caption : String -> Html msg
caption name =
    div
        [ style "font-size" "11px"
        , style "color" "var(--text-2)"
        , style "font-weight" "600"
        , style "text-transform" "uppercase"
        , style "letter-spacing" "0.06em"
        , style "margin" "0 0 5px 1px"
        ]
        [ text name ]


{-| The same button as everywhere else on the page (`buttonBaseStyle`). -}
btn : Bool -> List (Html.Attribute msg)
btn active =
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


slider : Int -> Int -> Int -> (String -> msg) -> Bool -> Html msg
slider lo hi value toMsg disabled =
    input
        [ A.type_ "range"
        , A.min (String.fromInt lo)
        , A.max (String.fromInt hi)
        , A.value (String.fromInt value)
        , A.disabled disabled
        , onInput toMsg
        , style "width" "100%"
        , style "min-width" "110px"
        , style "margin" "4px 0"
        , style "accent-color" "var(--btn-on-bg)"
        , style "opacity"
            (if disabled then
                "0.35"

             else
                "1"
            )
        ]
        []


dropdown : (String -> msg) -> String -> List ( String, String ) -> Html msg
dropdown toMsg current options =
    Html.select
        [ onInput toMsg
        , style "font" "inherit"
        , style "font-size" "14px"
        , style "padding" "5px 8px"
        , style "border" "1px solid var(--btn-bd)"
        , style "border-radius" "6px"
        , style "background" "var(--btn-bg)"
        , style "color" "var(--btn-text)"
        , style "min-width" "120px"
        ]
        (List.map (\( v, label ) -> option [ A.value v, A.selected (v == current) ] [ text label ]) options)


stepper : String -> String -> Int -> Bool -> Bool -> msg -> msg -> Html msg
stepper lessLabel moreLabel value canLess canMore less more =
    let
        side label enabled msg glyph =
            button
                (onClick msg
                    :: attribute "aria-label" label
                    :: A.disabled (not enabled)
                    :: btn False
                    ++ [ style "margin" "0"
                       , style "min-width" "34px"
                       , style "opacity"
                            (if enabled then
                                "1"

                             else
                                "0.4"
                            )
                       ]
                )
                [ text glyph ]
    in
    span [ style "display" "inline-flex", style "align-items" "center", style "gap" "8px" ]
        [ side lessLabel canLess less "−"
        , span [ style "min-width" "2ch", style "text-align" "center", style "font-size" "16px", style "font-weight" "600" ]
            [ text (String.fromInt value) ]
        , side moreLabel canMore more "+"
        ]


capitalize : String -> String
capitalize s =
    String.toUpper (String.left 1 s) ++ String.dropLeft 1 s


boolString : Bool -> String
boolString b =
    if b then
        "true"

    else
        "false"



-- LISTS


getAt : Int -> List a -> Maybe a
getAt i list =
    if i < 0 then
        Nothing

    else
        List.head (List.drop i list)


setAt : Int -> a -> List a -> List a
setAt i x =
    List.indexedMap
        (\j y ->
            if j == i then
                x

            else
                y
        )


indexOf : a -> List a -> Maybe Int
indexOf x list =
    List.indexedMap Tuple.pair list
        |> List.filter (\( _, y ) -> y == x)
        |> List.head
        |> Maybe.map Tuple.first
