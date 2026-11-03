#!/usr/bin/env python3
"""slotcheck.py - analyse OUT timing logged by zxsim.py --outlog.

Prints, per scene window, how regular the sound steps are, and the code
locations (from the pasmo symbol file) that produce the worst gaps.
"""
import bisect
import sys
from collections import defaultdict

import numpy as np

SLOT = 448   # same channel: every second step
outs = np.load(sys.argv[1])
syms = []
for line in open(sys.argv[2]):
    parts = line.split()
    if len(parts) == 3 and parts[1] == "EQU" and parts[2].endswith("H"):
        v = int(parts[2][:-1], 16)
        if 0x8000 <= v < 0x10000:
            syms.append((v, parts[0]))
syms.sort()
addrs = [a for a, _ in syms]


def where(addr):
    i = bisect.bisect_right(addrs, addr) - 1
    return f"{syms[i][1]}+{addr - syms[i][0]}" if i >= 0 else hex(addr)


offset = int(sys.argv[3]) if len(sys.argv) > 3 else 28
t = outs[:, 0]
dt = t[2:] - t[:-2]
caller = outs[2:, 1]
for k in range(13):
    a, b = (offset + k * 192) * 69888, (offset + (k + 1) * 192) * 69888
    sel = (t[2:] >= a) & (t[2:] < b)
    d = dt[sel]
    if len(d) == 0:
        continue
    ok = np.mean(np.abs(d - SLOT) <= 8) * 100
    cover = np.sum(np.minimum(d, 2 * SLOT)) / (b - a) * 100
    big = np.sum(d > SLOT + 224)
    print(f"scene {k + 1:2d}: steps {len(d):6d}  within +-8T {ok:5.1f}%  "
          f"late>224T {big:5d}  mean {d.mean():6.1f}")
    if len(sys.argv) > 4:
        bad = defaultdict(list)
        for dd, c in zip(d, caller[sel]):
            if abs(dd - SLOT) > 8:
                bad[where(int(c))].append(int(dd))
        for loc, v in sorted(bad.items(), key=lambda kv: -len(kv[1]))[:6]:
            print(f"      {loc:28s} n={len(v):5d} median {int(np.median(v))}")
