import io, sys
p = 'src/Main.elm'
src = io.open(p, encoding='utf-8').read()

def rep(old, new):
    global src
    n = src.count(old)
    if n != 1:
        sys.exit("FAIL (%d matches):\n%s" % (n, old[:200]))
    src = src.replace(old, new)

rep('''{-| A lasso is a bead around each of its three notes joined by a ribbon: the
bead clears the 28px note marker on every side, whatever angle the ribbon
arrives at, and 34px across leaves a hair of daylight between the lassos of
neighboring string sets (`stringSpacing` is 36). The ring is the outline of
that shape, `triadLassoInset` thick. -}
triadBeadRadius : Float
triadBeadRadius =
    17


triadRibbonWidth : Float
triadRibbonWidth =
    24


triadLassoInset : Float
triadLassoInset =
    3''',
'''{-| A lasso is a bead around each of its three notes joined by a ribbon, and it
comes in two sizes, alternating by string set: 1-2-3 and 3-4-5 are drawn wide,
2-3-4 and 4-5-6 narrow. Neighboring sets share two strings and often the same
note, so at one size their lassos land on top of each other and the picture
turns to mush; at two sizes they nest, and you can follow either set through
the tangle. The small size still clears the 28px note markers on every side,
whatever angle the ribbon arrives at. -}
triadIsWide : Triad -> Bool
triadIsWide triad =
    case triad.notes of
        ( top, _ ) :: _ ->
            modBy 2 top == 1

        [] ->
            True


triadBeadRadius : Triad -> Float
triadBeadRadius triad =
    if triadIsWide triad then
        23

    else
        17


triadRibbonWidth : Triad -> Float
triadRibbonWidth triad =
    if triadIsWide triad then
        29

    else
        21


{-| How thick the ring around a lasso is. Anything the inset leaves inside the
note markers is simply hidden behind them, since markers are drawn later. -}
triadLassoInset : Float
triadLassoInset =
    3''')

rep('''        , SA.strokeWidth (String.fromFloat (triadRibbonWidth - 2 * inset))''',
'''        , SA.strokeWidth (String.fromFloat (triadRibbonWidth triad - 2 * inset))''')

rep('''                    , SA.r (String.fromFloat (triadBeadRadius - inset))''',
'''                    , SA.r (String.fromFloat (triadBeadRadius triad - inset))''')

rep('''        pad =
            triadBeadRadius + 4''',
'''        pad =
            triadBeadRadius triad + 4''')

io.open(p, 'w', encoding='utf-8').write(src)
print("ok")
