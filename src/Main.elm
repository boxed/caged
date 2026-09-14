port module Main exposing
    ( ScaleType(..)
    , StringSet(..)
    , Tuning
    , deriveBox
    , diagonalAnchor
    , diagonalShapes
    , diagonalShapesFor
    , main
    , noteAt
    , openAbs
    , openString
    , rootSpelling
    , scaleDegrees
    , scaleIntervals
    , spell
    , standardTuning
    , triadVoicingsFor
    , tunings
    )

import Browser
import Browser.Events
import Browser.Navigation as Nav
import Html exposing (Html, button, div, h1, p, span, text)
import Html.Attributes exposing (style)
import Html.Events exposing (onClick)
import Json.Decode as Decode
import Svg
import Svg.Attributes as SA
import Url exposing (Url)



-- MODEL


type alias Model =
    { necks : List Neck
    , active : Int
    , drag : Maybe Drag
    , tuning : Tuning
    , tuningOpen : Bool
    , focus : Maybe Focus
    , key : Nav.Key
    , wakeLockOn : Bool
    }


{-| The stretch of neck you are practicing in, as an inclusive pair of frets —
the **Highlight shapes** row. Setting one fades every shape that does not fall
in it to gray, on every neck at once — so a C–Am–G–F progression played between frets 4 and 8 shows
you box 1, box 1, box 3 and box 4 in color and nothing else. Like the tuning it
belongs to the hand, not to one neck, so it lives on the model. -}
type alias Focus =
    ( Int, Int )


{-| One fretboard's worth of choices. The page draws a list of these, so a
minor pentatonic neck can sit above a major triad neck; the tuning is not in
here because it is a property of the instrument, shared by every neck. -}
type alias Neck =
    { root : Int
    , scale : ScaleType
    , stringSet : StringSet
    }


{-| A neck plus the tuning it is played in, which is everything the drawing
code needs. `id` namespaces the SVG ids this neck mints: ids live in one
document-wide namespace, so without a prefix a `url(#…)` reference would
resolve to whichever neck rendered first and every later neck would wear the
first one's stripe patterns and triad masks. -}
type alias Board =
    { root : Int
    , scale : ScaleType
    , stringSet : StringSet
    , tuning : Tuning
    , focus : Maybe Focus
    , id : String
    }


{-| A reorder in progress. `from` is where the grabbed neck started and `to`
where it would land, recomputed on every pointer move from the distance
dragged and `rowHeight`, the height of one neck row — read off the DOM when
the drag starts, since Elm cannot measure the page itself. The list is
rendered in the previewed order, so the neck follows the finger. -}
type alias Drag =
    { from : Int
    , to : Int
    , startY : Float
    , rowHeight : Float
    }


{-| A guitar tuning is fully described by its six open-string pitch classes,
ordered string 1 (high E in standard) down to string 6 (low E). Everything
else — which notes are in the scale, where the CAGED boxes land, how the
diagonal shapes climb — is derived from these six numbers at runtime. -}
type alias Tuning =
    { name : String
    , slug : String
    , strings : List Int
    }


port requestWakeLock : () -> Cmd msg


port releaseWakeLock : () -> Cmd msg


port wakeLockChanged : (Bool -> msg) -> Sub msg


type ScaleType
    = MajorPent
    | MinorPent
    | Ionian
    | Aeolian
    | Dorian
    | Mixolydian
    | Phrygian
    | Lydian
    | Locrian
    | Blues
    | HarmonicMajor
    | HarmonicMinor
    | MelodicMajor
    | MelodicMinor
    | ChromaticMajor
    | ChromaticMinor
    | TriadMajor
    | TriadMinor
    | TriadDim
    | TriadAug
    | DiagonalMajorPent
    | DiagonalPent
    | DiagonalBlues


{-| Which three adjacent strings carry the triad lassos. `StringTrio t` names a
set by its highest string `t` (1–4) — strings t, t+1 and t+2 — and `AllStrings`
draws all four sets at once. Only the triad modes use it. -}
type StringSet
    = AllStrings
    | StringTrio Int




type Msg
    = SetRoot Int
    | SetScale ScaleType
    | SetTuning Tuning
    | SetStringSet StringSet
    | TuneString Int Int
    | SetFocus (Maybe Focus)
    | ToggleTuningList
    | Activate Int
    | AddNeck
    | RemoveNeck Int
    | DragStart Int Float Float
    | DragMove Float
    | DragEnd
    | UrlChanged Url
    | LinkClicked Browser.UrlRequest
    | ToggleWakeLock
    | WakeLockChanged Bool


init : () -> Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    let
        state =
            parseUrl url
    in
    ( { necks = state.necks
      , active = state.active
      , drag = Nothing
      , tuning = state.tuning
      , tuningOpen = False
      , focus = state.focus
      , key = key
      , wakeLockOn = False
      }
    , Cmd.none
    )



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SetRoot n ->
            sync { model | necks = mapActive (\neck -> { neck | root = modBy 12 n }) model }

        SetScale sc ->
            sync { model | necks = mapActive (\neck -> { neck | scale = sc }) model }

        SetStringSet set ->
            sync { model | necks = mapActive (\neck -> { neck | stringSet = set }) model }

        SetTuning t ->
            -- Picking a preset is the end of the errand, so the list folds
            -- away again. Custom is not: the per-string steppers it reveals
            -- are the thing you opened the list for.
            sync { model | tuning = t, tuningOpen = isCustom t }

        ToggleTuningList ->
            ( { model | tuningOpen = not model.tuningOpen }, Cmd.none )

        TuneString s delta ->
            let
                newStrings =
                    List.indexedMap
                        (\i n ->
                            if i == s - 1 then
                                modBy 12 (n + delta)

                            else
                                n
                        )
                        model.tuning.strings
            in
            sync { model | tuning = customFrom newStrings }

        SetFocus f ->
            sync { model | focus = Maybe.map clampFocus f }

        Activate i ->
            sync { model | active = clampIndex model.necks i }

        AddNeck ->
            -- The copy lands right under the neck it came from and takes over
            -- as active, so the scale and root buttons retune the new one
            -- rather than the one you were looking at.
            let
                i =
                    clampIndex model.necks model.active
            in
            sync
                { model
                    | necks = insertAt (i + 1) (activeNeck model) model.necks
                    , active = i + 1
                }

        RemoveNeck i ->
            -- Refused down to nothing: an empty list would draw no necks at
            -- all and leave the buttons with nothing to edit.
            if List.length model.necks <= 1 then
                ( model, Cmd.none )

            else
                let
                    remaining =
                        List.take i model.necks ++ List.drop (i + 1) model.necks
                in
                sync
                    { model
                        | necks = remaining
                        , active =
                            clampIndex remaining
                                (if model.active > i then
                                    model.active - 1

                                 else
                                    model.active
                                )
                    }

        DragStart i y rowHeight ->
            ( { model
                | active = clampIndex model.necks i
                , drag = Just { from = i, to = i, startY = y, rowHeight = rowHeight }
              }
            , Cmd.none
            )

        DragMove y ->
            case model.drag of
                Nothing ->
                    ( model, Cmd.none )

                Just drag ->
                    -- Measured from where the grab started, not from the last
                    -- move, so previewing the reorder cannot feed back into
                    -- the arithmetic and make the neck chase the finger.
                    let
                        slots =
                            round ((y - drag.startY) / max 1 drag.rowHeight)
                    in
                    ( { model | drag = Just { drag | to = clampIndex model.necks (drag.from + slots) } }
                    , Cmd.none
                    )

        DragEnd ->
            case model.drag of
                Nothing ->
                    ( model, Cmd.none )

                Just drag ->
                    sync
                        { model
                            | necks = moveItem drag.from drag.to model.necks
                            , active = drag.to
                            , drag = Nothing
                        }

        UrlChanged url ->
            let
                state =
                    parseUrl url
            in
            ( { model
                | necks = state.necks
                , active = state.active
                , tuning = state.tuning
                , focus = state.focus
              }
            , Cmd.none
            )

        LinkClicked request ->
            case request of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        ToggleWakeLock ->
            let
                next =
                    not model.wakeLockOn

                cmd =
                    if next then
                        requestWakeLock ()

                    else
                        releaseWakeLock ()
            in
            ( { model | wakeLockOn = next }, cmd )

        WakeLockChanged on ->
            ( { model | wakeLockOn = on }, Cmd.none )



{-| Every state change reaches the URL, so the address bar is always a link to
exactly what is on screen. -}
sync : Model -> ( Model, Cmd Msg )
sync model =
    ( model, Nav.replaceUrl model.key (modelUrl model) )



-- URL SERIALIZATION


modelUrl : Model -> String
modelUrl model =
    let
        base =
            case model.necks of
                -- One neck writes the URL it always wrote, so every link ever
                -- shared of a single fretboard still reads the way it did.
                [ neck ] ->
                    "?root="
                        ++ rootSlug neck.root
                        ++ "&scale="
                        ++ scaleSlug neck.scale
                        ++ (if hasStringSet neck then
                                "&strings=" ++ stringSetSlug neck.stringSet

                            else
                                ""
                           )

                necks ->
                    "?necks="
                        ++ String.join "," (List.map neckSlug necks)
                        ++ (if model.active == 0 then
                                ""

                            else
                                "&active=" ++ String.fromInt model.active
                           )

        withTuning =
            if model.tuning.slug == standardTuning.slug then
                base

            else
                base ++ "&tuning=" ++ model.tuning.slug
    in
    case model.focus of
        Nothing ->
            withTuning

        Just ( lo, hi ) ->
            withTuning ++ "&focus=" ++ String.fromInt lo ++ "-" ++ String.fromInt hi


{-| One neck as `root.scale`, with the string set appended in the triad modes
that have one: `A.minor-pent`, `C.triad-major.2-3-4`. -}
neckSlug : Neck -> String
neckSlug neck =
    rootSlug neck.root ++ "." ++ scaleSlug neck.scale ++ triadStrings neck


{-| The string-set selector only exists in the triad modes, so it is only
written there; every other mode keeps the URL it always had. -}
hasStringSet : Neck -> Bool
hasStringSet neck =
    isTriad neck.scale && neck.stringSet /= AllStrings


triadStrings : Neck -> String
triadStrings neck =
    if hasStringSet neck then
        "." ++ stringSetSlug neck.stringSet

    else
        ""


neckFromSlug : String -> Maybe Neck
neckFromSlug str =
    case String.split "." str of
        [ r, sc ] ->
            Maybe.map2 (\root scale -> { root = root, scale = scale, stringSet = AllStrings })
                (rootFromSlug r)
                (scaleFromSlug sc)

        [ r, sc, set ] ->
            Maybe.map3 (\root scale stringSet -> { root = root, scale = scale, stringSet = stringSet })
                (rootFromSlug r)
                (scaleFromSlug sc)
                (stringSetFromSlug set)

        _ ->
            Nothing


rootSlug : Int -> String
rootSlug n =
    case modBy 12 n of
        0 -> "C"
        1 -> "Cs"
        2 -> "D"
        3 -> "Ds"
        4 -> "E"
        5 -> "F"
        6 -> "Fs"
        7 -> "G"
        8 -> "Gs"
        9 -> "A"
        10 -> "As"
        11 -> "B"
        _ -> "A"


rootFromSlug : String -> Maybe Int
rootFromSlug s =
    case s of
        "C" -> Just 0
        "Cs" -> Just 1
        "D" -> Just 2
        "Ds" -> Just 3
        "E" -> Just 4
        "F" -> Just 5
        "Fs" -> Just 6
        "G" -> Just 7
        "Gs" -> Just 8
        "A" -> Just 9
        "As" -> Just 10
        "B" -> Just 11
        _ -> Nothing


scaleSlug : ScaleType -> String
scaleSlug s =
    case s of
        MajorPent -> "major-pent"
        MinorPent -> "minor-pent"
        Ionian -> "ionian"
        Aeolian -> "aeolian"
        Dorian -> "dorian"
        Mixolydian -> "mixolydian"
        Phrygian -> "phrygian"
        Lydian -> "lydian"
        Locrian -> "locrian"
        Blues -> "blues"
        HarmonicMajor -> "harmonic-major"
        HarmonicMinor -> "harmonic-minor"
        MelodicMajor -> "melodic-major"
        MelodicMinor -> "melodic-minor"
        ChromaticMajor -> "all-notes-major"
        ChromaticMinor -> "all-notes-minor"
        TriadMajor -> "triad-major"
        TriadMinor -> "triad-minor"
        TriadDim -> "triad-dim"
        TriadAug -> "triad-aug"
        DiagonalMajorPent -> "diagonal-major-pent"
        DiagonalPent -> "diagonal-pent"
        DiagonalBlues -> "diagonal-blues"


scaleFromSlug : String -> Maybe ScaleType
scaleFromSlug s =
    case s of
        "major-pent" -> Just MajorPent
        "minor-pent" -> Just MinorPent
        "ionian" -> Just Ionian
        "aeolian" -> Just Aeolian
        "dorian" -> Just Dorian
        "mixolydian" -> Just Mixolydian
        "phrygian" -> Just Phrygian
        "lydian" -> Just Lydian
        "locrian" -> Just Locrian
        "blues" -> Just Blues
        "harmonic-major" -> Just HarmonicMajor
        "harmonic-minor" -> Just HarmonicMinor
        "melodic-major" -> Just MelodicMajor
        "melodic-minor" -> Just MelodicMinor
        "all-notes-major" -> Just ChromaticMajor
        "all-notes-minor" -> Just ChromaticMinor
        "triad-major" -> Just TriadMajor
        "triad-minor" -> Just TriadMinor
        "triad-dim" -> Just TriadDim
        "triad-aug" -> Just TriadAug
        -- The all-notes map used to be a single mode; keep old links working.
        "all-notes" -> Just ChromaticMinor
        "diagonal-major-pent" -> Just DiagonalMajorPent
        "diagonal-pent" -> Just DiagonalPent
        "diagonal-blues" -> Just DiagonalBlues
        _ -> Nothing


stringSetSlug : StringSet -> String
stringSetSlug set =
    case set of
        AllStrings ->
            "all"

        StringTrio t ->
            String.join "-" (List.map String.fromInt [ t, t + 1, t + 2 ])


stringSetFromSlug : String -> Maybe StringSet
stringSetFromSlug s =
    case s of
        "all" -> Just AllStrings
        "1-2-3" -> Just (StringTrio 1)
        "2-3-4" -> Just (StringTrio 2)
        "3-4-5" -> Just (StringTrio 3)
        "4-5-6" -> Just (StringTrio 4)
        _ -> Nothing


{-| Everything the URL carries: the list of necks, which of them the controls
edit, and the tuning they are all played in. -}
type alias UrlState =
    { necks : List Neck
    , active : Int
    , tuning : Tuning
    , focus : Maybe Focus
    }


parseUrl : Url -> UrlState
parseUrl url =
    let
        pairs =
            url.query
                |> Maybe.withDefault ""
                |> String.split "&"
                |> List.filterMap
                    (\pair ->
                        case String.split "=" pair of
                            [ k, v ] -> Just ( k, v )
                            _ -> Nothing
                    )

        lookup k =
            pairs
                |> List.filter (\( k2, _ ) -> k2 == k)
                |> List.head
                |> Maybe.map Tuple.second

        scale =
            lookup "scale"
                |> Maybe.andThen scaleFromSlug
                |> Maybe.withDefault MinorPent

        stringSet =
            lookup "strings"
                |> Maybe.andThen stringSetFromSlug
                |> Maybe.withDefault AllStrings

        single =
            { root =
                lookup "root"
                    |> Maybe.andThen rootFromSlug
                    |> Maybe.withDefault 9
            , scale = scale
            , stringSet = stringSet
            }

        -- `roots` is the old multi-root param: a list of roots all sharing one
        -- scale. It is still read so links from that version keep working; it
        -- is never written any more.
        legacyRoots =
            lookup "roots"
                |> Maybe.map (String.split "-" >> List.filterMap rootFromSlug)
                |> Maybe.withDefault []
                |> List.map (\r -> { root = r, scale = scale, stringSet = stringSet })

        necks =
            case lookup "necks" |> Maybe.map (String.split "," >> List.filterMap neckFromSlug) of
                Just (first :: rest) ->
                    first :: rest

                _ ->
                    case legacyRoots of
                        first :: rest ->
                            first :: rest

                        [] ->
                            [ single ]
    in
    { necks = necks
    , active =
        lookup "active"
            |> Maybe.andThen String.toInt
            |> Maybe.withDefault 0
            |> clampIndex necks
    , tuning =
        lookup "tuning"
            |> Maybe.andThen tuningFromSlug
            |> Maybe.withDefault standardTuning
    , focus =
        lookup "focus"
            |> Maybe.andThen focusFromSlug
            |> Maybe.map clampFocus
    }


focusFromSlug : String -> Maybe Focus
focusFromSlug str =
    case List.map String.toInt (String.split "-" str) of
        [ Just lo, Just hi ] ->
            Just ( lo, hi )

        _ ->
            Nothing


{-| The neck the controls edit. The index is clamped rather than trusted so a
stale `?active=` in a shared link cannot point past the end of the list. -}
activeNeck : Model -> Neck
activeNeck model =
    List.drop (clampIndex model.necks model.active) model.necks
        |> List.head
        |> Maybe.withDefault defaultNeck


defaultNeck : Neck
defaultNeck =
    { root = 9, scale = MinorPent, stringSet = AllStrings }


{-| Applies an edit to the active neck and leaves the rest alone — every
control in the panel changes exactly one neck. -}
mapActive : (Neck -> Neck) -> Model -> List Neck
mapActive f model =
    let
        i =
            clampIndex model.necks model.active
    in
    List.indexedMap
        (\j neck ->
            if j == i then
                f neck

            else
                neck
        )
        model.necks


{-| The necks in the order they are drawn: the previewed order mid-drag, so
the neck being dragged travels with the pointer, and the committed order
otherwise. -}
orderedNecks : Model -> List Neck
orderedNecks model =
    case model.drag of
        Just drag ->
            moveItem drag.from drag.to model.necks

        Nothing ->
            model.necks


{-| Pairs a neck with the tuning and the SVG id prefix it draws under. The
prefix is the neck's position, not its root, because two necks may now share a
root (the same key in two different modes). -}
activeBoard : Model -> Board
activeBoard model =
    boardAt model (clampIndex model.necks model.active) (activeNeck model)


boardAt : Model -> Int -> Neck -> Board
boardAt model i neck =
    { root = neck.root
    , scale = neck.scale
    , stringSet = neck.stringSet
    , tuning = model.tuning
    , focus = model.focus
    , id = "n" ++ String.fromInt i ++ "-"
    }


{-| The window a fresh focus opens on: five frets from the 4th, which is box 1
of A minor pentatonic in standard tuning and the position most people practice
in first. -}
defaultFocus : Focus
defaultFocus =
    ( 4, 8 )


{-| Keeps a window on the neck and the right way round. The low end is clamped
against the high end rather than swapped past it, so a stepper pushed too far
simply stops instead of dragging the other end along behind it. -}
clampFocus : Focus -> Focus
clampFocus ( lo, hi ) =
    let
        h =
            clamp 0 numFrets hi
    in
    ( clamp 0 h lo, h )


{-| How many frets a shape spanning `lo`–`hi` has inside the focus window. -}
focusOverlap : Focus -> ( Int, Int ) -> Int
focusOverlap ( flo, fhi ) ( lo, hi ) =
    max 0 (min hi fhi - max lo flo + 1)


{-| Picks the shapes the focus window lights up: the ones with the most frets
inside it. Everything else is drawn gray.

`Nothing` means no window is set and nothing is muted, which is why this is a
`Maybe` rather than an empty list — "no focus" and "focus that lit nothing"
have to render differently.

Ties all stay lit. A window only as wide as one position picks out exactly one
shape, which is the point; a wider one legitimately holds two, and graying one
of them arbitrarily would be a lie. -}
focusedShapes : Maybe Focus -> List ( a, ( Int, Int ) ) -> Maybe (List a)
focusedShapes focus spans =
    case focus of
        Nothing ->
            Nothing

        Just win ->
            let
                scored =
                    List.map (\( key, span ) -> ( key, focusOverlap win span )) spans

                best =
                    scored |> List.map Tuple.second |> List.maximum |> Maybe.withDefault 0
            in
            Just
                (if best <= 0 then
                    []

                 else
                    scored |> List.filter (\( _, n ) -> n == best) |> List.map Tuple.first
                )


{-| Whether one shape should be drawn gray, given what the focus lit. -}
isMuted : Maybe (List a) -> a -> Bool
isMuted lit key =
    case lit of
        Nothing ->
            False

        Just keys ->
            not (List.member key keys)


clampIndex : List a -> Int -> Int
clampIndex xs i =
    clamp 0 (List.length xs - 1) i


insertAt : Int -> a -> List a -> List a
insertAt i x xs =
    List.take i xs ++ (x :: List.drop i xs)


{-| Pulls the item at `from` out of the list and drops it back in at `to`,
which is what a completed drag does to the neck order. -}
moveItem : Int -> Int -> List a -> List a
moveItem from to xs =
    case List.drop from xs |> List.head of
        Nothing ->
            xs

        Just x ->
            insertAt to x (List.take from xs ++ List.drop (from + 1) xs)


{-| Named presets resolve by their slug; anything else is parsed as a custom
tuning encoded as six dash-joined note slugs, high string to low (e.g.
`E-A-D-G-B-E`). A note-encoded slug always stays Custom — even when its notes
match a preset — so editing/entering custom mode round-trips through the URL
(`Nav.replaceUrl` re-fires `UrlChanged`) without collapsing back to a preset. -}
tuningFromSlug : String -> Maybe Tuning
tuningFromSlug s =
    case List.filter (\t -> t.slug == s) tunings of
        match :: _ ->
            Just match

        [] ->
            let
                parsed =
                    String.split "-" s |> List.filterMap rootFromSlug
            in
            if List.length parsed == 6 then
                Just (customFrom parsed)

            else
                Nothing


isCustom : Tuning -> Bool
isCustom t =
    t.name == customName


customName : String
customName =
    "Custom"


{-| A custom tuning from six pitch classes, always named "Custom" so the UI
stays in custom mode (steppers visible) even when the notes happen to match a
preset. The slug encodes the notes so it round-trips through the URL. -}
customFrom : List Int -> Tuning
customFrom strings =
    { name = customName
    , slug = String.join "-" (List.map rootSlug strings)
    , strings = strings
    }



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


{-| Enharmonically correct spelling.

Notes are spelled so each letter (A–G) is used once per octave, in order
starting from the root's letter. Accidentals — including double-sharps and
double-flats — are added to reach the right pitch class.

The root's letter is chosen to minimise the scale's total accidentals (see
`bestRootLetterIndex`): the same pitch class is spelled D♭ in a flat-leaning
scale but C♯ in a sharp-leaning one, and the absurd double-sharp keys
(e.g. naively spelling A♭ major as G♯ major with an F𝄪) never appear.
-}
letterCharForIndex : Int -> String
letterCharForIndex li =
    case li of
        0 -> "C"
        1 -> "D"
        2 -> "E"
        3 -> "F"
        4 -> "G"
        5 -> "A"
        6 -> "B"
        _ -> ""


letterPitchForIndex : Int -> Int
letterPitchForIndex li =
    case li of
        0 -> 0
        1 -> 2
        2 -> 4
        3 -> 5
        4 -> 7
        5 -> 9
        6 -> 11
        _ -> 0


{-| Accidental (signed semitones) needed to spell pitch class `pc` with letter
`li`, normalised to the range [-2, 2] band around the letter's natural pitch. -}
accidentalFor : Int -> Int -> Int
accidentalFor li pc =
    let
        raw =
            modBy 12 (pc - letterPitchForIndex li)
    in
    if raw <= 6 then
        raw

    else
        raw - 12


{-| Candidate letters for spelling a root: those needing at most a double
accidental (|acc| ≤ 2). -}
rootLetterCandidates : Int -> List Int
rootLetterCandidates pc =
    List.filter (\li -> abs (accidentalFor li pc) <= 2) (List.range 0 6)


{-| Cost of spelling a scale with a given root letter: the sum of squared
accidentals. Squaring penalises double accidentals (cost 4) far more than two
single ones (cost 2), so the minimal-cost spelling matches the conventional
key signature. -}
spellingCost : Int -> Int -> ScaleType -> Int
spellingCost root rootLi scale =
    List.map2
        (\i d ->
            let
                acc =
                    accidentalFor (modBy 7 (rootLi + (d - 1))) (modBy 12 (root + i))
            in
            acc * acc
        )
        (scaleIntervals scale)
        (scaleDegrees scale)
        |> List.sum


{-| Letter index (0=C … 6=B) for the root that spells the scale with the fewest
accidentals. Ties (e.g. F♯ vs G♭ major, both 6 accidentals) break toward the
sharp spelling. -}
bestRootLetterIndex : Int -> ScaleType -> Int
bestRootLetterIndex root scale =
    rootLetterCandidates (modBy 12 root)
        |> List.sortBy
            (\li ->
                -- primary: total cost; tiebreak: prefer larger root accidental (sharps)
                ( spellingCost root li scale, negate (accidentalFor li (modBy 12 root)) )
            )
        |> List.head
        |> Maybe.withDefault (rootLetterCandidates (modBy 12 root) |> List.head |> Maybe.withDefault 0)


accidentalGlyph : Int -> String
accidentalGlyph a =
    if a == 0 then
        ""

    else if a == 1 then
        "\u{266F}"

    else if a == 2 then
        "x"

    else if a == -1 then
        "\u{266D}"

    else if a == -2 then
        "\u{266D}\u{266D}"

    else if a > 0 then
        String.repeat a "\u{266F}"

    else
        String.repeat (negate a) "\u{266D}"


{-| Spell pitch class `pc` as the given scale `degree` (1–7) above a root whose
chosen letter index is `rootLi`. -}
spellDegree : Int -> Int -> Int -> String
spellDegree rootLi degree pc =
    let
        li =
            modBy 7 (rootLi + (degree - 1))
    in
    letterCharForIndex li ++ accidentalGlyph (accidentalFor li pc)


{-| Enharmonically spelled names for a `scale` rooted on pitch class `root`,
parallel to `scaleIntervals scale`. The root letter is chosen to minimise
accidentals across the whole scale. -}
spell : Int -> ScaleType -> List String
spell root scale =
    let
        rootLi =
            bestRootLetterIndex root scale
    in
    List.map2
        (\i d -> spellDegree rootLi d (modBy 12 (root + i)))
        (scaleIntervals scale)
        (scaleDegrees scale)


{-| The root's own spelled name under the given scale (the root-button label).
The all-notes map has no key signature to spell against, so it uses the plain
sharp names — matching what the fretboard shows there. -}
rootSpelling : ScaleType -> Int -> String
rootSpelling scale root =
    if isChromatic scale then
        noteName root

    else
        spellDegree (bestRootLetterIndex root scale) 1 (modBy 12 root)


{-| Scale-degree number (1–7) of each interval, parallel to `scaleIntervals`.
Pentatonics skip the missing degrees; the blues blue-note shares the 5th letter
(spelled ♭5, matching the interval labels). -}
scaleDegrees : ScaleType -> List Int
scaleDegrees st =
    case st of
        MajorPent -> [ 1, 2, 3, 5, 6 ]
        MinorPent -> [ 1, 3, 4, 5, 7 ]
        Ionian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Aeolian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Dorian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Mixolydian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Phrygian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Lydian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Locrian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Blues -> [ 1, 3, 4, 5, 5, 7 ]
        HarmonicMajor -> [ 1, 2, 3, 4, 5, 6, 7 ]
        HarmonicMinor -> [ 1, 2, 3, 4, 5, 6, 7 ]
        MelodicMajor -> [ 1, 2, 3, 4, 5, 6, 7 ]
        MelodicMinor -> [ 1, 2, 3, 4, 5, 6, 7 ]
        ChromaticMajor -> [ 1, 2, 2, 3, 3, 4, 5, 5, 6, 6, 7, 7 ]
        ChromaticMinor -> [ 1, 2, 2, 3, 3, 4, 5, 5, 6, 6, 7, 7 ]
        TriadMajor -> [ 1, 3, 5 ]
        TriadMinor -> [ 1, 3, 5 ]
        TriadDim -> [ 1, 3, 5 ]
        TriadAug -> [ 1, 3, 5 ]
        DiagonalMajorPent -> [ 1, 2, 3, 5, 6 ]
        DiagonalPent -> [ 1, 3, 4, 5, 7 ]
        DiagonalBlues -> [ 1, 3, 4, 5, 5, 7 ]


{-| Enharmonically spelled names for the scale's notes, parallel to
`scaleIntervals model.scale`. -}
spelledNotes : Board -> List String
spelledNotes board =
    spell board.root board.scale


{-| Spelled name for a given pitch class within the current scale. Falls back to
the plain sharp name for pitch classes outside the scale. -}
spelledName : Board -> Int -> String
spelledName board n =
    if isChromatic board.scale then
        -- All twelve pitch classes are present, so there is no key to spell
        -- against; the conventional sharp names keep the map readable.
        noteName n

    else
    let
        pc =
            modBy 12 n
    in
    List.map2 Tuple.pair (scaleNotes board) (spelledNotes board)
        |> List.filter (\( p, _ ) -> p == pc)
        |> List.head
        |> Maybe.map Tuple.second
        |> Maybe.withDefault (noteName n)


{-| Standard tuning: string 1 is the high E (top of diagram), string 6 is the
low E (bottom). Stored as open-string pitch classes (C=0), string 1 → 6. -}
standardTuning : Tuning
standardTuning =
    { name = "Standard", slug = "standard", strings = [ 4, 11, 7, 2, 9, 4 ] }


{-| Built-in tunings offered in the selector. `strings` lists the six open
pitch classes high (string 1) to low (string 6). Any tuning not in this list
is still fully supported as a custom tuning — the geometry is derived, not
table-driven. -}
tunings : List Tuning
tunings =
    [ standardTuning
    , { name = "Drop D", slug = "drop-d", strings = [ 4, 11, 7, 2, 9, 2 ] }
    , { name = "Eb Standard", slug = "eb-standard", strings = [ 3, 10, 6, 1, 8, 3 ] }
    , { name = "D Standard", slug = "d-standard", strings = [ 2, 9, 5, 0, 7, 2 ] }
    , { name = "Drop C", slug = "drop-c", strings = [ 2, 9, 5, 0, 7, 0 ] }
    , { name = "C# Standard (Iommi)", slug = "cs-standard", strings = [ 1, 8, 4, 11, 6, 1 ] }
    , { name = "DADGAD", slug = "dadgad", strings = [ 2, 9, 7, 2, 9, 2 ] }
    , { name = "Open G", slug = "open-g", strings = [ 2, 11, 7, 2, 7, 2 ] }
    , { name = "Open D", slug = "open-d", strings = [ 2, 9, 6, 2, 9, 2 ] }
    , { name = "Open E", slug = "open-e", strings = [ 4, 11, 8, 4, 11, 4 ] }
    ]


{-| Open-string pitch class for string `s` (1 = high E … 6 = low E). -}
openString : Tuning -> Int -> Int
openString tuning s =
    tuning.strings |> List.drop (s - 1) |> List.head |> Maybe.withDefault 0


noteAt : Tuning -> Int -> Int -> Int
noteAt tuning s f =
    modBy 12 (openString tuning s + f)


{-| The open pitch of string `s` in absolute semitones, counted up from the
lowest string. A tuning only stores pitch *classes*, so the span between two
adjacent strings is read as the smallest ascending interval that fits, with a
unison reading as an octave — true for every real tuning, and it keeps the six
strings strictly ascending in any custom one. Triads need this: "the next chord
tone above" is a question about pitch, not pitch class. -}
openAbs : Tuning -> Int -> Int
openAbs tuning s =
    List.foldl (\str acc -> acc + ascendingStep tuning str)
        (openString tuning 6)
        (List.range s 5)


{-| How far string `s` sounds above the string below it, in semitones (1–12). -}
ascendingStep : Tuning -> Int -> Int
ascendingStep tuning s =
    let
        d =
            modBy 12 (openString tuning s - openString tuning (s + 1))
    in
    if d == 0 then
        12

    else
        d


{-| How far string `s` is detuned from standard, as the smallest signed
semitone distance (e.g. Drop D's low E reads +2: a note now sounds two frets
higher than in standard). -}
stringDelta : Tuning -> Int -> Int
stringDelta tuning s =
    let
        d =
            modBy 12 (openString standardTuning s - openString tuning s)
    in
    if d > 6 then
        d - 12

    else
        d


{-| The per-string fret shift that re-derives a standard-tuning box shape for
an arbitrary tuning. The anchor lives on the low E (string 6); a box keeps the
*same pitches*, so on each string its frets move by how that string detuned
relative to the anchor string. Standard tuning gives 0 for every string, so all
existing shapes are unchanged. The shift preserves the pitch class at every box
edge, which is why boxes and note markers stay aligned for any tuning. -}
boxShift : Tuning -> Int -> Int
boxShift tuning s =
    stringDelta tuning s - stringDelta tuning 6


scaleIntervals : ScaleType -> List Int
scaleIntervals st =
    case st of
        MajorPent ->
            [ 0, 2, 4, 7, 9 ]

        MinorPent ->
            [ 0, 3, 5, 7, 10 ]

        Ionian ->
            [ 0, 2, 4, 5, 7, 9, 11 ]

        Aeolian ->
            [ 0, 2, 3, 5, 7, 8, 10 ]

        Dorian ->
            [ 0, 2, 3, 5, 7, 9, 10 ]

        Mixolydian ->
            [ 0, 2, 4, 5, 7, 9, 10 ]

        Phrygian ->
            [ 0, 1, 3, 5, 7, 8, 10 ]

        Lydian ->
            [ 0, 2, 4, 6, 7, 9, 11 ]

        Locrian ->
            [ 0, 1, 3, 5, 6, 8, 10 ]

        Blues ->
            [ 0, 3, 5, 6, 7, 10 ]

        -- Major with a ♭6, the mirror of harmonic minor's raised 7th.
        HarmonicMajor ->
            [ 0, 2, 4, 5, 7, 8, 11 ]

        HarmonicMinor ->
            [ 0, 2, 3, 5, 7, 8, 11 ]

        -- Major with ♭6 and ♭7 (Mixolydian ♭6), the mirror of melodic minor's
        -- raised 6th and 7th.
        MelodicMajor ->
            [ 0, 2, 4, 5, 7, 8, 10 ]

        MelodicMinor ->
            [ 0, 2, 3, 5, 7, 9, 11 ]

        ChromaticMajor ->
            List.range 0 11

        ChromaticMinor ->
            List.range 0 11

        TriadMajor ->
            [ 0, 4, 7 ]

        TriadMinor ->
            [ 0, 3, 7 ]

        TriadDim ->
            [ 0, 3, 6 ]

        TriadAug ->
            [ 0, 4, 8 ]

        DiagonalMajorPent ->
            [ 0, 2, 4, 7, 9 ]

        DiagonalPent ->
            [ 0, 3, 5, 7, 10 ]

        DiagonalBlues ->
            [ 0, 3, 5, 6, 7, 10 ]


scaleNotes : Board -> List Int
scaleNotes board =
    List.map (\i -> modBy 12 (board.root + i)) (scaleIntervals board.scale)


isInScale : Board -> Int -> Bool
isInScale board n =
    List.member (modBy 12 n) (scaleNotes board)


{-| The "shape anchor" fret on the low-E string.
Minor pent of R → R's fret on low E.
Major pent of R → relative minor (R - 3)'s fret on low E.
-}
rootFret : Board -> Int
rootFret board =
    let
        -- The anchor is the root's (or relative minor's) fret on the low-E
        -- string, so it follows the low E's open pitch in any tuning. In
        -- standard tuning (low E = 4) these reduce to the familiar −4 / −7.
        lowE =
            openString board.tuning 6

        minorAnchor =
            modBy 12 (board.root - lowE)

        majorAnchor =
            modBy 12 (board.root - 3 - lowE)
    in
    case board.scale of
        MajorPent ->
            majorAnchor

        MinorPent ->
            minorAnchor

        Ionian ->
            majorAnchor

        Aeolian ->
            minorAnchor

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

        Blues ->
            minorAnchor

        HarmonicMajor ->
            majorAnchor

        HarmonicMinor ->
            minorAnchor

        MelodicMajor ->
            majorAnchor

        MelodicMinor ->
            minorAnchor

        ChromaticMajor ->
            -- No boxes are drawn for the all-notes maps, so the anchor is
            -- unused; the matching flavor's anchor is the sane value.
            majorAnchor

        ChromaticMinor ->
            minorAnchor

        TriadMajor ->
            -- Triads draw lassos, not boxes, so the anchor is never read.
            majorAnchor

        TriadMinor ->
            minorAnchor

        TriadDim ->
            minorAnchor

        TriadAug ->
            majorAnchor

        DiagonalMajorPent ->
            diagonalAnchor board.tuning DiagonalMajorPent board.root

        DiagonalPent ->
            diagonalAnchor board.tuning DiagonalPent board.root

        DiagonalBlues ->
            diagonalAnchor board.tuning DiagonalBlues board.root


isDiagonal : ScaleType -> Bool
isDiagonal scale =
    scale == DiagonalPent || scale == DiagonalMajorPent || scale == DiagonalBlues


{-| The two all-notes maps — every note on the neck, with the chord tones read
through a minor (♭3, 5, ♭7) or major (3, 5, 7) lens. Neither is a scale, so they
share every special case in the code; only `noteRole` tells them apart. -}
isChromatic : ScaleType -> Bool
isChromatic scale =
    scale == ChromaticMinor || scale == ChromaticMajor


{-| The four triad modes: not scales either, but chords — three notes, drawn as
lassos around each close-position voicing instead of CAGED boxes. -}
isTriad : ScaleType -> Bool
isTriad scale =
    scale == TriadMajor || scale == TriadMinor || scale == TriadDim || scale == TriadAug


{-| The five box anchors are the minor-pentatonic degrees on the lowest string,
relative to the shape anchor (`rootFret`). Box 1 sits on the root (or, for
major-flavored scales, the relative minor); the rest climb the pentatonic
skeleton. -}
pentAnchor : Int -> Int
pentAnchor b =
    case b of
        1 -> 0
        2 -> 3
        3 -> 5
        4 -> 7
        _ -> 10


{-| Major-flavored scales anchor box 1 on the relative minor (a minor third
below the root), exactly as `rootFret` does. Measured from that anchor note the
scale's intervals rotate up a minor third. Minor-flavored scales anchor on the
root and need no rotation. -}
majorFlavored : ScaleType -> Bool
majorFlavored scale =
    case scale of
        MajorPent -> True
        Ionian -> True
        Dorian -> True
        Mixolydian -> True
        Phrygian -> True
        Lydian -> True
        Locrian -> True
        HarmonicMajor -> True
        MelodicMajor -> True
        _ -> False


{-| A box is a compact playing position: a five-fret window (a four-fret hand
span) on every string, starting one fret below the box's anchor note.

Every scale uses the *same* window, pentatonic or seven-note. The five major-
scale positions sit exactly on top of the pentatonic boxes — the two extra
degrees fill in inside the same window rather than pushing the position up the
neck — so a mode's box 1 and the pentatonic's box 1 are the same hand position.
-}
boxWindow : ( Int, Int )
boxWindow =
    ( -1, 3 )


{-| Pitch classes that count as scale notes *measured from a box's anchor note*
(see `majorFlavored`). -}
anchorScaleSet : ScaleType -> List Int
anchorScaleSet scale =
    let
        rotation =
            if majorFlavored scale then
                3

            else
                0
    in
    List.map (\i -> modBy 12 (i + rotation)) (scaleIntervals scale)


{-| Derive box `b` (1–5) for a tuning and scale as `(string, lo, hi)` frets
relative to the shape anchor. Each box is the position window around the box's
pentatonic anchor; on every string it spans from the lowest to the highest
scale note inside that window.

A box must **contain the complete scale** — every degree, somewhere across its
strings — so it is a self-contained position you can play the whole scale in.
That is the hard requirement; ergonomics is secondary. The base window is the
compact CAGED position (≤4-fret span); if a tuning's string spacing means that
window misses some degree, the upper bound grows until every degree is present.
For every ordinary tuning the base window is already complete, so nothing grows
and standard tuning reproduces the canonical pentatonic and Ionian shapes — the
major-scale positions land on the same windows as the pentatonic boxes. Only
degenerate tunings (e.g. all six strings the same pitch) force wider boxes.

It is the single source of truth for all CAGED box geometry — no per-mode or
per-tuning tables — and is root-independent (the root cancels against the
anchor). -}
deriveBox : Tuning -> ScaleType -> Int -> List ( Int, Int, Int )
deriveBox tuning scale b =
    let
        ( loOff, hiOff ) =
            boxWindow

        anchor =
            pentAnchor b

        scaleSet =
            anchorScaleSet scale

        lo =
            anchor + loOff

        -- A note at relative fret `off` on string `s` is in the scale when its
        -- pitch class, measured from the anchor note on the low E, is in the
        -- set. open(s) − open(6) is the string's interval above the low E.
        degreeAt s off =
            modBy 12 (openString tuning s - openString tuning 6 + off)

        inScale s off =
            List.member (degreeAt s off) scaleSet

        -- Distinct scale degrees reachable on any string within [lo, upper].
        degreesIn upper =
            List.range 1 6
                |> List.concatMap
                    (\s ->
                        List.range lo upper
                            |> List.filterMap
                                (\off ->
                                    if inScale s off then
                                        Just (degreeAt s off)

                                    else
                                        Nothing
                                )
                    )
                |> List.foldl
                    (\d acc ->
                        if List.member d acc then
                            acc

                        else
                            d :: acc
                    )
                    []

        -- Grow the upper bound until the box holds every degree (capped well
        -- inside two octaves as a backstop). A no-op for ordinary tunings.
        grow upper =
            if List.length (degreesIn upper) >= List.length scaleSet || upper - lo >= 24 then
                upper

            else
                grow (upper + 1)

        hi =
            grow (anchor + hiOff)

        forString s =
            let
                offs =
                    List.filter (inScale s) (List.range lo hi)
            in
            Maybe.map2 (\loF hiF -> ( s, loF, hiF )) (List.minimum offs) (List.maximum offs)
    in
    List.filterMap forString (List.range 1 6)


positionBox : Board -> Int -> Int -> Maybe Int
positionBox board s f =
    if isDiagonal board.scale then
        diagonalBoxOf board.tuning board.scale board.root s f

    else if isInScale board (noteAt board.tuning s f) then
        -- The five boxes tile the neck, so every scale note belongs to a box;
        -- the marker is colored by role, not by box.
        Just 0

    else
        Nothing


{-| One close-position triad: three chord tones on three adjacent strings, one
per string, each the next chord tone above the one below it. `notes` runs from
the highest string (lowest number) down to the lowest, as `( string, fret )`
pairs; `inversion` is 0 (root position), 1 (first) or 2 (second), read off the
degree of the bottom note. -}
type alias Triad =
    { notes : List ( Int, Int )
    , inversion : Int
    }


{-| Every close-position triad voicing on the neck for the selected string
set(s) — the triad equivalent of `deriveBox`, and the single source of truth
for the lassos.

A voicing is built from the bottom up: take a chord tone on the set's lowest
string, then on each higher string take the *next* chord tone above the note
below it. That is what "close position" means, so the three notes are always
three different degrees (root, third, fifth in some rotation) and the shape
comes out compact without any hand-written fret table. Reading pitch rather
than pitch class (`openAbs`) is what makes it work in any tuning. -}
triadVoicingsFor : Tuning -> ScaleType -> Int -> StringSet -> List Triad
triadVoicingsFor tuning scale root set =
    List.concatMap (triadsOnStringSet tuning scale root) (stringSetTops set)


{-| The highest string of each three-string set in play. -}
stringSetTops : StringSet -> List Int
stringSetTops set =
    case set of
        AllStrings ->
            [ 1, 2, 3, 4 ]

        StringTrio t ->
            [ t ]


triadsOnStringSet : Tuning -> ScaleType -> Int -> Int -> List Triad
triadsOnStringSet tuning scale root top =
    let
        -- Sorted, so the index of a degree *is* the inversion its bass note
        -- gives: 0 root position, 1 first (third in the bass), 2 second.
        degrees =
            List.sort (scaleIntervals scale)

        degreeAt k =
            degrees
                |> List.drop (modBy (List.length degrees) k)
                |> List.head
                |> Maybe.withDefault 0

        degreeOf s f =
            degrees
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, d ) -> modBy 12 (noteAt tuning s f - root) == d)
                |> List.head
                |> Maybe.map Tuple.first

        pitch s f =
            openAbs tuning s + f

        -- Where degree `deg` sits on string `s` in the octave above pitch `p`:
        -- the lowest such fret, or nothing when that note would fall off the
        -- end of the neck. Insisting on the *next degree* (rather than the next
        -- chord tone of any degree) is what keeps a voicing in close position:
        -- near the nut the note it wants can be below fret 0, and then this
        -- voicing simply does not exist there rather than doubling a degree.
        degreeAbove s deg p =
            List.range 0 numFrets
                |> List.filter
                    (\f ->
                        modBy 12 (noteAt tuning s f - root)
                            == deg
                            && pitch s f
                            > p
                            && pitch s f
                            < p
                            + 12
                    )
                |> List.head

        voicingFrom inv low =
            degreeAbove (top + 1) (degreeAt (inv + 1)) (pitch (top + 2) low)
                |> Maybe.andThen
                    (\mid ->
                        degreeAbove top (degreeAt (inv + 2)) (pitch (top + 1) mid)
                            |> Maybe.map
                                (\high ->
                                    { notes = [ ( top, high ), ( top + 1, mid ), ( top + 2, low ) ]
                                    , inversion = inv
                                    }
                                )
                    )
    in
    List.range 0 numFrets
        |> List.filterMap
            (\low -> degreeOf (top + 2) low |> Maybe.andThen (\inv -> voicingFrom inv low))


{-| Diagonal pentatonic: a 2-string climbing shape. The shapes are identical
for the minor and major variants — only the anchor moves. Minor starts on the
♭3 (pattern 1's lower string carries ♭3, 4, 5; upper string ♭7, R); major is
the same shape shifted down so it starts on the root (lower string R, 2, 3;
upper string 5, 6). There are two patterns: pattern 2 is each pattern-1 shape
rotated 180° and offset 5 frets left, so its strings swap note content (lower
carries ♭7, R; upper ♭3, 4, 5 for minor). Together the two patterns partition
every pentatonic note on the neck. `color` tints the shape (one color per
pattern); `lower`/`upper` are the two strings and `lowerRels`/`upperRels` are
their frets measured from the anchor fret on the low-E string. The +1 shift on
the top pair absorbs the G→B major-third tuning offset. -}
type alias DiagShape =
    { color : Int
    , lower : Int
    , lowerRels : List Int
    , upper : Int
    , upperRels : List Int
    }


diagonalShapes : List DiagShape
diagonalShapes =
    diagonalShapesFor DiagonalPent


{-| The diagonal shapes for a given scale. Minor and major pentatonic share the
same six shapes (only the anchor differs, handled by `diagonalAnchor`). Blues
reuses the minor-pent shapes and inserts the ♭5 blue note on each shape's
♭3-4-5 string, where it sits between the 4 and the 5. Because the blue note is
interior to a string's existing fret span, the shape polygons are unchanged. -}
diagonalShapesFor : ScaleType -> List DiagShape
diagonalShapesFor scale =
    case scale of
        DiagonalBlues ->
            -- Pattern 1: ♭5 added between 4 and 5 on the lower string.
            [ { color = 1, lower = 6, lowerRels = [ 0, 2, 3, 4 ], upper = 5, upperRels = [ 2, 4 ] }
            , { color = 1, lower = 4, lowerRels = [ 2, 4, 5, 6 ], upper = 3, upperRels = [ 4, 6 ] }
            , { color = 1, lower = 2, lowerRels = [ 5, 7, 8, 9 ], upper = 1, upperRels = [ 7, 9 ] }

            -- Pattern 2: ♭5 added between 4 and 5 on the upper string.
            , { color = 2, lower = 6, lowerRels = [ -5, -3 ], upper = 5, upperRels = [ -5, -3, -2, -1 ] }
            , { color = 2, lower = 4, lowerRels = [ -3, -1 ], upper = 3, upperRels = [ -3, -1, 0, 1 ] }
            , { color = 2, lower = 2, lowerRels = [ 0, 2 ], upper = 1, upperRels = [ 0, 2, 3, 4 ] }
            ]

        _ ->
            -- Pattern 1: three notes on the lower string, two right-aligned on the upper.
            [ { color = 1, lower = 6, lowerRels = [ 0, 2, 4 ], upper = 5, upperRels = [ 2, 4 ] }
            , { color = 1, lower = 4, lowerRels = [ 2, 4, 6 ], upper = 3, upperRels = [ 4, 6 ] }
            , { color = 1, lower = 2, lowerRels = [ 5, 7, 9 ], upper = 1, upperRels = [ 7, 9 ] }

            -- Pattern 2: each pattern-1 shape rotated 180° and offset 5 frets left —
            -- two notes on the lower string, three left-aligned on the upper.
            , { color = 2, lower = 6, lowerRels = [ -5, -3 ], upper = 5, upperRels = [ -5, -3, -1 ] }
            , { color = 2, lower = 4, lowerRels = [ -3, -1 ], upper = 3, upperRels = [ -3, -1, 1 ] }
            , { color = 2, lower = 2, lowerRels = [ 0, 2 ], upper = 1, upperRels = [ 0, 2, 4 ] }
            ]


{-| Anchor fret on the low-E string (open = pitch 4). Minor anchors on the ♭3
(root + 3 - 4 = root - 1); major anchors on the root (root - 4). -}
diagonalAnchor : Tuning -> ScaleType -> Int -> Int
diagonalAnchor tuning scale root =
    let
        lowE =
            openString tuning 6
    in
    case scale of
        DiagonalMajorPent ->
            modBy 12 (root - lowE)

        _ ->
            modBy 12 (root + 3 - lowE)


diagonalBoxOf : Tuning -> ScaleType -> Int -> Int -> Int -> Maybe Int
diagonalBoxOf tuning scale root s f =
    let
        rel =
            modBy 12 (f - diagonalAnchor tuning scale root - boxShift tuning s)

        matches shape =
            let
                memberMod rels =
                    List.member rel (List.map (modBy 12) rels)
            in
            if (s == shape.lower && memberMod shape.lowerRels) || (s == shape.upper && memberMod shape.upperRels) then
                Just shape.color

            else
                Nothing
    in
    diagonalShapesFor scale
        |> List.filterMap matches
        |> List.head






type NoteRole
    = Root
    | Third
    | Fifth
    | Seventh
    | Other


noteRole : Board -> Int -> NoteRole
noteRole board n =
    if isChromatic board.scale then
        -- The all-notes maps have no scale to pick *which* third or seventh is
        -- the diatonic one, so the mode itself says: minor marks ♭3/♭7, major
        -- marks 3/7. The 5th (7 semitones) is the same either way.
        let
            interval =
                modBy 12 (n - board.root)
        in
        if interval == 0 then
            Root

        else if interval == chromaticThird board.scale then
            Third

        else if interval == 7 then
            Fifth

        else if interval == chromaticSeventh board.scale then
            Seventh

        else
            Other

    else
    let
        interval =
            modBy 12 (n - board.root)

        thirdInterval =
            case board.scale of
                MajorPent -> 4
                MinorPent -> 3
                Ionian -> 4
                Aeolian -> 3
                Dorian -> 3
                Mixolydian -> 4
                Phrygian -> 3
                Lydian -> 4
                Locrian -> 3
                Blues -> 3
                HarmonicMajor -> 4
                HarmonicMinor -> 3
                MelodicMajor -> 4
                MelodicMinor -> 3
                ChromaticMajor -> -1
                ChromaticMinor -> -1
                TriadMajor -> 4
                TriadMinor -> 3
                TriadDim -> 3
                TriadAug -> 4
                DiagonalMajorPent -> 4
                DiagonalPent -> 3
                DiagonalBlues -> 3

        seventhInterval =
            case board.scale of
                MajorPent -> -1
                MinorPent -> 10
                Ionian -> 11
                Aeolian -> 10
                Dorian -> 10
                Mixolydian -> 10
                Phrygian -> 10
                Lydian -> 11
                Locrian -> 10
                Blues -> 10
                HarmonicMajor -> 11
                HarmonicMinor -> 11
                MelodicMajor -> 10
                MelodicMinor -> 11
                ChromaticMajor -> -1
                ChromaticMinor -> -1
                TriadMajor -> -1
                TriadMinor -> -1
                TriadDim -> -1
                TriadAug -> -1
                DiagonalMajorPent -> -1
                DiagonalPent -> 10
                DiagonalBlues -> 10
    in
    if interval == 0 then
        Root

    else if interval == thirdInterval then
        Third

    else if interval == fifthInterval board.scale then
        Fifth

    else if interval == seventhInterval then
        Seventh

    else
        Other


{-| The 5th's interval. Everything in the app treats 7 semitones as the 5th —
the blues ♭5 and Locrian's ♭5 are marked as ordinary tones — and only the
diminished and augmented triads, whose 5th *is* the altered note, differ. -}
fifthInterval : ScaleType -> Int
fifthInterval scale =
    case scale of
        TriadDim ->
            6

        TriadAug ->
            8

        _ ->
            7


{-| Which third and seventh the all-notes maps mark. `ChromaticMajor` uses the
major flavors, everything else the minor ones. -}
chromaticThird : ScaleType -> Int
chromaticThird scale =
    if scale == ChromaticMajor then
        4

    else
        3


chromaticSeventh : ScaleType -> Int
chromaticSeventh scale =
    if scale == ChromaticMajor then
        11

    else
        10


{-| All-notes mode paints each marker with its pitch-class color, so the neck
reads as twelve repeating hues instead of a field of identical circles. Hues
follow the circle of fifths (see the `--pc-*` vars in index.html): a semitone
step lands half the wheel away, so adjacent frets never look alike, and the
naturals fall in the warm half with the accidentals in the cool half.
-}
pitchColor : Int -> String
pitchColor n =
    "var(--pc-" ++ String.fromInt (modBy 12 n) ++ ")"


{-| Marker for the all-notes map: the pitch-class color carries the identity,
so the shape only has to say root-or-not (square vs circle).
-}
chromaticMarker : NoteRole -> Float -> Float -> Int -> Svg.Svg Msg
chromaticMarker role cx cy n =
    let
        ring extra =
            Svg.circle
                ([ SA.cx (String.fromFloat cx)
                 , SA.cy (String.fromFloat cy)
                 , SA.r "14"
                 , SA.fill (pitchColor n)
                 ]
                    ++ extra
                )
                []
    in
    case role of
        Root ->
            Svg.rect
                [ SA.x (String.fromFloat (cx - 14))
                , SA.y (String.fromFloat (cy - 14))
                , SA.width "28"
                , SA.height "28"
                , SA.rx "3"
                , SA.fill (pitchColor n)
                , SA.stroke "var(--nut)"
                , SA.strokeWidth "2.5"
                ]
                []

        Third ->
            ring
                [ SA.stroke "var(--chord-bd)"
                , SA.strokeWidth "2"
                , SA.strokeDasharray "4 3"
                ]

        Fifth ->
            ring
                [ SA.stroke "var(--chord-bd)"
                , SA.strokeWidth "2"
                , SA.strokeLinecap "round"
                , SA.strokeDasharray "0.1 4"
                ]

        Seventh ->
            ring
                [ SA.stroke "var(--chord-bd)"
                , SA.strokeWidth "1.6"
                , SA.strokeDasharray "4 3"
                , SA.strokeOpacity "0.5"
                ]

        Other ->
            ring
                [ SA.stroke "var(--note-bd)"
                , SA.strokeWidth "1.3"
                , SA.strokeOpacity "0.6"
                ]


{-| A box's fill, gray when the highlight window is set and this box is not the
one that falls in it. -}
boxFill : Bool -> Int -> String
boxFill muted b =
    if muted then
        "var(--box-off)"

    else
        boxColor b


boxColor : Int -> String
boxColor b =
    case b of
        1 -> "var(--box-1)"
        2 -> "var(--box-2)"
        3 -> "var(--box-3)"
        4 -> "var(--box-4)"
        5 -> "var(--box-5)"
        _ -> "var(--surface-bd)"


{-| One color per inversion, so a lasso says at a glance which chord tone is in
the bass. The hues match boxes 1–3, but saturated: a 3px ring needs more punch
than a 55%-opacity fill. -}
inversionColor : Bool -> Int -> String
inversionColor muted inv =
    if muted then
        "var(--inv-off)"

    else
        case inv of
            0 -> "var(--inv-1)"
            1 -> "var(--inv-2)"
            _ -> "var(--inv-3)"


{-| A lasso's interior, pre-blended with the page instead of drawn translucent.
Overlapping translucent pills stacked their tints into muddy colors that no
longer said which inversion they belonged to; an opaque blend always reads as
its own color. It costs the fretboard showing through, which is why the pills
are painted largest-first and the inlay dots move on top of them in triad
mode. `--bg` is `light-dark()`, so the same blend lands on the light or the
dark page as appropriate. -}
inversionFill : Bool -> Int -> String
inversionFill muted inv =
    "color-mix(in srgb, " ++ inversionColor muted inv ++ " " ++ triadFillPct ++ ", var(--bg))"


triadFillPct : String
triadFillPct =
    "18%"


{-| A lasso is a bead around each of its three notes joined by a ribbon, and
every string set gets its own size, so wherever sets pile onto the same note
their lassos nest instead of landing on top of each other.

The sizes are *not* handed out in string order. A set overlaps its neighbor on
two strings but the set beyond that on only one, so the sizes are interleaved —
2-3-4 smallest, 4-5-6 next, 1-2-3 next, 3-4-5 largest — which puts two steps
between every pair that shares two strings and leaves only the loosest pairs a
single step apart. On any one string at most three sets meet, and they are
always at least a step and a half apart there.

The smallest size is the floor: the pill has to clear the root markers, whose
corners sit 18.6px out from the note center (a 28px square, rounded 3) — not
the 14px of the circles, which is what a first pass at this sized itself to and
why the roots poked out of it. The largest is the ceiling: much beyond this and
a pill swallows the neighboring strings whole. -}
triadSizeStep : Triad -> Int
triadSizeStep triad =
    case triad.notes of
        ( 1, _ ) :: _ ->
            2

        ( 2, _ ) :: _ ->
            0

        ( 3, _ ) :: _ ->
            3

        _ ->
            1


triadLassoRadius : Triad -> Float
triadLassoRadius triad =
    20 + 5 * toFloat (triadSizeStep triad)


{-| How thick the ring around a lasso is. Anything the inset leaves inside the
note markers is simply hidden behind them, since markers are drawn later. -}
triadLassoInset : Float
triadLassoInset =
    3


{-| Solid box fill opacity. Overlap stripes pre-blend the box colors with the
background at the matching ratio (`boxBlendPct`) so a striped overlap reads the
same as the solid boxes around it — keep the two in sync. -}
boxFillOpacity : String
boxFillOpacity =
    "0.55"


boxBlendPct : String
boxBlendPct =
    "55%"



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


view : Model -> Browser.Document Msg
view model =
    { title = "Guitar Fretboard Visualizer"
    , body = [ viewBody model ]
    }


viewBody : Model -> Html Msg
viewBody model =
    let
        necks =
            orderedNecks model

        many =
            List.length necks > 1
    in
    div [ style "margin" "1rem 0.5rem" ]
        [ div
            [ style "display" "flex"
            , style "justify-content" "space-between"
            , style "align-items" "center"
            , style "gap" "12px"
            , style "flex-wrap" "wrap"
            ]
            [ h1 [ style "margin" "0 0 6px" ] [ text "Guitar Fretboard Visualizer" ]
            , wakeLockButton model
            ]
        , if many then
            -- Each neck carries its own title, so the single shared one above
            -- the controls would have nothing left to name.
            text ""

          else
            viewScaleTitle (activeBoard model)
        , viewControls model
        , div
            -- A drag is a press and a sweep, which is also how you select
            -- text; without this the sweep paints the page blue.
            [ style "user-select"
                (case model.drag of
                    Just _ ->
                        "none"

                    Nothing ->
                        "auto"
                )
            ]
            (List.indexedMap (viewNeck model many) necks)
        , addNeckButton
        , viewLegend (activeBoard model)
        ]


{-| One fretboard, in its slot. With a single neck this is bare — no handle,
no title, no remove button — so the page looks exactly as it did before
there was a list to reorder. -}
viewNeck : Model -> Bool -> Int -> Neck -> Html Msg
viewNeck model many i neck =
    let
        -- `i` is the slot on screen, which is not where the neck lives in the
        -- model while a drag previews a new order. Messages and the SVG id
        -- prefix name the neck by its place in the model, so they stay put as
        -- the preview shuffles.
        slot =
            committedIndexOf model i

        board =
            boardAt model slot neck

        isActive =
            i == displayIndexOf model model.active

        beingDragged =
            case model.drag of
                Just drag ->
                    drag.to == i

                Nothing ->
                    False
    in
    if not many then
        viewFretboard board

    else
        div
            [ onClick (Activate slot)
            , style "display" "flex"
            , style "align-items" "flex-start"
            , style "gap" "8px"
            , style "padding" "6px 6px 18px"
            , style "border-left"
                (if isActive then
                    "3px solid var(--btn-on-bg)"

                 else
                    "3px solid transparent"
                )
            , style "background"
                (if beingDragged then
                    "var(--btn-bg)"

                 else
                    "transparent"
                )
            , style "border-radius" "6px"
            ]
            [ dragHandle slot
            , div [ style "min-width" "0", style "flex" "1" ]
                [ div
                    [ style "display" "flex"
                    , style "align-items" "flex-start"
                    , style "gap" "8px"
                    ]
                    [ div [ style "flex" "1", style "min-width" "0" ] [ viewScaleTitle board ]
                    , removeNeckButton slot
                    ]
                , viewFretboard board
                ]
            ]


{-| Where a neck sits on screen, which is its committed slot unless a drag is
previewing a different order. -}
displayIndexOf : Model -> Int -> Int
displayIndexOf model i =
    case model.drag of
        Nothing ->
            i

        Just drag ->
            indexAfterMove drag.from drag.to i


{-| The inverse: which neck in the committed list is showing in screen slot
`i`, so a click on a previewed row still names the right neck. -}
committedIndexOf : Model -> Int -> Int
committedIndexOf model i =
    List.range 0 (List.length model.necks - 1)
        |> List.filter (\j -> displayIndexOf model j == i)
        |> List.head
        |> Maybe.withDefault i


{-| Where the item at `i` ends up once the item at `from` is pulled out and
dropped back in at `to`. -}
indexAfterMove : Int -> Int -> Int -> Int
indexAfterMove from to i =
    if i == from then
        to

    else if from < to && i > from && i <= to then
        i - 1

    else if to < from && i >= to && i < from then
        i + 1

    else
        i


{-| The grip. Dragging is done with pointer events rather than HTML5 drag and
drop, which does not fire for touch at all — and a fretboard chart is
something you reorder on the tablet propped up in front of you. -}
dragHandle : Int -> Html Msg
dragHandle i =
    div
        [ Html.Events.on "pointerdown" (dragStartDecoder i)
        , Html.Events.on "pointermove" (Decode.map DragMove clientY)
        , Html.Events.on "pointerup" (Decode.succeed DragEnd)
        , Html.Events.on "pointercancel" (Decode.succeed DragEnd)
        , Html.Attributes.title "Drag to reorder"
        , style "flex" "0 0 auto"
        , style "padding" "8px 4px"
        , style "cursor" "grab"
        , style "color" "var(--text-2)"
        , style "line-height" "0"

        -- Without this the browser claims the gesture for scrolling and no
        -- pointermove ever arrives on touch.
        , style "touch-action" "none"
        , style "user-select" "none"
        ]
        [ Svg.svg
            [ SA.viewBox "0 0 10 16"
            , SA.width "10"
            , SA.height "16"
            , SA.fill "currentColor"
            ]
            (List.concatMap
                (\y -> List.map (\x -> gripDot x y) [ 2, 8 ])
                [ 2, 6, 10, 14 ]
            )
        ]


gripDot : Int -> Int -> Svg.Svg Msg
gripDot x y =
    Svg.circle
        [ SA.cx (String.fromInt x)
        , SA.cy (String.fromInt y)
        , SA.r "1.5"
        ]
        []


{-| The grab reads the row height off the DOM, since a drag has to know how
far one slot is and Elm cannot measure the page. The handle sits inside the
row, so the row is its parent. -}
dragStartDecoder : Int -> Decode.Decoder Msg
dragStartDecoder i =
    Decode.map2 (DragStart i)
        clientY
        (Decode.oneOf
            [ Decode.at [ "currentTarget", "parentElement", "offsetHeight" ] Decode.float
            , Decode.succeed 220
            ]
        )


clientY : Decode.Decoder Float
clientY =
    Decode.field "clientY" Decode.float


removeNeckButton : Int -> Html Msg
removeNeckButton i =
    button
        [ Html.Events.stopPropagationOn "click" (Decode.succeed ( RemoveNeck i, True ))
        , Html.Attributes.title "Remove this neck"
        , style "flex" "0 0 auto"
        , style "padding" "2px 8px"
        , style "border" "1px solid var(--btn-bd)"
        , style "border-radius" "6px"
        , style "cursor" "pointer"
        , style "font-size" "15px"
        , style "line-height" "1.3"
        , style "font-family" "inherit"
        , style "background" "var(--btn-bg)"
        , style "color" "var(--btn-text)"
        ]
        [ text "×" ]


{-| Copies the active neck, so you reshape the copy with the ordinary root and
scale buttons rather than building a neck from nothing. -}
addNeckButton : Html Msg
addNeckButton =
    div [ style "margin" "4px 0 0 3px" ]
        [ button
            ([ onClick AddNeck ] ++ buttonBaseStyle False)
            [ text "+ Add neck" ]
        ]


wakeLockButton : Model -> Html Msg
wakeLockButton model =
    button
        ([ onClick ToggleWakeLock
         , style "min-width" "120px"
         ]
            ++ buttonBaseStyle model.wakeLockOn
        )
        [ text
            (if model.wakeLockOn then
                "Screen on"

             else
                "Keep screen on"
            )
        ]


viewScaleTitle : Board -> Html Msg
viewScaleTitle board =
    let
        scaleName =
            rootSpelling board.scale board.root
                ++ " "
                ++ (case board.scale of
                        MajorPent -> "Major Pentatonic"
                        MinorPent -> "Minor Pentatonic"
                        Ionian -> "Major (Ionian)"
                        Aeolian -> "Minor (Aeolian)"
                        Dorian -> "Dorian"
                        Mixolydian -> "Mixolydian"
                        Phrygian -> "Phrygian"
                        Lydian -> "Lydian"
                        Locrian -> "Locrian"
                        Blues -> "Blues"
                        HarmonicMajor -> "Harmonic Major"
                        HarmonicMinor -> "Harmonic Minor"
                        MelodicMajor -> "Melodic Major"
                        MelodicMinor -> "Melodic Minor"
                        ChromaticMajor -> "— All Notes (major)"
                        ChromaticMinor -> "— All Notes (minor)"
                        TriadMajor -> "Major Triad"
                        TriadMinor -> "Minor Triad"
                        TriadDim -> "Diminished Triad"
                        TriadAug -> "Augmented Triad"
                        DiagonalMajorPent -> "Diagonal Major Pentatonic"
                        DiagonalPent -> "Diagonal Minor Pentatonic"
                        DiagonalBlues -> "Diagonal Blues"
                   )

        intervalLabels =
            case board.scale of
                MajorPent -> [ "R", "2", "3", "5", "6" ]
                MinorPent -> [ "R", "♭3", "4", "5", "♭7" ]
                Ionian -> [ "R", "2", "3", "4", "5", "6", "7" ]
                Aeolian -> [ "R", "2", "♭3", "4", "5", "♭6", "♭7" ]
                Dorian -> [ "R", "2", "♭3", "4", "5", "6", "♭7" ]
                Mixolydian -> [ "R", "2", "3", "4", "5", "6", "♭7" ]
                Phrygian -> [ "R", "♭2", "♭3", "4", "5", "♭6", "♭7" ]
                Lydian -> [ "R", "2", "3", "♯4", "5", "6", "7" ]
                Locrian -> [ "R", "♭2", "♭3", "4", "♭5", "♭6", "♭7" ]
                Blues -> [ "R", "♭3", "4", "♭5", "5", "♭7" ]
                HarmonicMajor -> [ "R", "2", "3", "4", "5", "♭6", "7" ]
                HarmonicMinor -> [ "R", "2", "♭3", "4", "5", "♭6", "7" ]
                MelodicMajor -> [ "R", "2", "3", "4", "5", "♭6", "♭7" ]
                MelodicMinor -> [ "R", "2", "♭3", "4", "5", "6", "7" ]
                ChromaticMajor -> List.repeat 12 ""
                ChromaticMinor -> List.repeat 12 ""
                TriadMajor -> [ "R", "3", "5" ]
                TriadMinor -> [ "R", "♭3", "5" ]
                TriadDim -> [ "R", "♭3", "♭5" ]
                TriadAug -> [ "R", "3", "♯5" ]
                DiagonalMajorPent -> [ "R", "2", "3", "5", "6" ]
                DiagonalPent -> [ "R", "♭3", "4", "5", "♭7" ]
                DiagonalBlues -> [ "R", "♭3", "4", "♭5", "5", "♭7" ]

        -- The notes ride alongside the heading rather than under it, each with
        -- its scale degree stacked beneath instead of trailing in brackets:
        -- one line of vertical space instead of two, and the degrees line up
        -- into their own row you can read across.
        detail =
            if isChromatic board.scale then
                [ aside
                    ("Every note on the neck · hue = note · "
                        ++ (if board.scale == ChromaticMajor then
                                "3 · 5 · 7"

                            else
                                "♭3 · 5 · ♭7"
                           )
                        ++ " from "
                        ++ noteName board.root
                    )
                ]

            else
                List.map2 noteChip (spelledNotes board) intervalLabels
                    ++ (if isTriad board.scale then
                            [ aside (stringSetLabel board.stringSet) ]

                        else
                            []
                       )
    in
    div
        -- Centered, not baselined: the two blocks are built to the same height
        -- (22 × 1.2 for the name, 13 + 10 at 1.15 for a note over its degree),
        -- so centering lines their tops and bottoms up and the pair reads as
        -- one band rather than as a title with something hanging off it.
        [ style "display" "flex"
        , style "align-items" "center"
        , style "flex-wrap" "wrap"
        , style "gap" "2px 20px"
        , style "margin-bottom" "6px"
        ]
        [ div
            [ style "font-size" "22px"
            , style "font-weight" "600"
            , style "line-height" "1.2"
            ]
            [ text scaleName ]
        , div
            [ style "display" "flex"
            , style "align-items" "center"
            , style "flex-wrap" "wrap"
            , style "gap" "0 10px"
            ]
            detail
        ]


{-| One note of the scale with its degree stacked under it, in place of the
bracketed pair this used to print on a line of its own. A common minimum width
keeps the degrees lined up into their own row. -}
noteChip : String -> String -> Html Msg
noteChip note degree =
    div
        [ style "display" "inline-flex"
        , style "flex-direction" "column"
        , style "align-items" "center"
        , style "line-height" "1.15"
        , style "min-width" "16px"
        ]
        [ span
            [ style "font-size" "13px"
            , style "font-weight" "600"
            , style "color" "var(--text-2)"
            ]
            [ text note ]
        , span
            [ style "font-size" "10px"
            , style "color" "var(--text-2)"
            , style "opacity" "0.75"
            ]
            [ text degree ]
        ]


{-| A muted note beside the heading, for the modes that have something to say
there instead of a list of scale degrees. -}
aside : String -> Html Msg
aside s =
    span
        [ style "font-size" "13px"
        , style "color" "var(--text-2)"
        ]
        [ text s ]


viewControls : Model -> Html Msg
viewControls model =
    div [ style "margin-bottom" "18px" ]
        [ controlBlock
            -- One radio group of 23 options, broken into the families a player
            -- would look in. The family name carries the context, so the
            -- buttons inside it can just say "Major" — which is what makes the
            -- whole picker fit in two lines instead of four long rows.
            [ pickerGroup "Pentatonic"
                [ scaleButton model MajorPent "Major"
                , scaleButton model MinorPent "Minor"
                , scaleButton model Blues "Blues"
                ]
            , pickerGroup "Modes"
                [ scaleButton model Ionian "Major (Ionian)"
                , scaleButton model Aeolian "Minor (Aeolian)"
                , scaleButton model Dorian "Dorian"
                , scaleButton model Mixolydian "Mixolydian"
                , scaleButton model Phrygian "Phrygian"
                , scaleButton model Lydian "Lydian"
                , scaleButton model Locrian "Locrian"
                ]
            , pickerGroup "Harmonic"
                [ scaleButton model HarmonicMajor "Major"
                , scaleButton model HarmonicMinor "Minor"
                ]
            , pickerGroup "Melodic"
                [ scaleButton model MelodicMajor "Major"
                , scaleButton model MelodicMinor "Minor"
                ]
            , pickerGroup "Diagonal"
                [ scaleButton model DiagonalMajorPent "Major"
                , scaleButton model DiagonalPent "Minor"
                , scaleButton model DiagonalBlues "Blues"
                ]
            , pickerGroup "Triads"
                [ scaleButton model TriadMajor "Major"
                , scaleButton model TriadMinor "Minor"
                , scaleButton model TriadDim "Diminished"
                , scaleButton model TriadAug "Augmented"
                ]
            , pickerGroup "All notes"
                [ scaleButton model ChromaticMajor "Major"
                , scaleButton model ChromaticMinor "Minor"
                ]
            ]
        , if isTriad (activeNeck model).scale then
            controlBlock
                [ pickerGroup "Strings"
                    (stringSetButton model AllStrings "All"
                        :: List.map
                            (\t -> stringSetButton model (StringTrio t) (stringSetSlug (StringTrio t)))
                            [ 1, 2, 3, 4 ]
                    )
                ]

          else
            text ""
        , controlBlock
            [ pickerGroup "Root" (List.map (rootButton model) (List.range 0 11)) ]
        , setupRow model
        , if model.tuningOpen then
            controlBlock
                (List.map (tuningButton model) tunings ++ [ customButton model ])

          else
            text ""
        , if model.tuningOpen && isCustom model.tuning then
            div [ style "display" "flex", style "align-items" "center" ]
                (List.map (stringStepper model) (List.range 1 6))

          else
            text ""
        ]


{-| The bottom row: the two settings you reach for least, each folded down to a
button that says where it stands. Everything above it is a list you pick from
every time you set a neck up, so those stay open; these two you set once and
play, so they stay shut until you ask. -}
setupRow : Model -> Html Msg
setupRow model =
    div
        [ style "margin-bottom" "8px"
        , style "display" "flex"
        , style "align-items" "center"
        , style "flex-wrap" "wrap"
        , style "gap" "6px 12px"
        ]
        (tuningToggle model
            :: highlightToggle model
            :: highlightFrets model
        )


{-| Names the tuning you are in, and opens the list of them when pressed. -}
tuningToggle : Model -> Html Msg
tuningToggle model =
    button
        ([ onClick ToggleTuningList
         , style "min-width" "80px"
         ]
            ++ buttonBaseStyle model.tuningOpen
        )
        -- The caret is what separates this from the toggle beside it: one
        -- opens a list, the other is on or off.
        [ text
            (tuningLabel model.tuning
                ++ (if model.tuningOpen then
                        " ▴"

                    else
                        " ▾"
                   )
            )
        ]


{-| A preset says its own name. A custom tuning has no name worth reading, so
it spells out its six notes instead — written low string to high, the way a
tuning is normally written down — and the button stays readable with the
steppers folded away. -}
tuningLabel : Tuning -> String
tuningLabel t =
    if isCustom t then
        "Custom tuning: " ++ String.join " " (List.map noteName (List.reverse t.strings))

    else
        t.name ++ " tuning"


{-| Switches the highlight window on and reveals the fret steppers. Pressing it
again puts them away and returns every shape to its own color. -}
highlightToggle : Model -> Html Msg
highlightToggle model =
    let
        on =
            model.focus /= Nothing
    in
    button
        ([ onClick
            (SetFocus
                (if on then
                    Nothing

                 else
                    Just defaultFocus
                )
            )
         , style "min-width" "80px"
         ]
            ++ buttonBaseStyle on
        )
        [ text "Highlight shapes" ]


{-| The window itself, shown only while the highlight is on — there is nothing
to say about a window that is not in use. -}
highlightFrets : Model -> List (Html Msg)
highlightFrets model =
    case model.focus of
        Nothing ->
            []

        Just ( lo, hi ) ->
            [ span
                [ style "display" "inline-flex"
                , style "align-items" "center"
                , style "gap" "2px"
                , style "font-size" "13px"
                , style "color" "var(--text-2)"
                ]
                [ text "Frets"
                , fretStepper lo (\d -> SetFocus (Just ( lo + d, hi )))
                , text "–"
                , fretStepper hi (\d -> SetFocus (Just ( lo, hi + d )))
                ]
            ]


fretStepper : Int -> (Int -> Msg) -> Html Msg
fretStepper value toMsg =
    div
        [ style "display" "inline-flex"
        , style "flex-direction" "column"
        , style "align-items" "center"
        , style "margin" "0 3px"
        ]
        [ stepperButton (toMsg 1) "▲"
        , span
            [ style "font-size" "13px"
            , style "font-weight" "600"
            , style "padding" "2px 0"
            , style "min-width" "26px"
            , style "text-align" "center"
            , style "color" "var(--text)"
            ]
            [ text (String.fromInt value) ]
        , stepperButton (toMsg -1) "▼"
        ]


tuningButton : Model -> Tuning -> Html Msg
tuningButton model t =
    button
        ([ onClick (SetTuning t)
         , style "min-width" "80px"
         ]
            ++ buttonBaseStyle (model.tuning.slug == t.slug)
        )
        [ text t.name ]


{-| Enters custom mode (revealing the per-string steppers), seeded from the
current tuning's notes. -}
customButton : Model -> Html Msg
customButton model =
    button
        ([ onClick (SetTuning (customFrom model.tuning.strings))
         , style "min-width" "80px"
         ]
            ++ buttonBaseStyle (isCustom model.tuning)
        )
        [ text "Custom" ]


{-| Per-string up/down stepper. Editing any string yields a custom tuning,
which the box/scale geometry derives at runtime exactly like a preset. Strings
are shown low (6) to high (1), matching how a player reads the neck. -}
stringStepper : Model -> Int -> Html Msg
stringStepper model uiIndex =
    let
        s =
            7 - uiIndex

        note =
            openString model.tuning s
    in
    div
        [ style "display" "inline-flex"
        , style "flex-direction" "column"
        , style "align-items" "center"
        , style "margin" "0 3px"
        ]
        [ stepperButton (TuneString s 1) "▲"
        , span
            [ style "font-size" "13px"
            , style "font-weight" "600"
            , style "padding" "2px 0"
            , style "min-width" "26px"
            , style "text-align" "center"
            , style "color" "var(--text)"
            ]
            [ text (noteName note) ]
        , stepperButton (TuneString s -1) "▼"
        ]


stepperButton : Msg -> String -> Html Msg
stepperButton msg glyph =
    button
        [ onClick msg
        , style "padding" "0 6px"
        , style "border" "1px solid var(--btn-bd)"
        , style "border-radius" "4px"
        , style "cursor" "pointer"
        , style "font-size" "11px"
        , style "line-height" "1.4"
        , style "font-family" "inherit"
        , style "background" "var(--btn-bg)"
        , style "color" "var(--btn-text)"
        ]
        [ text glyph ]


{-| A line of the control panel: groups laid side by side, wrapping between
them as the window narrows. Capped at the width of the neck it controls —
without that the panel would lay every group on one line and drag the whole
page out to match, since the body sizes itself to its widest row. -}
controlBlock : List (Html Msg) -> Html Msg
controlBlock groups =
    div
        [ style "display" "flex"
        , style "align-items" "center"
        , style "flex-wrap" "wrap"
        , style "row-gap" "6px"
        , style "margin-bottom" "8px"
        , style "max-width" (String.fromFloat totalWidth ++ "px")
        ]
        groups


{-| One named family of buttons. The name rides with the buttons rather than
sitting in a column of its own, which is what lets several families share a
line. A family wraps internally only when it has to, so its name never breaks
away from what it names. -}
pickerGroup : String -> List (Html Msg) -> Html Msg
pickerGroup caption buttons =
    span
        [ style "display" "inline-flex"
        , style "align-items" "center"
        , style "flex-wrap" "wrap"
        , style "row-gap" "6px"
        , style "margin-right" "14px"
        ]
        (span
            [ style "font-size" "11px"
            , style "color" "var(--text-2)"
            , style "font-weight" "600"
            , style "text-transform" "uppercase"
            , style "letter-spacing" "0.06em"
            , style "margin-right" "7px"
            , style "white-space" "nowrap"
            ]
            [ text caption ]
            :: buttons
        )


noteButtonRow : Model -> Html Msg
noteButtonRow model =
    span [] (List.map (rootButton model) (List.range 0 11))


rootButton : Model -> Int -> Html Msg
rootButton model n =
    let
        neck =
            activeNeck model
    in
    button
        ([ onClick (SetRoot n)
         , style "min-width" "44px"
         ]
            ++ buttonBaseStyle (neck.root == n)
        )
        [ text (rootSpelling neck.scale n) ]


scaleButton : Model -> ScaleType -> String -> Html Msg
scaleButton model st lbl =
    button
        ([ onClick (SetScale st)
         , style "min-width" "80px"
         ]
            ++ buttonBaseStyle ((activeNeck model).scale == st)
        )
        [ text lbl ]


stringSetButton : Model -> StringSet -> String -> Html Msg
stringSetButton model set lbl =
    button
        ([ onClick (SetStringSet set)
         , style "min-width" "80px"
         ]
            ++ buttonBaseStyle ((activeNeck model).stringSet == set)
        )
        [ text lbl ]


{-| How the selected string set reads in prose. -}
stringSetLabel : StringSet -> String
stringSetLabel set =
    case set of
        AllStrings ->
            "all string sets"

        StringTrio t ->
            "strings " ++ stringSetSlug (StringTrio t)


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


viewFretboard : Board -> Html Msg
viewFretboard board =
    let
        -- Box tints are translucent, so the neck goes under them and shows
        -- through. Triad pills are opaque and are meant to read as solid
        -- shapes, so there the whole neck — inlay dots, fret lines and strings
        -- alike — goes under the lassos.
        neckAndRegions =
            if isTriad board.scale then
                drawFretMarkers ++ drawFretLines ++ drawStrings ++ drawBoxRegions board

            else
                drawFretMarkers ++ drawBoxRegions board ++ drawFretLines ++ drawStrings
    in
    Svg.svg
        [ SA.viewBox ("0 0 " ++ String.fromFloat totalWidth ++ " " ++ String.fromFloat totalHeight)
        , SA.width (String.fromFloat totalWidth)
        , SA.style "max-width: 100%; height: auto;"
        ]
        (List.concat
            [ [ stripePatternDefs board ]
            , neckAndRegions
            , drawNotes board
            , drawFretNumbers
            , drawInlayDots
            ]
        )



-- BOX POLYGONS


drawBoxRegions : Board -> List (Svg.Svg Msg)
drawBoxRegions board =
    if isChromatic board.scale then
        -- The all-notes map is not a scale: every fret is a scale tone, so a
        -- CAGED box would cover the whole neck. Show the bare fretboard.
        []

    else if isTriad board.scale then
        -- A triad is a chord, not a position: the grouping that matters is the
        -- three-note voicing, so each one gets its own lasso.
        drawTriadLassos board

    else if isDiagonal board.scale then
        drawDiagonalRegions board

    else
        drawBoxRegionsBoxes board


drawBoxRegionsBoxes : Board -> List (Svg.Svg Msg)
drawBoxRegionsBoxes board =
    let
        octaves =
            [ -1, 0, 1 ]

        -- Which box instances the highlight window lights, keyed by box number
        -- and octave, since the same box repeats up the neck and only the one
        -- under your hand is in position.
        lit =
            focusedShapes board.focus
                (List.concatMap
                    (\b -> List.map (\o -> ( ( b, o ), boxSpan board b o )) octaves)
                    [ 1, 2, 3, 4, 5 ]
                )

        solids =
            List.concatMap
                (\b -> List.filterMap (drawSolidBox board lit b) octaves)
                [ 1, 2, 3, 4, 5 ]

        -- Adjacent boxes share notes wherever the position windows overlap; the
        -- overlap is rendered as a striped two-color band. With `deriveBox` this
        -- can happen for any scale (e.g. pentatonic in Open G), not just the
        -- 7-note modes. In standard tuning pentatonic boxes only touch, so the
        -- overlaps collapse to invisible zero-width pinches.
        overlaps =
            List.concatMap
                (\pair -> List.filterMap (drawOverlapStripe board lit pair) octaves)
                [ ( 1, 2 ), ( 2, 3 ), ( 3, 4 ), ( 4, 5 ) ]

        wrapOverlaps =
            List.filterMap (drawWrapOverlap board lit) octaves
    in
    solids ++ overlaps ++ wrapOverlaps


drawDiagonalRegions : Board -> List (Svg.Svg Msg)
drawDiagonalRegions board =
    let
        octaves =
            [ -2, -1, 0, 1, 2 ]

        shapes =
            diagonalShapesFor board.scale

        instances =
            List.concatMap
                (\( i, shape ) -> List.map (\o -> ( ( i, o ), shape, o )) octaves)
                (List.indexedMap Tuple.pair shapes)

        lit =
            focusedShapes board.focus
                (List.map
                    (\( key, shape, o ) ->
                        ( key, diagonalSpan board.tuning board.scale board.root shape o )
                    )
                    instances
                )
    in
    List.filterMap
        (\( key, shape, o ) ->
            drawDiagonalShape board.tuning board.scale board.root (isMuted lit key) shape o
        )
        instances


{-| A climbing shape's reach, lowest fret on its lower string to highest on its
upper — what the highlight window is compared against. These shapes are meant
to be slid rather than played in one place, so the window only says which one
you are nearest, and the rest fade. -}
diagonalSpan : Tuning -> ScaleType -> Int -> DiagShape -> Int -> ( Int, Int )
diagonalSpan tuning scale root shape octave =
    let
        shift =
            diagonalAnchor tuning scale root + 12 * octave

        ends rels boxIndex =
            let
                s2 =
                    shift + boxShift tuning boxIndex
            in
            ( s2 + (List.minimum rels |> Maybe.withDefault 0)
            , s2 + (List.maximum rels |> Maybe.withDefault 0)
            )

        ( loL, hiL ) =
            ends shape.lowerRels shape.lower

        ( loU, hiU ) =
            ends shape.upperRels shape.upper
    in
    ( min loL loU, max hiL hiU )


{-| One diagonal shape: a stepped polygon spanning two adjacent strings.
Both edges are staircases that step at the midline between the strings; an
edge where both strings share a fret (pattern 1's right, pattern 2's left)
collapses to a vertical line. The shape repeats every 12 frets (one octave)
to fill the neck. -}
drawDiagonalShape : Tuning -> ScaleType -> Int -> Bool -> DiagShape -> Int -> Maybe (Svg.Svg Msg)
drawDiagonalShape tuning scale root muted shape octave =
    let
        shift =
            diagonalAnchor tuning scale root + 12 * octave

        shiftL =
            shift + boxShift tuning shape.lower

        shiftU =
            shift + boxShift tuning shape.upper

        loL =
            shiftL + (List.minimum shape.lowerRels |> Maybe.withDefault 0)

        hiL =
            shiftL + (List.maximum shape.lowerRels |> Maybe.withDefault 0)

        loU =
            shiftU + (List.minimum shape.upperRels |> Maybe.withDefault 0)

        hiU =
            shiftU + (List.maximum shape.upperRels |> Maybe.withDefault 0)

        inRange =
            List.any
                (\( lo, hi ) ->
                    (lo >= 0 && lo <= numFrets) || (hi >= 0 && hi <= numFrets)
                )
                [ ( loL, hiL ), ( loU, hiU ) ]

        pad =
            stringSpacing * 0.55

        yLoBot =
            stringY shape.lower + pad

        yMid =
            (stringY shape.lower + stringY shape.upper) / 2

        yUpTop =
            stringY shape.upper - pad

        verts =
            [ ( fretCenterX loL, yLoBot )
            , ( fretCenterX hiL, yLoBot )
            , ( fretCenterX hiL, yMid )
            , ( fretCenterX hiU, yMid )
            , ( fretCenterX hiU, yUpTop )
            , ( fretCenterX loU, yUpTop )
            , ( fretCenterX loU, yMid )
            , ( fretCenterX loL, yMid )
            ]

        pointsStr =
            verts
                |> List.map (\( x, y ) -> String.fromFloat x ++ "," ++ String.fromFloat y)
                |> String.join " "
    in
    if inRange then
        Just
            (Svg.polygon
                [ SA.points pointsStr
                , SA.fill (boxFill muted shape.color)
                , SA.fillOpacity "0.45"
                ]
                []
            )

    else
        Nothing


{-| Every triad voicing on the neck, drawn as a lasso through its three notes:
a soft wash inside and a ring around it, colored by which chord tone is in the
bass. -}
drawTriadLassos : Board -> List (Svg.Svg Msg)
drawTriadLassos board =
    let
        -- Largest pill first. The fills are opaque, so a pill hides whatever it
        -- covers; painting big to small leaves the small ones on top, where
        -- they would otherwise be swallowed by the sets around them. Every
        -- fill goes down before any ring, so no ring is ever painted over.
        voicings =
            triadVoicingsFor board.tuning board.scale board.root board.stringSet
                |> List.sortBy (\triad -> -(triadLassoRadius triad))

        -- A voicing is in position when you can reach all three notes without
        -- moving your hand, so here the test is containment, not the boxes'
        -- "overlaps most". A lasso poking out of the window is one you cannot
        -- play there, whichever way it leans.
        muted triad =
            case board.focus of
                Nothing ->
                    False

                Just ( lo, hi ) ->
                    not (List.all (\( _, f ) -> f >= lo && f <= hi) triad.notes)
    in
    List.map (\triad -> triadFill (muted triad) triad) voicings
        ++ List.concat
            (List.indexedMap
                (\i triad -> triadRing board.id (muted triad) i triad)
                voicings
            )


{-| The lasso shape, shrunk by `inset`: one round-capped, round-joined stroke
along the three note centers, which is a pill of `triadLassoRadius` — each note
sitting in a rounded end or elbow of it. Drawing the shape and the same shape
inset, and subtracting one from the other, is what leaves an even outline.
`attrs` paints it. -}
triadCapsule : Triad -> Float -> List (Svg.Attribute Msg) -> Svg.Svg Msg
triadCapsule triad inset attrs =
    Svg.path
        (SA.d (triadPath triad)
            :: SA.fill "none"
            :: SA.strokeWidth (String.fromFloat (2 * (triadLassoRadius triad - inset)))
            :: SA.strokeLinecap "round"
            :: SA.strokeLinejoin "round"
            :: attrs
        )
        []


{-| The ribbon's centerline, through the three note centers. -}
triadPath : Triad -> String
triadPath triad =
    triad.notes
        |> List.map (\( s, f ) -> String.fromFloat (noteX f) ++ "," ++ String.fromFloat (stringY s))
        |> String.join " L "
        |> String.append "M "


{-| The lasso's interior. -}
triadFill : Bool -> Triad -> Svg.Svg Msg
triadFill muted triad =
    triadCapsule triad 0 [ SA.stroke (inversionFill muted triad.inversion) ]


{-| The lasso outline: the shape minus the same shape inset, which leaves an
even ring around it. It is a masked rectangle rather than the obvious pair of
strokes (wide in the color, narrower in the background color) because that pair
would paint over whatever sits under the lasso — the inlay dots, and the rings
of any lasso it crosses. The mask punches the middle out instead, so the ring
is genuinely hollow and lassos can overlap freely. -}
triadRing : String -> Bool -> Int -> Triad -> List (Svg.Svg Msg)
triadRing prefix muted index triad =
    let
        maskId =
            prefix ++ "triad-lasso-" ++ String.fromInt index

        -- Clear of the widest part of the shape, so the mask never clips it.
        pad =
            triadLassoRadius triad + 4

        span toCoord =
            let
                vs =
                    List.map toCoord triad.notes

                lo =
                    List.minimum vs |> Maybe.withDefault 0
            in
            ( lo - pad, (List.maximum vs |> Maybe.withDefault 0) - lo + 2 * pad )

        ( x0, w ) =
            span (\( _, f ) -> noteX f)

        ( y0, h ) =
            span (\( s, _ ) -> stringY s)

        box =
            [ SA.x (String.fromFloat x0)
            , SA.y (String.fromFloat y0)
            , SA.width (String.fromFloat w)
            , SA.height (String.fromFloat h)
            ]

        layer color inset =
            triadCapsule triad inset [ SA.stroke color ]
    in
    [ Svg.mask (SA.id maskId :: SA.maskUnits "userSpaceOnUse" :: box)
        [ layer "#ffffff" 0
        , layer "#000000" triadLassoInset
        ]
    , Svg.rect (SA.fill (inversionColor muted triad.inversion) :: SA.mask ("url(#" ++ maskId ++ ")") :: box) []
    ]


{-| The stretch of neck one drawn box instance covers, lowest fret on any
string to highest — what the highlight window is compared against. -}
boxSpan : Board -> Int -> Int -> ( Int, Int )
boxSpan board b octave =
    let
        shift =
            rootFret board + 12 * octave

        cells =
            deriveBox board.tuning board.scale b
    in
    ( shift + (List.map (\( _, lo, _ ) -> lo) cells |> List.minimum |> Maybe.withDefault 0)
    , shift + (List.map (\( _, _, hi ) -> hi) cells |> List.maximum |> Maybe.withDefault 0)
    )


drawSolidBox : Board -> Maybe (List ( Int, Int )) -> Int -> Int -> Maybe (Svg.Svg Msg)
drawSolidBox board lit b octave =
    let
        fRoot =
            rootFret board

        shift =
            fRoot + 12 * octave

        positions =
            List.map
                (\( s, lo, hi ) -> ( s, lo + shift, hi + shift ))
                (deriveBox board.tuning board.scale b)

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
                , SA.fill (boxFill (isMuted lit ( b, octave )) b)
                , SA.fillOpacity boxFillOpacity
                ]
                []
            )

    else
        Nothing


drawOverlapStripe : Board -> Maybe (List ( Int, Int )) -> ( Int, Int ) -> Int -> Maybe (Svg.Svg Msg)
drawOverlapStripe board lit ( b1, b2 ) octave =
    let
        fRoot =
            rootFret board

        shift =
            fRoot + 12 * octave

        overlapPositions =
            List.map2
                (\( s, lo1, hi1 ) ( _, lo2, hi2 ) ->
                    ( s, max lo1 lo2 + shift, min hi1 hi2 + shift )
                )
                (deriveBox board.tuning board.scale b1)
                (deriveBox board.tuning board.scale b2)

        hasRealOverlap =
            List.any (\( _, lo, hi ) -> hi >= lo) overlapPositions

        inRange =
            List.any
                (\( _, lo, hi ) ->
                    (lo >= 0 && lo <= numFrets) || (hi >= 0 && hi <= numFrets)
                )
                overlapPositions
    in
    if hasRealOverlap && inRange then
        Just
            (Svg.polygon
                [ SA.points (polygonPoints overlapPositions)
                , SA.fill
                    (stripeRef board.id
                        ( b1, b2 )
                        ( isMuted lit ( b1, octave ), isMuted lit ( b2, octave ) )
                    )
                ]
                []
            )

    else
        Nothing


{-| A stripe has a color per side, so with the highlight window set each side
mutes on its own — the band where an in-position box meets an out-of-position
one is half color, half gray, which is exactly what it is. That means four
patterns per pair rather than one, and the id has to say which. -}
stripeMutings : List ( Bool, Bool )
stripeMutings =
    [ ( False, False ), ( True, False ), ( False, True ), ( True, True ) ]


stripeId : ( Int, Int ) -> ( Bool, Bool ) -> String
stripeId ( b1, b2 ) ( m1, m2 ) =
    let
        mark m =
            if m then
                "m"

            else
                ""
    in
    "ovlp-" ++ String.fromInt b1 ++ mark m1 ++ "-" ++ String.fromInt b2 ++ mark m2


stripeRef : String -> ( Int, Int ) -> ( Bool, Bool ) -> String
stripeRef prefix pair muting =
    "url(#" ++ prefix ++ stripeId pair muting ++ ")"


stripePatternDefs : Board -> Svg.Svg Msg
stripePatternDefs board =
    Svg.defs []
        (List.concatMap
            (\pair -> List.map (overlapStripePattern board.id pair) stripeMutings)
            [ ( 1, 2 ), ( 2, 3 ), ( 3, 4 ), ( 4, 5 ), ( 5, 1 ) ]
        )


drawWrapOverlap : Board -> Maybe (List ( Int, Int )) -> Int -> Maybe (Svg.Svg Msg)
drawWrapOverlap board lit octave =
    let
        fRoot =
            rootFret board

        shift5 =
            fRoot + 12 * octave

        shift1 =
            fRoot + 12 * (octave + 1)

        overlapPositions =
            List.map2
                (\( s, lo5, hi5 ) ( _, lo1, hi1 ) ->
                    ( s
                    , max (lo5 + shift5) (lo1 + shift1)
                    , min (hi5 + shift5) (hi1 + shift1)
                    )
                )
                (deriveBox board.tuning board.scale 5)
                (deriveBox board.tuning board.scale 1)

        hasRealOverlap =
            List.any (\( _, lo, hi ) -> hi >= lo) overlapPositions

        inRange =
            List.any
                (\( _, lo, hi ) ->
                    (lo >= 0 && lo <= numFrets) || (hi >= 0 && hi <= numFrets)
                )
                overlapPositions
    in
    if hasRealOverlap && inRange then
        Just
            (Svg.polygon
                [ SA.points (polygonPoints overlapPositions)
                , SA.fill
                    (stripeRef board.id
                        ( 5, 1 )
                        ( isMuted lit ( 5, octave ), isMuted lit ( 1, octave + 1 ) )
                    )
                ]
                []
            )

    else
        Nothing


overlapStripePattern : String -> ( Int, Int ) -> ( Bool, Bool ) -> Svg.Svg Msg
overlapStripePattern prefix ( b1, b2 ) ( m1, m2 ) =
    let
        period = 14
        half = period / 2

        -- Pre-blend the box color with the page background at the same ratio
        -- as solid boxes (`boxFillOpacity`), so opaque stripes visually match
        -- adjacent solid box regions.
        blended muted b =
            "color-mix(in srgb, " ++ boxFill muted b ++ " " ++ boxBlendPct ++ ", var(--bg))"
    in
    Svg.pattern
        [ SA.id (prefix ++ stripeId ( b1, b2 ) ( m1, m2 ))
        , SA.patternUnits "userSpaceOnUse"
        , SA.width (String.fromFloat period)
        , SA.height (String.fromFloat period)
        , SA.patternTransform "rotate(45)"
        ]
        [ Svg.rect
            [ SA.x "0"
            , SA.y "0"
            , SA.width (String.fromFloat half)
            , SA.height (String.fromFloat period)
            , SA.fill (blended m1 b1)
            ]
            []
        , Svg.rect
            [ SA.x (String.fromFloat half)
            , SA.y "0"
            , SA.width (String.fromFloat half)
            , SA.height (String.fromFloat period)
            , SA.fill (blended m2 b2)
            ]
            []
        ]




{-| Polygon points for a per-string `(string, lo_fret, hi_fret)` shape.
Edges land at fret-center positions (= note positions) so the polygon
ends *beneath* the boundary scale note. Used for both solid boxes and
stripe overlaps. Pinch overlaps (lo == hi) collapse to a single point on
that string and are visually invisible there — accepted trade-off for
consistent edge alignment with notes. -}
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


drawNotes : Board -> List (Svg.Svg Msg)
drawNotes board =
    let
        forString s =
            List.filterMap (drawNoteAt board s) (List.range 0 numFrets)
    in
    List.concatMap forString (List.range 1 6)


drawNoteAt : Board -> Int -> Int -> Maybe (Svg.Svg Msg)
drawNoteAt board s f =
    case positionBox board s f of
        Just _ ->
            let
                n = noteAt board.tuning s f
                role = noteRole board n
                cx = noteX f
                cy = stringY s

                background =
                    if isChromatic board.scale then
                        chromaticMarker role cx cy n

                    else
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

                        Seventh ->
                            Svg.circle
                                [ SA.cx (String.fromFloat cx)
                                , SA.cy (String.fromFloat cy)
                                , SA.r "14"
                                , SA.fill "var(--note-bg)"
                                , SA.stroke "var(--chord-bd)"
                                , SA.strokeWidth "1.5"
                                , SA.strokeDasharray "4 3"
                                , SA.strokeOpacity "0.5"
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
                                , SA.strokeOpacity "0.5"
                                ]
                                []

                textColor =
                    if isChromatic board.scale then
                        -- Pastel in light mode, deep in dark mode: the ordinary
                        -- note text color reads on every pitch-class fill.
                        "var(--note-text)"

                    else
                    case role of
                        Root -> "var(--root-text)"
                        Third -> "var(--note-text)"
                        Fifth -> "var(--note-text)"
                        Seventh -> "var(--note-text)"
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
                        [ Svg.text (spelledName board n) ]
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


viewLegend : Board -> Html Msg
viewLegend board =
    let
        boxes =
            if isChromatic board.scale then
                []

            else if isTriad board.scale then
                legendText "Bass note:"
                    :: List.map legendRing [ ( 0, "root" ), ( 1, "3rd (1st inv)" ), ( 2, "5th (2nd inv)" ) ]

            else if isDiagonal board.scale then
                legendText "Patterns:"
                    :: List.map legendSwatch [ ( 1, "1" ), ( 2, "2" ) ]

            else
                legendText "Boxes:"
                    :: List.map legendSwatch [ ( 1, "1" ), ( 2, "2" ), ( 3, "3" ), ( 4, "4" ), ( 5, "5" ) ]

        highlight =
            case board.focus of
                Nothing ->
                    []

                Just ( lo, hi ) ->
                    [ [ legendChip "var(--box-off)"
                            ("outside frets " ++ String.fromInt lo ++ "–" ++ String.fromInt hi)
                      ]
                    ]

        tones =
            if isChromatic board.scale then
                [ legendText "Tones:"
                , legendMarker "square-pc" "Root"
                , legendMarker "circle-pc-dashed"
                    (if board.scale == ChromaticMajor then
                        "3rd"

                     else
                        "♭3"
                    )
                , legendMarker "circle-pc-dotted" "5th"
                , legendMarker "circle-pc-double"
                    (if board.scale == ChromaticMajor then
                        "7th"

                     else
                        "♭7"
                    )
                , legendMarker "circle-pc" "other"
                , legendText "hue = note"
                ]

            else if isTriad board.scale then
                -- A triad has nothing but chord tones, so there is no 7th and
                -- no "other" to explain.
                [ legendText "Tones:"
                , legendMarker "square-dark" "Root"
                , legendMarker "circle-dashed" "3rd"
                , legendMarker "circle-dotted" "5th"
                ]

            else
                [ legendText "Tones:"
                , legendMarker "square-dark" "Root"
                , legendMarker "circle-dashed" "3rd"
                , legendMarker "circle-dotted" "5th"
                , legendMarker "circle-double" "7th"
                , legendMarker "circle-plain" "other"
                ]
    in
    div
        [ style "margin-top" "16px"
        , style "font-size" "13px"
        , style "color" "var(--text-2)"
        , style "display" "flex"
        , style "gap" "18px"
        , style "flex-wrap" "wrap"
        , style "align-items" "center"
        ]
        (List.map legendGroup
            ((if List.isEmpty boxes then
                []

              else
                [ boxes ]
             )
                ++ (tones :: highlight)
            )
        )


{-| A label plus its swatches/markers, kept together so the label never
line-breaks away from the icons it explains. The group wraps as a unit
relative to its siblings (and only wraps internally on very narrow screens).
-}
legendGroup : List (Html Msg) -> Html Msg
legendGroup children =
    div
        [ style "display" "inline-flex"
        , style "flex-wrap" "wrap"
        , style "align-items" "center"
        , style "gap" "18px"
        ]
        children


legendText : String -> Html Msg
legendText s =
    span [ style "font-weight" "600", style "color" "var(--text-strong)" ] [ text s ]


legendSwatch : ( Int, String ) -> Html Msg
legendSwatch ( b, lbl ) =
    legendChip (boxColor b) lbl


legendChip : String -> String -> Html Msg
legendChip color lbl =
    span
        [ style "display" "inline-flex"
        , style "align-items" "center"
        , style "gap" "6px"
        ]
        [ span
            [ style "display" "inline-block"
            , style "width" "16px"
            , style "height" "16px"
            , style "background" color
            , style "border" ("1px solid " ++ color)
            , style "border-radius" "3px"
            , style "opacity" "0.75"
            ]
            []
        , text lbl
        ]


{-| A lasso in miniature: a hollow ring in the inversion's color. -}
legendRing : ( Int, String ) -> Html Msg
legendRing ( inv, lbl ) =
    span
        [ style "display" "inline-flex"
        , style "align-items" "center"
        , style "gap" "6px"
        ]
        [ span
            [ style "display" "inline-block"
            , style "width" "16px"
            , style "height" "16px"
            , style "box-sizing" "border-box"
            , style "border" ("3px solid " ++ inversionColor False inv)
            , style "border-radius" "8px"
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

        -- A few pitch-class hues in one chip, to say "colored by note".
        pcGradient =
            "linear-gradient(135deg, var(--pc-0), var(--pc-7), var(--pc-4))"

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

                "square-pc" ->
                    span
                        (common
                            ++ [ style "background" pcGradient
                               , style "border" "2px solid var(--nut)"
                               , style "border-radius" "2px"
                               ]
                        )
                        []

                "circle-pc" ->
                    span
                        (common
                            ++ [ style "background" pcGradient
                               , style "border" "1px solid var(--note-bd)"
                               , style "border-radius" "50%"
                               ]
                        )
                        []

                "circle-pc-dashed" ->
                    span
                        (common
                            ++ [ style "background" pcGradient
                               , style "border" "2px dashed var(--chord-bd)"
                               , style "border-radius" "50%"
                               ]
                        )
                        []

                "circle-pc-dotted" ->
                    span
                        (common
                            ++ [ style "background" pcGradient
                               , style "border" "2px dotted var(--chord-bd)"
                               , style "border-radius" "50%"
                               ]
                        )
                        []

                "circle-pc-double" ->
                    span
                        (common
                            ++ [ style "background" pcGradient
                               , style "border" "1.6px dashed var(--chord-bd)"
                               , style "border-radius" "50%"
                               , style "opacity" "0.6"
                               ]
                        )
                        []

                "circle-double" ->
                    span
                        (common
                            ++ [ style "background" "var(--note-bg)"
                               , style "border" "1.5px dashed var(--chord-bd)"
                               , style "border-radius" "50%"
                               , style "opacity" "0.5"
                               ]
                        )
                        []

                _ ->
                    span
                        (common
                            ++ [ style "background" "var(--note-bg)"
                               , style "border" "1px solid var(--note-bd)"
                               , style "border-radius" "50%"
                               , style "opacity" "0.5"
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


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ wakeLockChanged WakeLockChanged

        -- Touch pointers are captured by the handle, so its own pointermove is
        -- enough there. A mouse is not captured and walks straight off the
        -- handle, so while a drag is live the document is watched too.
        , case model.drag of
            Just _ ->
                Sub.batch
                    [ Browser.Events.onMouseMove (Decode.map DragMove clientY)
                    , Browser.Events.onMouseUp (Decode.succeed DragEnd)
                    ]

            Nothing ->
                Sub.none
        ]


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }
