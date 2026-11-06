// The Practice panel's band and ear: everything Elm cannot do. Practice.elm owns the chart, the
// controls and what every note means; this file only makes the sound and listens. It talks to
// Elm through two ports: `bandOut` (Elm -> here: state, play, stop, listen, unlisten) and
// `bandIn` (here -> Elm: playing, beat, heard, ear).
//
// The band: drums, bass, keys and guitar synthesized with Web Audio, the acoustic guitar and the
// ballad piano from recorded samples in sounds/ (FluidR3 General MIDI soundfont via
// gleitz/midi-js-soundfonts, both MIT licensed), fetched on the first Play.
// read while this file loads: by the time connectBand runs, currentScript is the page's own
const SOUNDS = new URL('sounds/', document.currentScript ? document.currentScript.src : location.href);

function connectBand(app) {
  'use strict';
  const send = msg => app.ports.bandIn.send(msg);

  const DOM_BASS = [[0, 4, 7, 9], [0, 4, 7, 10]];
  // How each chord type is played; what it is called is Practice.elm's business. keys: electric-piano
  // voicing, bass: shuffle boogie patterns (one note per beat), gtr: six-string rhythm-guitar shape
  // (intervals above the low root, low string first), fam: chord family.
  const QUALS = [
    { id: 'maj',  fam: 'maj', keys: [0, 4, 7],       bass: [[0, 4, 7, 9], [0, 4, 5, 7]],    gtr: [0, 7, 12, 16, 19, 24] },
    { id: 'm',    fam: 'min', keys: [0, 3, 7],       bass: [[0, 3, 7, 10], [0, 3, 5, 7]],   gtr: [0, 7, 12, 15, 19, 24] },
    { id: '7',    fam: 'dom', keys: [0, 4, 10],      bass: DOM_BASS,                        gtr: [0, 7, 10, 16, 19, 24] },
    { id: 'm7',   fam: 'min', keys: [3, 10, 14],     bass: [[0, 3, 7, 10], [0, 3, 5, 7]],   gtr: [0, 7, 10, 15, 19, 24] },
    { id: 'maj7', fam: 'maj', keys: [4, 7, 11],      bass: [[0, 4, 7, 9], [0, 4, 7, 11]],   gtr: [0, 7, 11, 16, 19, 24] },
    { id: '6',    fam: 'maj', keys: [4, 7, 9],       bass: [[0, 4, 7, 9]],                  gtr: [0, 7, 9, 16, 19, 24] },
    { id: 'm6',   fam: 'min', keys: [3, 7, 9],       bass: [[0, 3, 7, 9]],                  gtr: [0, 7, 9, 15, 19, 24] },
    { id: '9',    fam: 'dom', keys: [4, 10, 14],     bass: DOM_BASS,                        gtr: [0, 7, 10, 16, 26, 31] },
    { id: '13',   fam: 'dom', keys: [4, 9, 10, 14],  bass: DOM_BASS,                        gtr: [0, 7, 10, 16, 21, 26] },
    { id: '7#9',  fam: 'dom', keys: [4, 10, 15],     bass: DOM_BASS,                        gtr: [0, 7, 10, 16, 27] },
    { id: '7b9',  fam: 'dom', keys: [4, 10, 13],     bass: DOM_BASS,                        gtr: [0, 7, 10, 16, 25] },
    { id: 'dim7', fam: 'dim', keys: [0, 3, 6, 9],    bass: [[0, 3, 6, 9]],                  gtr: [0, 6, 9, 15, 18, 24] },
  ];
  const QUAL_BY_ID = Object.fromEntries(QUALS.map(q => [q.id, q]));

  // modern-style bass lines: eight eighth-note slots per bar, null = let the previous note ring
  const MODERN_BASS = {
    dom: [[0, null, 0, 0, 0, 7, 10, 0], [0, null, 0, 0, 12, null, 10, 7]],
    min: [[0, null, 0, 0, 0, 7, 10, 0], [0, null, 0, 0, 12, null, 10, 7]],
    maj: [[0, null, 0, 0, 0, 7, 9, 0],  [0, null, 0, 0, 12, null, 9, 7]],
    dim: [[0, null, 0, 0, 3, null, 6, 9]],
  };
  // modern-style guitar: eight eighth-note slots per bar. D = downstroke, U = upstroke, m = palm-muted chunk, - = rest
  const MODERN_GTR = ['D-DU -UD-'].map(s => s.replace(/ /g, '').split(''));

  // what the band plays, as Elm last sent it: { style, bpm, feel, bars: [{ root, q }], mix }
  const state = { style: 'modern', bpm: 100, feel: 8, bars: [{ root: 9, q: '7' }],
    mix: { drums: 0.8, bass: 0.9, keys: 0.55, guitar: 0.75, master: 0.9 }, playing: false };

  // one recorded note every three semitones; the pitches between shift the nearest one
  const GTR_SAMPLES = [40, 43, 46, 49, 52, 55, 58, 61, 64, 67, 70, 73, 76];
  const PIANO_SAMPLES = [53, 56, 59, 62, 65, 68, 71, 74, 77, 80, 83];
  async function loadSample(ctx, file) {
    const res = await fetch(new URL(file, SOUNDS));
    if (!res.ok) throw new Error(`${file}: ${res.status}`);
    return ctx.decodeAudioData(await res.arrayBuffer());
  }

  // ---------- audio engine ----------
  let audio = null;

  function createAudio() {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();

    const master = ctx.createGain();
    master.gain.value = state.mix.master;
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -14; comp.knee.value = 18; comp.ratio.value = 4;
    comp.attack.value = 0.004; comp.release.value = 0.18;
    master.connect(comp).connect(ctx.destination);

    const bus = {};
    ['drums', 'bass', 'keys', 'guitar'].forEach(n => {
      bus[n] = ctx.createGain(); bus[n].gain.value = state.mix[n]; bus[n].connect(master);
    });

    // a small room: generated impulse response
    const irLen = Math.floor(ctx.sampleRate * 1.3);
    const ir = ctx.createBuffer(2, irLen, ctx.sampleRate);
    for (let c = 0; c < 2; c++) {
      const d = ir.getChannelData(c);
      for (let i = 0; i < irLen; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / irLen, 3.2);
    }
    const room = ctx.createConvolver(); room.buffer = ir;
    const roomOut = ctx.createGain(); roomOut.gain.value = 0.22;
    room.connect(roomOut).connect(master);
    const roomSend = { drums: ctx.createGain(), keys: ctx.createGain(), guitar: ctx.createGain() };
    roomSend.drums.gain.value = 0.35; roomSend.keys.gain.value = 0.5; roomSend.guitar.gain.value = 0.3;
    bus.drums.connect(roomSend.drums).connect(room);
    bus.keys.connect(roomSend.keys).connect(room);
    bus.guitar.connect(roomSend.guitar).connect(room);

    // shared noise buffer
    const noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
    const nd = noiseBuf.getChannelData(0);
    for (let i = 0; i < nd.length; i++) nd[i] = Math.random() * 2 - 1;

    const noise = (t, dur) => {
      const s = ctx.createBufferSource(); s.buffer = noiseBuf; s.loop = true;
      s.start(t); s.stop(t + dur + 0.05); return s;
    };
    const midiHz = m => 440 * Math.pow(2, (m - 69) / 12);

    // --- drums ---
    function kick(t, vel) {
      const o = ctx.createOscillator(); o.type = 'sine';
      o.frequency.setValueAtTime(150, t);
      o.frequency.exponentialRampToValueAtTime(42, t + 0.11);
      const g = ctx.createGain();
      g.gain.setValueAtTime(vel, t);
      g.gain.exponentialRampToValueAtTime(0.001, t + 0.32);
      o.connect(g).connect(bus.drums);
      o.start(t); o.stop(t + 0.35);
      // click
      const c = noise(t, 0.02);
      const cf = ctx.createBiquadFilter(); cf.type = 'highpass'; cf.frequency.value = 2500;
      const cg = ctx.createGain(); cg.gain.setValueAtTime(vel * 0.25, t);
      cg.gain.exponentialRampToValueAtTime(0.001, t + 0.02);
      c.connect(cf).connect(cg).connect(bus.drums);
    }
    // The kit is kept warm on purpose: synthesized noise above ~9 kHz reads as harsh and artificial,
    // so every cymbal and the snare wires are filtered and eased in rather than clicked on.
    // closed hi-hat: a soft "tss" played with the tip of the stick. The fizz above 10 kHz is cut,
    // the attack is eased in over a couple of milliseconds rather than a click, and it's quiet.
    function softHat(t, vel) {
      const dur = 0.07;
      const n = noise(t, dur);
      const hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 5500; hp.Q.value = 0.5;
      const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 9000; lp.Q.value = 0.5;
      const g = ctx.createGain();
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(vel * 0.4, t + 0.002);
      g.gain.exponentialRampToValueAtTime(vel * 0.12, t + 0.025);
      g.gain.exponentialRampToValueAtTime(0.001, t + dur);
      n.connect(hp).connect(lp).connect(g).connect(bus.drums);
    }
    // snare: a warm, fat backbeat. The noise (the wires) is kept below ~4 kHz and eased in,
    // the drum's own tone carries the weight, and the tail is short and dark.
    function snare(t, vel) {
      const n = noise(t, 0.3);
      const bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 1400; bp.Q.value = 0.6;
      const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 3800; lp.Q.value = 0.5;
      const g = ctx.createGain();
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(vel * 0.7, t + 0.003);
      g.gain.exponentialRampToValueAtTime(vel * 0.2, t + 0.07);
      g.gain.exponentialRampToValueAtTime(0.001, t + 0.28);
      n.connect(bp).connect(lp).connect(g).connect(bus.drums);
      const o = ctx.createOscillator(); o.type = 'sine';
      o.frequency.setValueAtTime(210, t); o.frequency.exponentialRampToValueAtTime(175, t + 0.1);
      const og = ctx.createGain();
      og.gain.setValueAtTime(0.0001, t);
      og.gain.exponentialRampToValueAtTime(vel * 0.5, t + 0.002);
      og.gain.exponentialRampToValueAtTime(0.001, t + 0.16);
      o.connect(og).connect(bus.drums); o.start(t); o.stop(t + 0.18);
    }
    // crash: a soft, dark wash struck with a mallet-light touch rather than a bright splash
    function crash(t, vel) {
      const dur = 2.2;
      const n = noise(t, dur);
      const bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 4200; bp.Q.value = 0.5;
      const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.setValueAtTime(7000, t);
      lp.frequency.exponentialRampToValueAtTime(3500, t + 1.2);
      const g = ctx.createGain();
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(vel, t + 0.015);
      g.gain.exponentialRampToValueAtTime(vel * 0.35, t + 0.3);
      g.gain.exponentialRampToValueAtTime(0.001, t + dur);
      n.connect(bp).connect(lp).connect(g).connect(bus.drums);
    }
    function hat(t, vel, open) {
      if (!open) return softHat(t, vel);
      const dur = 0.3;
      const n = noise(t, dur);
      const hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 4500; hp.Q.value = 0.5;
      const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 8500; lp.Q.value = 0.5;
      const g = ctx.createGain();
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(vel * 0.4, t + 0.004);
      g.gain.exponentialRampToValueAtTime(0.001, t + dur);
      n.connect(hp).connect(lp).connect(g).connect(bus.drums);
    }
    function ride(t, vel, dur) {
      const n = noise(t, dur);
      const bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 6000; bp.Q.value = 0.6;
      const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 8500; lp.Q.value = 0.5;
      const g = ctx.createGain();
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(vel * 0.6, t + 0.003);
      g.gain.exponentialRampToValueAtTime(0.001, t + dur);
      n.connect(bp).connect(lp).connect(g).connect(bus.drums);
      // bell ping, softer and lower than a bright splash
      const o = ctx.createOscillator(); o.type = 'sine'; o.frequency.value = 3400;
      const og = ctx.createGain(); og.gain.setValueAtTime(0.0001, t);
      og.gain.exponentialRampToValueAtTime(vel * 0.18, t + 0.002);
      og.gain.exponentialRampToValueAtTime(0.001, t + Math.min(dur, 0.12));
      o.connect(og).connect(bus.drums); o.start(t); o.stop(t + 0.14);
    }

    // --- rhythm guitar: Karplus-Strong strings into a soft-clip drive ---
    const gtrDrive = ctx.createWaveShaper();
    {
      const N = 1024, k = 1.4, curve = new Float32Array(N), norm = Math.tanh(k);
      for (let i = 0; i < N; i++) { const x = (i / (N - 1)) * 2 - 1; curve[i] = Math.tanh(k * x) / norm; }
      gtrDrive.curve = curve; gtrDrive.oversample = '2x';
    }
    const gtrIn = ctx.createGain(); gtrIn.gain.value = 0.45;
    const gtrLowCut = ctx.createBiquadFilter(); gtrLowCut.type = 'highpass'; gtrLowCut.frequency.value = 90; gtrLowCut.Q.value = 0.7;
    // a magnetic pickup: resonant lowpass around 3 kHz, then everything above it falls away fast
    const gtrPickup = ctx.createBiquadFilter(); gtrPickup.type = 'lowpass'; gtrPickup.frequency.value = 3000; gtrPickup.Q.value = 1.3;
    // a guitar cabinet: steep roll-off above 4.5 kHz, a little presence, warm low mids
    const gtrCab1 = ctx.createBiquadFilter(); gtrCab1.type = 'lowpass'; gtrCab1.frequency.value = 3800; gtrCab1.Q.value = 0.8;
    const gtrCab2 = ctx.createBiquadFilter(); gtrCab2.type = 'lowpass'; gtrCab2.frequency.value = 4600; gtrCab2.Q.value = 0.6;
    const gtrPresence = ctx.createBiquadFilter(); gtrPresence.type = 'peaking'; gtrPresence.frequency.value = 2000; gtrPresence.gain.value = 1; gtrPresence.Q.value = 1;
    const gtrBody = ctx.createBiquadFilter(); gtrBody.type = 'peaking'; gtrBody.frequency.value = 450; gtrBody.gain.value = 3; gtrBody.Q.value = 0.9;
    const gtrOut = ctx.createGain(); gtrOut.gain.value = 0.5;
    gtrIn.connect(gtrLowCut).connect(gtrPickup).connect(gtrDrive).connect(gtrCab1).connect(gtrCab2).connect(gtrPresence).connect(gtrBody).connect(gtrOut).connect(bus.guitar);

    // The acoustic: recorded notes, so the chain only tidies. The samples peak around -18 dBFS,
    // hence the make-up gain. A little air on top, boom trimmed below the low E.
    const acIn = ctx.createGain(); acIn.gain.value = 2.4;
    const acLowCut = ctx.createBiquadFilter(); acLowCut.type = 'highpass'; acLowCut.frequency.value = 75; acLowCut.Q.value = 0.7;
    const acAir = ctx.createBiquadFilter(); acAir.type = 'highshelf'; acAir.frequency.value = 6000; acAir.gain.value = 2;
    acIn.connect(acLowCut).connect(acAir).connect(bus.guitar);

    const sampleMidis = GTR_SAMPLES;
    const gtrSamples = {};
    let gtrReady = false;
    const gtrLoad = Promise.all(sampleMidis.map(async m => {
      gtrSamples[m] = await loadSample(ctx, `guitar-${m}.mp3`);
    })).then(() => { gtrReady = true; console.info('guitar: samples ready'); })
      .catch(e => console.warn('guitar: samples failed to decode, using the synth', e));

    function pluckSample(t, midi, dur, vel, muted) {
      let best = sampleMidis[0];
      for (const m of sampleMidis) if (Math.abs(m - midi) < Math.abs(best - midi)) best = m;
      const src = ctx.createBufferSource();
      src.buffer = gtrSamples[best];
      src.playbackRate.value = Math.pow(2, (midi - best) / 12) * (1 + (Math.random() - 0.5) * 0.004);
      const g = ctx.createGain();
      const v = vel * (muted ? 0.7 : 1);
      g.gain.setValueAtTime(v, t);
      if (muted) {
        g.gain.setValueAtTime(v, t + 0.03);
        g.gain.exponentialRampToValueAtTime(0.001, t + Math.min(dur, 0.14));
      } else {
        // let it ring, then the hand damps it just before the next strum
        g.gain.setValueAtTime(v, t + Math.max(0.05, dur - 0.07));
        g.gain.exponentialRampToValueAtTime(0.001, t + dur);
      }
      let node = src;
      if (muted) { const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 700; src.connect(lp); node = lp; }
      node.connect(g).connect(acIn);
      src.start(t);
      src.stop(t + dur + 0.05);
    }

    // A plucked string's spectrum: harmonic n has amplitude sin(n*pi*pick)/n, so harmonics near
    // the pick position's node start weak (the comb you hear as "picked near the bridge").
    // Two waves for two pick positions, chosen per strum.
    const pickWaves = [0.13, 0.19].map(pos => {
      const H = 48, real = new Float32Array(H), imag = new Float32Array(H);
      for (let n = 1; n < H; n++) imag[n] = Math.sin(n * Math.PI * pos) / n / (1 + Math.pow(n / 16, 2));
      return ctx.createPeriodicWave(real, imag);
    });
    let pickVariant = 0;

    // One string. The cues that read as "picked" rather than "keyed": an instant attack with a
    // short pick-scrape burst, a pitch overshoot that settles in the first 90 ms, a fast initial
    // drop into a long ring, and overtones that fade faster than the fundamental.
    function pluck(t, midi, dur, vel, muted) {
      if (gtrReady) return pluckSample(t, midi, dur, vel, muted);
      const f = midiHz(midi);
      const det = (Math.random() - 0.5) * 8;
      const o1 = ctx.createOscillator(); o1.setPeriodicWave(pickWaves[pickVariant]); o1.frequency.value = f;
      const o2 = ctx.createOscillator(); o2.setPeriodicWave(pickWaves[pickVariant]); o2.frequency.value = f;
      const o2g = ctx.createGain(); o2g.gain.value = 0.4;
      const bend = muted ? 25 : 14 * vel;                  // strings go sharp when hit, then settle
      [o1, o2].forEach((o, i) => {
        const base = det + i * 6;
        o.detune.setValueAtTime(base + bend, t);
        o.detune.linearRampToValueAtTime(base, t + 0.09);
      });
      const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.Q.value = 0.8;
      const fOpen = muted ? 900 + f : Math.min(7000, 2200 + f * 5);
      const fClose = muted ? 220 + f : 380 + f * 1.4;
      lp.frequency.setValueAtTime(fOpen, t);
      lp.frequency.exponentialRampToValueAtTime(fClose, t + (muted ? 0.06 : 0.4));
      const g = ctx.createGain();
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(vel, t + 0.0015);
      if (muted) {
        g.gain.exponentialRampToValueAtTime(0.001, t + dur);
      } else {
        const hold = Math.max(0.36, dur - 0.04);
        g.gain.exponentialRampToValueAtTime(vel * 0.6, t + 0.07);
        g.gain.exponentialRampToValueAtTime(vel * 0.42, t + 0.35);
        g.gain.exponentialRampToValueAtTime(Math.max(0.002, vel * 0.42 * Math.exp(-(hold - 0.35) / 1.5)), t + hold);
        g.gain.exponentialRampToValueAtTime(0.001, t + dur);
      }
      o1.connect(lp); o2.connect(o2g).connect(lp);
      lp.connect(g).connect(gtrIn);
      o1.start(t); o2.start(t);
      o1.stop(t + dur + 0.02); o2.stop(t + dur + 0.02);
      // pick scrape: a few milliseconds of band-limited noise riding the attack
      const scrapeDur = muted ? 0.03 : 0.009;
      const n = noise(t, scrapeDur);
      const nf = ctx.createBiquadFilter(); nf.type = 'bandpass'; nf.frequency.value = muted ? 1800 : 3200; nf.Q.value = 0.9;
      const ng = ctx.createGain();
      ng.gain.setValueAtTime(vel * (muted ? 0.9 : 0.65), t);
      ng.gain.exponentialRampToValueAtTime(0.001, t + scrapeDur);
      n.connect(nf).connect(ng).connect(gtrIn);
    }
    // strum low-to-high on a downstroke, high-to-low on an upstroke, with a human's unevenness
    function strum(t, midis, dur, vel, muted, upstroke, beatDur) {
      pickVariant = Math.random() < 0.5 ? 0 : 1;
      let order;
      if (upstroke) {
        const top = Math.min(midis.length, 3 + Math.floor(Math.random() * 2));
        order = midis.slice(-top).reverse();
      } else order = midis;
      // the hand moves with the tempo: a relaxed strum at 60 bpm spreads over ~120 ms, a fast one
      // at 200 bpm over ~40 ms; harder strums are quicker, mutes are a flick
      const perString = Math.min(0.034, Math.max(0.008, beatDur * (upstroke ? 0.017 : 0.028)));
      const gap = perString * (muted ? 0.55 : 1) * (1.25 - 0.5 * vel);
      let time = t;
      order.forEach((m, i) => {
        // downstrokes lean on the bass strings, upstrokes are lighter throughout
        const shape = upstroke ? 0.8 - i * 0.03 : 1 - i * 0.05;
        const v = vel * shape * (0.9 + Math.random() * 0.2);
        pluck(time, m, dur, Math.min(1, v), muted);
        time += gap * (0.7 + Math.random() * 0.6);
      });
    }

    // --- bass ---
    // dark: a round, deep ballad bass (less saw, filter mostly closed)
    function bassNote(t, midi, dur, vel, dark) {
      const f = midiHz(midi);
      const o1 = ctx.createOscillator(); o1.type = 'sawtooth'; o1.frequency.value = f;
      const o2 = ctx.createOscillator(); o2.type = 'triangle'; o2.frequency.value = f;
      const mix1 = ctx.createGain(); mix1.gain.value = dark ? 0.12 : 0.35;
      const mix2 = ctx.createGain(); mix2.gain.value = dark ? 0.85 : 0.7;
      const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.Q.value = dark ? 0.8 : 1.5;
      lp.frequency.setValueAtTime(dark ? 520 : 1100, t);
      lp.frequency.exponentialRampToValueAtTime(dark ? 150 : 320, t + 0.16);
      const g = ctx.createGain();
      g.gain.setValueAtTime(0, t);
      g.gain.linearRampToValueAtTime(vel, t + 0.008);
      g.gain.exponentialRampToValueAtTime(vel * 0.55, t + 0.14);
      g.gain.setValueAtTime(vel * 0.55, t + dur - 0.04);
      g.gain.exponentialRampToValueAtTime(0.001, t + dur + 0.03);
      o1.connect(mix1).connect(lp); o2.connect(mix2).connect(lp);
      lp.connect(g).connect(bus.bass);
      o1.start(t); o2.start(t); o1.stop(t + dur + 0.05); o2.stop(t + dur + 0.05);
    }

    // --- keys (electric piano) ---
    const keysLP = ctx.createBiquadFilter(); keysLP.type = 'lowpass'; keysLP.frequency.value = 3800;
    keysLP.connect(bus.keys);
    function keysChord(t, midis, dur, vel) {
      const per = vel * 1.5 / midis.length;
      midis.forEach((m, idx) => {
        const f = midiHz(m) * (1 + (Math.random() - 0.5) * 0.0015);
        const tt = t + idx * 0.006; // a slight roll
        const g = ctx.createGain();
        g.gain.setValueAtTime(0, tt);
        g.gain.linearRampToValueAtTime(per, tt + 0.005);
        g.gain.exponentialRampToValueAtTime(0.001, tt + dur);
        const o1 = ctx.createOscillator(); o1.type = 'sine'; o1.frequency.value = f;
        const o2 = ctx.createOscillator(); o2.type = 'triangle'; o2.frequency.value = f;
        const o2g = ctx.createGain(); o2g.gain.value = 0.22;
        const o3 = ctx.createOscillator(); o3.type = 'sine'; o3.frequency.value = f * 2;
        const o3g = ctx.createGain(); o3g.gain.setValueAtTime(0.28, tt);
        o3g.gain.exponentialRampToValueAtTime(0.01, tt + 0.25);
        o1.connect(g); o2.connect(o2g).connect(g); o3.connect(o3g).connect(g);
        g.connect(keysLP);
        [o1, o2, o3].forEach(o => { o.start(tt); o.stop(tt + dur + 0.05); });
      });
    }

    // --- organ pad (ballad): drawbar-style additive tone, a slow swell, a gentle shared vibrato ---
    const organWave = (() => {
      const amps = { 1: 1, 2: 0.7, 3: 0.3, 4: 0.22, 6: 0.08, 8: 0.05 };
      const real = new Float32Array(13), imag = new Float32Array(13);
      Object.entries(amps).forEach(([n, a]) => { imag[n] = a; });
      return ctx.createPeriodicWave(real, imag);
    })();
    const organLP = ctx.createBiquadFilter(); organLP.type = 'lowpass'; organLP.frequency.value = 2800; organLP.Q.value = 0.5;
    const organOut = ctx.createGain(); organOut.gain.value = 0.5;
    organLP.connect(organOut).connect(bus.keys);
    const organLfo = ctx.createOscillator(); organLfo.frequency.value = 5.6;
    const organLfoDepth = ctx.createGain(); organLfoDepth.gain.value = 5; // cents
    organLfo.connect(organLfoDepth); organLfo.start();
    function organChord(t, midis, dur, vel) {
      const per = vel / midis.length;
      midis.forEach(m => {
        const o = ctx.createOscillator(); o.setPeriodicWave(organWave); o.frequency.value = midiHz(m);
        o.detune.value = (Math.random() - 0.5) * 6;
        organLfoDepth.connect(o.detune);
        const g = ctx.createGain();
        g.gain.setValueAtTime(0, t);
        g.gain.linearRampToValueAtTime(per, t + 0.12);
        g.gain.setValueAtTime(per, t + dur - 0.1);
        g.gain.linearRampToValueAtTime(0, t + dur + 0.05);
        o.connect(g).connect(organLP);
        o.start(t); o.stop(t + dur + 0.1);
        o.onended = () => organLfoDepth.disconnect(o.detune);
      });
    }

    // --- ballad piano: a hammered string, bright on the strike and mellowing as it rings ---
    const pianoWave = (() => {
      const H = 28, real = new Float32Array(H), imag = new Float32Array(H);
      for (let n = 1; n < H; n++) imag[n] = Math.sin(n * Math.PI * 0.12) / Math.pow(n, 0.85);
      return ctx.createPeriodicWave(real, imag);
    })();
    // Recorded grand piano notes; the synth below is only a fallback if they fail to decode.
    // The samples peak around -21 dBFS, hence the make-up gain. A gentle top cut keeps the
    // repeated triplets from getting glassy.
    const pnIn = ctx.createGain(); pnIn.gain.value = 3;
    const pnTop = ctx.createBiquadFilter(); pnTop.type = 'highshelf'; pnTop.frequency.value = 5000; pnTop.gain.value = -2;
    pnIn.connect(pnTop).connect(bus.keys);
    const pianoMidis = PIANO_SAMPLES;
    const pianoSamples = {};
    let pianoReady = false;
    const pianoLoad = Promise.all(pianoMidis.map(async m => {
      pianoSamples[m] = await loadSample(ctx, `piano-${m}.mp3`);
    })).then(() => { pianoReady = true; console.info('piano: samples ready'); })
      .catch(e => console.warn('piano: samples failed to decode, using the synth', e));
    function pianoSample(t, m, dur, vel) {
      let best = pianoMidis[0];
      for (const x of pianoMidis) if (Math.abs(x - m) < Math.abs(best - m)) best = x;
      const src = ctx.createBufferSource();
      src.buffer = pianoSamples[best];
      src.playbackRate.value = Math.pow(2, (m - best) / 12);
      // softer strikes are darker on a real piano
      const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 3000 + 6000 * vel; lp.Q.value = 0.5;
      const g = ctx.createGain();
      g.gain.setValueAtTime(vel, t);
      g.gain.setValueAtTime(vel, t + Math.max(0.05, dur - 0.12));
      g.gain.exponentialRampToValueAtTime(0.001, t + dur);   // the damper comes down
      src.connect(lp).connect(g).connect(pnIn);
      src.start(t); src.stop(t + dur + 0.05);
    }
    function pianoChord(t, midis, dur, vel) {
      if (pianoReady) {
        midis.forEach((m, idx) => pianoSample(t + idx * 0.004 + Math.random() * 0.006, m, dur, vel * (0.9 + Math.random() * 0.15)));
        return;
      }
      const per = vel * 2 / midis.length;
      midis.forEach((m, idx) => {
        const f = midiHz(m);
        const tt = t + idx * 0.003 + Math.random() * 0.004;
        const o1 = ctx.createOscillator(); o1.setPeriodicWave(pianoWave); o1.frequency.value = f;
        const o2 = ctx.createOscillator(); o2.setPeriodicWave(pianoWave); o2.frequency.value = f;
        o2.detune.value = 3 + Math.random() * 2;            // the unison strings, slightly apart
        const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.Q.value = 0.6;
        lp.frequency.setValueAtTime(Math.min(5000, 2000 + f * 5), tt);
        lp.frequency.exponentialRampToValueAtTime(Math.min(2500, 900 + f * 2.5), tt + 0.35);
        const g = ctx.createGain();
        g.gain.setValueAtTime(0, tt);
        g.gain.linearRampToValueAtTime(per, tt + 0.003);
        g.gain.exponentialRampToValueAtTime(per * 0.45, tt + 0.12);
        g.gain.setValueAtTime(per * 0.45, tt + dur - 0.08);
        g.gain.exponentialRampToValueAtTime(0.001, tt + dur);
        o1.connect(lp); o2.connect(lp); lp.connect(g).connect(bus.keys);
        [o1, o2].forEach(o => { o.start(tt); o.stop(tt + dur + 0.02); });
      });
    }
    // --- voicings ---
    const bassRoot = pc => 28 + ((pc - 4 + 12) % 12);   // E1 .. E♭2
    const keysRoot = pc => 53 + ((pc - 5 + 12) % 12);   // F3 .. E4
    const chordTones = bar => {
      const q = QUAL_BY_ID[bar.q]; const r = keysRoot(bar.root);
      return q.keys.map(i => r + i);
    };
    // guitar voicing: root between E2 and E♭3, top string kept at or below E5
    const GTR_TOP = 76;
    const guitarRoot = pc => 40 + ((pc - 4 + 12) % 12);
    const guitarVoicing = bar => {
      const r = guitarRoot(bar.root);
      const notes = QUAL_BY_ID[bar.q].gtr.map(i => { let n = r + i; while (n > GTR_TOP && n - 12 > r) n -= 12; return n; });
      return [...new Set(notes)].sort((a, b) => a - b);
    };

    // --- one beat of the band ---
    function scheduleBeat(t, beatDur, barIdx, beat) {
      const bars = state.bars;
      const bar = bars[barIdx % bars.length];
      const next = bars[(barIdx + 1) % bars.length];
      const sw = 0.5 + (state.feel / 100) * (2 / 3 - 0.5);
      const up = t + beatDur * sw;
      const upDur = beatDur * (1 - sw);
      if (state.style === 'ballad') return balladBeat(t, beatDur, barIdx, beat, bar, next);
      if (state.style === 'modern') return modernBeat(t, beatDur, barIdx, beat, bar, next, sw, up, upDur);
      shuffleBeat(t, beatDur, barIdx, beat, bar, next, sw, up, upDur);
    }

    function modernBeat(t, beatDur, barIdx, beat, bar, next, sw, up, upDur) {
      const n = state.bars.length;
      const pos = barIdx % n;
      const top = pos === 0, last = pos === n - 1;
      const r = Math.random;
      const q = QUAL_BY_ID[bar.q];
      const slot = beat * 2;                 // eighth-note slot of the downbeat; slot + 1 is the "and"
      const onDur = beatDur * sw, offDur = upDur;

      // drums: closed hat eighths, kick 1 / and-of-2 / 3, snare 2 & 4, crash at the top, fill into the top
      if (top && beat === 0) crash(t, 0.22);
      hat(t, beat === 0 || beat === 2 ? 0.8 : 0.6, false);
      const fill = last && beat === 3;
      if (!fill) hat(up, beat === 3 && barIdx % 2 === 1 ? 0.5 : 0.4, beat === 3 && barIdx % 2 === 1);
      if (beat === 0 || beat === 2) kick(t, 1.0);
      if (beat === 1) kick(up, 0.85);
      if (beat === 3 && !fill && r() < 0.3) kick(up, 0.6);
      if (beat === 1 || beat === 3) snare(t, 0.85);
      if (beat === 2 && r() < 0.4) snare(up, 0.16);
      if (fill) [0.35, 0.5, 0.7].forEach((v, k) => snare(t + beatDur * (k + 1) / 4, v));

      // bass: eighth-note line with octave jumps, from the chord family
      const patterns = MODERN_BASS[q.fam];
      const line = patterns[barIdx % patterns.length];
      const root = bassRoot(bar.root);
      const play = (slotIdx, time, dur) => {
        const iv = line[slotIdx];
        if (iv === null) return;
        const ringsOn = slotIdx < 7 && line[slotIdx + 1] === null;
        bassNote(time, root + iv, (ringsOn ? dur + (slotIdx % 2 ? onDur : offDur) : dur) * 0.95, 0.95);
      };
      play(slot, t, onDur);
      play(slot + 1, up, offDur);

      // rhythm guitar: open strums and palm-muted chunks from a per-bar pattern
      const pattern = MODERN_GTR[barIdx % MODERN_GTR.length];
      const voicing = guitarVoicing(bar);
      const power = [voicing[0], voicing[0] + 7, voicing[0] + 12];
      const hit = (slotIdx, time, dur, offbeat) => {
        const k = pattern[slotIdx];
        if (k === '-') return;
        if (k === 'D' || k === 'U') {
          const upstroke = k === 'U';
          let ring = 1; while (slotIdx + ring < 8 && pattern[slotIdx + ring] === '-') ring++;
          const accent = slotIdx === 0 ? 0.8 : (upstroke ? 0.58 : 0.68);
          strum(time, voicing, Math.max(0.4, beatDur * 0.5 * ring * 1.4), accent + (r() - 0.5) * 0.1, false, upstroke, beatDur);
        } else strum(time, power, 0.15, 0.3, true, offbeat, beatDur);
      };
      hit(slot, t, onDur, false);
      hit(slot + 1, up, offDur, true);

      // keys: a pad under the top of the bar, an occasional answer on the and-of-3
      const tones = chordTones(bar);
      if (beat === 0) keysChord(t, tones, beatDur * 3.6, 0.55);
      if (beat === 2 && r() < 0.5) keysChord(up, tones, beatDur * 0.7, 0.4);
    }

    // 12/8 ballad: each beat is a dotted quarter split into three eighth-note triplets
    function balladBeat(t, beatDur, barIdx, beat, bar, next) {
      const n = state.bars.length;
      const pos = barIdx % n;
      const top = pos === 0, last = pos === n - 1;
      const r = Math.random;
      const tr = beatDur / 3;
      const trip = k => t + k * tr;

      // drums: hat on every triplet, a light kick on 1 & 3, a warm snare on 2 & 4, crash at the top, triplet fill into the top
      const fill = last && beat === 3;
      if (top && beat === 0) crash(t, 0.18);
      if (!fill) [0.42, 0.2, 0.26].forEach((v, k) => hat(trip(k), v * (0.9 + r() * 0.2), false));
      if (beat === 0 || beat === 2) kick(t, 0.4);
      if (beat === 3 && !fill && r() < 0.45) kick(trip(2), 0.25);
      if (beat === 1 && r() < 0.2) kick(trip(2), 0.22);
      if (beat === 1 || beat === 3) snare(t, 0.85);
      if (fill) { snare(t, 0.85); [0.45, 0.6].forEach((v, k) => snare(trip(k + 1), v)); }

      // bass: low and round: root, fifth, root, then the fifth and a step into the next chord on the last triplet
      const BALLAD_BASS = 0.22; // the deep, round bass carries far more energy than the triplet piano
      const root = bassRoot(bar.root);
      const q = QUAL_BY_ID[bar.q];
      const fifth = q.fam === 'dim' ? 6 : 7;
      if (beat === 0) bassNote(t, root, beatDur * 1.02, 0.95 * BALLAD_BASS, true);
      if (beat === 1) bassNote(t, root + fifth, beatDur * 1.02, 0.8 * BALLAD_BASS, true);
      if (beat === 2) bassNote(t, root, beatDur * 1.02, 0.8 * BALLAD_BASS, true);
      if (beat === 3) {
        const target = bassRoot(next.root);
        if (target === root) bassNote(t, root + fifth, beatDur * 1.02, 0.8 * BALLAD_BASS, true);
        else {
          bassNote(t, root + fifth, tr * 2.02, 0.8 * BALLAD_BASS, true);
          const below = target - 1, above = target + 2;
          bassNote(trip(2), Math.abs(below - (root + fifth)) <= Math.abs(above - (root + fifth)) ? below : above, tr * 1.02, 0.7 * BALLAD_BASS, true);
        }
      }

      // keys: piano-style triplet chords on every eighth over a held organ chord
      const tones = chordTones(bar);
      const piano = tones.concat(tones.map(m => m + 12));
      [0.5, 0.3, 0.36].forEach((v, k) => pianoChord(trip(k), piano, tr * 1.6, v * (beat === 0 && k === 0 ? 1.15 : 1)));
      if (beat === 0) organChord(t, tones, beatDur * 4, 0.35);
    }

    function shuffleBeat(t, beatDur, barIdx, beat, bar, next, sw, up, upDur) {
      const r = Math.random;

      // drums: shuffle ride, kick on 1 & 3, snare on 2 & 4
      ride(t, beat === 0 ? 0.55 : 0.4, 0.28);
      ride(up, 0.24, 0.16);
      if (beat === 0 || beat === 2) kick(t, 0.95);
      if (beat === 2 && r() < 0.35) kick(up, 0.5);
      if (beat === 1 || beat === 3) snare(t, 0.6);
      if (beat === 3 && r() < 0.3) snare(up, 0.18);

      // bass: boogie pattern from the chord tones, chromatic pickup into the next bar
      const q = QUAL_BY_ID[bar.q];
      const pattern = q.bass[barIdx % q.bass.length];
      const root = bassRoot(bar.root);
      bassNote(t, root + pattern[beat], beatDur * 0.92, 0.9);
      if (beat === 3 && r() < 0.55) {
        const target = bassRoot(next.root);
        const pickup = r() < 0.6 ? target - 1 : target + 1;
        bassNote(up, pickup, upDur * 0.9, 0.7);
      }

      // keys: comp
      const tones = chordTones(bar);
      if (beat === 0) keysChord(t, tones, beatDur * 1.6, 0.6);
      if (beat === 1) keysChord(up, tones, beatDur * 0.4, 0.42);
      if (beat === 2 && r() < 0.45) keysChord(up, tones, beatDur * 0.4, 0.35);
      if (beat === 3) {
        keysChord(t, tones, beatDur * 0.5, 0.4);
        if (r() < 0.6) keysChord(up, tones, beatDur * 0.35, 0.34);
      }
    }

    // --- scheduler (lookahead) ---
    // Background tabs get their timers throttled to once a second, so schedule much further
    // ahead while hidden; when visible stay tight so tempo and chord changes land quickly.
    const LOOKAHEAD_MS = 25;
    const ahead = () => (document.hidden ? 1.5 : 0.16);
    let timer = null, nextTime = 0, beatCount = 0;
    const queue = [];

    function loop() {
      while (nextTime < ctx.currentTime + ahead()) {
        const beatDur = 60 / state.bpm;
        const barIdx = Math.floor(beatCount / 4);
        const beat = beatCount % 4;
        scheduleBeat(nextTime, beatDur, barIdx, beat);
        queue.push({ time: nextTime, bar: barIdx, beat });
        nextTime += beatDur;
        beatCount++;
      }
      timer = setTimeout(loop, LOOKAHEAD_MS);
    }
    document.addEventListener('visibilitychange', () => {
      if (timer !== null && document.hidden) { clearTimeout(timer); loop(); }
    });

    return {
      ctx, queue, ready: Promise.all([gtrLoad, pianoLoad]),
      start() {
        master.gain.cancelScheduledValues(ctx.currentTime);
        master.gain.setValueAtTime(state.mix.master, ctx.currentTime);
        queue.length = 0;
        beatCount = 0;
        nextTime = ctx.currentTime + 0.08;
        loop();
      },
      stop() {
        clearTimeout(timer); timer = null;
        master.gain.setTargetAtTime(0, ctx.currentTime, 0.03);
        queue.length = 0;
      },
      setLevel(name, v) {
        const node = name === 'master' ? master : bus[name];
        node.gain.setTargetAtTime(v, ctx.currentTime, 0.02);
      },
    };
  }

  // ---------- transport ----------
  // The playhead runs off the audio clock: each scheduled beat goes in a queue, and every
  // animation frame reports the latest one that has sounded.
  let lastBeat = '';
  function frame() {
    if (!state.playing) return;
    const now = audio.ctx.currentTime;
    let ev = null;
    while (audio.queue.length && audio.queue[0].time <= now) ev = audio.queue.shift();
    if (ev) {
      const id = ev.bar + ':' + ev.beat;
      if (id !== lastBeat) { lastBeat = id; send({ type: 'beat', bar: ev.bar, beat: ev.beat }); }
    }
    requestAnimationFrame(frame);
  }

  let starting = false;
  async function play() {
    if (state.playing || starting) return;
    starting = true;
    if (!audio) audio = createAudio();
    if (audio.ctx.state === 'suspended') await audio.ctx.resume();
    await Promise.race([audio.ready, new Promise(r => setTimeout(r, 2500))]); // don't let a slow load block play
    starting = false;
    state.playing = true;
    lastBeat = '';
    audio.start();
    send({ type: 'playing', on: true });
    requestAnimationFrame(frame);
  }
  function stop() {
    if (!state.playing) return;
    state.playing = false;
    audio.stop();
    send({ type: 'playing', on: false });
  }

  function setBand(band) {
    Object.assign(state, { style: band.style, bpm: band.bpm, feel: band.feel, bars: band.bars });
    Object.keys(band.mix).forEach(name => {
      state.mix[name] = band.mix[name];
      if (audio) audio.setLevel(name, band.mix[name]);
    });
  }

  // ---------- listening ----------
  // The mic is pitch-tracked with a McLeod-style normalized autocorrelation, and every note that
  // holds for three frames (about 50 ms, so pick attacks don't count) goes to Elm, which decides
  // whether it is in. The band leaking into the mic is all chord tones, so it never reads as out.
  const ear = { on: false, ctx: null, stream: null, an: null, buf: null, last: -1, run: 0, shown: -1 };


  // returns a frequency in Hz, or 0 when there's no clear pitch
  function detectPitch(x, sr) {
    const n = x.length;
    let rms = 0;
    for (let i = 0; i < n; i++) rms += x[i] * x[i];
    if (Math.sqrt(rms / n) < 0.008) return 0;
    const minTau = Math.floor(sr / 1400), maxTau = Math.min(Math.floor(sr / 65), n >> 1);
    const w = n - maxTau;
    const nsdf = new Float32Array(maxTau + 1);
    for (let tau = minTau; tau <= maxTau; tau++) {
      let acf = 0, m = 0;
      for (let i = 0; i < w; i++) { const a = x[i], b = x[i + tau]; acf += a * b; m += a * a + b * b; }
      nsdf[tau] = m > 0 ? 2 * acf / m : 0;
    }
    // peaks between positive-going and negative-going zero crossings; take the first one near the top
    const peaks = [];
    let tau = minTau;
    while (tau < maxTau && nsdf[tau] > 0) tau++;
    while (tau < maxTau) {
      while (tau < maxTau && nsdf[tau] <= 0) tau++;
      let best = tau;
      while (tau < maxTau && nsdf[tau] > 0) { if (nsdf[tau] > nsdf[best]) best = tau; tau++; }
      if (tau < maxTau) peaks.push(best);
    }
    if (!peaks.length) return 0;
    const top = Math.max(...peaks.map(p => nsdf[p]));
    if (top < 0.82) return 0; // noise, chords, drums
    const p = peaks.find(q => nsdf[q] >= 0.9 * top);
    const a = nsdf[p - 1], b = nsdf[p], c = nsdf[p + 1];
    const shift = (a - c) / (2 * (a - 2 * b + c)) || 0;
    return sr / (p + Math.max(-1, Math.min(1, shift)));
  }


  function listenFrame() {
    if (!ear.on) return;
    ear.an.getFloatTimeDomainData(ear.buf);
    const f = detectPitch(ear.buf, ear.ctx.sampleRate);
    const midi = f ? Math.round(69 + 12 * Math.log2(f / 440)) : -1;
    ear.run = midi === ear.last ? ear.run + 1 : 1;
    ear.last = midi;
    if (ear.run >= 3 && midi !== ear.shown) {
      ear.shown = midi;
      send({ type: 'heard', pc: midi < 0 ? -1 : midi % 12 });
    }
    requestAnimationFrame(listenFrame);
  }
  async function listen() {
    if (ear.on) return;
    try {
      ear.stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
      });
    } catch (e) {
      send({ type: 'ear', on: false, message: e && e.name === 'NotAllowedError' ? 'Microphone access was blocked.' : 'No microphone available here.' });
      return;
    }
    ear.ctx = new (window.AudioContext || window.webkitAudioContext)();
    const src = ear.ctx.createMediaStreamSource(ear.stream);
    ear.an = ear.ctx.createAnalyser();
    ear.an.fftSize = 2048;
    ear.buf = new Float32Array(ear.an.fftSize);
    src.connect(ear.an);
    const mute = ear.ctx.createGain(); mute.gain.value = 0; // keeps the graph pulling without sending the mic to the speakers
    ear.an.connect(mute).connect(ear.ctx.destination);
    ear.on = true; ear.last = -1; ear.run = 0; ear.shown = -1;
    send({ type: 'ear', on: true, message: '' });
    requestAnimationFrame(listenFrame);
  }
  function unlisten() {
    if (!ear.on) return;
    ear.on = false;
    ear.stream.getTracks().forEach(t => t.stop());
    ear.ctx.close();
    ear.ctx = null;
    send({ type: 'heard', pc: -1 });
    send({ type: 'ear', on: false, message: '' });
  }

  // ---------- from Elm ----------
  const STORE = 'caged-practice';
  app.ports.bandOut.subscribe(msg => {
    if (msg.type === 'state') {
      setBand(msg.band);
      try { localStorage.setItem(STORE, JSON.stringify(msg.save)); } catch (e) { /* storage blocked */ }
    }
    else if (msg.type === 'play') { setBand(msg.band); play(); }
    else if (msg.type === 'stop') stop();
    else if (msg.type === 'listen') listen();
    else if (msg.type === 'unlisten') unlisten();
  });

  // Elm cannot cancel a key's default action from a document subscription, so the keys the
  // Practice panel uses are stopped here while it is open: Space would click the focused button
  // and the arrows would scroll the page.
  document.addEventListener('keydown', e => {
    if (!document.querySelector('.practice-panel') || e.metaKey || e.ctrlKey || e.altKey) return;
    const t = e.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'SELECT' || t.tagName === 'TEXTAREA')) return;
    if (e.code === 'Space' || e.key.startsWith('Arrow')) e.preventDefault();
  });
}

// what the panel was left showing last time, read before Elm starts so it opens on it
function savedPractice() {
  try { return JSON.parse(localStorage.getItem('caged-practice')); } catch (e) { return null; }
}

// A link can set up the panel: ?root=A&scale=aeolian&practice=Am-F-C-G opens it on that chart (chords as the saved
// chart writes them, dash-separated) in the neck's key, keeping the saved style and tempo. The parameter is used once:
// it goes into the saved chart and out of the address, so a reload keeps any edits made since.
function linkedPractice() {
  const params = new URLSearchParams(location.search);
  const chart = params.get('practice');
  if (chart === null) return null;
  params.delete('practice');
  const query = params.toString();
  history.replaceState(null, '', location.pathname + (query ? '?' + query : '') + location.hash);
  const keys = { C: 'C', Cs: 'Db', D: 'D', Ds: 'Eb', E: 'E', F: 'F', Fs: 'Gb', G: 'G', Gs: 'Ab', A: 'A', As: 'Bb', B: 'B' };
  const save = Object.assign({}, savedPractice(), { chords: chart.split('-').filter(Boolean) });
  delete save.prog;
  if (keys[params.get('root')]) save.key = keys[params.get('root')];
  try { localStorage.setItem('caged-practice', JSON.stringify(save)); } catch (e) { /* storage blocked */ }
  return save;
}
