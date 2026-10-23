port module Main exposing
    ( ScaleType(..)
    , StringSet(..)
    , Tuning
    , anchorOpen
    , deriveBox
    , diagonalAnchor
    , diagonalOf
    , plainOf
    , diagonalShapes
    , diagonalShapesFor
    , fourthsFor
    , main
    , midiAt
    , nextLowString
    , noteAt
    , openAbs
    , openString
    , resizeTuning
    , rootSpelling
    , scaleDegrees
    , scaleFromSlug
    , scaleIntervals
    , scaleSlug
    , spell
    , standardFor
    , standardTuning
    , stringCount
    , thirdsFor
    , toggleInterval
    , triadVoicingsFor
    , tuningFromSlug
    , tunings
    , tuningsFor
    )

import Browser
import Browser.Events
import Browser.Navigation as Nav
import Html exposing (Html, button, div, h1, p, span, text)
import Html.Attributes exposing (attribute, class, style)
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

    -- The two drawers the controls fold into: the scale picker (root and
    -- scale), which opens under the active neck's heading, and the display
    -- options behind the gear. Open by default on a big screen, shut on a
    -- phone or tablet, where they would push the neck off the first screen.
    -- Drawer state, so like `tuningOpen` not in the URL.
    , scaleOpen : Bool
    , viewOpen : Bool

    -- Which tab of the scale picker is showing. Opening the picker turns it to
    -- the tab that holds the neck's scale; switching tabs only browses.
    , pickerTab : PickerTab

    -- A window too narrow to keep both drawers open. There the drawers act
    -- like menus: one open at a time, and picking a scale shuts the picker.
    , compact : Bool
    , focus : Maybe Focus

    -- The one string you are working on — the **Highlight string** button.
    -- With one set, every note off that string is drawn faded, so a scale you
    -- are walking up a single string reads on its own while the notes around
    -- it stay visible as context. Like the fret window it belongs to the hand
    -- rather than to one neck, so it lives here and applies to every neck.
    , stringFocus : Maybe Int

    -- The **Monochrome** button: boxes and lassos swap their colors for hatched
    -- textures, for printing on a black-and-white printer. Browsers do not
    -- tell a page what the printer can do (`@media (monochrome)` never matches
    -- in print), so it has to be a switch. Like the tuning it applies to every
    -- neck, since a sheet goes to one printer.
    , mono : Bool

    -- The **Degrees** button: every note marker names its interval from the
    -- root (R, 2, ♭3 …) instead of the note. Like monochrome it is a way of
    -- reading the whole page, so it applies to every neck.
    , degrees : Bool

    -- The **Two columns** button: the necks sit two to a row at half width,
    -- which fits twice as many on a printed page.
    , twoColumns : Bool
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
    , stringFocus : Maybe Int
    , mono : Bool
    , degrees : Bool
    , id : String
    , slot : Int
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


{-| A tuning is fully described by its open-string pitch classes, one per
string, ordered string 1 (high E in standard) down to the lowest string (the low
E, string 6, on a guitar). There can be any number of strings, so the length of
the list is the string count. Everything else — which notes are in the scale,
where the CAGED boxes land, how the diagonal shapes climb — is derived from
these numbers at runtime. -}
type alias Tuning =
    { name : String
    , slug : String
    , strings : List Int
    }


port requestWakeLock : () -> Cmd msg


port releaseWakeLock : () -> Cmd msg


port wakeLockChanged : (Bool -> msg) -> Sub msg


{-| Plucks a note, as a MIDI note number — `index.html` synthesizes it. -}
port playNote : Int -> Cmd msg


type ScaleType
    = MajorPent
    | MinorPent
    | MajorBlues
    | Ionian
    | Dorian
    | Phrygian
    | Lydian
    | Mixolydian
    | Aeolian
    | Locrian
    | Blues
    | DominantPent
    | MinorSixPent
    | HarmonicMajor
    | HarmonicMinor
    | UkrainianDorian
    | PhrygianDominant
    | MelodicMajor
    | MelodicMinor
    | DorianFlat2
    | LydianAugmented
    | LydianDominant
    | LocrianNat2
    | Altered
    | BebopDominant
    | BebopMajor
    | BebopMinor
    | DimHalfWhole
    | DimWholeHalf
    | WholeTone
    | DoubleHarmonic
    | HungarianMinor
    | Hirajoshi
    | InSen
    | ChromaticMajor
    | ChromaticMinor
    | Blank
    | TriadMajor
    | TriadMinor
    | TriadDim
    | TriadAug
    | TriadSus2
    | TriadSus4
    | ArpMaj7
    | ArpDom7
    | ArpMin7
    | ArpHalfDim
    | ArpDim7
    | Diagonal ScaleType
    | Plain ScaleType
    | Custom ScaleType (List Int)


{-| Which three adjacent strings carry the triad lassos. `StringTrio t` names a
set by its highest string `t` — strings t, t+1 and t+2, so 1 up to two short of
the string count — and `AllStrings` draws every set at once. Only the triad
modes use it. -}
type StringSet
    = AllStrings
    | StringTrio Int




type Msg
    = SetRoot Int
    | SetScale ScaleType
    | SetTuning Tuning
    | SetStringSet Int StringSet
    | TuneString Int Int
    | ChangeStringCount Int
    | SetFocus (Maybe Focus)
    | SetStringFocus (Maybe Int)
    | ToggleMono
    | ToggleDegrees
    | ToggleColumns
    | ToggleTuningList
    | ToggleScalePicker Int
    | SetPickerTab PickerTab
    | ToggleViewPanel
    | WindowResized Int
    | AddNeck
    | RemoveNeck Int
    | DragStart Int Float Float
    | DragMove Float
    | DragEnd
    | UrlChanged Url
    | LinkClicked Browser.UrlRequest
    | ToggleWakeLock
    | WakeLockChanged Bool
    | FretClicked Int Int Int Bool


{-| The scale picker's tabs: what kind of thing the neck shows. -}
type PickerTab
    = ScalesTab
    | ChordsTab
    | NotesTab


{-| The tab a scale's button is on. -}
tabOf : ScaleType -> PickerTab
tabOf scale =
    let
        base =
            baseScale (boxedOf scale)
    in
    if isTriad base || isArpeggio base then
        ChordsTab

    else if isChromatic base then
        NotesTab

    else
        ScalesTab


init : Int -> Url -> Nav.Key -> ( Model, Cmd Msg )
init width url key =
    let
        state =
            parseUrl url

        activeScale =
            List.drop state.active state.necks
                |> List.head
                |> Maybe.map .scale
                |> Maybe.withDefault defaultNeck.scale

        compact =
            width < compactWidth
    in
    ( { necks = state.necks
      , active = state.active
      , drag = Nothing
      , tuning = state.tuning
      , tuningOpen = False
      , scaleOpen = not compact
      , viewOpen = not compact
      , pickerTab = tabOf activeScale
      , compact = compact
      , focus = state.focus
      , stringFocus = state.stringFocus
      , mono = state.mono
      , degrees = state.degrees
      , twoColumns = state.twoColumns
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
            -- On a small screen picking a scale is the end of the errand, so
            -- the picker shuts. A root does not shut it: root and scale are
            -- usually set together.
            sync
                { model
                    | necks = mapActive (\neck -> { neck | scale = sc }) model
                    , scaleOpen = model.scaleOpen && not model.compact
                }

        SetStringSet i set ->
            sync
                { model
                    | necks =
                        List.indexedMap
                            (\j neck ->
                                if j == i then
                                    { neck | stringSet = set }

                                else
                                    neck
                            )
                            model.necks
                }

        SetTuning t ->
            -- Picking a preset is the end of the errand, so the list folds
            -- away again. Custom is not: the per-string steppers it reveals
            -- are the thing you opened the list for.
            sync { model | tuning = t, tuningOpen = isCustom t }

        ToggleTuningList ->
            ( { model | tuningOpen = not model.tuningOpen }, Cmd.none )

        ToggleScalePicker i ->
            -- A neck's heading opens the picker under it. Pressing another
            -- neck's heading moves the picker there, which is what makes that
            -- neck the one the picker edits. On a small screen one drawer at
            -- a time: two open push the neck off the screen again.
            let
                opening =
                    i /= model.active || not model.scaleOpen
            in
            sync
                { model
                    | active = clampIndex model.necks i
                    , scaleOpen = opening
                    , viewOpen = model.viewOpen && not (model.compact && opening)
                    , pickerTab =
                        if opening then
                            List.drop i model.necks
                                |> List.head
                                |> Maybe.map (.scale >> tabOf)
                                |> Maybe.withDefault model.pickerTab

                        else
                            model.pickerTab
                }

        SetPickerTab tab ->
            ( { model | pickerTab = tab }, Cmd.none )

        ToggleViewPanel ->
            ( { model
                | viewOpen = not model.viewOpen
                , scaleOpen = model.scaleOpen && not (model.compact && not model.viewOpen)
              }
            , Cmd.none
            )

        WindowResized width ->
            ( { model | compact = width < compactWidth }, Cmd.none )

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

        ChangeStringCount delta ->
            -- Strings come and go at the low end, so every string keeps its
            -- number, and a new one is tuned by continuing the pattern. What
            -- pointed at a string that is gone is pulled back onto the neck.
            let
                tuning =
                    resizeTuning (stringCount model.tuning + delta) model.tuning

                strings =
                    stringCount tuning
            in
            sync
                { model
                    | tuning = tuning
                    , necks = List.map (normalizeNeck strings) model.necks
                    , stringFocus = Maybe.map (clampString strings) model.stringFocus
                }

        SetFocus f ->
            sync { model | focus = Maybe.map clampFocus f }

        SetStringFocus s ->
            sync { model | stringFocus = Maybe.map (clampString (stringCount model.tuning)) s }

        ToggleMono ->
            sync { model | mono = not model.mono }

        ToggleDegrees ->
            sync { model | degrees = not model.degrees }

        ToggleColumns ->
            sync { model | twoColumns = not model.twoColumns }

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
                    -- In two columns a row down is two slots on, so the
                    -- neck keeps its column as it travels.
                    let
                        perRow =
                            if model.twoColumns then
                                2

                            else
                                1

                        slots =
                            perRow * round ((y - drag.startY) / max 1 drag.rowHeight)
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
                , stringFocus = state.stringFocus
                , mono = state.mono
                , degrees = state.degrees
                , twoColumns = state.twoColumns
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

        FretClicked _ s f True ->
            -- Shift-click only listens.
            ( model, playNote (midiAt model.tuning s f) )

        FretClicked slot s f False ->
            -- A click both sounds the note and toggles its pitch class in or
            -- out of that neck's scale.
            let
                toggle neck =
                    { neck | scale = toggleInterval (modBy 12 (noteAt model.tuning s f - neck.root)) neck.scale }

                ( synced, cmd ) =
                    sync
                        { model
                            | necks =
                                List.indexedMap
                                    (\j neck ->
                                        if j == slot then
                                            toggle neck

                                        else
                                            neck
                                    )
                                    model.necks
                        }
            in
            ( synced, Cmd.batch [ cmd, playNote (midiAt model.tuning s f) ] )



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
        withFocus =
            case model.focus of
                Nothing ->
                    withTuning

                Just ( lo, hi ) ->
                    withTuning ++ "&focus=" ++ String.fromInt lo ++ "-" ++ String.fromInt hi

        withString =
            case model.stringFocus of
                Nothing ->
                    withFocus

                Just s ->
                    withFocus ++ "&string=" ++ String.fromInt s

        withMono =
            if model.mono then
                withString ++ "&mono=1"

            else
                withString

        withDegrees =
            if model.degrees then
                withMono ++ "&degrees=1"

            else
                withMono
    in
    if model.twoColumns then
        withDegrees ++ "&cols=2"

    else
        withDegrees


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
        MajorBlues -> "major-blues"
        Ionian -> "ionian"
        Aeolian -> "aeolian"
        Dorian -> "dorian"
        Mixolydian -> "mixolydian"
        Phrygian -> "phrygian"
        Lydian -> "lydian"
        Locrian -> "locrian"
        Blues -> "blues"
        DominantPent -> "dominant-pent"
        MinorSixPent -> "minor-6-pent"
        HarmonicMajor -> "harmonic-major"
        HarmonicMinor -> "harmonic-minor"
        UkrainianDorian -> "ukrainian-dorian"
        PhrygianDominant -> "phrygian-dominant"
        MelodicMajor -> "melodic-major"
        MelodicMinor -> "melodic-minor"
        DorianFlat2 -> "dorian-b2"
        LydianAugmented -> "lydian-augmented"
        LydianDominant -> "lydian-dominant"
        LocrianNat2 -> "locrian-nat2"
        Altered -> "altered"
        BebopDominant -> "bebop-dominant"
        BebopMajor -> "bebop-major"
        BebopMinor -> "bebop-minor"
        DimHalfWhole -> "dim-half-whole"
        DimWholeHalf -> "dim-whole-half"
        WholeTone -> "whole-tone"
        DoubleHarmonic -> "double-harmonic"
        HungarianMinor -> "hungarian-minor"
        Hirajoshi -> "hirajoshi"
        InSen -> "in-sen"
        ChromaticMajor -> "all-notes-major"
        ChromaticMinor -> "all-notes-minor"
        Blank -> "blank"
        TriadMajor -> "triad-major"
        TriadMinor -> "triad-minor"
        TriadDim -> "triad-dim"
        TriadAug -> "triad-aug"
        TriadSus2 -> "triad-sus2"
        TriadSus4 -> "triad-sus4"
        ArpMaj7 -> "arp-maj7"
        ArpDom7 -> "arp-7"
        ArpMin7 -> "arp-m7"
        ArpHalfDim -> "arp-m7b5"
        ArpDim7 -> "arp-dim7"
        Diagonal base -> diagonalSlug base
        Plain base -> "plain-" ++ scaleSlug base
        Custom base intervals -> scaleSlug base ++ "_" ++ String.concat (List.map intervalDigit intervals)


{-| A diagonal scale's slug. The five that existed before every seven-note scale
could be drawn diagonally keep the slugs they had, so old links still open. -}
diagonalSlug : ScaleType -> String
diagonalSlug base =
    case base of
        MajorPent -> "diagonal-major-pent"
        MinorPent -> "diagonal-pent"
        Blues -> "diagonal-blues"
        Ionian -> "diagonal-major"
        Aeolian -> "diagonal-minor"
        _ -> "diagonal-" ++ scaleSlug base


{-| One interval as a single hex digit, so a custom scale's notes pack into
the URL as `minor-pent_0257a` without separators. -}
intervalDigit : Int -> String
intervalDigit i =
    String.slice i (i + 1) "0123456789ab"


scaleFromSlug : String -> Maybe ScaleType
scaleFromSlug str =
    if String.startsWith "plain-" str then
        scaleFromSlug (String.dropLeft (String.length "plain-") str)
            |> Maybe.andThen plainOf

    else
    case String.split "_" str of
        [ base, digits ] ->
            presetFromSlug base
                |> Maybe.map
                    (\b ->
                        customScale b
                            (String.toList digits
                                |> List.filterMap (\c -> String.indexes (String.fromChar c) "0123456789ab" |> List.head)
                            )
                    )

        _ ->
            presetFromSlug str


presetFromSlug : String -> Maybe ScaleType
presetFromSlug s =
    case s of
        "major-pent" -> Just MajorPent
        "minor-pent" -> Just MinorPent
        "major-blues" -> Just MajorBlues
        "ionian" -> Just Ionian
        "aeolian" -> Just Aeolian
        "dorian" -> Just Dorian
        "mixolydian" -> Just Mixolydian
        "phrygian" -> Just Phrygian
        "lydian" -> Just Lydian
        "locrian" -> Just Locrian
        "blues" -> Just Blues
        "dominant-pent" -> Just DominantPent
        "minor-6-pent" -> Just MinorSixPent
        "harmonic-major" -> Just HarmonicMajor
        "harmonic-minor" -> Just HarmonicMinor
        "ukrainian-dorian" -> Just UkrainianDorian
        "phrygian-dominant" -> Just PhrygianDominant
        "melodic-major" -> Just MelodicMajor
        "melodic-minor" -> Just MelodicMinor
        "dorian-b2" -> Just DorianFlat2
        "lydian-augmented" -> Just LydianAugmented
        "lydian-dominant" -> Just LydianDominant
        "locrian-nat2" -> Just LocrianNat2
        "altered" -> Just Altered
        "bebop-dominant" -> Just BebopDominant
        "bebop-major" -> Just BebopMajor
        "bebop-minor" -> Just BebopMinor
        "dim-half-whole" -> Just DimHalfWhole
        "dim-whole-half" -> Just DimWholeHalf
        "whole-tone" -> Just WholeTone
        "double-harmonic" -> Just DoubleHarmonic
        "hungarian-minor" -> Just HungarianMinor
        "hirajoshi" -> Just Hirajoshi
        "in-sen" -> Just InSen
        "all-notes-major" -> Just ChromaticMajor
        "all-notes-minor" -> Just ChromaticMinor
        "blank" -> Just Blank
        "triad-major" -> Just TriadMajor
        "triad-minor" -> Just TriadMinor
        "triad-dim" -> Just TriadDim
        "triad-aug" -> Just TriadAug
        "triad-sus2" -> Just TriadSus2
        "triad-sus4" -> Just TriadSus4
        "arp-maj7" -> Just ArpMaj7
        "arp-7" -> Just ArpDom7
        "arp-m7" -> Just ArpMin7
        "arp-m7b5" -> Just ArpHalfDim
        "arp-dim7" -> Just ArpDim7
        -- The all-notes map used to be a single mode; keep old links working.
        "all-notes" -> Just ChromaticMinor
        "diagonal-major-pent" -> Just (Diagonal MajorPent)
        "diagonal-pent" -> Just (Diagonal MinorPent)
        "diagonal-blues" -> Just (Diagonal Blues)
        "diagonal-major" -> Just (Diagonal Ionian)
        "diagonal-minor" -> Just (Diagonal Aeolian)
        _ ->
            if String.startsWith "diagonal-" s then
                presetFromSlug (String.dropLeft (String.length "diagonal-") s)
                    |> Maybe.andThen diagonalOf

            else
                Nothing


stringSetSlug : StringSet -> String
stringSetSlug set =
    case set of
        AllStrings ->
            "all"

        StringTrio t ->
            String.join "-" (List.map String.fromInt [ t, t + 1, t + 2 ])


stringSetFromSlug : String -> Maybe StringSet
stringSetFromSlug s =
    if s == "all" then
        Just AllStrings

    else
        case List.map String.toInt (String.split "-" s) of
            [ Just a, Just b, Just c ] ->
                if a >= 1 && b == a + 1 && c == a + 2 then
                    Just (StringTrio a)

                else
                    Nothing

            _ ->
                Nothing


{-| A string set the tuning actually has: three adjacent strings that exist, or
all of them. Taking a string away leaves a set that pointed at it meaning
"all", rather than nothing. -}
normalizeSet : Int -> StringSet -> StringSet
normalizeSet n set =
    case set of
        StringTrio t ->
            if t >= 1 && t <= n - 2 then
                set

            else
                AllStrings

        AllStrings ->
            AllStrings


normalizeNeck : Int -> Neck -> Neck
normalizeNeck n neck =
    { neck | stringSet = normalizeSet n neck.stringSet }


{-| Everything the URL carries: the list of necks, which of them the controls
edit, and the tuning they are all played in. -}
type alias UrlState =
    { necks : List Neck
    , active : Int
    , tuning : Tuning
    , focus : Maybe Focus
    , stringFocus : Maybe Int
    , mono : Bool
    , degrees : Bool
    , twoColumns : Bool
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
                |> Maybe.withDefault defaultNeck.scale

        stringSet =
            lookup "strings"
                |> Maybe.andThen stringSetFromSlug
                |> Maybe.withDefault AllStrings

        single =
            { root =
                lookup "root"
                    |> Maybe.andThen rootFromSlug
                    |> Maybe.withDefault defaultNeck.root
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

        tuning =
            lookup "tuning"
                |> Maybe.andThen tuningFromSlug
                |> Maybe.withDefault standardTuning

        strings =
            stringCount tuning
    in
    { necks = List.map (normalizeNeck strings) necks
    , active =
        lookup "active"
            |> Maybe.andThen String.toInt
            |> Maybe.withDefault 0
            |> clampIndex necks
    , tuning = tuning
    , focus =
        lookup "focus"
            |> Maybe.andThen focusFromSlug
            |> Maybe.map clampFocus
    , stringFocus =
        lookup "string"
            |> Maybe.andThen String.toInt
            |> Maybe.map (clampString strings)
    , mono = lookup "mono" == Just "1"
    , degrees = lookup "degrees" == Just "1"
    , twoColumns = lookup "cols" == Just "2"
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


{-| What a bare page opens on: C major, the first scale in the picker. -}
defaultNeck : Neck
defaultNeck =
    { root = 0, scale = Ionian, stringSet = AllStrings }


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
    , stringSet = normalizeSet (stringCount model.tuning) neck.stringSet
    , tuning = model.tuning
    , focus = model.focus
    , stringFocus = model.stringFocus
    , mono = model.mono
    , degrees = model.degrees
    , id = "n" ++ String.fromInt i ++ "-"
    , slot = i
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


{-| The string a fresh string highlight opens on: the lowest string, the one a
scale is usually walked up first (the low E on a six-string neck, which is also
the string the boxes are anchored to). -}
defaultStringFocus : Tuning -> Int
defaultStringFocus =
    stringCount


{-| Keeps a string number on the neck, given how many strings it has. -}
clampString : Int -> Int -> Int
clampString n =
    clamp 1 n


{-| How far back the notes off the highlighted string are drawn. They fade
rather than disappear: where the note you want sits relative to its neighbors
is half of what you are looking at. -}
offStringOpacity : Float
offStringOpacity =
    0.25


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


{-| Named presets resolve by their slug. The ones that carry on to any number
of strings take the count as a suffix (`standard-7`, `all-fourths-8`); without
one they mean six, as they always did. Anything else is parsed as a custom
tuning encoded as dash-joined note slugs, high string to low (e.g.
`E-A-D-G-B-E`, as many as it has strings). A note-encoded slug always stays
Custom — even when its notes match a preset — so editing/entering custom mode
round-trips through the URL (`Nav.replaceUrl` re-fires `UrlChanged`) without
collapsing back to a preset. -}
tuningFromSlug : String -> Maybe Tuning
tuningFromSlug s =
    case List.filter (\t -> t.slug == s) (tunings ++ extendedTunings) of
        match :: _ ->
            Just match

        [] ->
            case generatedFromSlug s of
                Just t ->
                    Just t

                Nothing ->
                    let
                        tokens =
                            String.split "-" s

                        parsed =
                            List.filterMap rootFromSlug tokens
                    in
                    if List.length parsed == List.length tokens && List.length parsed <= maxStrings then
                        Just (customFrom parsed)

                    else
                        Nothing


{-| `standard-7`, `all-fourths-8`, `all-major-thirds-5`: a rule-built tuning and
its string count. -}
generatedFromSlug : String -> Maybe Tuning
generatedFromSlug s =
    case List.reverse (String.split "-" s) of
        last :: rest ->
            case String.toInt last of
                Just n ->
                    if n >= 1 && n <= maxStrings then
                        case String.join "-" (List.reverse rest) of
                            "standard" ->
                                Just (standardFor n)

                            "all-fourths" ->
                                Just (fourthsFor n)

                            "all-major-thirds" ->
                                Just (thirdsFor n)

                            _ ->
                                Nothing

                    else
                        Nothing

                Nothing ->
                    Nothing

        [] ->
            Nothing


isCustom : Tuning -> Bool
isCustom t =
    t.name == customName


customName : String
customName =
    "Custom"


{-| A custom tuning from its open-string pitch classes, always named "Custom" so the UI
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


{-| Candidate letters for spelling a root. A natural note is always its own
letter — the root you picked as C is never shown as B♯, even where that would
save accidentals (C diminished 7th would otherwise come out B♯ D♯ F♯ A). A black
key is either of its two names. -}
rootLetterCandidates : Int -> List Int
rootLetterCandidates pc =
    case List.filter (\li -> accidentalFor li pc == 0) (List.range 0 6) of
        [] ->
            List.filter (\li -> abs (accidentalFor li pc) == 1) (List.range 0 6)

        natural ->
            natural


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
        MajorBlues -> [ 1, 2, 3, 3, 5, 6 ]
        Ionian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Aeolian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Dorian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Mixolydian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Phrygian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Lydian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Locrian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Blues -> [ 1, 3, 4, 5, 5, 7 ]
        DominantPent -> [ 1, 2, 3, 5, 7 ]
        MinorSixPent -> [ 1, 3, 4, 5, 6 ]
        HarmonicMajor -> [ 1, 2, 3, 4, 5, 6, 7 ]
        HarmonicMinor -> [ 1, 2, 3, 4, 5, 6, 7 ]
        UkrainianDorian -> [ 1, 2, 3, 4, 5, 6, 7 ]
        PhrygianDominant -> [ 1, 2, 3, 4, 5, 6, 7 ]
        MelodicMajor -> [ 1, 2, 3, 4, 5, 6, 7 ]
        MelodicMinor -> [ 1, 2, 3, 4, 5, 6, 7 ]
        DorianFlat2 -> [ 1, 2, 3, 4, 5, 6, 7 ]
        LydianAugmented -> [ 1, 2, 3, 4, 5, 6, 7 ]
        LydianDominant -> [ 1, 2, 3, 4, 5, 6, 7 ]
        LocrianNat2 -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Altered -> [ 1, 2, 2, 3, 5, 5, 7 ]
        BebopDominant -> [ 1, 2, 3, 4, 5, 6, 7, 7 ]
        BebopMajor -> [ 1, 2, 3, 4, 5, 6, 6, 7 ]
        BebopMinor -> [ 1, 2, 3, 3, 4, 5, 6, 7 ]
        DimHalfWhole -> [ 1, 2, 2, 3, 4, 5, 6, 7 ]
        DimWholeHalf -> [ 1, 2, 3, 4, 5, 6, 6, 7 ]
        WholeTone -> [ 1, 2, 3, 4, 5, 7 ]
        DoubleHarmonic -> [ 1, 2, 3, 4, 5, 6, 7 ]
        HungarianMinor -> [ 1, 2, 3, 4, 5, 6, 7 ]
        Hirajoshi -> [ 1, 2, 3, 5, 6 ]
        InSen -> [ 1, 2, 4, 5, 7 ]
        ChromaticMajor -> [ 1, 2, 2, 3, 3, 4, 5, 5, 6, 6, 7, 7 ]
        ChromaticMinor -> [ 1, 2, 2, 3, 3, 4, 5, 5, 6, 6, 7, 7 ]
        Blank -> []
        TriadMajor -> [ 1, 3, 5 ]
        TriadMinor -> [ 1, 3, 5 ]
        TriadDim -> [ 1, 3, 5 ]
        TriadAug -> [ 1, 3, 5 ]
        TriadSus2 -> [ 1, 2, 5 ]
        TriadSus4 -> [ 1, 4, 5 ]
        ArpMaj7 -> [ 1, 3, 5, 7 ]
        ArpDom7 -> [ 1, 3, 5, 7 ]
        ArpMin7 -> [ 1, 3, 5, 7 ]
        ArpHalfDim -> [ 1, 3, 5, 7 ]
        ArpDim7 -> [ 1, 3, 5, 7 ]
        Diagonal base -> scaleDegrees base
        Plain base -> scaleDegrees base
        Custom base intervals -> List.map (customDegree base) intervals


{-| The scale degree an edited scale's interval is spelled as: the preset's own
where it has that note, otherwise the common reading (♭2, ♭3, ♭5, ♭6, ♭7). -}
customDegree : ScaleType -> Int -> Int
customDegree base i =
    List.map2 Tuple.pair (scaleIntervals base) (scaleDegrees base)
        |> List.filter (\( j, _ ) -> j == i)
        |> List.head
        |> Maybe.map Tuple.second
        |> Maybe.withDefault
            (List.drop i [ 1, 2, 2, 3, 3, 4, 5, 5, 6, 6, 7, 7 ] |> List.head |> Maybe.withDefault 1)


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


{-| How many strings a tuning has. The list *is* the tuning, so this is the
whole of the string count: nothing else on the model has to agree with it. -}
stringCount : Tuning -> Int
stringCount t =
    max 1 (List.length t.strings)


{-| The most strings the page will draw. It is only here so a hand-edited link
cannot ask for a neck with a hundred million strings; the stepper stops at the
same number, since the URL is re-read after every change. -}
maxStrings : Int
maxStrings =
    1000


{-| The open pitch class of string `s` in standard tuning, continued below the
low E in fourths (B, F♯, C♯ …) for as many strings as there are. Strings are
numbered from the top, so a string keeps its standard note whatever is added
below it. This is what Standard means at seven strings and up, and what the
diagonal shapes are measured against (`stringDelta`), since their pairs of
strings climb in fourths. The box windows use `windowOpen` instead. -}
referenceOpen : Int -> Int
referenceOpen s =
    if s <= 6 then
        standardTuning.strings |> List.drop (s - 1) |> List.head |> Maybe.withDefault 4

    else
        modBy 12 (4 - 5 * (s - 6))


{-| The open pitch class each string's box window is measured against: standard
tuning, repeated every five strings (E A D G B, then E B G D A … down the neck),
so below the sixth string a string is measured against the one five above it.
Standard tuning's top and bottom strings are both E, two octaves apart, and the
boxes show the same notes on both. This carries that on: strings five apart
sit two octaves apart in the reference, so each box shows the same notes on
them whatever the tuning, rather than slipping a fret every five strings the
way a tuning in fourths drifts against itself (25 semitones, not 24). -}
windowOpen : Int -> Int
windowOpen s =
    if s <= 6 then
        referenceOpen s

    else
        referenceOpen (modBy 5 (s - 2) + 2)


{-| The MIDI note of string `s` in standard tuning, continued down in fourths
the same way: the low E is E2 (40), the high E is E4 (64), a seventh string is
B1 (35). -}
referenceMidi : Int -> Int
referenceMidi s =
    if s <= 6 then
        [ 64, 59, 55, 50, 45, 40 ] |> List.drop (s - 1) |> List.head |> Maybe.withDefault 40

    else
        40 - 5 * (s - 6)


{-| The string the box geometry is anchored to: the low E, or the lowest string
there is when there are fewer than six. -}
anchorString : Tuning -> Int
anchorString t =
    min 6 (stringCount t)


{-| The open pitch the low E would have in this tuning, whether or not there is
one. With six or more strings it is just string 6. With fewer, it is the
lowest string's pitch moved to where standard tuning keeps the low E relative
to it — so a five-string neck without its low E draws its boxes in the same
places the six-string one does, instead of sliding them to the A string. -}
anchorOpen : Tuning -> Int
anchorOpen t =
    let
        a =
            anchorString t
    in
    modBy 12 (openString t a + referenceOpen 6 - referenceOpen a)


{-| A tuning of `n` strings from a rule that gives the pitch class of string
`s`, named and slugged so it can be looked up again. Only the six-string slug is
bare (`all-fourths`), so every link made before there were other counts still
means what it did. -}
generated : String -> String -> Int -> (Int -> Int) -> Tuning
generated name base n note =
    { name = name
    , slug =
        if n == 6 then
            base

        else
            base ++ "-" ++ String.fromInt n
    , strings = List.map (\s -> modBy 12 (note s)) (List.range 1 n)
    }


{-| Standard tuning for any number of strings: the top `n` of standard
tuning, continued below in fourths. -}
standardFor : Int -> Tuning
standardFor n =
    generated "Standard" "standard" n referenceOpen


{-| Every string a fourth below the one above, from the high F: E A D G C F at
six strings, B E A D G C F at seven. -}
fourthsFor : Int -> Tuning
fourthsFor n =
    generated "All Fourths" "all-fourths" n (\s -> 5 - 5 * (s - 1))


{-| Every string a major third below the one above, from the high C: E G♯ C E
G♯ C at six strings. Three strings go all the way round the octave, so the
pattern repeats every third string. -}
thirdsFor : Int -> Tuning
thirdsFor n =
    generated "All Major Thirds" "all-major-thirds" n (\s -> 0 - 4 * (s - 1))


{-| Built-in six-string tunings offered in the selector. `strings` lists the
open pitch classes high (string 1) to low (string 6). Any tuning not in a list
is still fully supported as a custom tuning — the geometry is derived, not
table-driven. -}
tunings : List Tuning
tunings =
    [ standardTuning
    , { name = "Drop D", slug = "drop-d", strings = [ 4, 11, 7, 2, 9, 2 ] }
    , { name = "D♯/E♭ Standard", slug = "eb-standard", strings = [ 3, 10, 6, 1, 8, 3 ] }
    , { name = "D Standard", slug = "d-standard", strings = [ 2, 9, 5, 0, 7, 2 ] }
    , { name = "Drop C", slug = "drop-c", strings = [ 2, 9, 5, 0, 7, 0 ] }
    , { name = "C♯/D♭ Standard", slug = "cs-standard", strings = [ 1, 8, 4, 11, 6, 1 ] }
    , fourthsFor 6
    , thirdsFor 6
    , { name = "DADGAD", slug = "dadgad", strings = [ 2, 9, 7, 2, 9, 2 ] }
    , { name = "Open G", slug = "open-g", strings = [ 2, 11, 7, 2, 7, 2 ] }
    , { name = "Open D", slug = "open-d", strings = [ 2, 9, 6, 2, 9, 2 ] }
    , { name = "Open E", slug = "open-e", strings = [ 4, 11, 8, 4, 11, 4 ] }
    ]


{-| The named seven- and eight-string tunings, which only exist at their own
string count. -}
extendedTunings : List Tuning
extendedTunings =
    [ { name = "Drop A", slug = "drop-a", strings = [ 4, 11, 7, 2, 9, 4, 9 ] }
    , { name = "A Standard", slug = "a-standard", strings = [ 2, 9, 5, 0, 7, 2, 9 ] }
    , { name = "Russian (Open G)", slug = "russian", strings = [ 2, 11, 7, 2, 11, 7, 2 ] }
    , { name = "Drop E", slug = "drop-e", strings = [ 4, 11, 7, 2, 9, 4, 11, 4 ] }
    , { name = "E Standard", slug = "e-standard", strings = [ 2, 9, 5, 0, 7, 2, 9, 4 ] }
    ]


{-| The tunings offered for a string count: whatever is named for it, then
standard, all fourths and all major thirds, which carry on to any number of
strings. -}
tuningsFor : Int -> List Tuning
tuningsFor n =
    if n == 6 then
        tunings

    else
        [ standardFor n ]
            ++ List.filter (\t -> stringCount t == n) extendedTunings
            ++ [ fourthsFor n, thirdsFor n ]


{-| What the next string below the lowest is most likely tuned to: the same
step again. A tuning in fourths goes on in fourths, so standard grows a low B
and then an F♯, and one in major thirds goes on in major thirds. A step wider
than a fourth (the fifth that Drop D and the open tunings end on) would drop
the new string far below the rest, so those take a fourth instead. -}
nextLowString : List Int -> Int
nextLowString strings =
    case List.reverse strings of
        low :: next :: _ ->
            let
                step =
                    modBy 12 (next - low)
            in
            modBy 12
                (low
                    - (if step >= 1 && step <= 5 then
                        step

                       else
                        5
                      )
                )

        [ only ] ->
            modBy 12 (only - 5)

        [] ->
            4


{-| The same tuning with `n` strings, taken from or added to the low end, so
every string keeps its number. The result is a named tuning when it is one —
standard with a string added is Standard (7) — and Custom otherwise; a
tuning that was already Custom stays Custom, for the same reason a typed-in
tuning always does (`customFrom`). -}
resizeTuning : Int -> Tuning -> Tuning
resizeTuning n tuning =
    let
        target =
            clamp 1 maxStrings n

        grow notes =
            if List.length notes >= target then
                notes

            else
                grow (notes ++ [ nextLowString notes ])

        strings =
            grow (List.take target tuning.strings)
    in
    if isCustom tuning then
        customFrom strings

    else
        case List.filter (\t -> t.strings == strings) (tuningsFor (List.length strings)) of
            named :: _ ->
                named

            [] ->
                customFrom strings


{-| Open-string pitch class for string `s` (1 = high E … the lowest string). -}
openString : Tuning -> Int -> Int
openString tuning s =
    tuning.strings |> List.drop (s - 1) |> List.head |> Maybe.withDefault 0


noteAt : Tuning -> Int -> Int -> Int
noteAt tuning s f =
    modBy 12 (openString tuning s + f)


{-| The open pitch of string `s` in absolute semitones, counted up from the
lowest string. A tuning only stores pitch *classes*, so the span between two
adjacent strings is read as the smallest ascending interval that fits, with a
unison reading as an octave — true for every real tuning, and it keeps the
strings strictly ascending in any custom one. Triads need this: "the next chord
tone above" is a question about pitch, not pitch class. -}
openAbs : Tuning -> Int -> Int
openAbs tuning s =
    List.foldl (\str acc -> acc + ascendingStep tuning str)
        (openString tuning (stringCount tuning))
        (List.range s (stringCount tuning - 1))


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
higher than in standard). Past the sixth string, standard is continued in
fourths (`referenceOpen`). -}
stringDelta : Tuning -> Int -> Int
stringDelta tuning s =
    let
        d =
            modBy 12 (referenceOpen s - openString tuning s)
    in
    if d > 6 then
        d - 12

    else
        d


{-| The per-string fret shift that re-derives a standard-tuning box shape for
an arbitrary tuning. The anchor lives on the low E (see `anchorString`); a box
keeps the *same pitches*, so on each string its frets move by how that string
detuned relative to the anchor string. Standard tuning gives 0 for every
string, so all existing shapes are unchanged. The shift preserves the pitch
class at every box edge, which is why boxes and note markers stay aligned for
any tuning. -}
boxShift : Tuning -> Int -> Int
boxShift tuning s =
    stringDelta tuning s - stringDelta tuning (anchorString tuning)


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

        -- The major pentatonic with the minor third as a passing tone.
        MajorBlues ->
            [ 0, 2, 3, 4, 7, 9 ]

        Blues ->
            [ 0, 3, 5, 6, 7, 10 ]

        -- Mixolydian and Dorian cut to five notes: the major pentatonic with
        -- a ♭7 for the 6, the minor pentatonic with a 6 for the ♭7.
        DominantPent ->
            [ 0, 2, 4, 7, 10 ]

        MinorSixPent ->
            [ 0, 3, 5, 7, 9 ]

        -- Major with a ♭6, the mirror of harmonic minor's raised 7th.
        HarmonicMajor ->
            [ 0, 2, 4, 5, 7, 8, 11 ]

        HarmonicMinor ->
            [ 0, 2, 3, 5, 7, 8, 11 ]

        -- Harmonic minor's fourth mode.
        UkrainianDorian ->
            [ 0, 2, 3, 6, 7, 9, 10 ]

        -- Harmonic minor's fifth mode: the dominant of a minor key.
        PhrygianDominant ->
            [ 0, 1, 4, 5, 7, 8, 10 ]

        -- Major with ♭6 and ♭7 (Mixolydian ♭6), the mirror of melodic minor's
        -- raised 6th and 7th.
        MelodicMajor ->
            [ 0, 2, 4, 5, 7, 8, 10 ]

        MelodicMinor ->
            [ 0, 2, 3, 5, 7, 9, 11 ]

        -- Melodic minor's modes, in mode order (mode 5 is melodic major):
        -- the two dominant scales of jazz are 4, Lydian dominant (7♯11), and
        -- 7, the altered dominant; Locrian ♮2 (6) is the half-diminished one.
        DorianFlat2 ->
            [ 0, 1, 3, 5, 7, 9, 10 ]

        LydianAugmented ->
            [ 0, 2, 4, 6, 8, 9, 11 ]

        LydianDominant ->
            [ 0, 2, 4, 6, 7, 9, 10 ]

        LocrianNat2 ->
            [ 0, 2, 3, 5, 6, 8, 10 ]

        Altered ->
            [ 0, 1, 3, 4, 6, 8, 10 ]

        -- The bebop scales add one chromatic passing tone to a seven-note
        -- scale, so a run of eighth notes lands its chord tones on the beat:
        -- the major 7th in Mixolydian, the ♭6 in major, the 3rd in Dorian.
        BebopDominant ->
            [ 0, 2, 4, 5, 7, 9, 10, 11 ]

        BebopMajor ->
            [ 0, 2, 4, 5, 7, 8, 9, 11 ]

        BebopMinor ->
            [ 0, 2, 3, 4, 5, 7, 9, 10 ]

        -- The symmetric scales: the diminished ones repeat every minor
        -- third, the whole-tone scale every whole step.
        DimHalfWhole ->
            [ 0, 1, 3, 4, 6, 7, 9, 10 ]

        DimWholeHalf ->
            [ 0, 2, 3, 5, 6, 8, 9, 11 ]

        WholeTone ->
            [ 0, 2, 4, 6, 8, 10 ]

        -- Double harmonic major and Hungarian minor are one scale a fifth
        -- apart (Hungarian minor is the fourth mode), two augmented 2nds each.
        -- Hirajoshi and In Sen are Japanese pentatonics.
        DoubleHarmonic ->
            [ 0, 1, 4, 5, 7, 8, 11 ]

        HungarianMinor ->
            [ 0, 2, 3, 6, 7, 8, 11 ]

        Hirajoshi ->
            [ 0, 2, 3, 7, 8 ]

        InSen ->
            [ 0, 1, 5, 7, 10 ]

        ChromaticMajor ->
            List.range 0 11

        ChromaticMinor ->
            List.range 0 11

        Blank ->
            []

        TriadMajor ->
            [ 0, 4, 7 ]

        TriadMinor ->
            [ 0, 3, 7 ]

        TriadDim ->
            [ 0, 3, 6 ]

        TriadAug ->
            [ 0, 4, 8 ]

        -- The suspended triads put a 2nd or a 4th where the third would be.
        TriadSus2 ->
            [ 0, 2, 7 ]

        TriadSus4 ->
            [ 0, 5, 7 ]

        -- Seventh-chord arpeggios, always drawn as diagonal sweep shapes
        -- (`isArpeggio`).
        ArpMaj7 ->
            [ 0, 4, 7, 11 ]

        ArpDom7 ->
            [ 0, 4, 7, 10 ]

        ArpMin7 ->
            [ 0, 3, 7, 10 ]

        ArpHalfDim ->
            [ 0, 3, 6, 10 ]

        ArpDim7 ->
            [ 0, 3, 6, 9 ]

        Diagonal base ->
            scaleIntervals base

        Plain base ->
            scaleIntervals base

        Custom _ intervals ->
            intervals


{-| A scale built by clicking notes on and off the neck. It remembers the
preset it started from: that names it, spells it, and picks its third and
seventh where the notes alone leave it open — and toggling back to the
preset's own notes turns it back into that preset, so its button lights up
again. -}
customScale : ScaleType -> List Int -> ScaleType
customScale base intervals =
    let
        sorted =
            List.sort (List.foldl (\i acc -> if List.member i acc then acc else i :: acc) [] intervals)
    in
    if sorted == List.sort (scaleIntervals base) then
        base

    else
        Custom base sorted


{-| The preset a scale started from — itself, unless it has been edited. -}
baseScale : ScaleType -> ScaleType
baseScale scale =
    case scale of
        Custom base _ ->
            base

        _ ->
            scale


{-| Adds the interval to the scale, or takes it out if it is already there. -}
toggleInterval : Int -> ScaleType -> ScaleType
toggleInterval interval scale =
    case scale of
        Plain inner ->
            -- Building a scale on a neck with no shapes keeps it that way.
            Plain (toggleInterval interval inner)

        _ ->
            toggleIntervalShaped interval scale


toggleIntervalShaped : Int -> ScaleType -> ScaleType
toggleIntervalShaped interval scale =
    let
        intervals =
            scaleIntervals scale
    in
    customScale (baseScale scale)
        (if List.member interval intervals then
            List.filter ((/=) interval) intervals

         else
            interval :: intervals
        )


{-| Of two candidate intervals for a chord tone (♭3 or 3, ♭7 or 7), the one an
edited scale holds — or, if it holds both, the one its preset uses. -}
pickTone : ScaleType -> List Int -> Int -> Int -> Int -> Int
pickTone base intervals fromBase a b =
    case ( List.member a intervals, List.member b intervals ) of
        ( True, False ) ->
            a

        ( False, True ) ->
            b

        ( True, True ) ->
            fromBase

        ( False, False ) ->
            -1


{-| The MIDI note sounding at a fret. The lowest string sits nearest where
standard tuning, continued down in fourths, puts it (the low E of a guitar is E2
= 40, a seventh string B1), and the rest are stacked above it by `openAbs`. -}
midiAt : Tuning -> Int -> Int -> Int
midiAt tuning s f =
    let
        n =
            stringCount tuning

        low =
            referenceMidi n + modBy 12 (openString tuning n - referenceOpen n + 6) - 6
    in
    low + openAbs tuning s - openString tuning n + f


scaleNotes : Board -> List Int
scaleNotes board =
    List.map (\i -> modBy 12 (board.root + i)) (scaleIntervals board.scale)


isInScale : Board -> Int -> Bool
isInScale board n =
    List.member (modBy 12 n) (scaleNotes board)


{-| The "shape anchor" fret on the low-E string (`anchorOpen`).
Minor pent of R → R's fret on low E.
Major pent of R → relative minor (R - 3)'s fret on low E.
-}
rootFret : Board -> Int
rootFret board =
    let
        -- The anchor is a fret on the low string, so it follows that string's
        -- open pitch in any tuning. In standard tuning (low E = 4) a minor
        -- scale anchors at R − 4 and a major one at R − 7.
        lowE =
            anchorOpen board.tuning
    in
    case board.scale of
        _ ->
            if isDiagonal board.scale then
                diagonalAnchor board.tuning board.scale board.root

            else
                modBy 12 (board.root - anchorOffset board.scale - lowE)


isDiagonal : ScaleType -> Bool
isDiagonal scale =
    case scale of
        Diagonal _ -> True
        _ -> isArpeggio scale


{-| The seventh-chord arpeggios. They are always drawn diagonally, the way a
triad is always lassoed: an arpeggio is learned as a sweep shape climbing
across the neck, two notes per string, not as a position, so there are no
boxes for it. -}
isArpeggio : ScaleType -> Bool
isArpeggio scale =
    List.member scale [ ArpMaj7, ArpDom7, ArpMin7, ArpHalfDim, ArpDim7 ]


{-| The diagonal climbing shapes of a scale, for the scales that have them:
the blues, which has shapes of its own, every five- and seven-note scale,
whose shapes `splitDiagonalPatterns` reads off its intervals, and the arpeggios, which are diagonal already. An edited scale has
none: it is drawn in boxes. -}
diagonalOf : ScaleType -> Maybe ScaleType
diagonalOf scale =
    case scale of
        MajorPent -> Just (Diagonal scale)
        MinorPent -> Just (Diagonal scale)
        Blues -> Just (Diagonal scale)
        Diagonal _ -> Nothing
        Custom _ _ -> Nothing
        _ ->
            if isArpeggio scale then
                Just scale

            else if List.member (List.length (scaleIntervals scale)) [ 5, 7 ] then
                Just (Diagonal scale)

            else
                Nothing


{-| A scale drawn with no shapes at all, just its notes: for every scale that
has shapes to leave off, which is all but the all-notes maps (no shapes to
begin with) and the triads (whose lassos are the point). -}
plainOf : ScaleType -> Maybe ScaleType
plainOf scale =
    case scale of
        Diagonal _ -> Nothing
        Plain _ -> Nothing
        _ ->
            if isChromatic scale || isTriad scale then
                Nothing

            else
                Just (Plain scale)


isPlain : ScaleType -> Bool
isPlain scale =
    case scale of
        Plain _ -> True
        _ -> False


{-| The scale a diagonal or plain one draws, in boxes; every other scale is itself. -}
boxedOf : ScaleType -> ScaleType
boxedOf scale =
    case scale of
        Diagonal base -> base
        Plain base -> base
        _ -> scale


{-| The two all-notes maps — every note on the neck, with the chord tones read
through a minor (♭3, 5, ♭7) or major (3, 5, 7) lens. Neither is a scale, so they
share every special case in the code; only `noteRole` tells them apart. `Blank`
rides along: it is the same bare neck with no notes on it at all.
-}
isChromatic : ScaleType -> Bool
isChromatic scale =
    scale == ChromaticMinor || scale == ChromaticMajor || scale == Blank


{-| What a triad's middle tone is called: the 3rd, or the 2nd or 4th that a
suspended chord has in its place. -}
triadMiddle : ScaleType -> String
triadMiddle scale =
    case scale of
        TriadSus2 -> "2nd"
        TriadSus4 -> "4th"
        _ -> "3rd"


{-| The triad modes (major, minor, diminished, augmented, sus2, sus4): not scales either, but chords — three notes, drawn as
lassos around each close-position voicing instead of CAGED boxes. -}
isTriad : ScaleType -> Bool
isTriad scale =
    List.member scale [ TriadMajor, TriadMinor, TriadDim, TriadAug, TriadSus2, TriadSus4 ]


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


{-| How far the root sits above box 1's anchor note, in semitones. Box 1
anchors on the low string at the minor-pentatonic root that the scale's boxes
are built around: the root itself for minor scales, and the relative minor (a
minor third below) for major ones.

The church modes all borrow the boxes of their parent major scale, so they all
anchor on that scale's relative minor — D Dorian on A, like C major, since it
holds the same notes. Anchoring Dorian on its own relative minor (B) put its
boxes two frets off C major's, in positions no one plays. -}
anchorOffset : ScaleType -> Int
anchorOffset scale =
    case scale of
        MajorPent -> 3
        MajorBlues -> 3
        Ionian -> 3
        Dorian -> 5
        Phrygian -> 7
        Lydian -> 8
        Mixolydian -> 10
        DominantPent -> 10
        MinorSixPent -> 5
        UkrainianDorian -> 5
        DorianFlat2 -> 2
        LydianAugmented -> 3
        LocrianNat2 -> 9
        DoubleHarmonic -> 7
        InSen -> 7
        Locrian -> 2
        HarmonicMajor -> 3
        PhrygianDominant -> 7
        MelodicMajor -> 3
        LydianDominant -> 5
        Altered -> 11
        BebopDominant -> 10
        BebopMajor -> 3
        BebopMinor -> 5
        DimHalfWhole -> 3
        WholeTone -> 3
        ChromaticMajor -> 3
        TriadMajor -> 3
        TriadAug -> 3
        Diagonal base -> anchorOffset base
        Plain base -> anchorOffset base
        Custom base intervals ->
            -- An edited scale goes by its third: while it still has the
            -- preset's third it keeps the preset's boxes, and once it has
            -- swapped it for the other one it anchors as a plain minor or major
            -- scale. With both thirds or neither the preset decides.
            let
                baseThird =
                    pickTone base (scaleIntervals base) 0 3 4
            in
            case pickTone base intervals 0 3 4 of
                3 ->
                    if baseThird == 3 then
                        anchorOffset base

                    else
                        0

                4 ->
                    if baseThird == 4 then
                        anchorOffset base

                    else
                        3

                _ ->
                    anchorOffset base
        _ -> 0


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
(see `anchorOffset`). -}
anchorScaleSet : ScaleType -> List Int
anchorScaleSet scale =
    List.map (\i -> modBy 12 (i + anchorOffset scale)) (scaleIntervals scale)


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

The window is a range of *pitches*, not of frets: on each string it is moved by
however far that string is tuned from standard (`stringShift`), so a box holds
the same notes as the standard-tuning shape, refingered. In E A D G C F the top
two strings sit a semitone above standard, so their window drops a fret and
every pentatonic box keeps two notes per string. Held to one fret range on
every string, those strings picked up a third note in some boxes and lost one
in others.

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

        strings =
            List.range 1 (stringCount tuning)

        -- A note at relative fret `off` on string `s` is in the scale when its
        -- pitch class, measured from the anchor note on the low E, is in the
        -- set. open(s) − open(low E) is the string's interval above the low E.
        degreeAt s off =
            modBy 12 (openString tuning s - anchorOpen tuning + off)

        inScale s off =
            List.member (degreeAt s off) scaleSet

        -- Distinct scale degrees reachable on any string within its window.
        degreesIn upper =
            strings
                |> List.concatMap
                    (\s ->
                        List.range (lo + stringShift tuning s) (upper + stringShift tuning s)
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
                    List.filter (inScale s)
                        (List.range (lo + stringShift tuning s) (hi + stringShift tuning s))
            in
            Maybe.map2 (\loF hiF -> ( s, loF, hiF )) (List.minimum offs) (List.maximum offs)
    in
    List.filterMap forString strings


{-| How many frets a box window moves on string `s` so it covers the pitches it
would in standard tuning (`windowOpen`): minus however far the string sits above
its standard interval over the low string. Taken the short way round the octave,
since a tuning stores only pitch classes, so no string moves more than six
frets. -}
stringShift : Tuning -> Int -> Int
stringShift tuning s =
    let
        interval =
            openString tuning s - anchorOpen tuning

        standardInterval =
            windowOpen s - windowOpen 6
    in
    negate (modBy 12 (interval - standardInterval + 6) - 6)


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

    -- How wide its lasso is drawn, which depends on the string set it sits on
    -- (`triadSetRadius`), so that sets sharing notes nest instead of coincide.
    , radius : Float
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
    List.concatMap (triadsOnStringSet tuning scale root) (stringSetTops (stringCount tuning) set)


{-| The highest string of each three-string set in play, on a neck with `n`
strings: every set there is, or the one named when it exists. -}
stringSetTops : Int -> StringSet -> List Int
stringSetTops n set =
    case set of
        AllStrings ->
            List.range 1 (n - 2)

        StringTrio t ->
            if t >= 1 && t <= n - 2 then
                [ t ]

            else
                []


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
                                    , radius = triadSetRadius (stringCount tuning) top
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
    diagonalShapesFor 6 (Diagonal MinorPent)


{-| The diagonal shapes for a given scale on a neck of `n` strings. Minor and
major pentatonic share the same six shapes (only the anchor differs, handled by
`diagonalAnchor`). Blues reuses the minor-pent shapes and inserts the ♭5 blue
note on each shape's ♭3-4-5 string, where it sits between the 4 and the 5.
Because the blue note is interior to a string's existing fret span, the shape
polygons are unchanged.

The strings are paired from the top — 2/1, 4/3, 6/5, then 8/7 and so on — and
the pairs climb: each is the octave split of the one below it, an octave up.
Two strings up in fourths is ten semitones, so each step up the neck moves the
shape two frets toward the nut, except across standard tuning's major third
(G to B), where it moves three. The shapes are written out for the lowest of
the three standard pairs and moved by `diagonalPairOffset` for the others, which
carries on past the sixth string, where standard tuning is all fourths. A neck
with an odd number of strings ends in a half pair: its last string, alone, with
the notes it would carry in the pair (`lowerRels` is empty). -}
diagonalShapesFor : Int -> ScaleType -> List DiagShape
diagonalShapesFor n scale =
    let
        ( pattern1, pattern2 ) =
            diagonalPatterns scale

        -- Bottom pair first, the way the shapes have always been listed.
        pairs =
            List.reverse (List.range 0 ((n + 1) // 2 - 1))

        shapeFor color ( lowerRels, upperRels ) k =
            let
                offset =
                    diagonalPairOffset k

                lower =
                    2 * k + 2
            in
            { color = color
            , lower = lower
            , lowerRels =
                if lower <= n then
                    List.map ((+) offset) lowerRels

                else
                    []
            , upper = 2 * k + 1
            , upperRels = List.map ((+) offset) upperRels
            }
    in
    List.map (shapeFor 1 pattern1) pairs ++ List.map (shapeFor 2 pattern2) pairs


{-| How many frets the shapes of pair `k` (counted from the top, 0 being strings
2/1) sit above the ones written out for the sixth/fifth strings. -}
diagonalPairOffset : Int -> Int
diagonalPairOffset k =
    if k >= 2 then
        -2 * (k - 2)

    else if k == 1 then
        2

    else
        5


{-| The two patterns for the sixth/fifth string pair, as `( lowerRels, upperRels )`.
Pattern 1 is the one that starts on the lower string; pattern 2 is it rotated
180° and offset 5 frets left, so the strings swap note content. -}
diagonalPatterns : ScaleType -> ( ( List Int, List Int ), ( List Int, List Int ) )
diagonalPatterns scale =
    case boxedOf scale of
        Blues ->
            -- Pattern 1: ♭5 added between 4 and 5 on the lower string.
            -- Pattern 2: ♭5 added between 4 and 5 on the upper string.
            ( ( [ 0, 2, 3, 4 ], [ 2, 4 ] )
            , ( [ -5, -3 ], [ -5, -3, -2, -1 ] )
            )

        base ->
            splitDiagonalPatterns base


{-| An octave split over a string pair, read off the intervals: 4 + 3 for a
seven-note scale, 3 + 2 for a pentatonic, 2 + 2 for an arpeggio. Rotated to
start on the box anchor (`anchorOffset`), the lower string carries the first
half of the notes and the upper string, a fourth up, the rest. A pentatonic
starts instead wherever its three notes sit closest (`compactStart`): that is
the classic shape — the minor pentatonic's string holds ♭3 4 5, two whole steps,
not R ♭3 4 — and it gives every other pentatonic the same kind of shape. Pattern 2 is the same octave the other way
round: the second half on the lower string, an octave down, and the first half
on the upper. Natural minor gives the classic diagonal minor shape, and every
mode draws its parent scale's shapes, the way its boxes are its parent's boxes
— D Dorian draws C major's. An arpeggio anchors on its root, so it climbs as
the two-notes-per-string sweep shape: R 3 on one string, 5 7 on the next. -}
splitDiagonalPatterns : ScaleType -> ( ( List Int, List Int ), ( List Int, List Int ) )
splitDiagonalPatterns scale =
    let
        sorted =
            List.sort (anchorScaleSet scale)

        half =
            (List.length sorted + 1) // 2

        rotated =
            if List.length sorted == 5 then
                rotateFrom (compactStart half sorted) sorted

            else
                sorted

        low =
            List.take half rotated

        high =
            List.drop half rotated

        down n =
            List.map (\i -> i - n)
    in
    ( ( low, down 5 high ), ( down 12 high, down 5 low ) )


{-| The notes from index `i` on, the ones before it moved up an octave. -}
rotateFrom : Int -> List Int -> List Int
rotateFrom i notes =
    List.drop i notes ++ List.map ((+) 12) (List.take i notes)


{-| Where a run of `count` consecutive notes spans the fewest frets; the first
such place if several tie. -}
compactStart : Int -> List Int -> Int
compactStart count notes =
    List.range 0 (List.length notes - 1)
        |> List.map
            (\i ->
                let
                    run =
                        List.take count (rotateFrom i notes)
                in
                ( List.maximum run |> Maybe.withDefault 0
                    |> (\hi -> hi - (List.minimum run |> Maybe.withDefault 0))
                , i
                )
            )
        |> List.minimum
        |> Maybe.map Tuple.second
        |> Maybe.withDefault 0


{-| Anchor fret on the low-E string (open = pitch 4, see `anchorOpen`): the box
anchor, which the split shapes are measured from. Blues keeps its hand-written
shapes, which are measured from the ♭3. -}
diagonalAnchor : Tuning -> ScaleType -> Int -> Int
diagonalAnchor tuning scale root =
    let
        lowE =
            anchorOpen tuning
    in
    case boxedOf scale of
        Blues ->
            modBy 12 (root + 3 - lowE)

        base ->
            modBy 12 (root - anchorOffset base - lowE)


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
    diagonalShapesFor (stringCount tuning) scale
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
            thirdOf board.scale

        seventhInterval =
            seventhOf board.scale
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


{-| Which third a scale's markers mark: 3 (minor) or 4 (major), −1 for none. -}
thirdOf : ScaleType -> Int
thirdOf scale =
    case scale of
        MajorPent -> 4
        MinorPent -> 3
        MajorBlues -> 4
        Ionian -> 4
        Aeolian -> 3
        Dorian -> 3
        Mixolydian -> 4
        Phrygian -> 3
        Lydian -> 4
        Locrian -> 3
        Blues -> 3
        DominantPent -> 4
        MinorSixPent -> 3
        HarmonicMajor -> 4
        HarmonicMinor -> 3
        UkrainianDorian -> 3
        PhrygianDominant -> 4
        MelodicMajor -> 4
        MelodicMinor -> 3
        DorianFlat2 -> 3
        LydianAugmented -> 4
        LydianDominant -> 4
        LocrianNat2 -> 3
        Altered -> 4
        BebopDominant -> 4
        BebopMajor -> 4
        BebopMinor -> 3
        DimHalfWhole -> 4
        DimWholeHalf -> 3
        WholeTone -> 4
        DoubleHarmonic -> 4
        HungarianMinor -> 3
        Hirajoshi -> 3
        InSen -> -1
        ChromaticMajor -> -1
        ChromaticMinor -> -1
        Blank -> -1
        TriadMajor -> 4
        TriadMinor -> 3
        TriadDim -> 3
        TriadAug -> 4
        TriadSus2 -> -1
        TriadSus4 -> -1
        ArpMaj7 -> 4
        ArpDom7 -> 4
        ArpMin7 -> 3
        ArpHalfDim -> 3
        ArpDim7 -> 3
        Diagonal base -> thirdOf base
        Plain base -> thirdOf base
        Custom base intervals -> pickTone base intervals (thirdOf base) 3 4


{-| Which seventh a scale's markers mark: 10 (♭7) or 11 (7), −1 for none. -}
seventhOf : ScaleType -> Int
seventhOf scale =
    case scale of
        MajorPent -> -1
        MinorPent -> 10
        MajorBlues -> -1
        Ionian -> 11
        Aeolian -> 10
        Dorian -> 10
        Mixolydian -> 10
        Phrygian -> 10
        Lydian -> 11
        Locrian -> 10
        Blues -> 10
        DominantPent -> 10
        MinorSixPent -> -1
        HarmonicMajor -> 11
        HarmonicMinor -> 11
        UkrainianDorian -> 10
        PhrygianDominant -> 10
        MelodicMajor -> 10
        MelodicMinor -> 11
        DorianFlat2 -> 10
        LydianAugmented -> 11
        LydianDominant -> 10
        LocrianNat2 -> 10
        Altered -> 10
        BebopDominant -> 10
        BebopMajor -> 11
        BebopMinor -> 10
        DimHalfWhole -> 10
        DimWholeHalf -> 11
        WholeTone -> 10
        DoubleHarmonic -> 11
        HungarianMinor -> 11
        Hirajoshi -> -1
        InSen -> 10
        ChromaticMajor -> -1
        ChromaticMinor -> -1
        Blank -> -1
        TriadMajor -> -1
        TriadMinor -> -1
        TriadDim -> -1
        TriadAug -> -1
        TriadSus2 -> -1
        TriadSus4 -> -1
        ArpMaj7 -> 11
        ArpDom7 -> 10
        ArpMin7 -> 10
        ArpHalfDim -> 10
        ArpDim7 -> 9
        Diagonal base -> seventhOf base
        Plain base -> seventhOf base
        Custom base intervals -> pickTone base intervals (seventhOf base) 10 11


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

        ArpHalfDim ->
            6

        ArpDim7 ->
            6

        Diagonal base ->
            fifthInterval base

        Plain base ->
            fifthInterval base

        Custom base intervals ->
            if List.member (fifthInterval base) intervals then
                fifthInterval base

            else
                7

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
reads as twelve repeating hues instead of a field of identical circles. The
hues are a rainbow walked round the circle of fifths (see the `--pc-*` vars in
index.html): strings a fourth apart sit one step apart, so a fret reads as a
gradient that jumps at the B string, and a semitone lands half the wheel away,
so adjacent frets never look alike.
-}
pitchColor : Int -> String
pitchColor n =
    "var(--pc-" ++ String.fromInt (modBy 12 n) ++ ")"


{-| Marker for the all-notes map: the pitch-class color carries the identity,
so the shape only has to say root-or-not (square vs circle).
-}
chromaticMarker : NoteRole -> Float -> Float -> String -> Svg.Svg Msg
chromaticMarker role cx cy fill =
    let
        ring extra =
            Svg.circle
                ([ SA.cx (String.fromFloat cx)
                 , SA.cy (String.fromFloat cy)
                 , SA.r "14"
                 , SA.fill fill
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
                , SA.fill fill
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


{-| A box region: its polygon in its color at `opacity`, or in monochrome its
hatching at full strength — the texture is mostly holes already, so the neck
shows through it. A muted box in monochrome is left unpainted: any gray it could
fade to would read as one more texture. `key` names the region's clip path, so
it has to be unique on the neck. -}
regionShape : Board -> String -> String -> Bool -> Int -> List ( Float, Float ) -> Svg.Svg Msg
regionShape board key opacity muted b verts =
    if not board.mono then
        Svg.polygon [ SA.points (pointsAttr verts), SA.fill (boxFill muted b), SA.fillOpacity opacity ] []

    else if muted then
        Svg.g [] []

    else
        hatchClipped (board.id ++ "clip-" ++ key)
            [ Svg.polygon [ SA.points (pointsAttr verts) ] [] ]
            (bounds verts)
            b


pointsAttr : List ( Float, Float ) -> String
pointsAttr verts =
    verts
        |> List.map (\( x, y ) -> String.fromFloat x ++ "," ++ String.fromFloat y)
        |> String.join " "


{-| The bounding box of some points, as ( ( left, right ), ( top, bottom ) ). -}
bounds : List ( Float, Float ) -> ( ( Float, Float ), ( Float, Float ) )
bounds pts =
    let
        xs =
            List.map Tuple.first pts

        ys =
            List.map Tuple.second pts

        lo =
            List.minimum >> Maybe.withDefault 0

        hi =
            List.maximum >> Maybe.withDefault 0
    in
    ( ( lo xs, hi xs ), ( lo ys, hi ys ) )


{-| The monochrome stand-ins for the five box colors: vector textures, so a
printer draws them as clean marks at its own resolution instead of enlarging a
pixel grid. They are real geometry — one path per region, clipped to it
(`hatchClipped`) — not SVG `<pattern>` fills: Chrome rasterizes a pattern
when it prints, even to PDF, and every texture came out blurred. Each is a different *structure*, not just a different density, so
two boxes side by side stay apart on paper, and where two overlap — monochrome
draws both textures there instead of a stripe — the pair reads as both:

  1. dots
  2. rising diagonals
  3. open rings
  4. small diagonal crosses
  5. falling diagonals

Adjacent boxes never get the two diagonals, which together are one more
crosshatch, nor the dots and the crosses, which blur together; boxes 1–3
double as the triad inversions. None of the textures
has a horizontal or vertical line in it, since those would run along the
strings and frets and muddle the neck.

**Everything composes, including with the neck.** The texture repeats every
fret and every string gap, anchored on a fret line and a string (`hatchOrigin`),
so every cell of the neck carries exactly the same piece of it, phase-locked to the
strings and frets instead of beating against them. The diagonals step
`fretWidth / 6` across and `stringSpacing / 4` down — whole divisions of the
cell — and cross on the
strings, the fret lines, and the box edges (fret centers, string midpoints).
The marks all sit on crossings too, so both diagonals run
through every mark and any pair of textures interlocks the same way
everywhere. The three mark textures share the same crossings and nest: a dot
fits inside the cross, the cross inside the ring, so boxes 3 and 4 overlapping
read ⊗ and 1 and 3 read ◉.

Box edges run along fret centers and string midpoints, and the lattice keeps
every mark clear of those, so an edge falls between marks rather than through
them. -}
hatchTexture : Int -> ( Float, Float ) -> ( ( Float, Float ), ( Float, Float ) ) -> Svg.Svg Msg
hatchTexture b ( ox, oy ) ( ( xa, xb ), ( ya, yb ) ) =
    let
        num =
            String.fromFloat

        wx =
            fretWidth / 6

        wy =
            stringSpacing / 4

        -- Overrun the box a little, so nothing stops short of the clip edge.
        top =
            ya - wy

        bottom =
            yb + wy

        -- A diagonal family: line c runs through x = `x c y`, and lines `cs`
        -- are the ones that cross the box.
        lines x cs =
            Svg.path
                [ SA.d
                    (String.concat
                        (List.map
                            (\c ->
                                "M" ++ num (x c top) ++ " " ++ num top
                                    ++ " L" ++ num (x c bottom) ++ " " ++ num bottom ++ " "
                            )
                            cs
                        )
                    )
                , SA.stroke "var(--text)"
                , SA.strokeWidth "1"
                , SA.fill "none"
                ]
                []

        u a =
            (a - ox) / wx

        v a =
            (a - oy) / wy

        -- The odd multiples of half a step between two coordinates.
        odds a z step =
            List.range (floor (a / step)) (ceiling (z / step))
                |> List.filter (\n -> modBy 2 n == 1)
                |> List.map (\n -> toFloat n * step)

        marks =
            List.concatMap
                (\x -> List.map (\y -> ( ox + x, oy + y )) (odds (top - oy) (bottom - oy) (wy / 2)))
                (odds (xa - wx - ox) (xb + wx - ox) (wx / 2))

        markPath draw attrs =
            Svg.path (SA.d (String.concat (List.map draw marks)) :: attrs) []

        stroked =
            [ SA.fill "none", SA.stroke "var(--text)", SA.strokeWidth "0.9" ]

        -- A circle as two half arcs, so a whole texture is one path.
        circle r ( x, y ) =
            "M" ++ num (x - r) ++ " " ++ num y
                ++ " a" ++ num r ++ " " ++ num r ++ " 0 1 0 " ++ num (2 * r) ++ " 0"
                ++ " a" ++ num r ++ " " ++ num r ++ " 0 1 0 " ++ num (-2 * r) ++ " 0Z "

        cross a ( x, y ) =
            "M" ++ num (x - a) ++ " " ++ num (y - a) ++ " L" ++ num (x + a) ++ " " ++ num (y + a)
                ++ " M" ++ num (x + a) ++ " " ++ num (y - a) ++ " L" ++ num (x - a) ++ " " ++ num (y + a) ++ " "
    in
    case b of
        2 ->
            -- (x − ox)/wx + (y − oy)/wy = c
            lines (\c y -> ox + wx * (toFloat c - v y))
                (List.range (floor (u xa + v top)) (ceiling (u xb + v bottom)))

        5 ->
            -- (x − ox)/wx − (y − oy)/wy = c
            lines (\c y -> ox + wx * (toFloat c + v y))
                (List.range (floor (u xa - v bottom)) (ceiling (u xb - v top)))

        -- The marks take the crossings at odd multiples of half a step both
        -- ways, since the even ones include every crossing that lands on a
        -- string, a fret or a box edge. Each quarter of a fret-by-string
        -- rectangle gets six, symmetric within it. They are sized to nest: a
        -- dot inside the cross, and the cross's arms just reaching the inside
        -- of the ring, the way ⊗ is drawn.
        1 ->
            markPath (circle 1.55) [ SA.fill "var(--text)" ]

        3 ->
            markPath (circle 2.3) stroked

        _ ->
            markPath (cross 1.4) stroked


{-| Box `b`'s texture clipped to a shape: the clip path, then the texture drawn
over the shape's bounding box through it. Clip paths stay vector when Chrome
prints; pattern fills do not. -}
hatchClipped : String -> List (Svg.Svg Msg) -> ( ( Float, Float ), ( Float, Float ) ) -> Int -> Svg.Svg Msg
hatchClipped id shape box b =
    Svg.g []
        [ Svg.clipPath [ SA.id id ] shape
        , Svg.g [ SA.clipPath ("url(#" ++ id ++ ")") ] [ hatchTexture b hatchOrigin box ]
        ]


{-| Pins the texture to the neck: anchored on the first fret line and the top
string, so the strings and fret lines fall at the same place in it everywhere. -}
hatchOrigin : ( Float, Float )
hatchOrigin =
    ( fretLineX 0, stringY 1 )


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
on six strings 2-3-4 is smallest, 4-5-6 next, 1-2-3 next, 3-4-5 largest — which
puts two steps between every pair that shares two strings and leaves only the
loosest pairs a single step apart. On any one string at most three sets meet,
and they are always at least a step and a half apart there.

Four sizes only carry that as far as six strings: past it a fifth is needed,
because the order 1-2-3, 2-3-4, … would otherwise have to repeat a size two sets
apart. The pattern then repeats every five sets, and all five are squeezed under
the same ceiling.

The smallest size is the floor: the pill has to clear the root markers, whose
corners sit 18.6px out from the note center (a 28px square, rounded 3) — not
the 14px of the circles, which is what a first pass at this sized itself to and
why the roots poked out of it. The largest is the ceiling: much beyond this and
a pill swallows the neighboring strings whole. -}
triadSetRadius : Int -> Int -> Float
triadSetRadius strings top =
    let
        size =
            [ 2, 0, 3, 1, 4 ]
                |> List.drop (modBy 5 (top - 1))
                |> List.head
                |> Maybe.withDefault 1

        step =
            if strings >= 7 then
                3.75

            else
                5
    in
    20 + step * toFloat size


triadLassoRadius : Triad -> Float
triadLassoRadius triad =
    triad.radius


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


{-| How tall the neck is for `n` strings: one gap between each pair. A single
string still gets a gap's worth of neck, so the frets have something to span. -}
fretboardHeight : Int -> Float
fretboardHeight n =
    stringSpacing * toFloat (max 1 (n - 1))


totalWidth : Float
totalWidth =
    leftMargin + nutWidth + fretWidth * toFloat numFrets + rightMargin


totalHeight : Int -> Float
totalHeight n =
    topMargin + fretboardHeight n + 80


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
            [ class "no-print"
            , style "display" "flex"
            , style "justify-content" "space-between"
            , style "align-items" "center"
            , style "gap" "12px"
            , style "flex-wrap" "wrap"
            ]
            [ h1 [ class "app-title", style "margin" "0 0 6px" ] [ span [ class "wide-only" ] [ text "Guitar " ], text "Fretboard Visualizer" ]
            , span [ style "display" "flex", style "gap" "6px" ]
                [ gearButton model, wakeLockButton model ]
            ]
        , if model.viewOpen then
            viewOptions model

          else
            text ""
        , div
            -- A drag is a press and a sweep, which is also how you select
            -- text; without this the sweep paints the page blue.
            ([ style "user-select"
                (case model.drag of
                    Just _ ->
                        "none"

                    Nothing ->
                        "auto"
                )
            ]
                ++ (if model.twoColumns then
                        -- Pinned to one neck's width, so two columns halve
                        -- each neck instead of the grid growing the page to
                        -- fit two whole ones.
                        [ style "display" "grid"
                        , style "grid-template-columns" "repeat(2, minmax(0, 1fr))"
                        , style "column-gap" "16px"
                        , style "width" (String.fromFloat totalWidth ++ "px")
                        , style "max-width" "100%"
                        ]

                    else
                        []
                   )
            )
            (List.indexedMap (viewNeck model many) necks)
        , addNeckButton
        , viewLegend (activeBoard model)
        ]


{-| One fretboard, in its slot, under its heading. With a single neck there
is no handle and no remove button, so the page looks as it did before there
was a list to reorder. -}
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

        beingDragged =
            case model.drag of
                Just drag ->
                    drag.to == i

                Nothing ->
                    False
    in
    if not many then
        div [] [ neckHeading model slot board, viewFretboard board ]

    else
        div
            [ class "neck-row"
            , style "display" "flex"
            , style "align-items" "flex-start"
            , style "gap" "8px"
            , style "padding" "6px 6px 18px"
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
                    [ div [ style "flex" "1", style "min-width" "0" ] [ neckHeading model slot board ]
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
        [ class "no-print"
        , Html.Events.on "pointerdown" (dragStartDecoder i)
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
        [ class "no-print"
        , Html.Events.stopPropagationOn "click" (Decode.succeed ( RemoveNeck i, True ))
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
    div [ class "no-print", style "margin" "4px 0 0 3px" ]
        [ button
            ([ onClick AddNeck ] ++ buttonBaseStyle False)
            [ text "+ Add neck" ]
        ]


wakeLockButton : Model -> Html Msg
wakeLockButton model =
    button
        ([ onClick ToggleWakeLock
         , class "no-print"
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
    div
        -- Centered, not baselined: the two blocks are built to the same height
        -- (22 × 1.2 for the name, 13 + 10 at 1.15 for a note over its degree),
        -- so centering lines their tops and bottoms up and the pair reads as
        -- one band rather than as a title with something hanging off it.
        [ -- A printed blank neck speaks for itself; "Blank neck" over each
          -- one on the sheet would just be noise.
          class
            (if board.scale == Blank then
                "no-print"

             else
                ""
            )
        , style "display" "flex"
        , style "align-items" "center"
        , style "flex-wrap" "wrap"
        , style "gap" "2px 20px"
        , style "margin-bottom" "6px"
        ]
        (scaleTitleParts board)


{-| The scale's name and its notes, the two blocks of a neck heading. The
scale picker's button wears them too, so the button reads as the heading. -}
scaleTitleParts : Board -> List (Html Msg)
scaleTitleParts board =
    let
        scaleName =
            (if board.scale == Blank then
                ""

             else
                rootSpelling board.scale board.root ++ " "
            )
                ++ scaleTitle board.scale

        -- The notes ride alongside the heading rather than under it, each with
        -- its scale degree stacked beneath instead of trailing in brackets:
        -- one line of vertical space instead of two, and the degrees line up
        -- into their own row you can read across.
        detail =
            if board.scale == Blank then
                []

            else if isChromatic board.scale then
                [ aside
                    ("Every note on the neck · "
                        ++ (if board.mono then
                                ""

                            else
                                "hue = note · "
                           )
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
                List.map2 noteChip (spelledNotes board) (intervalLabels board.scale)
                    ++ (if isTriad board.scale then
                            [ aside (stringSetLabel board.stringSet) ]

                        else
                            []
                       )
    in
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


{-| The name a scale goes by in its heading, after the root. An edited scale
is named after the preset it came from plus what changed (`Minor Pentatonic
+2 +6`), while that is short enough to read; past that it is just custom. -}
scaleTitle : ScaleType -> String
scaleTitle scale =
    case scale of
        MajorPent -> "Major Pentatonic"
        MinorPent -> "Minor Pentatonic"
        MajorBlues -> "Major Blues"
        Ionian -> "Major (Ionian)"
        Aeolian -> "Minor (Aeolian)"
        Dorian -> "Dorian"
        Mixolydian -> "Mixolydian"
        Phrygian -> "Phrygian"
        Lydian -> "Lydian"
        Locrian -> "Locrian"
        Blues -> "Blues"
        DominantPent -> "Dominant Pentatonic"
        MinorSixPent -> "Minor 6 Pentatonic"
        HarmonicMajor -> "Harmonic Major"
        HarmonicMinor -> "Harmonic Minor"
        UkrainianDorian -> "Ukrainian Dorian"
        PhrygianDominant -> "Phrygian Dominant"
        MelodicMajor -> "Melodic Major"
        MelodicMinor -> "Melodic Minor"
        DorianFlat2 -> "Dorian ♭2"
        LydianAugmented -> "Lydian Augmented"
        LydianDominant -> "Lydian Dominant"
        LocrianNat2 -> "Locrian ♮2"
        Altered -> "Altered"
        BebopDominant -> "Bebop Dominant"
        BebopMajor -> "Bebop Major"
        BebopMinor -> "Bebop Minor"
        DimHalfWhole -> "Half-Whole Diminished"
        DimWholeHalf -> "Whole-Half Diminished"
        WholeTone -> "Whole Tone"
        DoubleHarmonic -> "Double Harmonic Major"
        HungarianMinor -> "Hungarian Minor"
        Hirajoshi -> "Hirajoshi"
        InSen -> "In Sen"
        ChromaticMajor -> "— All Notes (major)"
        ChromaticMinor -> "— All Notes (minor)"
        Blank -> "Blank neck"
        TriadMajor -> "Major Triad"
        TriadMinor -> "Minor Triad"
        TriadDim -> "Diminished Triad"
        TriadAug -> "Augmented Triad"
        TriadSus2 -> "Sus2 Triad"
        TriadSus4 -> "Sus4 Triad"
        ArpMaj7 -> "Major 7th Arpeggio"
        ArpDom7 -> "Dominant 7th Arpeggio"
        ArpMin7 -> "Minor 7th Arpeggio"
        ArpHalfDim -> "Half-Diminished Arpeggio"
        ArpDim7 -> "Diminished 7th Arpeggio"
        Diagonal base -> "Diagonal " ++ scaleTitle base
        Plain base -> scaleTitle base
        Custom base intervals ->
            let
                baseIntervals =
                    scaleIntervals base

                added =
                    List.filter (\i -> not (List.member i baseIntervals)) intervals

                removed =
                    List.filter (\i -> not (List.member i intervals)) baseIntervals

                changes =
                    List.map (\i -> "+" ++ customLabel base i) added
                        ++ List.map (\i -> "\u{2212}" ++ customLabel base i) removed
            in
            if base == Blank || isChromatic base || List.length changes > 3 then
                "Custom scale"

            else
                scaleTitle base ++ " " ++ String.join " " changes


{-| The interval of each scale tone from the root, as a player names it —
parallel to `scaleIntervals`. The all-notes maps have no degrees of their
own, so their heading lists none (`degreeName` names their notes instead). -}
intervalLabels : ScaleType -> List String
intervalLabels st =
    case st of
        MajorPent -> [ "R", "2", "3", "5", "6" ]
        MinorPent -> [ "R", "♭3", "4", "5", "♭7" ]
        MajorBlues -> [ "R", "2", "♭3", "3", "5", "6" ]
        Ionian -> [ "R", "2", "3", "4", "5", "6", "7" ]
        Aeolian -> [ "R", "2", "♭3", "4", "5", "♭6", "♭7" ]
        Dorian -> [ "R", "2", "♭3", "4", "5", "6", "♭7" ]
        Mixolydian -> [ "R", "2", "3", "4", "5", "6", "♭7" ]
        Phrygian -> [ "R", "♭2", "♭3", "4", "5", "♭6", "♭7" ]
        Lydian -> [ "R", "2", "3", "♯4", "5", "6", "7" ]
        Locrian -> [ "R", "♭2", "♭3", "4", "♭5", "♭6", "♭7" ]
        Blues -> [ "R", "♭3", "4", "♭5", "5", "♭7" ]
        DominantPent -> [ "R", "2", "3", "5", "♭7" ]
        MinorSixPent -> [ "R", "♭3", "4", "5", "6" ]
        HarmonicMajor -> [ "R", "2", "3", "4", "5", "♭6", "7" ]
        HarmonicMinor -> [ "R", "2", "♭3", "4", "5", "♭6", "7" ]
        UkrainianDorian -> [ "R", "2", "♭3", "♯4", "5", "6", "♭7" ]
        PhrygianDominant -> [ "R", "♭2", "3", "4", "5", "♭6", "♭7" ]
        MelodicMajor -> [ "R", "2", "3", "4", "5", "♭6", "♭7" ]
        MelodicMinor -> [ "R", "2", "♭3", "4", "5", "6", "7" ]
        DorianFlat2 -> [ "R", "♭2", "♭3", "4", "5", "6", "♭7" ]
        LydianAugmented -> [ "R", "2", "3", "♯4", "♯5", "6", "7" ]
        LydianDominant -> [ "R", "2", "3", "♯4", "5", "6", "♭7" ]
        LocrianNat2 -> [ "R", "2", "♭3", "4", "♭5", "♭6", "♭7" ]
        Altered -> [ "R", "♭2", "♯2", "3", "♭5", "♯5", "♭7" ]
        BebopDominant -> [ "R", "2", "3", "4", "5", "6", "♭7", "7" ]
        BebopMajor -> [ "R", "2", "3", "4", "5", "♭6", "6", "7" ]
        BebopMinor -> [ "R", "2", "♭3", "3", "4", "5", "6", "♭7" ]
        DimHalfWhole -> [ "R", "♭2", "♯2", "3", "♯4", "5", "6", "♭7" ]
        DimWholeHalf -> [ "R", "2", "♭3", "4", "♭5", "♭6", "6", "7" ]
        WholeTone -> [ "R", "2", "3", "♯4", "♯5", "♭7" ]
        DoubleHarmonic -> [ "R", "♭2", "3", "4", "5", "♭6", "7" ]
        HungarianMinor -> [ "R", "2", "♭3", "♯4", "5", "♭6", "7" ]
        Hirajoshi -> [ "R", "2", "♭3", "5", "♭6" ]
        InSen -> [ "R", "♭2", "4", "5", "♭7" ]
        ChromaticMajor -> List.repeat 12 ""
        ChromaticMinor -> List.repeat 12 ""
        Blank -> []
        TriadMajor -> [ "R", "3", "5" ]
        TriadMinor -> [ "R", "♭3", "5" ]
        TriadDim -> [ "R", "♭3", "♭5" ]
        TriadAug -> [ "R", "3", "♯5" ]
        TriadSus2 -> [ "R", "2", "5" ]
        TriadSus4 -> [ "R", "4", "5" ]
        ArpMaj7 -> [ "R", "3", "5", "7" ]
        ArpDom7 -> [ "R", "3", "5", "♭7" ]
        ArpMin7 -> [ "R", "♭3", "5", "♭7" ]
        ArpHalfDim -> [ "R", "♭3", "♭5", "♭7" ]
        ArpDim7 -> [ "R", "♭3", "♭5", "♭♭7" ]
        Diagonal base -> intervalLabels base
        Plain base -> intervalLabels base
        Custom base intervals -> List.map (customLabel base) intervals


{-| How an edited scale labels an interval: as its preset does where the preset
has that note, otherwise by the common name. -}
customLabel : ScaleType -> Int -> String
customLabel base i =
    List.map2 Tuple.pair (scaleIntervals base) (intervalLabels base)
        |> List.filter (\( j, lbl ) -> j == i && lbl /= "")
        |> List.head
        |> Maybe.map Tuple.second
        |> Maybe.withDefault
            (List.drop i [ "R", "♭2", "2", "♭3", "3", "4", "♭5", "5", "♭6", "6", "♭7", "7" ] |> List.head |> Maybe.withDefault "")


{-| What a note marker reads in Degrees mode: the interval from the root, as
the scale names it — so the 4th of Lydian is ♯4, not ♭5. The all-notes maps
have no scale to name it by, so they use the common name for each interval. -}
degreeName : Board -> Int -> String
degreeName board n =
    let
        interval =
            modBy 12 (n - board.root)

        common =
            [ "R", "♭2", "2", "♭3", "3", "4", "♭5", "5", "♭6", "6", "♭7", "7" ]
                |> List.drop interval
                |> List.head
                |> Maybe.withDefault ""
    in
    List.map2 Tuple.pair (scaleIntervals board.scale) (intervalLabels board.scale)
        |> List.filter (\( i, lbl ) -> i == interval && lbl /= "")
        |> List.head
        |> Maybe.map Tuple.second
        |> Maybe.withDefault common


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


{-| The display options behind the gear: the settings you set once and then
play, each folded down to a button that says where it stands. -}
viewOptions : Model -> Html Msg
viewOptions model =
    div [ class "no-print", style "margin-bottom" "10px" ]
        [ setupRow model
        , if model.tuningOpen then
            controlBlock
                (List.map (tuningButton model) (tuningsFor (stringCount model.tuning)) ++ [ customButton model ])

          else
            text ""
        , if model.tuningOpen && isCustom model.tuning then
            div [ style "display" "flex", style "align-items" "center", style "flex-wrap" "wrap" ]
                (List.map (stringStepper model) (List.range 1 (stringCount model.tuning)))

          else
            text ""
        ]


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
            :: stringCountControl model
            :: highlightToggle model
            :: highlightFrets model
            ++ (stringToggle model :: highlightString model)
            ++ [ degreesToggle model, monoToggle model, columnsToggle model ]
        )


{-| Opens and shuts the display options. An icon rather than a label: it sits
in the page header beside Keep screen on and should not compete with it. -}
gearButton : Model -> Html Msg
gearButton model =
    button
        ([ onClick ToggleViewPanel
         , attribute "aria-label" "Display options"
         , attribute "aria-expanded"
            (if model.viewOpen then
                "true"

             else
                "false"
            )
         , Html.Attributes.title "Display options"
         , class "no-print"
         ]
            ++ buttonBaseStyle model.viewOpen
            ++ [ style "padding" "5px 7px", style "line-height" "0" ]
        )
        [ Svg.svg
            [ SA.viewBox "0 0 24 24"
            , SA.width "18"
            , SA.height "18"
            , SA.fill "none"
            , SA.stroke "currentColor"
            , SA.strokeWidth "2"
            , SA.strokeLinecap "round"
            , SA.strokeLinejoin "round"
            ]
            [ Svg.circle [ SA.cx "12", SA.cy "12", SA.r "3" ] []
            , Svg.path [ SA.d "M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z" ] []
            ]
        ]


{-| A neck's heading, which is also its controls: pressing it opens the scale
picker under it, and in a triad mode the string sets sit beneath it. There is
no separate toolbar naming the scale a second time, and no selected neck to
keep track of — the neck you are editing is the one the picker is under. -}
neckHeading : Model -> Int -> Board -> Html Msg
neckHeading model slot board =
    let
        open =
            model.scaleOpen && slot == model.active
    in
    div []
        [ scaleHeadingButton slot open board

        -- The button does not print, so this copy is the printed heading.
        , div [ class "print-only" ] [ viewScaleTitle board ]
        , if open then
            scalePicker model

          else
            text ""
        , if isTriad board.scale && stringCount board.tuning >= 3 then
            div [ class "no-print" ]
                [ controlBlock
                    [ pickerGroup "Strings"
                        (stringSetButton slot board AllStrings "All"
                            :: List.map
                                (\t -> stringSetButton slot board (StringTrio t) (stringSetSlug (StringTrio t)))
                                (List.range 1 (stringCount board.tuning - 2))
                        )
                    ]
                ]

          else
            text ""
        ]


{-| The heading drawn as a button: the same name and notes as a printed
heading, plus a chevron that says it opens. It wears a button's border and
fill even while shut, since a heading that only looks like a heading gives no
hint that pressing it does anything. -}
scaleHeadingButton : Int -> Bool -> Board -> Html Msg
scaleHeadingButton slot open board =
    button
        [ onClick (ToggleScalePicker slot)
        , class "no-print heading-button"
        , attribute "aria-expanded"
            (if open then
                "true"

             else
                "false"
            )
        , Html.Attributes.title "Change root and scale"
        , style "display" "flex"
        , style "align-items" "center"
        , style "gap" "2px 20px"
        , style "flex-wrap" "wrap"
        , style "margin" "0 0 8px"
        , style "padding" "4px 10px"
        , style "border" "1px solid var(--btn-bd)"
        , style "border-radius" "8px"

        -- Open, the border thickens by an inset ring rather than a wider
        -- border, so the heading does not shift when it opens.
        , style "box-shadow"
            (if open then
                "inset 0 0 0 1px var(--btn-on-bg)"

             else
                "none"
            )
        , style "background" "var(--btn-bg)"
        , style "color" "inherit"
        , style "font-family" "inherit"
        , style "text-align" "left"
        , style "cursor" "pointer"
        ]
        (scaleTitleParts board ++ [ chevron open ])


{-| A down chevron, flipped when open. Drawn rather than typed: the ▾ glyph
is a speck at text size. -}
chevron : Bool -> Html Msg
chevron open =
    Svg.svg
        [ SA.viewBox "0 0 24 24"
        , SA.width "20"
        , SA.height "20"
        , SA.fill "none"
        , SA.stroke "currentColor"
        , SA.strokeWidth "2.5"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        , SA.style
            ("flex: 0 0 auto; color: var(--btn-text); transition: transform 0.15s"
                ++ (if open then
                        "; transform: rotate(180deg)"

                    else
                        ""
                   )
            )
        ]
        [ Svg.polyline [ SA.points "6 9 12 15 18 9" ] [] ]


{-| The root and the scale: what you pick every time you set a neck up. -}
scalePicker : Model -> Html Msg
scalePicker model =
    div [ class "no-print" ]
        [ -- What to show, in one panel tabbed into the scales, the chords and
          -- the all-notes maps. A family is a tinted card with its name on
          -- top, so its buttons read as one unit even where the families flow
          -- several to a line; the card's name carries the context, so the
          -- buttons inside can just say "Major".
          div
            [ style "background" "var(--surface)"
            , style "border" "1px solid var(--surface-bd)"
            , style "border-radius" "10px"
            , style "padding" "10px 12px 12px"
            , style "margin-bottom" "10px"
            , style "max-width" (String.fromFloat totalWidth ++ "px")
            , style "box-sizing" "border-box"
            ]
            [ pickerTabs model
            , case model.pickerTab of
                ScalesTab ->
                    pickerCards
                        [ scaleGroup "Modes"
                            [ scaleButton model Ionian "Major (Ionian)"
                            , scaleButton model Dorian "Dorian"
                            , scaleButton model Phrygian "Phrygian"
                            , scaleButton model Lydian "Lydian"
                            , scaleButton model Mixolydian "Mixolydian"
                            , scaleButton model Aeolian "Minor (Aeolian)"
                            , scaleButton model Locrian "Locrian"
                            ]
                        , scaleGroup "Pentatonic"
                            [ scaleButton model MajorPent "Major"
                            , scaleButton model MinorPent "Minor"
                            , scaleButton model MajorBlues "Major blues"
                            , scaleButton model Blues "Minor blues"
                            , scaleButton model DominantPent "Dominant"
                            , scaleButton model MinorSixPent "Minor 6"
                            ]
                        , scaleGroup "Harmonic"
                            [ scaleButton model HarmonicMajor "Major"
                            , scaleButton model HarmonicMinor "Minor"
                            , scaleButton model UkrainianDorian "Ukrainian Dorian"
                            , scaleButton model PhrygianDominant "Phrygian dominant"
                            ]
                        , scaleGroup "Melodic"
                            [ scaleButton model MelodicMajor "Major"
                            , scaleButton model MelodicMinor "Minor"
                            , scaleButton model DorianFlat2 "Dorian ♭2"
                            , scaleButton model LydianAugmented "Lydian augmented"
                            , scaleButton model LydianDominant "Lydian dominant"
                            , scaleButton model LocrianNat2 "Locrian ♮2"
                            , scaleButton model Altered "Altered"
                            ]
                        , scaleGroup "Bebop"
                            [ scaleButton model BebopDominant "Dominant"
                            , scaleButton model BebopMajor "Major"
                            , scaleButton model BebopMinor "Minor"
                            ]
                        , scaleGroup "Symmetric"
                            [ scaleButton model DimHalfWhole "Dim half-whole"
                            , scaleButton model DimWholeHalf "Dim whole-half"
                            , scaleButton model WholeTone "Whole tone"
                            ]
                        , scaleGroup "Exotic"
                            [ scaleButton model DoubleHarmonic "Double harmonic"
                            , scaleButton model HungarianMinor "Hungarian minor"
                            , scaleButton model Hirajoshi "Hirajoshi"
                            , scaleButton model InSen "In Sen"
                            ]
                        ]

                ChordsTab ->
                    pickerCards
                        [ scaleGroup "Triads"
                            [ scaleButton model TriadMajor "Major"
                            , scaleButton model TriadMinor "Minor"
                            , scaleButton model TriadDim "Diminished"
                            , scaleButton model TriadAug "Augmented"
                            , scaleButton model TriadSus2 "Sus2"
                            , scaleButton model TriadSus4 "Sus4"
                            ]
                        , scaleGroup "Arpeggios"
                            [ scaleButton model ArpMaj7 "maj7"
                            , scaleButton model ArpDom7 "7"
                            , scaleButton model ArpMin7 "m7"
                            , scaleButton model ArpHalfDim "m7♭5"
                            , scaleButton model ArpDim7 "dim7"
                            ]
                        ]

                NotesTab ->
                    pickerCards
                        [ scaleGroup ""
                            [ scaleButton model ChromaticMajor "Major"
                            , scaleButton model ChromaticMinor "Minor"
                            , scaleButton model Blank "None"
                            ]
                        ]
            ]
        , -- How to show it, apart from what: the neck's key and how its
          -- scale is drawn.
          div
            [ style "display" "flex"
            , style "flex-wrap" "wrap"
            , style "gap" "8px"
            , style "margin-bottom" "10px"
            , style "max-width" (String.fromFloat totalWidth ++ "px")
            ]
            [ scaleGroup "Root" (List.map (rootButton model) (List.range 0 11))
            , let
                -- Triads are always lassoed and the all-notes maps have no
                -- shapes, so there is no way of drawing them to pick.
                boxed =
                    boxedOf (activeNeck model).scale
              in
              if isTriad boxed || isChromatic boxed then
                text ""

              else
                shapeGroup model
            ]
        ]


{-| The tab bar along the top of the scale picker: Scales, Chord tones, All notes.
Only one tab's families show at a time, so a picker of some fifty buttons
reads as one short list. The tab that holds the neck's current scale carries a
dot, so while you browse another tab you can still see where the selection
is. -}
pickerTabs : Model -> Html Msg
pickerTabs model =
    let
        current =
            tabOf (activeNeck model).scale

        tab t lbl =
            let
                on =
                    model.pickerTab == t
            in
            button
                [ onClick (SetPickerTab t)
                , style "background" "none"
                , style "border" "none"
                , style "border-bottom"
                    (if on then
                        "2px solid var(--text-strong)"

                     else
                        "2px solid transparent"
                    )
                , style "margin" "0 14px -1px 0"
                , style "padding" "4px 2px 7px"
                , style "cursor" "pointer"
                , style "font-family" "inherit"
                , style "font-size" "14px"
                , style "font-weight"
                    (if on then
                        "600"

                     else
                        "500"
                    )
                , style "color"
                    (if on then
                        "var(--text-strong)"

                     else
                        "var(--text-2)"
                    )
                , style "display" "inline-flex"
                , style "align-items" "center"
                , style "gap" "6px"
                ]
                (text lbl
                    :: (if current == t && not on then
                            [ span
                                [ style "width" "6px"
                                , style "height" "6px"
                                , style "border-radius" "50%"
                                , style "background" "var(--text-2)"
                                , Html.Attributes.title "The current scale is on this tab"
                                ]
                                []
                            ]

                        else
                            []
                       )
                )
    in
    div
        [ style "display" "flex"
        , style "border-bottom" "1px solid var(--surface-bd)"
        , style "margin-bottom" "10px"
        ]
        [ tab ScalesTab "Scales"
        , tab ChordsTab "Chord tones"
        , tab NotesTab "All notes"
        ]


{-| One tab's families, flowing and wrapping. -}
pickerCards : List (Html Msg) -> Html Msg
pickerCards groups =
    div
        [ style "display" "flex"
        , style "flex-wrap" "wrap"
        , style "gap" "8px"
        ]
        groups


{-| A family of buttons as a tinted card, its name (if it has one) above the
buttons. The card is what holds the family together; the buttons inside it
wrap when they have to, under the name rather than beside it. -}
scaleGroup : String -> List (Html Msg) -> Html Msg
scaleGroup caption buttons =
    div
        [ style "background" "var(--group-bg)"
        , style "border-radius" "8px"
        , style "padding" "6px 6px 6px 8px"
        ]
        [ if String.isEmpty caption then
            text ""

          else
            div
                [ style "font-size" "11px"
                , style "color" "var(--text-2)"
                , style "font-weight" "600"
                , style "text-transform" "uppercase"
                , style "letter-spacing" "0.06em"
                , style "margin" "0 0 5px 1px"
                ]
                [ text caption ]
        , div
            [ style "display" "flex"
            , style "flex-wrap" "wrap"
            , style "row-gap" "4px"
            ]
            buttons
        ]


{-| How the scale is drawn: CAGED boxes, the diagonal climbing shapes, or no
shapes at all, just the notes. These are ways of drawing a scale rather than
scales of their own, so they are a switch beside the scale buttons instead of
a copy of every scale button. Each choice is there for every scale and is
disabled where the scale has no such form (`diagonalOf`, `plainOf`). -}
shapeGroup : Model -> Html Msg
shapeGroup model =
    let
        scale =
            (activeNeck model).scale

        boxed =
            boxedOf scale

        shapeButton lbl target on why =
            case target of
                Just t ->
                    button
                        ([ onClick (SetScale t), style "min-width" "80px" ]
                            ++ buttonBaseStyle on
                        )
                        [ text lbl ]

                Nothing ->
                    button
                        ([ Html.Attributes.disabled True
                         , Html.Attributes.title why
                         , style "min-width" "80px"
                         ]
                            ++ buttonBaseStyle False
                            ++ [ style "opacity" "0.4", style "cursor" "default" ]
                        )
                        [ text lbl ]
    in
    scaleGroup "Shape"
        [ shapeButton "Boxes"
            (if isArpeggio boxed then
                Nothing

             else
                Just boxed
            )
            (boxed == scale && not (isDiagonal scale))
            "Arpeggios are learned as diagonal sweep shapes, not positions"
        , shapeButton "Diagonal" (diagonalOf boxed) (isDiagonal scale) "Diagonal shapes exist for the five- and seven-note scales, the blues and the arpeggios"
        , shapeButton "None" (plainOf boxed) (isPlain scale) "The triads and the all-notes maps have no boxes to hide"
        ]


{-| How many strings the neck has. A new string goes on the low end and is
tuned to continue the pattern of the strings above it (`nextLowString`), so
standard tuning grows a B and then an F♯; take one away and the lowest goes.
▲ is more strings, as ▲ is more frets next to it. -}
stringCountControl : Model -> Html Msg
stringCountControl model =
    span
        [ style "display" "inline-flex"
        , style "align-items" "center"
        , style "gap" "2px"
        , style "font-size" "13px"
        , style "color" "var(--text-2)"
        , Html.Attributes.title "Strings are added and removed at the low end"
        ]
        [ text "Strings"
        , stepper (String.fromInt (stringCount model.tuning)) ChangeStringCount
        ]


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
                , stepper (String.fromInt lo) (\d -> SetFocus (Just ( lo + d, hi )))
                , text "–"
                , stepper (String.fromInt hi) (\d -> SetFocus (Just ( lo, hi + d )))
                ]
            ]


{-| Switches the string highlight on and reveals its stepper. Pressing it
again puts it away and brings every string back to full strength. -}
stringToggle : Model -> Html Msg
stringToggle model =
    let
        on =
            model.stringFocus /= Nothing
    in
    button
        ([ onClick
            (SetStringFocus
                (if on then
                    Nothing

                 else
                    Just (defaultStringFocus model.tuning)
                )
            )
         , style "min-width" "80px"
         ]
            ++ buttonBaseStyle on
        )
        [ text "Highlight string" ]


{-| Labels every note marker with its interval from the root instead of its
note name, for learning a shape as degrees rather than as letters. -}
degreesToggle : Model -> Html Msg
degreesToggle model =
    button
        ([ onClick ToggleDegrees, style "min-width" "80px" ] ++ buttonBaseStyle model.degrees)
        [ text "Degrees" ]


{-| Swaps every color on the necks for black-and-white hatched textures, for a
printer that has no color. It is on screen too, so what you see is what the
page will print. -}
monoToggle : Model -> Html Msg
monoToggle model =
    button
        ([ onClick ToggleMono, style "min-width" "80px" ] ++ buttonBaseStyle model.mono)
        [ text "Monochrome" ]


{-| Lays the necks out two to a row at half width, for fitting a page. -}
columnsToggle : Model -> Html Msg
columnsToggle model =
    button
        ([ onClick ToggleColumns, style "min-width" "80px" ] ++ buttonBaseStyle model.twoColumns)
        [ text "Two columns" ]


{-| Which string, shown only while the highlight is on. The stepper names the
string's open note as well as its number, since in a custom tuning the number
alone does not say what you are on. ▲ moves toward string 1, which is the one
drawn at the top of the neck. -}
highlightString : Model -> List (Html Msg)
highlightString model =
    case model.stringFocus of
        Nothing ->
            []

        Just s ->
            [ span
                [ style "display" "inline-flex"
                , style "align-items" "center"
                , style "gap" "2px"
                , style "font-size" "13px"
                , style "color" "var(--text-2)"
                ]
                [ text "String"
                , stepper (stringLabel model.tuning s) (\d -> SetStringFocus (Just (s - d)))
                ]
            ]


{-| A string as the stepper says it: its number and the note it is tuned to. -}
stringLabel : Tuning -> Int -> String
stringLabel tuning s =
    String.fromInt s ++ " (" ++ noteName (openString tuning s) ++ ")"


{-| The ▲/▼ pair the fret and string windows are set with. It takes the label
already rendered, because a string reads as `6 (E)` rather than as a bare
number. -}
stepper : String -> (Int -> Msg) -> Html Msg
stepper value toMsg =
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
            [ text value ]
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
are shown low to high, matching how a player reads the neck. -}
stringStepper : Model -> Int -> Html Msg
stringStepper model uiIndex =
    let
        s =
            stringCount model.tuning + 1 - uiIndex

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


{-| A scale's button. It lights for the scale however it is drawn (boxes,
diagonal or none), and keeps the neck drawn that way when the new scale can be. -}
scaleButton : Model -> ScaleType -> String -> Html Msg
scaleButton model st lbl =
    let
        current =
            (activeNeck model).scale

        target =
            case current of
                Diagonal _ ->
                    Maybe.withDefault st (diagonalOf st)

                Plain _ ->
                    Maybe.withDefault st (plainOf st)

                _ ->
                    st
    in
    button
        ([ onClick (SetScale target)
         , style "min-width" "80px"
         ]
            ++ buttonBaseStyle (boxedOf current == st)
        )
        [ text lbl ]


stringSetButton : Int -> Board -> StringSet -> String -> Html Msg
stringSetButton slot board set lbl =
    button
        ([ onClick (SetStringSet slot set)
         , style "min-width" "80px"
         ]
            ++ buttonBaseStyle (board.stringSet == set)
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
        strings =
            stringCount board.tuning

        -- Box tints are translucent, so the neck goes under them and shows
        -- through. Triad pills are opaque and are meant to read as solid
        -- shapes, so there the whole neck — inlay dots, fret lines and strings
        -- alike — goes under the lassos.
        neckAndRegions =
            if isTriad board.scale then
                drawFretMarkers strings ++ drawFretLines strings ++ drawStrings board ++ drawBoxRegions board

            else
                drawFretMarkers strings ++ drawBoxRegions board ++ drawFretLines strings ++ drawStrings board
    in
    Svg.svg
        [ SA.viewBox ("0 0 " ++ String.fromFloat totalWidth ++ " " ++ String.fromFloat (totalHeight strings))
        , SA.width (String.fromFloat totalWidth)
        , SA.style "max-width: 100%; height: auto;"
        ]
        (List.concat
            [ [ stripePatternDefs board ]
            , neckAndRegions
            , drawFifthsLadders board
            , drawNotes board
            , drawFretNumbers strings
            , drawInlayDots strings
            , drawHitAreas board
            ]
        )


{-| An invisible cell over every string at every fret, on top of everything
else, so a click anywhere on the neck plays that note and toggles it in or out
of the scale — the scale buttons are then just starting points for your own.
A shift-click only plays it. -}
drawHitAreas : Board -> List (Svg.Svg Msg)
drawHitAreas board =
    let
        cell s f =
            let
                ( x0, x1 ) =
                    if f == 0 then
                        ( leftMargin, leftMargin + nutWidth )

                    else
                        ( fretLineX (f - 1), fretLineX f )
            in
            Svg.rect
                [ SA.x (String.fromFloat x0)
                , SA.y (String.fromFloat (stringY s - stringSpacing / 2))
                , SA.width (String.fromFloat (x1 - x0))
                , SA.height (String.fromFloat stringSpacing)
                , SA.fill "transparent"
                , SA.style "cursor: pointer"
                , Html.Events.on "click"
                    (Decode.map (FretClicked board.slot s f) (Decode.field "shiftKey" Decode.bool))
                ]
                []
    in
    List.concatMap (\s -> List.map (cell s) (List.range 0 numFrets)) (List.range 1 (stringCount board.tuning))



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

    else if isPlain board.scale then
        []

    else
        drawBoxRegionsBoxes board


drawBoxRegionsBoxes : Board -> List (Svg.Svg Msg)
drawBoxRegionsBoxes board =
    let
        -- A string whose window shifts (see `stringShift`) can need the box an
        -- octave further out at either end of the neck.
        octaves =
            [ -2, -1, 0, 1, 2 ]

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
    if board.mono then
        -- Hatchings are mostly holes, so where two boxes overlap both
        -- simply show; a stripe would only chop each texture in half.
        solids

    else
        solids ++ overlaps ++ wrapOverlaps


drawDiagonalRegions : Board -> List (Svg.Svg Msg)
drawDiagonalRegions board =
    let
        shapes =
            diagonalShapesFor (stringCount board.tuning) board.scale

        instances =
            List.concatMap
                (\( i, shape ) -> List.map (\o -> ( ( i, o ), shape, o )) (diagonalOctaves shape))
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
            drawDiagonalShape board.tuning
                board.scale
                board.root
                (regionShape board
                    ("diag-" ++ String.fromInt (Tuple.first key) ++ "_" ++ String.fromInt o)
                    "0.45"
                    (isMuted lit key)
                    shape.color
                )
                shape
                o
        )
        instances


{-| The octaves a shape is drawn in. Five cover the neck for the shapes written
out for the top three pairs; each pair further down sits further toward the
nut (`diagonalPairOffset`), so its copies start further up the octaves. -}
diagonalOctaves : DiagShape -> List Int
diagonalOctaves shape =
    let
        pair =
            (shape.upper - 1) // 2
    in
    List.range -2 (2 + (2 * max 0 (pair - 2) + 11) // 12)


{-| The lowest and highest fret of a list of shape-relative frets, once shifted
to where the shape sits; `Nothing` for a string the shape has no notes on (a
half pair has none on its lower string). -}
relsSpan : Int -> List Int -> Maybe ( Int, Int )
relsSpan shift rels =
    Maybe.map2 (\lo hi -> ( shift + lo, shift + hi )) (List.minimum rels) (List.maximum rels)


{-| A climbing shape's reach, lowest fret on its lower string to highest on its
upper — what the highlight window is compared against. These shapes are meant
to be slid rather than played in one place, so the window only says which one
you are nearest, and the rest fade. -}
diagonalSpan : Tuning -> ScaleType -> Int -> DiagShape -> Int -> ( Int, Int )
diagonalSpan tuning scale root shape octave =
    let
        shift =
            diagonalAnchor tuning scale root + 12 * octave

        ends rels string =
            relsSpan (shift + boxShift tuning string) rels

        spans =
            List.filterMap identity
                [ ends shape.lowerRels shape.lower
                , ends shape.upperRels shape.upper
                ]
    in
    ( List.minimum (List.map Tuple.first spans) |> Maybe.withDefault 0
    , List.maximum (List.map Tuple.second spans) |> Maybe.withDefault 0
    )


{-| One diagonal shape: a stepped polygon spanning two adjacent strings.
Both edges are staircases that step at the midline between the strings; an
edge where both strings share a fret (pattern 1's right, pattern 2's left)
collapses to a vertical line. The shape repeats every 12 frets (one octave)
to fill the neck. A half pair, at the bottom of a neck with an odd number of
strings, is just the upper string's half of it. -}
drawDiagonalShape : Tuning -> ScaleType -> Int -> (List ( Float, Float ) -> Svg.Svg Msg) -> DiagShape -> Int -> Maybe (Svg.Svg Msg)
drawDiagonalShape tuning scale root paint shape octave =
    let
        shift =
            diagonalAnchor tuning scale root + 12 * octave

        lowerSpan =
            relsSpan (shift + boxShift tuning shape.lower) shape.lowerRels

        upperSpan =
            relsSpan (shift + boxShift tuning shape.upper) shape.upperRels

        inRange =
            List.any
                (\( lo, hi ) ->
                    (lo >= 0 && lo <= numFrets) || (hi >= 0 && hi <= numFrets)
                )
                (List.filterMap identity [ lowerSpan, upperSpan ])

        pad =
            stringSpacing * 0.55

        yMid =
            (stringY shape.lower + stringY shape.upper) / 2

        yUpTop =
            stringY shape.upper - pad

        verts =
            case ( lowerSpan, upperSpan ) of
                ( Just ( loL, hiL ), Just ( loU, hiU ) ) ->
                    let
                        yLoBot =
                            stringY shape.lower + pad
                    in
                    [ ( fretCenterX loL, yLoBot )
                    , ( fretCenterX hiL, yLoBot )
                    , ( fretCenterX hiL, yMid )
                    , ( fretCenterX hiU, yMid )
                    , ( fretCenterX hiU, yUpTop )
                    , ( fretCenterX loU, yUpTop )
                    , ( fretCenterX loU, yMid )
                    , ( fretCenterX loL, yMid )
                    ]

                ( Nothing, Just ( loU, hiU ) ) ->
                    let
                        yUpBot =
                            stringY shape.upper + pad
                    in
                    [ ( fretCenterX loU, yUpTop )
                    , ( fretCenterX hiU, yUpTop )
                    , ( fretCenterX hiU, yUpBot )
                    , ( fretCenterX loU, yUpBot )
                    ]

                _ ->
                    []
    in
    if inRange && not (List.isEmpty verts) then
        Just (paint verts)

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
    List.indexedMap (\i triad -> triadFill board i (muted triad) triad) voicings
        ++ List.concat
            (List.indexedMap
                (\i triad -> triadRing board.id (ringColor board (muted triad) triad.inversion) i triad)
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


{-| The lasso's interior. In monochrome the pill is still opaque — the page
color first, then the inversion's hatching over it — so it hides what it
covers exactly as the colored one does. The hatching is clipped to the pill,
and a clip path takes its children's fill, not their stroke, so the clip is
the pill spelled out as fills: a disc on each note and a band along each leg,
which is exactly what a round-capped, round-joined stroke covers. -}
triadFill : Board -> Int -> Bool -> Triad -> Svg.Svg Msg
triadFill board index muted triad =
    if board.mono then
        let
            r =
                triadLassoRadius triad

            pts =
                List.map (\( s, f ) -> ( noteX f, stringY s )) triad.notes

            num =
                String.fromFloat

            disc ( x, y ) =
                Svg.circle [ SA.cx (num x), SA.cy (num y), SA.r (num r) ] []

            band ( ax, ay ) ( bx, by ) =
                let
                    len =
                        max 0.001 (sqrt ((bx - ax) ^ 2 + (by - ay) ^ 2))

                    nx =
                        -(by - ay) / len * r

                    ny =
                        (bx - ax) / len * r
                in
                Svg.polygon
                    [ SA.points
                        (pointsAttr
                            [ ( ax + nx, ay + ny ), ( bx + nx, by + ny ), ( bx - nx, by - ny ), ( ax - nx, ay - ny ) ]
                        )
                    ]
                    []

            bands =
                case pts of
                    first :: rest ->
                        List.map2 band (first :: rest) rest

                    [] ->
                        []

            ( ( xa, xb ), ( ya, yb ) ) =
                bounds pts
        in
        Svg.g []
            (triadCapsule triad 0 [ SA.stroke "var(--bg)" ]
                :: (if muted then
                        []

                    else
                        [ hatchClipped (board.id ++ "clip-triad-" ++ String.fromInt index)
                            (List.map disc pts ++ bands)
                            ( ( xa - r, xb + r ), ( ya - r, yb + r ) )
                            (triad.inversion + 1)
                        ]
                   )
            )

    else
        triadCapsule triad 0 [ SA.stroke (inversionFill muted triad.inversion) ]


{-| The lasso's ring. In monochrome the texture inside says the inversion, so
the ring only has to be ink — or gray when the highlight window mutes it. -}
ringColor : Board -> Bool -> Int -> String
ringColor board muted inv =
    if not board.mono then
        inversionColor muted inv

    else if muted then
        "var(--inv-off)"

    else
        "var(--text-strong)"


{-| The lasso outline: the shape minus the same shape inset, which leaves an
even ring around it. It is one path holding both outlines, filled even-odd, so
the ring is genuinely hollow and lassos can overlap freely — the obvious pair
of strokes (wide in the color, narrower in the background color) would paint
over whatever sits under the lasso: the inlay dots, and the rings of any lasso
it crosses. It used to be a rectangle masked by those two strokes, but Chrome
prints a mask as a bitmap, so the rings came out jagged on paper; a path stays
vector. -}
triadRing : String -> String -> Int -> Triad -> List (Svg.Svg Msg)
triadRing _ ringFill _ triad =
    let
        pts =
            List.map (\( s, f ) -> ( noteX f, stringY s )) triad.notes

        r =
            triadLassoRadius triad
    in
    [ Svg.path
        [ SA.d (pillOutline pts r ++ pillOutline pts (r - triadLassoInset))
        , SA.fill ringFill
        , SA.fillRule "evenodd"
        ]
        []
    ]


{-| The outline of what a round-capped, round-joined stroke of width 2r along
a polyline covers, as a closed path: out along one side, round the far cap,
back along the other side, round the near cap. At each bend the outer side
goes round an arc and the inner side cuts the corner where the two offset
lines meet. That corner stays on both legs as long as r is under the legs'
rise, which it is: legs join adjacent strings, and the lassos are narrower
than a string gap. -}
pillOutline : List ( Float, Float ) -> Float -> String
pillOutline pts r =
    let
        num =
            String.fromFloat

        pt ( x, y ) =
            num x ++ " " ++ num y

        add ( ax, ay ) ( bx, by ) =
            ( ax + bx, ay + by )

        scale k ( x, y ) =
            ( k * x, k * y )

        cross ( ax, ay ) ( bx, by ) =
            ax * by - ay * bx

        unit ( ( ax, ay ), ( bx, by ) ) =
            let
                len =
                    max 0.001 (sqrt ((bx - ax) ^ 2 + (by - ay) ^ 2))
            in
            ( (bx - ax) / len, (by - ay) / len )

        normal ( dx, dy ) =
            ( -dy, dx )

        segs =
            case pts of
                first :: rest ->
                    List.map2 Tuple.pair (first :: rest) rest

                [] ->
                    []

        dirs =
            List.map unit segs

        arc to sweep =
            " A" ++ num r ++ " " ++ num r ++ " 0 0 " ++ sweep ++ " " ++ pt to

        sweepOf a b =
            if cross a b > 0 then
                "1"

            else
                "0"

        -- The join at vertex p between legs d1 and d2, on the side `side`
        -- (+1 or −1) of the normals, walking from leg `from` to leg `to`.
        join side p d1 d2 =
            let
                n1 =
                    scale side (normal d1)

                n2 =
                    scale side (normal d2)

                ( from, to ) =
                    if side > 0 then
                        ( n1, n2 )

                    else
                        ( n2, n1 )

                outer =
                    side * cross d1 d2 < 0

                dot =
                    Tuple.first n1 * Tuple.first n2 + Tuple.second n1 * Tuple.second n2
            in
            if outer then
                " L" ++ pt (add p (scale r from)) ++ arc (add p (scale r to)) (sweepOf from to)

            else
                " L" ++ pt (add p (scale (r / (1 + dot)) (add n1 n2)))

        bends =
            List.map3 (\p d1 d2 -> ( p, d1, d2 ))
                (List.drop 1 pts)
                dirs
                (List.drop 1 dirs)
    in
    case ( List.head pts, List.head (List.reverse pts), ( List.head dirs, List.head (List.reverse dirs) ) ) of
        ( Just p0, Just pm, ( Just d0, Just dm ) ) ->
            let
                n0 =
                    normal d0

                nm =
                    normal dm
            in
            "M"
                ++ pt (add p0 (scale r n0))
                ++ String.concat (List.map (\( p, d1, d2 ) -> join 1 p d1 d2) bends)
                ++ " L"
                ++ pt (add pm (scale r nm))
                ++ arc (add pm (scale -r nm)) "0"
                ++ String.concat (List.map (\( p, d1, d2 ) -> join -1 p d1 d2) (List.reverse bends))
                ++ " L"
                ++ pt (add p0 (scale -r n0))
                ++ arc (add p0 (scale r n0)) "0"
                ++ "Z "

        _ ->
            ""


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
            (regionShape board
                ("box-" ++ String.fromInt b ++ "_" ++ String.fromInt octave)
                boxFillOpacity
                (isMuted lit ( b, octave ))
                b
                (polygonVerts positions)
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
                [ SA.points (pointsAttr (polygonVerts overlapPositions))
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
                [ SA.points (pointsAttr (polygonVerts overlapPositions))
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
polygonVerts : List ( Int, Int, Int ) -> List ( Float, Float )
polygonVerts positions =
    let
        pad =
            stringSpacing * 0.55

        rows =
            List.sortBy (\( str, _, _ ) -> str) positions

        yMid sa sb =
            (stringY sa + stringY sb) / 2

        -- Each pair of neighboring strings is crossed at the midline between
        -- them: down the right edge, which steps from one string's last fret
        -- to the next's, and back up the left.
        pairs =
            List.map2 Tuple.pair rows (List.drop 1 rows)

        down ( ( sa, _, hiA ), ( sb, _, hiB ) ) =
            [ ( fretCenterX hiA, yMid sa sb ), ( fretCenterX hiB, yMid sa sb ) ]

        up ( ( sa, loA, _ ), ( sb, loB, _ ) ) =
            [ ( fretCenterX loB, yMid sa sb ), ( fretCenterX loA, yMid sa sb ) ]
    in
    case ( rows, List.reverse rows ) of
        ( ( top, loTop, hiTop ) :: _, ( bottom, loBottom, hiBottom ) :: _ ) ->
            [ ( fretCenterX loTop, stringY top - pad ), ( fretCenterX hiTop, stringY top - pad ) ]
                ++ List.concatMap down pairs
                ++ [ ( fretCenterX hiBottom, stringY bottom + pad ), ( fretCenterX loBottom, stringY bottom + pad ) ]
                ++ List.concatMap up (List.reverse pairs)

        _ ->
            []



fretCenterX : Int -> Float
fretCenterX f =
    -- noteX handles fret 0 specially; here we always use the "between lines" center
    if f <= 0 then
        leftMargin + nutWidth + fretWidth * (toFloat f - 0.5)

    else
        leftMargin + nutWidth + fretWidth * (toFloat f - 0.5)



-- FRETBOARD STRUCTURE


drawFretLines : Int -> List (Svg.Svg Msg)
drawFretLines strings =
    let
        top = topMargin - 4
        bot = topMargin + fretboardHeight strings + 4

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


{-| The strings. The highlighted one is drawn heavier and in the text
color: the faded notes say which string is live, and this says it again on the
stretches of neck that carry no notes. -}
drawStrings : Board -> List (Svg.Svg Msg)
drawStrings board =
    let
        leftX =
            leftMargin

        rightX =
            leftMargin + nutWidth + fretWidth * toFloat numFrets

        lit s =
            board.stringFocus == Just s

        drawLine s =
            Svg.line
                [ SA.x1 (String.fromFloat leftX)
                , SA.x2 (String.fromFloat rightX)
                , SA.y1 (String.fromFloat (stringY s))
                , SA.y2 (String.fromFloat (stringY s))
                , SA.stroke
                    (if lit s then
                        "var(--string-on)"

                     else
                        "var(--string)"
                    )
                , SA.strokeWidth
                    (if lit s then
                        "2.4"

                     else
                        "1"
                    )
                ]
                []
    in
    List.map drawLine (List.range 1 (stringCount board.tuning))


drawFretMarkers : Int -> List (Svg.Svg Msg)
drawFretMarkers strings =
    let
        singles = [ 3, 5, 7, 9, 15, 17, 19, 21 ]
        doubles = [ 12 ]
        midY = topMargin + fretboardHeight strings / 2

        -- The pair at the 12th fret straddles the middle a gap apart, or
        -- closer where the neck is too narrow to hold them that far out.
        gap = min stringSpacing (fretboardHeight strings / 4)

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
        ++ List.concatMap (\f -> [ dot f -gap, dot f gap ]) doubles



-- CIRCLE-OF-FIFTHS LADDERS


{-| Where the circle of fifths goes from string `s + 1` to the string above it:
the fret offset of the note a fourth up from the lower string, which is the
next pitch class round the circle (read the way the strings climb, B E A D G C
F …). 0 for strings a fourth apart, 1 across the major third from G to B in
standard tuning, and whatever the tuning says elsewhere, kept to −5…6 so the
path jogs the short way.
-}
fifthsStep : Tuning -> Int -> Int
fifthsStep tuning s =
    let
        o =
            modBy 12 (openString tuning (s + 1) + 5 - openString tuning s)
    in
    if o > 6 then
        o - 12

    else
        o


{-| Whether the ladders mean anything in this tuning: they read as "the circle
of fifths, shifted a fret" only on a neck tuned in fourths. So every pair of
strings but the lowest has to be a fourth apart or a semitone off one — a major
third (standard's G–B) kinks the ladder toward the body, a tritone (E A D G C
F#) toward the nut. The lowest pair may be anything, so the drop tunings
qualify. DADGAD and the open tunings fail, and their ladders would jog back and
forth to no purpose.
-}
laddersFit : Tuning -> Bool
laddersFit tuning =
    List.all (\s -> abs (fifthsStep tuning s) <= 1) (List.range 1 (stringCount tuning - 2))


{-| The all-notes map's answer to "why are the top two strings off by one":
each note is linked to the note a fourth up on the string above, i.e. the next
step round the circle of fifths. Across strings a fourth apart that link is
straight up the fret, so each fret becomes a ladder walking the rainbow; at the
G–B major third it jogs a fret toward the body, and that kink, repeated on every
fret, is the shift made visible. Each rung is a gradient between its two notes'
colors, so the line itself walks the circle. Drawn under the note markers.
-}
drawFifthsLadders : Board -> List (Svg.Svg Msg)
drawFifthsLadders board =
    let
        rung s f =
            let
                g =
                    f + fifthsStep board.tuning s
            in
            if g < 0 || g > numFrets then
                Nothing

            else
                Just ( s, f, g )

        rungs =
            List.concatMap
                (\s -> List.filterMap (rung s) (List.range 0 numFrets))
                (List.range 1 (stringCount board.tuning - 1))

        gradId ( s, f, _ ) =
            board.id ++ "ladder-" ++ String.fromInt s ++ "-" ++ String.fromInt f

        stop offset n =
            Svg.stop
                [ SA.offset offset
                , SA.style ("stop-color: " ++ pitchColor n)
                ]
                []

        gradient (( s, f, g ) as r) =
            Svg.linearGradient
                [ SA.id (gradId r)
                , SA.gradientUnits "userSpaceOnUse"
                , SA.x1 (String.fromFloat (noteX f))
                , SA.y1 (String.fromFloat (stringY (s + 1)))
                , SA.x2 (String.fromFloat (noteX g))
                , SA.y2 (String.fromFloat (stringY s))
                ]
                [ stop "0" (noteAt board.tuning (s + 1) f)
                , stop "1" (noteAt board.tuning s g)
                ]

        line (( s, f, g ) as r) =
            Svg.line
                [ SA.x1 (String.fromFloat (noteX f))
                , SA.y1 (String.fromFloat (stringY (s + 1)))
                , SA.x2 (String.fromFloat (noteX g))
                , SA.y2 (String.fromFloat (stringY s))
                , SA.stroke
                    (if board.mono then
                        "var(--note-bd)"

                     else
                        "url(#" ++ gradId r ++ ")"
                    )
                , SA.strokeWidth "6"
                , SA.strokeLinecap "round"
                ]
                []
    in
    if (board.scale == ChromaticMinor || board.scale == ChromaticMajor) && laddersFit board.tuning then
        (if board.mono then
            []

         else
            [ Svg.defs [] (List.map gradient rungs) ]
        )
            ++ List.map line rungs

    else
        []


-- NOTES


drawNotes : Board -> List (Svg.Svg Msg)
drawNotes board =
    let
        forString s =
            List.filterMap (drawNoteAt board s) (List.range 0 numFrets)
    in
    List.concatMap forString (List.range 1 (stringCount board.tuning))


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
                        -- Monochrome has no hues to spend, so the note
                        -- names alone say which note is which.
                        chromaticMarker role cx cy
                            (if board.mono then
                                "var(--note-bg)"

                             else
                                pitchColor n
                            )

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
                    Svg.g [ SA.fill textColor ]
                        (if board.degrees then
                            degreeLabel (degreeName board n) cx (cy + 4)

                         else
                            noteLabel (spelledName board n) cx (cy + 4)
                        )
            in
            Just
                (Svg.g (offString board s)
                    ((if board.mono then
                        [ noteHalo role cx cy ]

                      else
                        []
                     )
                        ++ [ background, labelNode ]
                    )
                )

        Nothing ->
            Nothing



{-| A page-colored rim under a note marker in monochrome, so a marker stands
clear of the hatching behind it instead of dissolving into its lines. It is the
marker's own shape grown by 3px; the circles' rim stops at the inner edge of
the smallest triad lasso ring. -}
noteHalo : NoteRole -> Float -> Float -> Svg.Svg Msg
noteHalo role cx cy =
    case role of
        Root ->
            Svg.rect
                [ SA.x (String.fromFloat (cx - 17))
                , SA.y (String.fromFloat (cy - 17))
                , SA.width "34"
                , SA.height "34"
                , SA.rx "6"
                , SA.fill "var(--bg)"
                ]
                []

        _ ->
            Svg.circle
                [ SA.cx (String.fromFloat cx)
                , SA.cy (String.fromFloat cy)
                , SA.r "17"
                , SA.fill "var(--bg)"
                ]
                []


{-| The font stack for text drawn in the SVG, the same as the page's. Chrome
does not know `-apple-system`, so without `system-ui` it falls through to
Helvetica. -}
svgFont : String
svgFont =
    "-apple-system, system-ui, \"Segoe UI\", Helvetica, Arial, sans-serif"


{-| A note name for a marker, centered on `cx` with its baseline at `y`: the
letter as bold text, then each accidental drawn as a path, raised like a
superscript. The font's own ♭ will not do: the system font draws it as a plain
lowercase b, and fonts with a real engraved flat are not on every platform.
Elm cannot measure text, so the letter's width comes from `letterWidth`. -}
noteLabel : String -> Float -> Float -> List (Svg.Svg Msg)
noteLabel name cx y =
    let
        letterNode x anchor txt =
            Svg.text_
                [ SA.x (String.fromFloat x)
                , SA.y (String.fromFloat y)
                , SA.textAnchor anchor
                , SA.fontSize "13"
                , SA.fontWeight "700"
                , SA.fontFamily svgFont
                ]
                [ Svg.text txt ]
    in
    case String.uncons name of
        Just ( letter, acc ) ->
            let
                glyphs =
                    List.filterMap accidentalPath (String.toList acc)

                step =
                    accidentalWidth + accidentalGap

                letterW =
                    letterWidth letter

                left =
                    cx - (letterW + toFloat (List.length glyphs) * step) / 2

                glyphAt i d =
                    Svg.path
                        [ SA.d d
                        , SA.fillRule "evenodd"
                        , SA.transform
                            ("translate("
                                ++ String.fromFloat (left + letterW + accidentalGap + toFloat i * step)
                                ++ ","
                                ++ String.fromFloat (y - 3.5)
                                ++ ") scale(0.9)"
                            )
                        ]
                        []
            in
            if List.isEmpty glyphs then
                [ letterNode cx "middle" name ]

            else
                letterNode left "start" (String.fromChar letter)
                    :: List.indexedMap glyphAt glyphs

        Nothing ->
            []


{-| An interval name for a marker, centered on `cx`: its accidentals drawn as
paths, raised like a superscript the way `noteLabel` raises them, then the
number (or R) as bold text. The accidental leads, as it is written: ♭3. -}
degreeLabel : String -> Float -> Float -> List (Svg.Svg Msg)
degreeLabel name cx y =
    let
        ( accs, rest ) =
            ( String.filter (\c -> accidentalPath c /= Nothing) name
            , String.filter (\c -> accidentalPath c == Nothing) name
            )

        glyphs =
            List.filterMap accidentalPath (String.toList accs)

        step =
            accidentalWidth + accidentalGap

        restW =
            String.toList rest |> List.map letterWidth |> List.sum

        left =
            cx - (toFloat (List.length glyphs) * step + restW) / 2

        glyphAt i d =
            Svg.path
                [ SA.d d
                , SA.fillRule "evenodd"
                , SA.transform
                    ("translate("
                        ++ String.fromFloat (left + toFloat i * step)
                        ++ ","
                        ++ String.fromFloat (y - 3.5)
                        ++ ") scale(0.9)"
                    )
                ]
                []
    in
    Svg.text_
        [ SA.x (String.fromFloat (left + toFloat (List.length glyphs) * step))
        , SA.y (String.fromFloat y)
        , SA.textAnchor "start"
        , SA.fontSize "13"
        , SA.fontWeight "700"
        , SA.fontFamily svgFont
        ]
        [ Svg.text rest ]
        :: List.indexedMap glyphAt glyphs


{-| Advance width of a bold 13px note letter, or interval digit, in the system
font, measured in the browser. Only used to center a label and its accidentals
together, so a platform whose font runs a little wider is off by a fraction of
a pixel. -}
letterWidth : Char -> Float
letterWidth c =
    case c of
        'A' -> 9.45
        'B' -> 8.94
        'C' -> 9.56
        'D' -> 9.64
        'E' -> 8.01
        'F' -> 7.69
        'G' -> 9.81
        'R' -> 8.95
        '1' -> 6.58
        '2' -> 8.28
        '3' -> 8.62
        '4' -> 8.85
        '5' -> 8.55
        '6' -> 8.81
        '7' -> 7.78
        _ -> 9


accidentalWidth : Float
accidentalWidth =
    4.5


accidentalGap : Float
accidentalGap =
    0.8


{-| Path for one accidental character as `accidentalGlyph` writes it, in a box
5 wide with the baseline at 0 (scaled by 0.9 when drawn). The flat is an
engraved one, a thin stem and a heavy pointed bowl, so it does not read as a
b; the sharp has the slanted, heavier bars of a printed one. -}
accidentalPath : Char -> Maybe String
accidentalPath c =
    case c of
        '\u{266D}' ->
            Just "M0,-10 H0.8 V-3.7 C2.3,-5.2 5.0,-5.0 5.0,-3.1 C5.0,-1.5 2.7,-0.3 0,1.1 Z M0.8,-2.6 V-0.1 C2.1,-0.9 3.5,-1.9 3.5,-2.9 C3.5,-3.9 1.9,-3.7 0.8,-2.6 Z"

        '\u{266F}' ->
            Just "M1.0,-9.6 H1.6 V1.4 H1.0 Z M3.4,-10.4 H4.0 V0.6 H3.4 Z M0,-5.6 L5,-7.0 V-5.7 L0,-4.3 Z M0,-1.6 L5,-3.0 V-1.7 L0,-0.3 Z"

        'x' ->
            Just "M0,-7 H1.3 L5,-2.5 V-1.2 H3.7 L0,-5.7 Z M5,-7 V-5.7 L1.3,-1.2 H0 V-2.5 L3.7,-7 Z"

        _ ->
            Nothing


{-| What a note marker wears when the string highlight is on and this note is
not on that string: the whole marker, label included, faded back behind the
one string you are working on. -}
offString : Board -> Int -> List (Svg.Attribute Msg)
offString board s =
    case board.stringFocus of
        Just t ->
            if t == s then
                []

            else
                [ SA.opacity (String.fromFloat offStringOpacity) ]

        Nothing ->
            []



-- FRET NUMBER LABELS


drawFretNumbers : Int -> List (Svg.Svg Msg)
drawFretNumbers strings =
    let
        y =
            topMargin + fretboardHeight strings + 38

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
                        , SA.fontFamily svgFont
                        , SA.fill "var(--fret-num)"
                        ]
                        [ Svg.text txt ]
            in
            bg ++ openTriangle ++ [ lbl ]
    in
    List.concatMap labelFor (List.range 0 numFrets)



-- INLAY DOT ROW (below fret numbers)


drawInlayDots : Int -> List (Svg.Svg Msg)
drawInlayDots strings =
    let
        singles = [ 3, 5, 7, 9, 15, 17, 19, 21 ]
        doubles = [ 12 ]
        y = topMargin + fretboardHeight strings + 60

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
            if isChromatic board.scale || isPlain board.scale then
                []

            else if isTriad board.scale then
                legendText "Bass note:"
                    :: List.map (legendRing board) [ ( 0, "root" ), ( 1, triadMiddle board.scale ++ " (1st inv)" ), ( 2, "5th (2nd inv)" ) ]

            else if isDiagonal board.scale then
                legendText "Patterns:"
                    :: List.map (legendSwatch board) [ ( 1, "1" ), ( 2, "2" ) ]

            else
                legendText "Boxes:"
                    :: List.map (legendSwatch board) [ ( 1, "1" ), ( 2, "2" ), ( 3, "3" ), ( 4, "4" ), ( 5, "5" ) ]

        highlight =
            case board.focus of
                Nothing ->
                    []

                Just ( lo, hi ) ->
                    [ [ (if board.mono then
                            legendBlank

                         else
                            legendChip "var(--box-off)"
                        )
                            ("outside frets " ++ String.fromInt lo ++ "–" ++ String.fromInt hi)
                      ]
                    ]

        strings =
            case board.stringFocus of
                Nothing ->
                    []

                Just s ->
                    [ [ legendFade ("off string " ++ stringLabel board.tuning s) ] ]

        tones =
            if board.scale == Blank then
                -- Nothing is drawn, so there is nothing to explain.
                []

            else if isChromatic board.scale then
                [ legendText "Tones:"
                , legendMarker board.mono "square-pc" "Root"
                , legendMarker board.mono "circle-pc-dashed"
                    (if board.scale == ChromaticMajor then
                        "3rd"

                     else
                        "♭3"
                    )
                , legendMarker board.mono "circle-pc-dotted" "5th"
                , legendMarker board.mono "circle-pc-double"
                    (if board.scale == ChromaticMajor then
                        "7th"

                     else
                        "♭7"
                    )
                , legendMarker board.mono "circle-pc" "other"
                ]
                    ++ (if board.mono then
                            []

                        else
                            [ legendText "hue = note" ]
                       )

            else if isTriad board.scale then
                -- A triad has nothing but chord tones, so there is no 7th and
                -- no "other" to explain.
                [ legendText "Tones:"
                , legendMarker board.mono "square-dark" "Root"
                , if thirdOf board.scale == -1 then
                    -- A sus chord's 2nd or 4th is not a third, so it wears the
                    -- plain marker of any other note.
                    legendMarker board.mono "circle-plain" (triadMiddle board.scale)

                  else
                    legendMarker board.mono "circle-dashed" "3rd"
                , legendMarker board.mono "circle-dotted" "5th"
                ]

            else
                [ legendText "Tones:"
                , legendMarker board.mono "square-dark" "Root"
                , legendMarker board.mono "circle-dashed" "3rd"
                , legendMarker board.mono "circle-dotted" "5th"
                , legendMarker board.mono "circle-double" "7th"
                , legendMarker board.mono "circle-plain" "other"
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
                ++ List.filter (not << List.isEmpty) (tones :: (highlight ++ strings))
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


{-| The off-string notes in miniature: an ordinary note marker at the opacity
they are drawn with. -}
legendFade : String -> Html Msg
legendFade lbl =
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
            , style "background" "var(--note-bg)"
            , style "border" "1px solid var(--note-bd)"
            , style "border-radius" "50%"
            , style "opacity" (String.fromFloat offStringOpacity)
            ]
            []
        , text lbl
        ]


legendText : String -> Html Msg
legendText s =
    span [ style "font-weight" "600", style "color" "var(--text-strong)" ] [ text s ]


legendSwatch : Board -> ( Int, String ) -> Html Msg
legendSwatch board ( b, lbl ) =
    if board.mono then
        hatchChip False b lbl

    else
        legendChip (boxColor b) lbl


{-| A box or lasso in monochrome: its hatching in a chip, square for a
box, a ringed circle for a lasso — half size, centered on the middle of a
fret-by-string cell. The legend is one per page, so its clip ids cannot collide
with another legend's. -}
hatchChip : Bool -> Int -> String -> Html Msg
hatchChip round b lbl =
    let
        id =
            "legend-hatch-" ++ String.fromInt b

        shape =
            [ SA.x "1", SA.y "1", SA.width "14", SA.height "14" ]
                ++ (if round then
                        [ SA.rx "7" ]

                    else
                        [ SA.rx "2" ]
                   )
    in
    span
        [ style "display" "inline-flex"
        , style "align-items" "center"
        , style "gap" "6px"
        ]
        [ Svg.svg [ SA.width "16", SA.height "16", SA.viewBox "0 0 16 16" ]
            [ Svg.clipPath [ SA.id id ] [ Svg.rect shape [] ]
            , Svg.g [ SA.clipPath ("url(#" ++ id ++ ")") ]
                [ Svg.g
                    [ SA.transform
                        ("translate(" ++ String.fromFloat (8 - fretWidth / 4) ++ " " ++ String.fromFloat (8 - stringSpacing / 4) ++ ") scale(0.5)")
                    ]
                    [ hatchTexture b ( 0, 0 ) ( ( 0, fretWidth ), ( 0, stringSpacing ) ) ]
                ]
            , Svg.rect
                (shape
                    ++ SA.fill "none"
                    :: (if round then
                            [ SA.stroke "var(--text-strong)", SA.strokeWidth "2" ]

                        else
                            [ SA.stroke "var(--surface-bd)", SA.strokeWidth "1" ]
                       )
                )
                []
            ]
        , text lbl
        ]


{-| What a muted shape looks like in monochrome: nothing, inside an outline. -}
legendBlank : String -> Html Msg
legendBlank lbl =
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
            , style "border" "1px solid var(--surface-bd)"
            , style "border-radius" "3px"
            ]
            []
        , text lbl
        ]


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
legendRing : Board -> ( Int, String ) -> Html Msg
legendRing board ( inv, lbl ) =
    if board.mono then
        hatchChip True (inv + 1) lbl

    else
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


legendMarker : Bool -> String -> String -> Html Msg
legendMarker mono kind lbl =
    let
        common =
            [ style "display" "inline-block"
            , style "width" "16px"
            , style "height" "16px"
            , style "box-sizing" "border-box"
            ]

        -- A few pitch-class hues in one chip, to say "colored by note".
        pcGradient =
            if mono then
                "var(--note-bg)"

            else
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
        , Browser.Events.onResize (\w _ -> WindowResized w)

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


{-| The window width, in CSS pixels, below which the drawers start shut and
act like menus: phones and tablets, where the open controls alone would fill
the first screen. -}
compactWidth : Int
compactWidth =
    1000


main : Program Int Model Msg
main =
    Browser.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }
