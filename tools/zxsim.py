#!/usr/bin/env python3
"""
zxsim.py - headless ZX Spectrum 48K harness for testing the demo.

Emulates the state after the BASIC loader (screen loaded, code loaded),
runs N frames with 50 Hz interrupts and dumps:
  - PNG screenshots of selected frames (with border),
  - a WAV file of the beeper output,
  - per-frame CPU usage statistics (T-states until main loop HALTs).

Requires the 'z80' package (pip install z80) and Pillow.
Contended memory is not emulated, so real timings are ~10-20% worse
for code touching $4000-$7FFF during the visible screen.
"""

import argparse
import struct
import sys
import wave
from pathlib import Path

import z80
from PIL import Image

T_FRAME = 69888
PALETTE = [
    (0, 0, 0), (0, 0, 205), (205, 0, 0), (205, 0, 205),
    (0, 205, 0), (0, 205, 205), (205, 205, 0), (205, 205, 205),
    (0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255),
    (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255),
]
DEFAULT_ROM = Path.home() / "Downloads/zx/Fuse for macOS/Fuse.app/Contents/Resources/48.rom"


def render(mem, border, frame_no):
    img = Image.new("RGB", (256 + 64, 192 + 48), PALETTE[border & 7])
    px = img.load()
    flash_phase = (frame_no // 16) & 1
    for y in range(192):
        base = 0x4000 | ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)
        for cx in range(32):
            byte = mem[base + cx]
            attr = mem[0x5800 + (y >> 3) * 32 + cx]
            ink = (attr & 7) | ((attr >> 3) & 8)
            paper = ((attr >> 3) & 7) | ((attr >> 3) & 8)
            if attr & 0x80 and flash_phase:
                ink, paper = paper, ink
            for b in range(8):
                c = ink if byte & (0x80 >> b) else paper
                px[32 + cx * 8 + b, 24 + y] = PALETTE[c]
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bin", nargs="?", help="raw code (skipped with --tap)")
    ap.add_argument("--tap", help="boot the ROM, type LOAD \"\" and load this TAP")
    ap.add_argument("--scr", help="screen loaded before the code (SCREEN$)")
    ap.add_argument("--rom", default=str(DEFAULT_ROM))
    ap.add_argument("--org", type=lambda s: int(s, 0), default=0x8000)
    ap.add_argument("--frames", type=int, default=100)
    ap.add_argument("--shots", default="", help="comma separated frame numbers")
    ap.add_argument("--every", type=int, default=0, help="screenshot every N frames")
    ap.add_argument("--out", default="sim_out")
    ap.add_argument("--wav", help="write beeper audio to this file")
    ap.add_argument("--stats", action="store_true")
    ap.add_argument("--outlog", help="save every OUT ($FE) time + caller to this .npy file")
    ap.add_argument("--window", type=int, default=0,
                    help="print stats per window of N frames")
    ap.add_argument("--offset", type=int, default=0,
                    help="first frame of the first window")
    ap.add_argument("--idle", type=lambda s: int(s, 0),
                    help="address of the main loop HALT, used for CPU stats")
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    shots = {int(s) for s in args.shots.split(",") if s.strip()}

    m = z80.Z80Machine()
    mem = m.memory
    rom = Path(args.rom).read_bytes()
    mem[0:len(rom)] = rom
    tap_blocks = []
    if args.tap:
        raw = Path(args.tap).read_bytes()
        i = 0
        while i < len(raw):
            n = raw[i] | (raw[i + 1] << 8)
            tap_blocks.append(raw[i + 2:i + 2 + n])
            i += 2 + n
    else:
        if args.scr:
            scr = Path(args.scr).read_bytes()
            mem[0x4000:0x4000 + len(scr)] = scr
        code = Path(args.bin).read_bytes()
        mem[args.org:args.org + len(code)] = code

    # ROM is read-only
    def on_write(addr, value):
        pass
    m.set_write_callback(on_write)
    m.mark_addrs(0, 0x4000, m.WRITE_MARK)

    state = {"border": 0, "frame": 0, "edges": [], "speaker": 0, "outs": []}

    def on_output(port, value):
        if port & 1 == 0 and args.outlog:
            sp = m.sp
            caller = mem[sp] | (mem[(sp + 1) & 0xFFFF] << 8)
            state["outs"].append((state["frame"] * T_FRAME + (T_FRAME - m.ticks_to_stop), caller))
        if port & 1 == 0:
            state["border"] = value & 7
            spk = (value >> 4) & 1
            if spk != state["speaker"]:
                state["speaker"] = spk
                t = state["frame"] * T_FRAME + (T_FRAME - m.ticks_to_stop)
                state["edges"].append((t, spk))
    m.set_output_callback(on_output)
    # keyboard: (row port high byte, bit) per key; LOAD "" + ENTER typed
    KEYS = {"J": (0xBF, 3), "ENTER": (0xBF, 0), "SS": (0x7F, 1), "P": (0xDF, 0)}
    typing = [(150, ["J"]), (160, []), (170, ["SS", "P"]), (180, []),
              (190, ["SS", "P"]), (200, []), (210, ["ENTER"]), (220, [])]
    pressed = []

    def on_input(port):
        if port & 1:
            return 0xFF
        hi = port >> 8
        v = 0xFF
        for k in pressed:
            row, bit = KEYS[k]
            if (~hi) & (~row) & 0xFF:   # this half-row is selected
                v &= ~(1 << bit)
        return v & 0xBF  # EAR bit low
    m.set_input_callback(on_input)
    m.set_get_int_vector_callback(lambda: 0xFF)

    if args.tap:
        m.pc = 0
        m.set_breakpoint(0x0556)
    else:
        m.pc = args.org
        m.sp = 0x5FFE
    m.iff1 = 0
    m.iff2 = 0

    def tap_trap():
        """emulate ROM LD-BYTES: A = flag, IX = addr, DE = length"""
        flag, ix, de = m.a, m.ix, m.de
        if tap_blocks:
            blk = tap_blocks.pop(0)
            data = blk[1:-1]
            if blk[0] == flag:
                n = min(de, len(data))
                mem[ix:ix + n] = data[:n]
                m.ix = ix + n
                m.de = 0
                m.f = m.f | 1
                print(f"tap: loaded {n} bytes at {ix:#06x} (flag {flag:#04x}) frame {state['frame']}")
            else:
                m.f = m.f & ~1
        else:
            m.f = m.f & ~1
        # RET
        sp = m.sp
        m.pc = mem[sp] | (mem[sp + 1] << 8)
        m.sp = sp + 2

    if args.idle is not None:
        m.set_breakpoint(args.idle)
    busy = []
    halt_seen = {"t": None}
    for f in range(args.frames):
        state["frame"] = f
        for when, keys in typing if args.tap else []:
            if when == f:
                pressed[:] = keys
        # interrupt at frame start
        m.on_handle_active_int()
        halt_seen["t"] = None
        remaining = T_FRAME
        m.ticks_to_stop = remaining
        while True:
            ev = m.run()
            if ev & m._BREAKPOINT_HIT and args.tap and m.pc == 0x0556:
                tap_trap()
                if m.ticks_to_stop == 0:
                    break
                continue
            if ev & m._BREAKPOINT_HIT:
                if halt_seen["t"] is None:
                    halt_seen["t"] = T_FRAME - m.ticks_to_stop
                m.step_over_breakpoint()
                if m.ticks_to_stop == 0:
                    break
                continue
            if m.ticks_to_stop == 0:
                break
        busy.append(halt_seen["t"])
        if f in shots or (args.every and f % args.every == 0):
            render(mem, state["border"], f).save(out / f"frame_{f:05d}.png")

    if args.stats:
        none = sum(1 for b in busy if b is None)
        vals = [b for b in busy if b is not None]
        print(f"frames: {len(busy)}, frames without HALT (overrun): {none}")
        if vals:
            print(f"T until HALT: min {min(vals)} avg {sum(vals)//len(vals)} max {max(vals)}")

    if args.outlog:
        import numpy as np
        np.save(args.outlog, np.array(state["outs"], dtype=np.int64))

    if args.window:
        start = args.offset
        k = 0
        while start < len(busy):
            win = busy[start:start + args.window]
            halts = [b for b in win if b is not None]
            # effective fps = frames in which the main loop reached HALT
            print(f"window {k:2d} [{start:5d}]: updates/s ~{len(halts) * 50 / len(win):4.1f}"
                  f"  avg T to HALT {sum(halts) // max(1, len(halts)):6d}")
            start += args.window
            k += 1

    if args.wav:
        rate = 44100
        total_t = args.frames * T_FRAME
        n = int(total_t * rate / 3500000)
        samples = bytearray(n * 2)
        edges = state["edges"]
        level = 0
        ei = 0
        tick_per_sample = 3500000 / rate
        for i in range(n):
            t0 = i * tick_per_sample
            t1 = t0 + tick_per_sample
            # average speaker level across the sample window
            acc = 0.0
            cur = t0
            while ei < len(edges) and edges[ei][0] < t1:
                et, lv = edges[ei]
                acc += level * (et - cur)
                cur = et
                level = lv
                ei += 1
            acc += level * (t1 - cur)
            v = acc / tick_per_sample
            s = int((v - 0.5) * 20000)
            struct.pack_into("<h", samples, i * 2, s)
        with wave.open(args.wav, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes(bytes(samples))
        print(f"wrote {args.wav} ({n / rate:.1f}s, {len(edges)} edges)")


if __name__ == "__main__":
    sys.exit(main())
