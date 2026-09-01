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
import Browser.Navigation as Nav
import Html exposing (Html, button, div, h1, p, span, text)
import Html.Attributes exposing (style)
import Html.Events exposing (onClick)
import Svg
import Svg.Attributes as SA
import Url exposing (Url)



-- MODEL


type alias Model =
    { root : Int
    , scale : ScaleType
    , tuning : Tuning
    , stringSet : StringSet
    , key : Nav.Key
    , wakeLockOn : Bool
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
    = MinorPent
    | MajorPent
    | Ionian
    | Dorian
    | Aeolian
    | Mixolydian
    | Phrygian
    | Lydian
    | Locrian
    | Blues
    | HarmonicMinor
    | MelodicMinor
    | ChromaticMinor
    | ChromaticMajor
    | TriadMajor
    | TriadMinor
    | TriadDim
    | TriadAug
    | DiagonalPent
    | DiagonalMajorPent
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
    ( { root = state.root
      , scale = state.scale
      , tuning = state.tuning
      , stringSet = state.stringSet
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
            let
                newModel =
                    { model | root = modBy 12 n }
            in
            ( newModel, Nav.replaceUrl model.key (modelUrl newModel) )

        SetScale s ->
            let
                newModel =
                    { model | scale = s }
            in
            ( newModel, Nav.replaceUrl model.key (modelUrl newModel) )

        SetTuning t ->
            let
                newModel =
                    { model | tuning = t }
            in
            ( newModel, Nav.replaceUrl model.key (modelUrl newModel) )

        SetStringSet set ->
            let
                newModel =
                    { model | stringSet = set }
            in
            ( newModel, Nav.replaceUrl model.key (modelUrl newModel) )

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

                newModel =
                    { model | tuning = customFrom newStrings }
            in
            ( newModel, Nav.replaceUrl model.key (modelUrl newModel) )

        UrlChanged url ->
            let
                state =
                    parseUrl url
            in
            ( { model
                | root = state.root
                , scale = state.scale
                , tuning = state.tuning
                , stringSet = state.stringSet
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



-- URL SERIALIZATION


modelUrl : Model -> String
modelUrl model =
    let
        base =
            "?root=" ++ rootSlug model.root ++ "&scale=" ++ scaleSlug model.scale

        withTuning =
            if model.tuning.slug == standardTuning.slug then
                base

            else
                base ++ "&tuning=" ++ model.tuning.slug
    in
    -- The string-set selector only exists in the triad modes, so its param is
    -- only carried there; every other mode keeps the URL it always had.
    if isTriad model.scale && model.stringSet /= AllStrings then
        withTuning ++ "&strings=" ++ stringSetSlug model.stringSet

    else
        withTuning


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
        MinorPent -> "minor-pent"
        MajorPent -> "major-pent"
        Ionian -> "ionian"
        Aeolian -> "aeolian"
        Mixolydian -> "mixolydian"
        Phrygian -> "phrygian"
        Lydian -> "lydian"
        Locrian -> "locrian"
        Blues -> "blues"
        HarmonicMinor -> "harmonic-minor"
        MelodicMinor -> "melodic-minor"
        ChromaticMinor -> "all-notes-minor"
        ChromaticMajor -> "all-notes-major"
        TriadMajor -> "triad-major"
        TriadMinor -> "triad-minor"
        TriadDim -> "triad-dim"
        TriadAug -> "triad-aug"
        DiagonalPent -> "diagonal-pent"
        DiagonalMajorPent -> "diagonal-major-pent"
        DiagonalBlues -> "diagonal-blues"
        Dorian -> "dorian"


scaleFromSlug : String -> Maybe ScaleType
scaleFromSlug s =
    case s of
        "minor-pent" -> Just MinorPent
        "major-pent" -> Just MajorPent
        "ionian" -> Just Ionian
        "aeolian" -> Just Aeolian
        "dorian" -> Just Dorian
        "mixolydian" -> Just Mixolydian
        "phrygian" -> Just Phrygian
        "lydian" -> Just Lydian
        "locrian" -> Just Locrian
        "blues" -> Just Blues
        "harmonic-minor" -> Just HarmonicMinor
        "melodic-minor" -> Just MelodicMinor
        "all-notes-minor" -> Just ChromaticMinor
        "all-notes-major" -> Just ChromaticMajor
        "triad-major" -> Just TriadMajor
        "triad-minor" -> Just TriadMinor
        "triad-dim" -> Just TriadDim
        "triad-aug" -> Just TriadAug
        -- The all-notes map used to be a single mode; keep old links working.
        "all-notes" -> Just ChromaticMinor
        "diagonal-pent" -> Just DiagonalPent
        "diagonal-major-pent" -> Just DiagonalMajorPent
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


{-| Everything the URL carries: root, mode, tuning and (triads only) the
string set the lassos are drawn on. -}
type alias UrlState =
    { root : Int
    , scale : ScaleType
    , tuning : Tuning
    , stringSet : StringSet
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

        root =
            lookup "root"
                |> Maybe.andThen rootFromSlug
                |> Maybe.withDefault 9

        scale =
            lookup "scale"
                |> Maybe.andThen scaleFromSlug
                |> Maybe.withDefault MinorPent

        tuning =
            lookup "tuning"
                |> Maybe.andThen tuningFromSlug
                |> Maybe.withDefault standardTuning

        stringSet =
            lookup "strings"
                |> Maybe.andThen stringSetFromSlug
                |> Maybe.withDefault AllStrings
    in
    { root = root, scale = scale, tuning = tuning, stringSet = stringSet }


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


{-| A custom tuning from six pitch classes, always named "Custom" so the UI
stays in custom mode (steppers visible) even when the notes happen to match a
preset. The slug encodes the notes so it round-trips through the URL. -}
customFrom : List Int -> Tuning
customFrom strings =
    { name = "Custom"
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
        MinorPent -> [ 1, 3, 4, 5, 7 ]
        MajorPent -> [ 1, 2, 3, 5, 6 ]
        Ionian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Dorian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Aeolian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Mixolydian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Phrygian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Lydian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Locrian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Blues -> [ 1, 3, 4, 5, 5, 7 ]
        HarmonicMinor -> [ 1, 2, 3, 4, 5, 6, 7 ]
        MelodicMinor -> [ 1, 2, 3, 4, 5, 6, 7 ]
        ChromaticMinor -> [ 1, 2, 2, 3, 3, 4, 5, 5, 6, 6, 7, 7 ]
        ChromaticMajor -> [ 1, 2, 2, 3, 3, 4, 5, 5, 6, 6, 7, 7 ]
        TriadMajor -> [ 1, 3, 5 ]
        TriadMinor -> [ 1, 3, 5 ]
        TriadDim -> [ 1, 3, 5 ]
        TriadAug -> [ 1, 3, 5 ]
        DiagonalPent -> [ 1, 3, 4, 5, 7 ]
        DiagonalMajorPent -> [ 1, 2, 3, 5, 6 ]
        DiagonalBlues -> [ 1, 3, 4, 5, 5, 7 ]


{-| Enharmonically spelled names for the scale's notes, parallel to
`scaleIntervals model.scale`. -}
spelledNotes : Model -> List String
spelledNotes model =
    spell model.root model.scale


{-| Spelled name for a given pitch class within the current scale. Falls back to
the plain sharp name for pitch classes outside the scale. -}
spelledName : Model -> Int -> String
spelledName model n =
    if isChromatic model.scale then
        -- All twelve pitch classes are present, so there is no key to spell
        -- against; the conventional sharp names keep the map readable.
        noteName n

    else
    let
        pc =
            modBy 12 n
    in
    List.map2 Tuple.pair (scaleNotes model) (spelledNotes model)
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
        MinorPent ->
            [ 0, 3, 5, 7, 10 ]

        MajorPent ->
            [ 0, 2, 4, 7, 9 ]

        Ionian ->
            [ 0, 2, 4, 5, 7, 9, 11 ]

        Dorian ->
            [ 0, 2, 3, 5, 7, 9, 10 ]

        Aeolian ->
            [ 0, 2, 3, 5, 7, 8, 10 ]

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

        HarmonicMinor ->
            [ 0, 2, 3, 5, 7, 8, 11 ]

        MelodicMinor ->
            [ 0, 2, 3, 5, 7, 9, 11 ]

        ChromaticMinor ->
            List.range 0 11

        ChromaticMajor ->
            List.range 0 11

        TriadMajor ->
            [ 0, 4, 7 ]

        TriadMinor ->
            [ 0, 3, 7 ]

        TriadDim ->
            [ 0, 3, 6 ]

        TriadAug ->
            [ 0, 4, 8 ]

        DiagonalPent ->
            [ 0, 3, 5, 7, 10 ]

        DiagonalMajorPent ->
            [ 0, 2, 4, 7, 9 ]

        DiagonalBlues ->
            [ 0, 3, 5, 6, 7, 10 ]


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
    let
        -- The anchor is the root's (or relative minor's) fret on the low-E
        -- string, so it follows the low E's open pitch in any tuning. In
        -- standard tuning (low E = 4) these reduce to the familiar −4 / −7.
        lowE =
            openString model.tuning 6

        minorAnchor =
            modBy 12 (model.root - lowE)

        majorAnchor =
            modBy 12 (model.root - 3 - lowE)
    in
    case model.scale of
        MinorPent ->
            minorAnchor

        MajorPent ->
            majorAnchor

        Ionian ->
            majorAnchor

        Dorian ->
            majorAnchor

        Aeolian ->
            minorAnchor

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

        HarmonicMinor ->
            minorAnchor

        MelodicMinor ->
            minorAnchor

        ChromaticMinor ->
            -- No boxes are drawn for the all-notes maps, so the anchor is
            -- unused; the matching flavor's anchor is the sane value.
            minorAnchor

        ChromaticMajor ->
            majorAnchor

        TriadMajor ->
            -- Triads draw lassos, not boxes, so the anchor is never read.
            majorAnchor

        TriadMinor ->
            minorAnchor

        TriadDim ->
            minorAnchor

        TriadAug ->
            majorAnchor

        DiagonalPent ->
            diagonalAnchor model.tuning DiagonalPent model.root

        DiagonalMajorPent ->
            diagonalAnchor model.tuning DiagonalMajorPent model.root

        DiagonalBlues ->
            diagonalAnchor model.tuning DiagonalBlues model.root


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


positionBox : Model -> Int -> Int -> Maybe Int
positionBox model s f =
    if isDiagonal model.scale then
        diagonalBoxOf model.tuning model.scale model.root s f

    else if isInScale model (noteAt model.tuning s f) then
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


noteRole : Model -> Int -> NoteRole
noteRole model n =
    if isChromatic model.scale then
        -- The all-notes maps have no scale to pick *which* third or seventh is
        -- the diatonic one, so the mode itself says: minor marks ♭3/♭7, major
        -- marks 3/7. The 5th (7 semitones) is the same either way.
        let
            interval =
                modBy 12 (n - model.root)
        in
        if interval == 0 then
            Root

        else if interval == chromaticThird model.scale then
            Third

        else if interval == 7 then
            Fifth

        else if interval == chromaticSeventh model.scale then
            Seventh

        else
            Other

    else
    let
        interval =
            modBy 12 (n - model.root)

        thirdInterval =
            case model.scale of
                MinorPent -> 3
                MajorPent -> 4
                Ionian -> 4
                Dorian -> 3
                Aeolian -> 3
                Mixolydian -> 4
                Phrygian -> 3
                Lydian -> 4
                Locrian -> 3
                Blues -> 3
                HarmonicMinor -> 3
                MelodicMinor -> 3
                ChromaticMinor -> -1
                ChromaticMajor -> -1
                TriadMajor -> 4
                TriadMinor -> 3
                TriadDim -> 3
                TriadAug -> 4
                DiagonalPent -> 3
                DiagonalMajorPent -> 4
                DiagonalBlues -> 3

        seventhInterval =
            case model.scale of
                MinorPent -> 10
                MajorPent -> -1
                Ionian -> 11
                Dorian -> 10
                Aeolian -> 10
                Mixolydian -> 10
                Phrygian -> 10
                Lydian -> 11
                Locrian -> 10
                Blues -> 10
                HarmonicMinor -> 11
                MelodicMinor -> 11
                ChromaticMinor -> -1
                ChromaticMajor -> -1
                TriadMajor -> -1
                TriadMinor -> -1
                TriadDim -> -1
                TriadAug -> -1
                DiagonalPent -> 10
                DiagonalMajorPent -> -1
                DiagonalBlues -> 10
    in
    if interval == 0 then
        Root

    else if interval == thirdInterval then
        Third

    else if interval == fifthInterval model.scale then
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
inversionColor : Int -> String
inversionColor inv =
    case inv of
        0 -> "var(--inv-1)"
        1 -> "var(--inv-2)"
        _ -> "var(--inv-3)"


{-| A lasso is a bead around each of its three notes joined by a ribbon, and
every string set gets its own size, so wherever sets pile onto the same note
their lassos nest instead of landing on top of each other.

The sizes are *not* handed out in string order. A set overlaps its neighbor on
two strings but the set beyond that on only one, so the sizes are interleaved —
2-3-4 smallest, 4-5-6 next, 1-2-3 next, 3-4-5 largest — which puts two steps
between every pair that shares two strings and leaves only the loosest pairs a
single step apart. On any one string at most three sets meet, and they are
always at least a step and a half apart there.

The smallest size is the floor: it still has to clear the 28px note markers on
every side, whatever angle the ribbon arrives at. The largest is the ceiling:
much beyond this and a bead swallows the neighboring strings. -}
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


triadBeadRadius : Triad -> Float
triadBeadRadius triad =
    17 + 6 * toFloat (triadSizeStep triad)


{-| The ribbon stays well under the bead at the larger sizes: it is the beads
that have to be told apart, and a ribbon as fat as its beads turns the lasso
into a sausage instead of a chain of notes. -}
triadRibbonWidth : Triad -> Float
triadRibbonWidth triad =
    min 30 (triadBeadRadius triad + 4)


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
        , viewScaleTitle model
        , viewControls model
        , viewFretboard model
        , viewLegend model
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


viewScaleTitle : Model -> Html Msg
viewScaleTitle model =
    let
        scaleName =
            rootSpelling model.scale model.root
                ++ " "
                ++ (case model.scale of
                        MinorPent -> "Minor Pentatonic"
                        MajorPent -> "Major Pentatonic"
                        Ionian -> "Ionian (Major)"
                        Dorian -> "Dorian"
                        Aeolian -> "Aeolian (Natural Minor)"
                        Mixolydian -> "Mixolydian"
                        Phrygian -> "Phrygian"
                        Lydian -> "Lydian"
                        Locrian -> "Locrian"
                        Blues -> "Blues"
                        HarmonicMinor -> "Harmonic Minor"
                        MelodicMinor -> "Melodic Minor"
                        ChromaticMinor -> "— All Notes (minor)"
                        ChromaticMajor -> "— All Notes (major)"
                        TriadMajor -> "Major Triad"
                        TriadMinor -> "Minor Triad"
                        TriadDim -> "Diminished Triad"
                        TriadAug -> "Augmented Triad"
                        DiagonalPent -> "Diagonal Minor Pentatonic"
                        DiagonalMajorPent -> "Diagonal Major Pentatonic"
                        DiagonalBlues -> "Diagonal Blues"
                   )

        intervalLabels =
            case model.scale of
                MinorPent -> [ "R", "♭3", "4", "5", "♭7" ]
                MajorPent -> [ "R", "2", "3", "5", "6" ]
                Ionian -> [ "R", "2", "3", "4", "5", "6", "7" ]
                Dorian -> [ "R", "2", "♭3", "4", "5", "6", "♭7" ]
                Aeolian -> [ "R", "2", "♭3", "4", "5", "♭6", "♭7" ]
                Mixolydian -> [ "R", "2", "3", "4", "5", "6", "♭7" ]
                Phrygian -> [ "R", "♭2", "♭3", "4", "5", "♭6", "♭7" ]
                Lydian -> [ "R", "2", "3", "♯4", "5", "6", "7" ]
                Locrian -> [ "R", "♭2", "♭3", "4", "♭5", "♭6", "♭7" ]
                Blues -> [ "R", "♭3", "4", "♭5", "5", "♭7" ]
                HarmonicMinor -> [ "R", "2", "♭3", "4", "5", "♭6", "7" ]
                MelodicMinor -> [ "R", "2", "♭3", "4", "5", "6", "7" ]
                ChromaticMinor -> List.repeat 12 ""
                ChromaticMajor -> List.repeat 12 ""
                TriadMajor -> [ "R", "3", "5" ]
                TriadMinor -> [ "R", "♭3", "5" ]
                TriadDim -> [ "R", "♭3", "♭5" ]
                TriadAug -> [ "R", "3", "♯5" ]
                DiagonalPent -> [ "R", "♭3", "4", "5", "♭7" ]
                DiagonalMajorPent -> [ "R", "2", "3", "5", "6" ]
                DiagonalBlues -> [ "R", "♭3", "4", "♭5", "5", "♭7" ]

        notePairs =
            List.map2
                (\nm lbl -> nm ++ " (" ++ lbl ++ ")")
                (spelledNotes model)
                intervalLabels

        subtitle =
            if isChromatic model.scale then
                "Every note on the neck · hue = note · "
                    ++ (if model.scale == ChromaticMajor then
                            "3 · 5 · 7"

                        else
                            "♭3 · 5 · ♭7"
                       )
                    ++ " marked from "
                    ++ noteName model.root

            else if isTriad model.scale then
                "Notes: "
                    ++ String.join "  ·  " notePairs
                    ++ "  ·  "
                    ++ stringSetLabel model.stringSet

            else
                "Notes: " ++ String.join "  ·  " notePairs
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
            [ text subtitle ]
        ]


viewControls : Model -> Html Msg
viewControls model =
    div [ style "margin-bottom" "18px" ]
        [ div [ style "margin-bottom" "8px" ]
            [ label "Scale"
            , scaleButton model MinorPent "Minor pentatonic"
            , scaleButton model MajorPent "Major pentatonic"
            , scaleButton model Ionian "Ionian"
            , scaleButton model Aeolian "Aeolian"
            , scaleButton model Dorian "Dorian"
            , scaleButton model Mixolydian "Mixolydian"
            , scaleButton model Phrygian "Phrygian"
            , scaleButton model Lydian "Lydian"
            , scaleButton model Locrian "Locrian"
            , scaleButton model Blues "Blues"
            , scaleButton model HarmonicMinor "Harmonic minor"
            , scaleButton model MelodicMinor "Melodic minor"
            ]
        , div [ style "margin-bottom" "8px" ]
            [ label "Diag. Scale"
            , scaleButton model DiagonalPent "Minor pentatonic"
            , scaleButton model DiagonalMajorPent "Major pentatonic"
            , scaleButton model DiagonalBlues "Blues"
            ]
        , div [ style "margin-bottom" "8px" ]
            [ label "Triads"
            , scaleButton model TriadMajor "Major"
            , scaleButton model TriadMinor "Minor"
            , scaleButton model TriadDim "Diminished"
            , scaleButton model TriadAug "Augmented"
            ]
        , if isTriad model.scale then
            div [ style "margin-bottom" "8px" ]
                (label "Strings"
                    :: stringSetButton model AllStrings "All"
                    :: List.map
                        (\t -> stringSetButton model (StringTrio t) (stringSetSlug (StringTrio t)))
                        [ 1, 2, 3, 4 ]
                )

          else
            text ""
        , div [ style "margin-bottom" "8px" ]
            [ label "No scale"
            , scaleButton model ChromaticMinor "All notes (minor)"
            , scaleButton model ChromaticMajor "All notes (major)"
            ]
        , div [ style "margin-bottom" "8px" ]
            [ label "Root" , noteButtonRow model ]
        , div [ style "margin-bottom" "8px" ]
            (label "Tuning"
                :: List.map (tuningButton model) tunings
                ++ [ customButton model ]
            )
        , if model.tuning.name == "Custom" then
            div [ style "display" "flex", style "align-items" "center" ]
                [ label "Strings"
                , span [] (List.map (stringStepper model) (List.range 1 6))
                ]

          else
            text ""
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
            ++ buttonBaseStyle (model.tuning.name == "Custom")
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
            , style "color" "var(--text-1)"
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
        [ text (rootSpelling model.scale n) ]


scaleButton : Model -> ScaleType -> String -> Html Msg
scaleButton model st lbl =
    button
        ([ onClick (SetScale st)
         , style "min-width" "80px"
         ]
            ++ buttonBaseStyle (model.scale == st)
        )
        [ text lbl ]


stringSetButton : Model -> StringSet -> String -> Html Msg
stringSetButton model set lbl =
    button
        ([ onClick (SetStringSet set)
         , style "min-width" "80px"
         ]
            ++ buttonBaseStyle (model.stringSet == set)
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


viewFretboard : Model -> Html Msg
viewFretboard model =
    Svg.svg
        [ SA.viewBox ("0 0 " ++ String.fromFloat totalWidth ++ " " ++ String.fromFloat totalHeight)
        , SA.width (String.fromFloat totalWidth)
        , SA.style "max-width: 100%; height: auto;"
        ]
        (List.concat
            [ [ stripePatternDefs ]
            , drawFretMarkers
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
    if isChromatic model.scale then
        -- The all-notes map is not a scale: every fret is a scale tone, so a
        -- CAGED box would cover the whole neck. Show the bare fretboard.
        []

    else if isTriad model.scale then
        -- A triad is a chord, not a position: the grouping that matters is the
        -- three-note voicing, so each one gets its own lasso.
        drawTriadLassos model

    else if isDiagonal model.scale then
        drawDiagonalRegions model

    else
        drawBoxRegionsBoxes model


drawBoxRegionsBoxes : Model -> List (Svg.Svg Msg)
drawBoxRegionsBoxes model =
    let
        octaves =
            [ -1, 0, 1 ]

        solids =
            List.concatMap
                (\b -> List.filterMap (drawSolidBox model b) octaves)
                [ 1, 2, 3, 4, 5 ]

        -- Adjacent boxes share notes wherever the position windows overlap; the
        -- overlap is rendered as a striped two-color band. With `deriveBox` this
        -- can happen for any scale (e.g. pentatonic in Open G), not just the
        -- 7-note modes. In standard tuning pentatonic boxes only touch, so the
        -- overlaps collapse to invisible zero-width pinches.
        overlaps =
            List.concatMap
                (\pair -> List.filterMap (drawOverlapStripe model pair) octaves)
                [ ( 1, 2 ), ( 2, 3 ), ( 3, 4 ), ( 4, 5 ) ]

        wrapOverlaps =
            List.filterMap (drawWrapOverlap model) octaves
    in
    solids ++ overlaps ++ wrapOverlaps


drawDiagonalRegions : Model -> List (Svg.Svg Msg)
drawDiagonalRegions model =
    let
        octaves =
            [ -2, -1, 0, 1, 2 ]
    in
    List.concatMap
        (\shape -> List.filterMap (drawDiagonalShape model.tuning model.scale model.root shape) octaves)
        (diagonalShapesFor model.scale)


{-| One diagonal shape: a stepped polygon spanning two adjacent strings.
Both edges are staircases that step at the midline between the strings; an
edge where both strings share a fret (pattern 1's right, pattern 2's left)
collapses to a vertical line. The shape repeats every 12 frets (one octave)
to fill the neck. -}
drawDiagonalShape : Tuning -> ScaleType -> Int -> DiagShape -> Int -> Maybe (Svg.Svg Msg)
drawDiagonalShape tuning scale root shape octave =
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
                , SA.fill (boxColor shape.color)
                , SA.fillOpacity "0.45"
                ]
                []
            )

    else
        Nothing


{-| Every triad voicing on the neck, drawn as a lasso through its three notes:
a soft wash inside and a ring around it, colored by which chord tone is in the
bass. -}
drawTriadLassos : Model -> List (Svg.Svg Msg)
drawTriadLassos model =
    let
        voicings =
            triadVoicingsFor model.tuning model.scale model.root model.stringSet
    in
    -- With one string set the wash reads the enclosed area at a glance; with all
    -- four it is four layers of tint over the same notes, so the lassos go
    -- outline-only there and the rings do the work.
    (if model.stringSet == AllStrings then
        []

     else
        List.map triadWash voicings
    )
        ++ List.concat (List.indexedMap triadRing voicings)


{-| The lasso shape, shrunk by `inset`: a ribbon along the three note centers
plus a bead around each. Insetting both by the same amount and subtracting one
from the other is what turns the shape into an even outline. The caller paints
it by setting `fill` and `stroke` on a wrapping group. -}
triadBody : Triad -> Float -> List (Svg.Svg Msg)
triadBody triad inset =
    Svg.path
        [ SA.d (triadPath triad)
        , SA.fill "none"
        , SA.strokeWidth (String.fromFloat (triadRibbonWidth triad - 2 * inset))
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        []
        :: List.map
            (\( s, f ) ->
                Svg.circle
                    [ SA.cx (String.fromFloat (noteX f))
                    , SA.cy (String.fromFloat (stringY s))
                    , SA.r (String.fromFloat (triadBeadRadius triad - inset))
                    , SA.strokeWidth "0"
                    ]
                    []
            )
            triad.notes


{-| The ribbon's centerline, through the three note centers. -}
triadPath : Triad -> String
triadPath triad =
    triad.notes
        |> List.map (\( s, f ) -> String.fromFloat (noteX f) ++ "," ++ String.fromFloat (stringY s))
        |> String.join " L "
        |> String.append "M "


{-| The wash inside a lasso. The whole shape fades as one group, so the bead
and ribbon do not double up where they overlap, and lassos that cross in the
all-string-sets view tint each other rather than hide each other. -}
triadWash : Triad -> Svg.Svg Msg
triadWash triad =
    Svg.g
        [ SA.opacity "0.13"
        , SA.fill (inversionColor triad.inversion)
        , SA.stroke (inversionColor triad.inversion)
        ]
        (triadBody triad 0)


{-| The lasso outline: the shape minus the same shape inset, which leaves an
even ring around it. It is a masked rectangle rather than the obvious pair of
strokes (wide in the color, narrower in the background color) because that pair
would paint over whatever sits under the lasso — the inlay dots, and the rings
of any lasso it crosses. The mask punches the middle out instead, so the ring
is genuinely hollow and lassos can overlap freely. -}
triadRing : Int -> Triad -> List (Svg.Svg Msg)
triadRing index triad =
    let
        maskId =
            "triad-lasso-" ++ String.fromInt index

        -- Clear of the widest part of the shape, so the mask never clips it.
        pad =
            triadBeadRadius triad + 4

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
            Svg.g [ SA.fill color, SA.stroke color ] (triadBody triad inset)
    in
    [ Svg.mask (SA.id maskId :: SA.maskUnits "userSpaceOnUse" :: box)
        [ layer "#ffffff" 0
        , layer "#000000" triadLassoInset
        ]
    , Svg.rect (SA.fill (inversionColor triad.inversion) :: SA.mask ("url(#" ++ maskId ++ ")") :: box) []
    ]


drawSolidBox : Model -> Int -> Int -> Maybe (Svg.Svg Msg)
drawSolidBox model b octave =
    let
        fRoot =
            rootFret model

        shift =
            fRoot + 12 * octave

        positions =
            List.map
                (\( s, lo, hi ) -> ( s, lo + shift, hi + shift ))
                (deriveBox model.tuning model.scale b)

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
                , SA.fillOpacity boxFillOpacity
                ]
                []
            )

    else
        Nothing


drawOverlapStripe : Model -> ( Int, Int ) -> Int -> Maybe (Svg.Svg Msg)
drawOverlapStripe model ( b1, b2 ) octave =
    let
        fRoot =
            rootFret model

        shift =
            fRoot + 12 * octave

        overlapPositions =
            List.map2
                (\( s, lo1, hi1 ) ( _, lo2, hi2 ) ->
                    ( s, max lo1 lo2 + shift, min hi1 hi2 + shift )
                )
                (deriveBox model.tuning model.scale b1)
                (deriveBox model.tuning model.scale b2)

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
                , SA.fill ("url(#ovlp-" ++ String.fromInt b1 ++ "-" ++ String.fromInt b2 ++ ")")
                ]
                []
            )

    else
        Nothing


stripePatternDefs : Svg.Svg Msg
stripePatternDefs =
    Svg.defs []
        (List.map overlapStripePattern
            [ ( 1, 2 ), ( 2, 3 ), ( 3, 4 ), ( 4, 5 ), ( 5, 1 ) ]
        )


drawWrapOverlap : Model -> Int -> Maybe (Svg.Svg Msg)
drawWrapOverlap model octave =
    let
        fRoot =
            rootFret model

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
                (deriveBox model.tuning model.scale 5)
                (deriveBox model.tuning model.scale 1)

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
                , SA.fill "url(#ovlp-5-1)"
                ]
                []
            )

    else
        Nothing


overlapStripePattern : ( Int, Int ) -> Svg.Svg Msg
overlapStripePattern ( b1, b2 ) =
    let
        period = 14
        half = period / 2

        -- Pre-blend the box color with the page background at the same ratio
        -- as solid boxes (`boxFillOpacity`), so opaque stripes visually match
        -- adjacent solid box regions.
        blended b =
            "color-mix(in srgb, " ++ boxColor b ++ " " ++ boxBlendPct ++ ", var(--bg))"
    in
    Svg.pattern
        [ SA.id ("ovlp-" ++ String.fromInt b1 ++ "-" ++ String.fromInt b2)
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
            , SA.fill (blended b1)
            ]
            []
        , Svg.rect
            [ SA.x (String.fromFloat half)
            , SA.y "0"
            , SA.width (String.fromFloat half)
            , SA.height (String.fromFloat period)
            , SA.fill (blended b2)
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
                n = noteAt model.tuning s f
                role = noteRole model n
                cx = noteX f
                cy = stringY s

                background =
                    if isChromatic model.scale then
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
                    if isChromatic model.scale then
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
                        [ Svg.text (spelledName model n) ]
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
viewLegend model =
    let
        boxes =
            if isChromatic model.scale then
                []

            else if isTriad model.scale then
                legendText "Bass note:"
                    :: List.map legendRing [ ( 0, "root" ), ( 1, "3rd (1st inv)" ), ( 2, "5th (2nd inv)" ) ]

            else if isDiagonal model.scale then
                legendText "Patterns:"
                    :: List.map legendSwatch [ ( 1, "1" ), ( 2, "2" ) ]

            else
                legendText "Boxes:"
                    :: List.map legendSwatch [ ( 1, "1" ), ( 2, "2" ), ( 3, "3" ), ( 4, "4" ), ( 5, "5" ) ]

        tones =
            if isChromatic model.scale then
                [ legendText "Tones:"
                , legendMarker "square-pc" "Root"
                , legendMarker "circle-pc-dashed"
                    (if model.scale == ChromaticMajor then
                        "3rd"

                     else
                        "♭3"
                    )
                , legendMarker "circle-pc-dotted" "5th"
                , legendMarker "circle-pc-double"
                    (if model.scale == ChromaticMajor then
                        "7th"

                     else
                        "♭7"
                    )
                , legendMarker "circle-pc" "other"
                , legendText "hue = note"
                ]

            else if isTriad model.scale then
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
        (if List.isEmpty boxes then
            [ legendGroup tones ]

         else
            [ legendGroup boxes, legendGroup tones ]
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
            , style "border" ("3px solid " ++ inversionColor inv)
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
subscriptions _ =
    wakeLockChanged WakeLockChanged


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
