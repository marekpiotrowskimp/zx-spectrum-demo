;; ============================================
;; Utilities: screen fills, copies, text, random, lava shimmer.
;; Long loops use the generated stepped routines (gen/fx_loops.asm),
;; so the beeper keeps playing while the screen is redrawn.
;; ============================================

;; ---- random: xorshift16 (J. Metcalf), A = random byte
rnd:
        PUSH HL
rnd_seed:
        LD HL, $A5C3
        LD A, H
        RRA
        LD A, L
        RRA
        XOR H
        LD H, A
        LD A, L
        RRA
        LD A, H
        RRA
        XOR L
        LD L, A
        XOR H
        LD H, A
        LD (rnd_seed + 1), HL
        POP HL
        RET

;; ---- A = pixel line (0..191) -> HL = screen address of the line
line_addr:
        LD L, A
        LD H, high line_lo
        LD A, (HL)
        INC H
        LD H, (HL)
        LD L, A
        RET

;; ---- clear bitmap ($4000-$57FF) with PUSH, stepped
cls_bitmap:
        LD HL, $5800
        LD DE, 0
        LD B, 192
        JP s_pushfill

;; ---- fill all attributes with A
fill_attrs:
        LD HL, $5800
        LD B, 96
        JP s_fill8

;; ---- black screen: attrs 0, bitmap clear
cls_black:
        XOR A
        CALL fill_attrs
        JR cls_bitmap

;; ---- fill attrs of char rows: B = first row, C = count, A = attr
fill_attr_rows:
        PUSH AF
        LD L, B
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        LD DE, $5800
        ADD HL, DE
        LD A, C
        ADD A, A
        ADD A, A
        LD B, A                 ; rows * 4 chunks of 8
        POP AF
        JP s_fill8

;; ---- checkerboard on the whole bitmap (tile effects)
;; one 256 byte page per pixel-line parity, filled top-down so the
;; PUSH fill never overwrites a finished page
checker_fill:
        LD HL, $5800
cf_page:
        PUSH HL
        LD DE, $AAAA
        BIT 0, H
        JR NZ, cf_even          ; page below H is odd (H-1)
        LD DE, $5555
cf_even:
        LD B, 8
        CALL s_pushfill
        POP HL
        DEC H
        LD A, H
        CP $40
        JR NZ, cf_page
        RET

;; ---- checkerboard on char rows B..23 (fire band)
checker_rows:
        LD A, B
        ADD A, A
        ADD A, A
        ADD A, A
        LD C, A                 ; first pixel line
ckr_line:
        LD A, C
        CALL line_addr
        LD A, C
        RRCA
        SBC A, A
        XOR $AA                 ; $AA even lines, $55 odd lines
        LD B, 4
        PUSH BC
        CALL s_fill8
        POP BC
        INC C
        LD A, C
        CP 192
        JR NZ, ckr_line
        RET

;; ---- copy char rows from SCRBUF: B = first row, C = count
copy_buf_rows:
        PUSH BC
        LD A, B
        ADD A, A
        ADD A, A
        ADD A, A
        LD L, A                 ; first line
        LD A, C
        ADD A, A
        ADD A, A
        ADD A, A
        LD B, A                 ; lines
        LD C, L
        CALL copy_buf_lines
        POP BC
        ; attributes
        LD L, B
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        LD DE, $5800
        ADD HL, DE
        EX DE, HL
        LD L, C
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        LD B, H
        LD C, L
        LD HL, SCRBUF + 6144 - $5800
        ADD HL, DE
        JP s_copy8

;; ---- remember the current attributes (source for lava_shimmer)
attr_snapshot:
        LD HL, $5800
attr_snap_from:
        LD DE, ATTRSNAP
        LD BC, 768
        JP s_copy8

;; ---- lava shimmer on char row B + (t & 3) (one row per frame)
lava_shimmer:
        LD A, (t_now)
        AND 3
        ADD A, B
        LD L, A
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        PUSH HL
        LD DE, $5800
        ADD HL, DE
        PUSH HL
        POP IX                  ; IX = screen attrs
        POP HL
        LD DE, ATTRSNAP
        ADD HL, DE              ; HL = snapshot attrs
        LD A, (t_now)
        ADD A, A
        ADD A, A
        ADD A, A
        ADD A, B
        ADD A, B
        LD C, A                 ; phase
        LD B, high shim_pg
        JP shimmer_row

;; ---- print zero terminated string HL at char D (col), E (row)
;; 8x8 ROM font, bitmap only
print_str:
        LD A, (HL)
        OR A
        RET Z
        PUSH HL
        PUSH DE
        CALL print_chr
        POP DE
        POP HL
        INC HL
        INC D
        CALL sA
        CALL sB
        JR print_str

print_chr:
        LD L, A
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        LD BC, $3C00
        ADD HL, BC
        LD A, E
        AND $18
        OR $40
        LD B, A
        LD A, E
        AND 7
        RRCA
        RRCA
        RRCA
        ADD A, D
        LD C, A
        LD E, 8
pc_line:
        LD A, (HL)
        LD (BC), A
        INC HL
        INC B
        DEC E
        JR NZ, pc_line
        RET

;; ---- double height string HL at char col D, char row E (uses E, E+1)
print_str2:
        LD A, (HL)
        OR A
        RET Z
        PUSH HL
        PUSH DE
        CALL print_chr2
        POP DE
        POP HL
        INC HL
        INC D
        JR print_str2

print_chr2:
        LD L, A
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        LD BC, $3C00
        ADD HL, BC              ; HL = font
        LD A, E
        ADD A, A
        ADD A, A
        ADD A, A
        LD E, A                 ; E = first pixel line
        LD B, 16
pc2_line:
        CALL sA
        PUSH BC
        PUSH HL
        LD A, E
        CALL line_addr
        LD A, L
        ADD A, D
        LD L, A
        EX (SP), HL             ; HL = font, (SP) = screen
        LD A, (HL)
        LD C, A
        RRCA
        AND $7F
        OR C                    ; bold
        EX (SP), HL
        LD (HL), A
        POP HL
        POP BC
        LD A, B
        AND 1
        JR Z, pc2_same
        INC HL
pc2_same:
        INC E
        CALL sB
        DJNZ pc2_line
        RET
