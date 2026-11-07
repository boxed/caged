"""Render the band's samples from FluidR3_GM.sf2 with fluidsynth.

usage: python3 -I sounds/render.py <FluidR3_GM.sf2> <scratch dir> sounds

FluidR3_GM.sf2 (MIT, © Frank Wen) is in Debian's fluid-soundfont-gm package. The guitar-* and
piano-* files predate this script; they come from gleitz/midi-js-soundfonts.

Each note is a one-note MIDI file rendered dry (no reverb or chorus: band.js has its own room),
trimmed, normalized per instrument (so velocity layers and the notes of one instrument keep
their balance), faded out and encoded as a mono mp3.
"""
import array
import os
import struct
import subprocess
import sys
import wave

SF2, WORK, OUT = sys.argv[1:4]
os.makedirs(WORK, exist_ok=True)

RATE = 44100
TPQ = 480  # ticks per quarter at 120 bpm: 960 ticks a second


def vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append(0x80 | (n & 0x7F))
        n >>= 7
    return bytes(reversed(out))


def midi_file(path, channel, program, note, vel, hold, length):
    ev = b''
    if channel != 9:
        ev += vlq(0) + bytes([0xC0 | channel, program])
    ev += vlq(0) + bytes([0x90 | channel, note, vel])
    hold_t = int(hold * 960)
    ev += vlq(hold_t) + bytes([0x80 | channel, note, 0])
    # a harmless controller at the end keeps the file (and the render) running through the release
    ev += vlq(int(length * 960) - hold_t) + bytes([0xB0 | channel, 0x50, 0])
    ev += vlq(0) + b'\xff\x2f\x00'
    track = b'MTrk' + struct.pack('>I', len(ev)) + ev
    with open(path, 'wb') as f:
        f.write(b'MThd' + struct.pack('>IHHH', 6, 0, 1, TPQ) + track)


def render(name, channel, program, note, vel, hold, length):
    mid = os.path.join(WORK, name + '.mid')
    wav = os.path.join(WORK, name + '.wav')
    midi_file(mid, channel, program, note, vel, hold, length)
    subprocess.run(['fluidsynth', '-ni', '-q', '-R', '0', '-C', '0', '-g', '0.5', '-r', str(RATE),
                    '-F', wav, SF2, mid], check=True, stdout=subprocess.DEVNULL)
    with wave.open(wav) as w:
        frames = array.array('h', w.readframes(w.getnframes()))
        ch = w.getnchannels()
    mono = [(frames[i] + frames[i + 1]) / 2 for i in range(0, len(frames), ch)] if ch == 2 else list(frames)
    return mono[:int(length * RATE)]


def write(name, samples, gain, fade):
    """Normalize by the instrument's shared gain, fade the tail, encode."""
    n = len(samples)
    # drop the dead tail
    last = n
    while last > 0 and abs(samples[last - 1]) * gain < 30:
        last -= 1
    samples = samples[:max(last, int(0.05 * RATE))]
    n = len(samples)
    f = min(int(fade * RATE), n)
    out = array.array('h', (int(max(-32767, min(32767, s * gain * (min(1, (n - i) / f) if f else 1))))
                            for i, s in enumerate(samples)))
    wav = os.path.join(WORK, name + '-out.wav')
    with wave.open(wav, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(out.tobytes())
    subprocess.run(['lame', '--quiet', '-m', 'm', '-b', '64', '--resample', '44.1', wav,
                    os.path.join(OUT, name + '.mp3')], check=True)


def instrument(renders, peak_db=-3, fade=0.25):
    """renders: [(name, samples)]; one gain for all of them."""
    peak = max(max(abs(s) for s in smp) for _, smp in renders) or 1
    gain = 32767 * 10 ** (peak_db / 20) / peak
    for name, smp in renders:
        write(name, smp, gain, fade)
        print(name)


EVERY_THIRD = lambda lo, hi: list(range(lo, hi + 1, 3))

# electric bass (finger), GM 34
instrument([(f'bass-{m}', render(f'bass-{m}', 0, 33, m, 100, 2.2, 2.5)) for m in EVERY_THIRD(25, 64)])
# electric piano 1 (Rhodes), GM 5
instrument([(f'epiano-{m}', render(f'epiano-{m}', 0, 4, m, 90, 3.2, 3.6)) for m in EVERY_THIRD(53, 83)], fade=0.4)
# drawbar organ, GM 17: long enough to hold a whole ballad bar at 40 bpm
instrument([(f'organ-{m}', render(f'organ-{m}', 0, 16, m, 100, 6.8, 7.0)) for m in EVERY_THIRD(53, 83)], fade=0.3)
# the standard kit, channel 10; two velocities where the kit has layers worth hearing
DRUMS = [
    ('kick', 36, 110, 0.6), ('kick-soft', 36, 60, 0.6),
    ('snare', 38, 110, 0.8), ('snare-soft', 38, 50, 0.6),
    ('hat', 42, 100, 0.35), ('hat-soft', 42, 55, 0.3),
    ('hat-open', 46, 90, 1.2),
    ('crash', 49, 100, 3.5),
    ('ride', 51, 90, 2.5), ('ride-bell', 53, 90, 2.5),
]
instrument([(f'drum-{n}', render(f'drum-{n}', 9, 0, note, vel, 0.1, length)) for n, note, vel, length in DRUMS],
           peak_db=-1, fade=0.05)
