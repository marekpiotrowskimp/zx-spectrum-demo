;; ============================================
;; Bitmap effects: logo burn-in / melt, ruins patch, 3D dot rune,
;; twister, scroller. Inner loops are generated with sound steps.
;; ============================================

;; --------------------------------------------
;; LOGO
;; --------------------------------------------

;; draw logo bitmap (18 bytes x 144 lines at char col 7, line 8)
draw_logo:
        LD A, LOGO_COL
        LD (cl_col + 1), A
        LD HL, logo_bmp
        LD C, LOGO_LINE
        LD B, LOGO_H
        JP copy_lines18

;; B = logo row -> HL = logo_attr source, DE = screen attr
logo_attr_row:
        LD L, B
        LD H, 0
        ADD HL, HL
        LD D, H
        LD E, L
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, DE              ; 18 * row
        LD DE, logo_attr
        ADD HL, DE
        PUSH HL
        LD A, B
        INC A                   ; logo row 0 = screen row 1
        LD L, A
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        LD DE, $5800 + LOGO_COL
        ADD HL, DE
        EX DE, HL
        POP HL
        RET

;; copy logo attributes of logo row B
logo_row_attrs:
        CALL logo_attr_row
        LD BC, LOGO_W
        LDIR
        RET

;; all logo attributes, rows A..17
logo_attrs_from:
        LD B, A
lafr_row:
        LD A, B
        CP 18
        RET NC
        PUSH BC
        CALL sA
        CALL logo_row_attrs
        CALL sB
        POP BC
        INC B
        JR lafr_row

;; fill logo row B with attr C where the logo attr is not black
logo_row_hot:
        CALL logo_attr_row
        LD B, LOGO_W
lrh_cell:
        LD A, (HL)
        AND $07
        JR Z, lrh_black
        LD A, C
lrh_black:
        LD (DE), A
        INC HL
        INC DE
        DJNZ lrh_cell
        RET

;; burn-in: the burn line rises from logo row 17 to the top
burn_frame:
        LD A, (t_now)
        CP 120
        RET NC
        LD L, A
        LD H, 0
        LD D, H
        LD E, L
        ADD HL, HL
        ADD HL, DE              ; 3t
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL              ; 24t
        ADD HL, DE              ; 25t
        ADD HL, HL              ; 50t
        LD A, 17
        SUB H                   ; burn row (may go negative)
        LD (burn_l), A
        ; row L: flickering red, row L+1: white hot, row L+2: logo
        BIT 7, A
        JR NZ, bf_no_l
        CALL rnd
        AND $04
        OR $42
        LD C, A
        LD A, (burn_l)
        LD B, A
        CALL sA
        CALL logo_row_hot
        CALL sB
bf_no_l:
        LD A, (burn_l)
        INC A
        BIT 7, A
        JR NZ, bf_no_l1
        CP 18
        JR NC, bf_no_l1
        LD B, A
        LD C, $47
        CALL sA
        CALL logo_row_hot
        CALL sB
bf_no_l1:
        LD A, (burn_l)
        ADD A, 2
        BIT 7, A
        RET NZ
        CP 18
        RET NC
        LD B, A
        CALL sA
        CALL logo_row_attrs
        JP sB

burn_l:         DB 0

;; melt: vertical ripple of the logo lines (interlaced)
melt_frame:
        ; amplitude 8, 4, 2 px through each beat
        LD A, (t_now)
mf_mod:
        CP 24
        JR C, mf_modok
        SUB 24
        JR mf_mod
mf_modok:
        RRCA
        RRCA
        RRCA
        AND 3
        ADD A, high melt_disp0
        LD (mf_dpa + 1), A
        LD (mf_dpb + 1), A
        LD A, (t_now)
        LD C, A
        ADD A, A
        ADD A, C
        ADD A, A                ; t*6
        LD (mf_pha + 1), A
        LD (mf_phb + 1), A
        LD A, (mf_field)
        XOR 1
        LD (mf_field), A
        LD B, A
        JP melt_lines

mf_field:       DB 0

;; replace the logo part of the picture with plain ruins for char
;; rows B..19 (rows below 11 are not patched)
ruins_patch:
        LD A, B
        CP 11
        JR NC, rp_from
        LD B, 11
rp_from:
        LD A, B
        CP 20
        RET NC
        PUSH BC
        ; bitmap: ruins_bmp + (row-11)*144, 8 lines
        SUB 11
        LD L, A
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL              ; *16
        LD D, H
        LD E, L
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL              ; *128
        ADD HL, DE              ; *144
        LD DE, ruins_bmp
        ADD HL, DE
        LD A, 7
        LD (cl_col + 1), A
        LD A, B
        ADD A, A
        ADD A, A
        ADD A, A
        LD C, A
        LD B, 8
        CALL copy_lines18
        POP BC
        ; attributes
        PUSH BC
        LD A, B
        SUB 11
        LD L, A
        LD H, 0
        ADD HL, HL
        LD D, H
        LD E, L
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, DE              ; *18
        LD DE, ruins_attr
        ADD HL, DE
        PUSH HL
        LD L, B
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        LD DE, $5800 + 7
        ADD HL, DE
        EX DE, HL
        POP HL
        LD BC, 18
        LDIR
        POP BC
        INC B
        JR rp_from

;; --------------------------------------------
;; 3D DOT RUNE (precomputed rotation, 96 dots of 2x2 pixels)
;; erase list at DOTSOLD: addr1, addr2, mask (5 bytes per dot)
;; --------------------------------------------
dots_clear_list:
        LD HL, DOTSOLD
        LD B, DOTS_N
dcl_loop:
        LD (HL), 0
        INC HL
        LD (HL), $40
        INC HL
        LD (HL), 0
        INC HL
        LD (HL), $40
        INC HL
        LD (HL), 0
        INC HL
        DJNZ dcl_loop
        RET

dots_frame:
        ; frame index = (t / 2) mod DOTS_FRAMES
        LD A, (t_now)
        SRL A
df_mod:
        CP DOTS_FRAMES
        JR C, df_modok
        SUB DOTS_FRAMES
        JR df_mod
df_modok:
        ; HL = dots_tab + index * DOTS_N * 2 (= *192)
        LD L, A
        LD H, 0
        LD D, H
        LD E, L
        ADD HL, HL
        ADD HL, DE
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        LD DE, dots_tab
        ADD HL, DE
        LD IX, DOTSOLD
        LD B, DOTS_N
        JP dots_loop

;; --------------------------------------------
;; TWISTER (precomputed 64 rotation lines x 2 dither phases)
;; 8 bytes wide at char column 12, lines 0..TW_LINES-1
;; --------------------------------------------
TW_LINES        EQU 144

twister_frame:
        LD A, (t_now)
        LD C, A
        ADD A, A
        LD (tw_ph + 1), A       ; wave phase t*2
        LD A, C
        ADD A, A
        ADD A, C
        LD (tw_base + 1), A     ; rotation t*3
        LD B, 0
        JP twist_lines

;; twister attributes: colour columns 12..19 on rows 0..17
twister_attrs:
        LD HL, $5800 + 12
        LD B, 18
ta_row:
        PUSH BC
        CALL sA
        LD DE, tw_cols
        EX DE, HL
        LD BC, 8
        LDIR
        EX DE, HL
        LD BC, 24
        ADD HL, BC
        CALL sB
        POP BC
        DJNZ ta_row
        RET

tw_cols:        DB $02, $42, $06, $46, $47, $46, $42, $02

;; --------------------------------------------
;; SCROLLER: double height ROM font, rows 3-4 (lines 24..39)
;; --------------------------------------------
SC_LINE         EQU 24

sc_ptr:         DW scroll_text
sc_bits:        DB 0
sc_buf:         DS 16

scroll_init:
        LD HL, scroll_text
        LD (sc_ptr), HL
        XOR A
        LD (sc_bits), A
        RET

;; shift the scroller by one pixel
scroll_step:
        LD A, (sc_bits)
        OR A
        JR NZ, ss_have
        ; next character -> sc_buf (each font row twice, bold)
        CALL sA
        LD HL, (sc_ptr)
        LD A, (HL)
        OR A
        JR NZ, ss_chr
        LD HL, scroll_text
        LD A, (HL)
ss_chr:
        INC HL
        LD (sc_ptr), HL
        LD L, A
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        LD BC, $3C00
        ADD HL, BC
        LD DE, sc_buf
        LD B, 8
ss_fill:
        LD A, (HL)
        LD C, A
        RRCA
        AND $7F
        OR C
        LD (DE), A
        INC DE
        LD (DE), A
        INC DE
        INC HL
        DJNZ ss_fill
        CALL sB
        LD A, 8
ss_have:
        DEC A
        LD (sc_bits), A
        LD IX, sc_buf
        LD B, 16
        LD E, SC_LINE
        JP scroll_lines

;; scroller colours cycling along the text
scroll_colors:
        LD A, (t_now)
        RRCA
        LD C, A
        LD HL, $5800 + 3 * 32
        LD B, 64
scc_loop:
        LD A, C
        AND 7
        PUSH HL
        LD HL, sc_cols
        ADD A, L
        LD L, A
        JR NC, scc_nc
        INC H
scc_nc:
        LD A, (HL)
        POP HL
        LD (HL), A
        INC HL
        INC C
        LD A, B
        AND 1
        CALL Z, sA
        LD A, B
        AND 1
        CALL NZ, sB
        DJNZ scc_loop
        RET

sc_cols:        DB $02, $42, $06, $46, $47, $46, $42, $02
