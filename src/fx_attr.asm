;; ============================================
;; Attribute (tile) effects on a checkerboard bitmap, 32x24 cells:
;; plasma, tunnel, logo zoomer, fire. Row loops are generated
;; (gen/fx_loops.asm) with the beeper steps scheduled in.
;; ============================================

;; --------------------------------------------
;; PLASMA: v = SX[x] + SD[x+y] + SY[y] -> ping-pong palette
;; --------------------------------------------
pl_pal:         DB high tile_fire

plasma_frame:
        LD A, (t_now)
        LD C, A
        ; SX[x] = usin[x*8 + t*3]
        ADD A, A
        ADD A, C
        LD E, A
        LD D, high usin_tab
        LD HL, WORKBUF
        LD B, 32
plx_loop:
        LD A, (DE)
        LD (HL), A
        INC L
        LD A, E
        ADD A, 8
        LD E, A
        LD A, B
        AND 1
        CALL Z, sA
        LD A, B
        AND 1
        CALL NZ, sB
        DJNZ plx_loop
        ; SD[i] = usin[i*6 - t*2]
        LD A, C
        ADD A, A
        NEG
        LD E, A
        LD L, $40
        LD B, 64
pld_loop:
        LD A, (DE)
        LD (HL), A
        INC L
        LD A, E
        ADD A, 6
        LD E, A
        LD A, B
        AND 1
        CALL Z, sA
        LD A, B
        AND 1
        CALL NZ, sB
        DJNZ pld_loop
        ; rows
        LD A, C
        ADD A, A
        ADD A, A
        LD (pl_syph), A
        LD IX, $5800
        XOR A
pl_row:
        LD (pl_y), A
        CALL sA
        ; SY = usin[y*10 + t*4], patched into the row loop
        LD B, A
        ADD A, A
        LD L, A
        ADD A, A
        ADD A, A
        ADD A, L
        LD HL, pl_syph
        ADD A, (HL)
        LD L, A
        LD H, high usin_tab
        LD A, (HL)
        LD (pl_sy0 + 1), A
        LD (pl_sy1 + 1), A
        LD (pl_sy2 + 1), A
        LD (pl_sy3 + 1), A
        LD (pl_sy4 + 1), A
        LD (pl_sy5 + 1), A
        LD (pl_sy6 + 1), A
        LD (pl_sy7 + 1), A
        LD A, B
        ADD A, $40
        LD L, A
        LD H, high WORKBUF
        LD DE, WORKBUF
        LD A, (pl_pal)
        LD B, A
        CALL sB
        CALL plasma_row         ; IX advances by 32 (low byte only)
        LD A, IXL
        OR A
        JR NZ, pl_nopage
        INC IXH
pl_nopage:
        LD A, (pl_y)
        INC A
        CP 24
        JR NZ, pl_row
        RET

pl_syph:        DB 0
pl_y:           DB 0

;; --------------------------------------------
;; TUNNEL: per cell (depth<<4 | angle) + offset -> texture attr
;; --------------------------------------------
tun_tex:        DB high ttex_fire
tun_speed:      DB 1

tunnel_frame:
        LD A, (t_now)
        LD B, A
        LD A, (tun_speed)
        DEC A
        JR Z, tn_s1
        SLA B
tn_s1:
        LD A, B
        ADD A, A
        ADD A, A
        ADD A, A
        ADD A, A                ; depth offset (t*16)
        LD C, A
        LD A, B
        RRCA
        RRCA
        RRCA
        AND 15                  ; slow rotation
        ADD A, C
        LD C, A
        LD DE, tunnel_tab
        LD IX, $5800
        LD B, 24
tn_row:
        PUSH BC
        LD A, (tun_tex)
        LD H, A
        CALL tunnel_row         ; DE, IX advance
        LD BC, 32
        ADD IX, BC
        POP BC
        DJNZ tn_row

        ; dark middle hides the depth aliasing
        LD HL, tunnel_hole
tn_hole:
        LD E, (HL)
        INC HL
        LD D, (HL)
        INC HL
        LD A, D
        OR A
        JR Z, tn_fog
        XOR A
        LD (DE), A
        LD A, L
        AND 2
        CALL Z, sA
        LD A, L
        AND 2
        CALL NZ, sB
        JR tn_hole
tn_fog:
        CALL sA
        LD HL, tunnel_fog
        LD B, high fade_tab
tn_fogl:
        LD E, (HL)
        INC HL
        LD D, (HL)
        INC HL
        LD A, D
        OR A
        JR Z, tn_done
        LD A, (DE)
        LD C, A
        LD A, (BC)
        LD (DE), A
        LD A, L
        AND 2
        CALL Z, sB
        LD A, L
        AND 2
        CALL NZ, sA
        JR tn_fogl
tn_done:
        JP sB

;; --------------------------------------------
;; ZOOMER: logo texture 32x32 (tile attrs), zoom + wobble
;; --------------------------------------------
zm_du:          DW 256
zm_dv:          DW 256
zm_v:           DW 0

zoom_frame:
        ; du = 150 + usin[t*1.25 + 64] * 6, dv = du (square cells)
        LD A, (t_now)
        LD B, A
        SRL A
        SRL A
        ADD A, B
        ADD A, 64
        LD L, A
        LD H, high usin_tab
        LD L, (HL)
        LD H, 0
        LD D, H
        LD E, L
        ADD HL, HL
        ADD HL, HL
        ADD HL, DE
        ADD HL, DE              ; *6
        LD DE, 150
        ADD HL, DE
        LD (zm_du), HL
        LD (zm_dv), HL

        ; colU[i] for i = 0..63, u(i) = 4096 + (i-32)*du
        LD HL, (zm_du)
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL              ; 32*du
        EX DE, HL
        LD HL, 4096
        OR A
        SBC HL, DE
        LD DE, (zm_du)
        LD IX, WORKBUF
        LD B, 64
zm_col:
        LD A, H
        AND 31
        LD (IX+0), A
        INC IX
        ADD HL, DE
        LD A, B
        AND 1
        CALL Z, sA
        LD A, B
        AND 1
        CALL NZ, sB
        DJNZ zm_col

        ; v start = 4096 - 12*dv
        LD HL, (zm_dv)
        ADD HL, HL
        ADD HL, HL              ; 4dv
        LD D, H
        LD E, L
        ADD HL, HL              ; 8dv
        ADD HL, DE              ; 12dv
        EX DE, HL
        LD HL, 4096
        OR A
        SBC HL, DE
        LD (zm_v), HL

        LD IX, $5800
        XOR A
zm_row:
        LD (zm_r), A
        CALL sA
        ; texture row v -> page + offset
        LD HL, (zm_v)
        LD A, H
        AND 31
        LD C, A
        RRCA
        RRCA
        RRCA
        AND 3
        ADD A, high zoom_tex
        LD (zm_page), A
        CALL sB
        LD A, C
        AND 7
        RRCA
        RRCA
        RRCA
        LD (zm_base), A
        CALL sA
        LD DE, (zm_dv)
        ADD HL, DE
        LD (zm_v), HL
        ; wobble: start index 16 + (sin >> 6)
        LD A, (zm_r)
        ADD A, A
        ADD A, A
        ADD A, A
        ADD A, A
        LD C, A
        LD A, (t_now)
        ADD A, A
        ADD A, A
        ADD A, A
        ADD A, C
        LD L, A
        LD H, high sin_tab
        CALL sB
        LD A, (HL)
        SRA A
        SRA A
        SRA A
        SRA A
        SRA A
        SRA A
        ADD A, 16
        CALL sA
        LD E, A
        LD D, high WORKBUF
        LD A, (zm_base)
        LD B, A
        LD A, (zm_page)
        LD H, A
        CALL sB
        CALL zoom_row
        LD BC, 32
        ADD IX, BC
        LD A, (zm_r)
        INC A
        CP 24
        JR NZ, zm_row
        RET

zm_r:           DB 0
zm_page:        DB 0
zm_base:        DB 0

;; --------------------------------------------
;; FIRE (tiles): F[r][x] = DEC[(F[r+1][x] + F[r+1][x+1]) / 2]
;; FIREBUF rows F[0..nr+1], seeds in F[nr], F[nr+1]
;; --------------------------------------------
fire_r0:        DB 0
fire_nr:        DB 18
fire_int:       DB $FF
fire_seeds:     DB 255, 40, 255, 255, 10, 255, 60, 255
                DB 255, 20, 255, 0, 255, 255, 30, 255

;; A = decay page, C = palette page
fire_setup:
        JP fire_patch

fire_clear:
        LD HL, FIREBUF
        LD B, 80                ; 640 bytes
        XOR A
        JP s_fill8

fire_step:
        ; ---- seeds row address = FIREBUF + nr*32
        LD A, (fire_nr)
        LD L, A
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        LD DE, FIREBUF
        ADD HL, DE
        PUSH HL
        ; change 3 random seed pairs (flames keep their place a while)
        LD B, 3
fs_mut:
        CALL sA
        CALL rnd
        AND 15
        LD E, A
        LD D, 0
        LD HL, fire_seeds
        ADD HL, DE
        CALL rnd
        CP 110
        JR C, fs_cold
        LD A, $FF
        JR fs_put
fs_cold:
        AND 63
fs_put:
        LD (HL), A
        CALL sB
        DJNZ fs_mut
        POP HL
        ; write both seed rows
        LD DE, fire_seeds
        LD A, (fire_int)
        LD C, A
        LD B, 16
fs_seed:
        LD A, (DE)
        INC DE
        AND C
        LD (HL), A
        INC HL
        LD (HL), A
        PUSH HL
        PUSH DE
        LD DE, 31
        ADD HL, DE
        LD (HL), A
        DEC HL
        LD (HL), A
        POP DE
        POP HL
        INC HL
        LD A, B
        AND 1
        CALL Z, sA
        LD A, B
        AND 1
        CALL NZ, sB
        DJNZ fs_seed

        ; ---- rows
        LD A, (fire_r0)
        LD L, A
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        LD DE, $5800
        ADD HL, DE
        PUSH HL
        POP IX
        LD HL, FIREBUF + 32
        LD A, (t_now)
        AND 2
        JR Z, fs_even
        DEC HL
fs_even:
        LD BC, FIREBUF
        LD A, (fire_nr)
fs_row:
        PUSH AF
        CALL fire_row           ; HL, BC advance by 32
        LD DE, 32
        ADD IX, DE
        POP AF
        DEC A
        JR NZ, fs_row
        RET
