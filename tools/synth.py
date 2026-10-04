"""Renders the web game's WebAudio sound effects to WAV files for the Godot port.
Mirrors burst() (filtered noise with attack/exp-decay) and tone() (oscillator with an
exponential pitch glide) from johns-beer-run.html, using the same RBJ biquads WebAudio uses."""
import numpy as np, wave, os, sys
from scipy.signal import lfilter

SR = 44100
MASTER = 0.55 * 2.9   # louder files; relative mix unchanged
rng = np.random.default_rng(7)
NOISE = rng.uniform(-1, 1, SR * 2)

def biquad(kind, f, q=1.0):
    w = 2 * np.pi * min(f, SR * 0.49) / SR
    a = np.sin(w) / (2 * q); c = np.cos(w)
    if kind == 'lowpass':  b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
    elif kind == 'highpass': b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
    else: b = [a, 0, -a]   # bandpass (constant 0 dB peak)
    A = [1 + a, -2 * c, 1 - a]
    return np.array(b) / A[0], np.array(A) / A[0]

def filt(x, kind, f, q=None):
    # WebAudio lowpass/highpass Q is in dB-ish resonance; default 1 -> treat ~0.707
    if q is None: q = 0.707 if kind != 'bandpass' else 1.0
    b, a = biquad(kind, f, q)
    return lfilter(b, a, x)

def env(n, att, dur, gain):
    t = np.arange(n) / SR
    e = np.where(t < att, gain * t / max(att, 1e-4),
                 gain * np.power(0.0005 / gain, np.clip((t - att) / max(dur - att, 1e-4), 0, 1)))
    return np.where(t > dur, 0, e)

def buf(seconds): return np.zeros(int(SR * seconds))

def mix(out, x, when):
    i = int(when * SR); j = min(len(out), i + len(x)); out[i:j] += x[:j - i]

def burst(out, type='bandpass', freq=1000, q=1, gain=.3, dur=.1, att=.005, when=0):
    n = int((dur + .05) * SR); off = rng.integers(0, len(NOISE) - n - 1)
    x = filt(NOISE[off:off + n], type, freq, q if type == 'bandpass' else None)
    mix(out, x * env(n, att, dur, gain), when)

def tone(out, f1, f2, dur, gain, when=0, type='sine'):
    n = int((dur + .05) * SR); t = np.arange(n) / SR
    f = f1 * np.power(f2 / f1, np.clip(t / dur, 0, 1))
    ph = 2 * np.pi * np.cumsum(f) / SR
    if type == 'sine': w = np.sin(ph)
    elif type == 'square': w = np.sign(np.sin(ph))
    elif type == 'triangle': w = 2 / np.pi * np.arcsin(np.sin(ph))
    else: w = 2 * ((ph / (2 * np.pi)) % 1) - 1   # sawtooth
    e = np.where(t < .02, gain * t / .02, gain * np.power(0.0005 / gain, np.clip((t - .02) / (dur - .02), 0, 1)))
    mix(out, w * np.where(t > dur, 0, e), when)

def sweep_noise(seconds, kind, q, f_pts, g_pts, loop=False):
    """noise through a filter whose cutoff and gain follow piecewise curves [(t,v),...]"""
    n = int(seconds * SR); t = np.arange(n) / SR
    x = np.resize(NOISE, n)
    fc = np.interp(t, *zip(*f_pts)); g = np.interp(t, *zip(*g_pts))
    y = np.zeros(n); blk = 256
    zi = None
    from scipy.signal import lfilter_zi
    for i in range(0, n, blk):
        b, a = biquad(kind, fc[i], q)
        seg = x[i:i + blk]
        if zi is None: zi = lfilter_zi(b, a) * 0
        y[i:i + blk], zi = lfilter(b, a, seg, zi=zi)
    return y * g

def write(name, x, outdir):
    x = np.clip(x * MASTER, -1, 1)
    pcm = (x * 32767).astype('<i2')
    with wave.open(os.path.join(outdir, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())

def main(outdir):
    os.makedirs(outdir, exist_ok=True)
    S = {}
    o = buf(.3); burst(o, 'lowpass', 180, gain=.25, dur=.12); tone(o, 90, 60, .1, .08); S['step'] = o
    o = buf(.7); tone(o, 180, 120, .5, .05, 0, 'sawtooth'); burst(o, 'lowpass', 400, gain=.15, dur=.3); S['creak'] = o
    o = buf(1.0); burst(o, 'lowpass', 300, gain=.2, dur=.2); tone(o, 60, 60.01, .8, .03, 0, 'sawtooth'); S['fridge'] = o
    o = buf(.3); burst(o, 'lowpass', 220, gain=.35, dur=.15); S['thunk'] = o
    o = buf(.5); burst(o, 'highpass', 900, gain=.05, dur=.02); burst(o, 'highpass', 3500, gain=.35, dur=.35, att=.01, when=.03); S['open'] = o
    o = buf(.3); tone(o, 220, 110, .16, .18); burst(o, 'lowpass', 500, gain=.15, dur=.12); S['gulp'] = o
    o = buf(.8); tone(o, 160, 110, .6, .06, 0, 'triangle'); S['ahh'] = o
    o = buf(.4); burst(o, 'bandpass', 1800, .8, .25, .18); burst(o, 'bandpass', 3000, 1, .15, .1, when=.08); S['crush'] = o
    S['sniff'] = sweep_noise(.9, 'bandpass', 1.4, [(0, 700), (.75, 4200), (.9, 4200)],
                             [(0, 0), (.08, .5), (.6, .35), (.85, .001), (.9, 0)])
    o = buf(.4); tone(o, 70, 48, .13, .32); tone(o, 66, 46, .11, .22, .16); S['beat'] = o
    o = buf(.4); burst(o, 'highpass', 3000, gain=.25, dur=.04); burst(o, 'bandpass', 1500, 2, .12, .25, when=.05); S['flick'] = o
    for i in range(4):
        o = buf(.2); tone(o, 180 + rng.random() * 260, 90 + rng.random() * 60, .08, .12); burst(o, 'lowpass', 420, gain=.08, dur=.06); S['bubble%d' % i] = o
    S['exhale'] = sweep_noise(1.35, 'bandpass', .8, [(0, 1400), (1.2, 500), (1.35, 500)],
                              [(0, 0), (.15, .3), (1.3, .001), (1.35, 0)])
    o = buf(.8)
    for i in range(3): burst(o, 'bandpass', 500, 1, .35, .13, when=i * .22); tone(o, 160, 110, .1, .08, i * .22, 'sawtooth')
    S['cough'] = o
    for k in range(3):
        b = 420 + rng.random() * 300; n = int(.7 * SR); t = np.arange(n) / SR
        f = np.interp(t, [0, .18, .55, .7], [b, b * 1.7, b * 1.05, b * 1.05]); ph = 2 * np.pi * np.cumsum(f) / SR
        saw = 2 * ((ph / (2 * np.pi)) % 1) - 1
        y = np.zeros(n)
        for i in range(0, n, 256):
            fc = np.interp(t[i], [0, .2, .55, .7], [800, 1900, 950, 950]); bb, aa = biquad('bandpass', fc, 5)
            y[i:i + 256] = lfilter(bb, aa, saw[i:i + 256])
        S['meow%d' % k] = y * np.interp(t, [0, .05, .38, .65, .7], [0, .16, .12, .001, 0]) * 3
    # snore: one breath cycle, looped by the game every 2.6 s
    S['snore'] = sweep_noise(2.6, 'lowpass', .707, [(0, 260), (2.6, 260)], [(0, 0), (1.0, .45), (1.6, 0), (2.6, 0)])
    for i in range(6):
        o = buf(.1); burst(o, 'bandpass', 2500 + rng.random() * 3000, 3, .06 + rng.random() * .08, .03); S['crackle%d' % i] = o
    f = sweep_noise(3.5, 'bandpass', .7, [(0, 400), (.6, 1400), (3, 600), (3.5, 600)], [(0, 0), (.25, .45), (1.6, .3), (3.4, .001), (3.5, 0)])
    burst(f, 'highpass', 1500, gain=.25, dur=.08); S['flush'] = f
    o = buf(1.5)
    for w in (.575, .875, 1.175):
        burst(o, 'lowpass', 420, gain=.9, dur=.11, when=w); tone(o, 170, 95, .09, .35, w, 'triangle'); burst(o, 'bandpass', 1400, 2, .12, .03, when=w)
    S['knock'] = o
    o = buf(.9); tone(o, 1318, 1318.1, .35, .06); tone(o, 1047, 1047.1, .5, .06, .18); S['chime'] = o
    o = buf(.6); tone(o, 1568, 1568.1, .12, .08, 0, 'square'); tone(o, 2093, 2093.1, .3, .08, .1, 'square'); burst(o, 'highpass', 4000, gain=.15, dur=.3, when=.05); S['register'] = o
    o = buf(.4); burst(o, 'highpass', 2500, gain=.3, dur=.05); burst(o, 'highpass', 1800, gain=.3, dur=.06, when=.12); S['rack'] = o
    o = buf(1.1); burst(o, 'lowpass', 3200, gain=.9, dur=.09, att=.001); burst(o, 'bandpass', 900, .7, .5, .35); tone(o, 140, 40, .18, .5); burst(o, 'lowpass', 600, gain=.25, dur=.9, when=.03); S['shot'] = o
    o = buf(1.2); burst(o, 'highpass', 2000, gain=.25, dur=.05); burst(o, 'bandpass', 1200, 1, .3, .06, when=.5); burst(o, 'highpass', 2500, gain=.3, dur=.05, when=.95); S['reload'] = o
    o = buf(1.8); tone(o, 220, 110, 1.2, .2, 0, 'sawtooth'); tone(o, 165, 82, 1.4, .18, .15, 'sawtooth'); S['fail'] = o
    o = buf(.9)
    for i in range(10): burst(o, 'highpass', 3000 + rng.random() * 4000, gain=.35, dur=.08 + rng.random() * .15, when=i * .03)
    burst(o, 'lowpass', 400, gain=.5, dur=.4); S['shatter'] = o
    o = buf(.2); tone(o, 1100, 120, .08, .12, 0, 'square'); S['zap'] = o
    o = buf(.9); tone(o, 55, 150, .45, .16, 0, 'sawtooth'); burst(o, 'lowpass', 280, gain=.45, dur=.45); S['engine_start'] = o
    o = buf(.8); burst(o, 'lowpass', 500, gain=.9 * .8 + .2, dur=.4); burst(o, 'highpass', 2800, gain=.25 * .8, dur=.25, when=.03); tone(o, 110, 50, .3, .25 * .8); S['crash'] = o
    o = buf(.6); tone(o, 392, 390, .45, .12, 0, 'square'); tone(o, 494, 492, .45, .1, 0, 'square'); S['horn'] = o
    # engine loop at 60 Hz (game pitch-shifts it): saw + sub-octave square through a lowpass, 2 s of whole cycles
    t = np.arange(SR * 2) / SR
    eng = (2 * ((60 * t) % 1) - 1) + np.sign(np.sin(2 * np.pi * 30 * t))
    S['engine_loop'] = filt(eng, 'lowpass', 700) * .09
    o = buf(.6); tone(o, 420, 160, .4, .22, 0, 'sawtooth'); burst(o, 'bandpass', 900, 1.5, .3, .3); S['hurt'] = o
    o = buf(.4); burst(o, 'lowpass', 160, gain=.6, dur=.25); tone(o, 80, 45, .2, .2); S['thud'] = o
    o = buf(.7); tone(o, 2093, 2093.1, .5, .09); burst(o, 'lowpass', 400, gain=.3, dur=.12, when=.05); S['till_ding'] = o
    for i in range(3):
        o = buf(.25); burst(o, 'highpass', 2500 + i * 900, gain=.18, dur=.06); burst(o, 'lowpass', 600 + i * 200, gain=.25, dur=.12, when=.02); S['clink%d' % i] = o
    # siren: square wave alternating 960 / 720 Hz every 1/1.4 s, two full cycles, lowpassed
    n = int(SR * 2 / 1.4 * 2); t = np.arange(n) / SR
    f = np.where((np.floor(t * 1.4) % 2) == 1, 960.0, 720.0); ph = 2 * np.pi * np.cumsum(f) / SR
    S['siren_loop'] = filt(np.sign(np.sin(ph)), 'lowpass', 1800) * .035 * 3
    # loops: room tone, TV hiss, trip drone
    n = SR * 4; x = np.resize(NOISE, n)
    S['room_loop'] = filt(x, 'lowpass', 320) * .05 + filt(np.roll(x, 1234), 'bandpass', 900, 2) * .018
    t = np.arange(SR * 8) / SR; d = np.zeros_like(t)
    for fr in (110, 164.8, 220.6, 277.2):
        fr = fr * 2 ** ((rng.random() - .5) * 14 / 1200)
        fr = round(fr * 8) / 8          # whole cycles in 8 s so the loop is seamless
        ph = 2 * np.pi * fr * t
        d += (2 / np.pi * np.arcsin(np.sin(ph))) if fr > 200 else (2 * ((fr * t) % 1) - 1)
    y = np.zeros_like(d)
    for i in range(0, len(d), 256):
        fc = 900 + 600 * np.sin(2 * np.pi * .125 * t[i]); bb, aa = biquad('lowpass', max(fc, 80), 6 * .35)
        y[i:i + 256] = lfilter(bb, aa, d[i:i + 256])
    S['drone_loop'] = y * .05
    for k, v in S.items(): write(k, v, outdir)
    print('wrote', len(S), 'sounds to', outdir)

if __name__ == '__main__':
    main(sys.argv[1])
