#!/usr/bin/env python3
"""
slotgen.py - schedules sound steps into straight-line Z80 code.

The beeper engine needs a CALL sA / CALL sB every SLOT_T T-states.
Code is described as a list of (instruction, T-states) items; the
scheduler inserts the step calls every SLOT_W T-states of work,
padding with harmless filler instructions so every slot has the same
length. Steps preserve all registers and flags (they own AF', the
alternate registers and IY).
"""

SLOT_W = 95          # work T-states between two steps (224 - 129)
TOL = 3              # an instruction may overshoot a slot by this much

# fillers: (T, instruction) - no effect on registers or flags
FILLERS = [(13, "LD (pad_dummy), A"), (12, "JR $+2"), (10, "JP $+3"), (4, "NOP")]


def pad(t):
    """Best filler sequence for t T-states (never more than t+2)."""
    best = (abs(t), [])
    # small search over combinations
    for a in range(0, 4):
        for b in range(0, 4):
            for c in range(0, 4):
                for d in range(0, 30):
                    s = 13 * a + 12 * b + 10 * c + 4 * d
                    if s > t + 2:
                        break
                    err = abs(t - s)
                    n = a + b + c + d
                    if err < best[0] or (err == best[0] and n < len(best[1])):
                        best = (err, ["LD (pad_dummy), A"] * a + ["JR $+2"] * b
                                + ["JP $+3"] * c + ["NOP"] * d)
    return best[1]


class Seq:
    def __init__(self):
        self.items = []

    def i(self, text, t):
        self.items.append(("i", text, t))
        return self

    def label(self, name):
        self.items.append(("l", name, 0))
        return self

    def extend(self, other):
        self.items += other.items
        return self


def schedule(seq, lead_in=0, tail=0, first="A", pad_end=True):
    """Insert step calls.

    lead_in: T-states already spent in the first slot before this code
             (e.g. the loop jump that precedes the body).
    tail:    T-states of code that follows the last step (e.g. the loop
             jump), reserved in the last slot.
    Returns (lines, number_of_steps, next_channel).
    """
    out = []
    acc = lead_in
    ch = first
    steps = 0

    def step():
        nonlocal acc, ch, steps
        out.extend("        " + p for p in pad(SLOT_W - acc))
        out.append(f"        CALL s{ch}")
        ch = "B" if ch == "A" else "A"
        steps += 1
        acc = 0

    labels = []
    for kind, text, t in seq.items:
        if kind == "l":
            # keep labels glued to their instruction (self-modifying code
            # patches label+1), so a step is never inserted in between
            labels.append(text)
            continue
        if acc + t > SLOT_W + TOL:
            step()
        out.extend(f"{lb}:" for lb in labels)
        labels = []
        out.append(f"        {text:<28}; {t}")
        acc += t
    out.extend(f"{lb}:" for lb in labels)
    if pad_end:
        if acc + tail > SLOT_W + TOL:
            step()
        acc += tail
        step()
    return out, steps, ch


def loop(name, body, ctrl, ctrl_t, first="A"):
    """A loop whose body + control jump is a whole, even number of slots.

    body: Seq (without the loop jump); ctrl: list of control lines
    executed after the last step (must end with the jump to `name`).
    """
    lines, steps, ch = schedule(body, lead_in=ctrl_t, tail=0, first=first)
    if steps % 2:
        # keep sA/sB alternating across iterations
        lines.extend("        " + p for p in pad(SLOT_W))
        lines.append(f"        CALL s{ch}")
        steps += 1
    return [f"{name}:"] + lines + ["        " + c for c in ctrl], steps
