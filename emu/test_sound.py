"""Check the beeps in a WAV saved by max80 -s.

Usage: test_sound.py sound.wav COUNT

The TRM (TS-14) gives the beep as about 2 kHz for about 1/15 second,
the schematics as 1953 Hz for 3 to 4 ticks, 49 to 66 ms. The file
must hold COUNT beeps, or at least N with COUNT written N+, each 45-70
ms long at 1900-2100 Hz.
"""
import array
import sys
import wave


def beeps(path):
    w = wave.open(path)
    rate = w.getframerate()
    a = array.array('h', w.readframes(w.getnframes()))
    out, start, quiet = [], None, 0
    for i, v in enumerate(a):
        if v:
            if start is None:
                start = i
            quiet = 0
        elif start is not None:
            quiet += 1
            if quiet > rate // 1000:	# a gap of 1 ms ends a beep
                end = i - quiet + 1
                seg = a[start:end]
                flips = sum(1 for k in range(1, len(seg))
                            if (seg[k] > 0) != (seg[k - 1] > 0))
                secs = (end - start) / rate
                out.append((start / rate, secs * 1000, flips / 2 / secs))
                start, quiet = None, 0
    return out


def main():
    found = beeps(sys.argv[1])
    at_least = sys.argv[2].endswith('+')
    want = int(sys.argv[2].rstrip('+'))
    print('%d beeps: ' % len(found) +
          (', '.join('%.3f s %.1f ms %.0f Hz' % b for b in found[:3]) or 'none'))
    count_ok = len(found) >= want if at_least else len(found) == want
    ok = count_ok and all(45 <= ms <= 70 and 1900 <= hz <= 2100
                                    for _, ms, hz in found)
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
