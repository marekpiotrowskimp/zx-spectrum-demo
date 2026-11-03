;; ============================================
;; Scene list: 13 scenes x 192 frames (8 beats @ 125 BPM)
;; init_* runs once when the scene starts (screen may be redrawn),
;; frm_* runs every main loop pass with t_now = frame within scene.
;; Every long loop keeps calling the sound steps (see sound.asm).
;; ============================================

init_tab:
        DW init_sparks, init_fire, init_burn, init_melt
        DW init_plasma, init_tunnel, init_dots, init_zoom
        DW init_ruins, init_twister, init_quad, init_finale
        DW init_silence
frame_tab:
        DW frm_sparks, frm_fire, frm_burn, frm_melt
        DW frm_plasma, frm_tunnel, frm_dots, frm_zoom
        DW frm_ruins, frm_twister, frm_quad, frm_finale
        DW frm_silence

;; common scene start: black border and attributes
scene_start:
        XOR A
        CALL set_border
        XOR A
        JP fill_attrs

;; border flash on every beat (first 2 frames), colour B / C
beat_border:
        LD A, (t_now)
bb_mod:
        CP 24
        JR C, bb_ok
        SUB 24
        JR bb_mod
bb_ok:
        CP 2
        LD A, B
        JR C, bb_set
        LD A, C
bb_set:
        LD HL, border
        CP (HL)
        RET Z
        JP set_border

;; --------------------------------------------
;; 1. sparks rising from the lava + title
;; --------------------------------------------
init_sparks:
        CALL scene_start
        CALL cls_bitmap
        LD B, 18
        LD C, 6
        CALL copy_buf_rows
        LD B, 18
        CALL ruins_patch
        CALL sparks_gradient
        LD A, 8
        LD (sp_ymin), A
        LD A, 140
        LD (sp_ymax), A
        LD A, 32
        LD (sp_count), A
        XOR A
        LD (fs_lit), A
        LD (fs_txt), A
        CALL attr_snapshot
        JP sp_init

fs_lit:         DB 0

sparks_gradient:
        LD B, 0
        LD C, 6
        LD A, $02
        CALL fill_attr_rows
        LD B, 6
        LD C, 5
        LD A, $42
        CALL fill_attr_rows
        LD B, 11
        LD C, 4
        LD A, $06
        CALL fill_attr_rows
        LD B, 15
        LD C, 3
        LD A, $46
        JP fill_attr_rows

frm_sparks:
        CALL sp_update
        LD B, 18
        CALL lava_shimmer
        ; lightning on beats 1 and 5: one bright flash, then restore
        LD A, (t_now)
        CP 2
        JR C, fs_flash
        SUB 96
        CP 2
        JR C, fs_flash
        LD A, (fs_lit)
        OR A
        JR Z, fs_text
        XOR A
        LD (fs_lit), A
        CALL set_border
        CALL sparks_gradient
        JR fs_text
fs_flash:
        LD A, (fs_lit)
        OR A
        JR NZ, fs_text
        INC A
        LD (fs_lit), A
        LD A, 7
        CALL set_border
        LD B, 0
        LD C, 18
        LD A, $7F               ; white paper, bright
        CALL fill_attr_rows
fs_text:
        ; texts appear once t passes 100 / 130 / 150
        LD A, (fs_txt)
        LD HL, fs_txt_t
        LD E, A
        LD D, 0
        ADD HL, DE
        LD A, (t_now)
        CP (HL)
        RET C
        LD A, E
        INC A
        LD (fs_txt), A
        DEC A
        JR Z, fs_t1
        DEC A
        JR Z, fs_t2
        DEC A
        RET NZ
        LD HL, txt_sub2
        LD DE, $070D
        JP print_str
fs_t1:
        LD HL, txt_title
        LD DE, $0E07            ; col 14, row 7
        JP print_str2
fs_t2:
        LD HL, txt_sub
        LD DE, $080B
        JP print_str

fs_txt:         DB 0
fs_txt_t:       DB 100, 130, 150, 255

;; --------------------------------------------
;; 2. fire rising
;; --------------------------------------------
init_fire:
        CALL scene_start
        CALL checker_fill
        CALL fire_clear
        LD A, 6
        LD (fire_r0), A
        LD A, 18
        LD (fire_nr), A
        LD A, high dec_tall
        LD C, high ramp_fire
        JP fire_setup

frm_fire:
        LD A, (t_now)
        LD C, $3F
        CP 40
        JR C, ff_int
        LD C, $7F
        CP 80
        JR C, ff_int
        LD C, $FF
ff_int:
        LD A, C
        LD (fire_int), A
        JP fire_step

;; --------------------------------------------
;; 3. logo burns in, lava band below
;; --------------------------------------------
init_burn:
        CALL scene_start
        CALL cls_bitmap
        CALL draw_logo
        LD B, 19
        CALL checker_rows
        CALL fire_clear
        LD A, 19
        LD (fire_r0), A
        LD A, 5
        LD (fire_nr), A
        LD A, $FF
        LD (fire_int), A
        LD A, high dec_band
        LD C, high ramp_fire
        JP fire_setup

frm_burn:
        CALL burn_frame
        LD B, $02
        LD C, 0
        CALL beat_border
        JP fire_step

;; --------------------------------------------
;; 4. logo melts in the heat
;; --------------------------------------------
init_melt:
        XOR A
        JP logo_attrs_from

frm_melt:
        CALL melt_frame
        LD B, $02
        LD C, 0
        CALL beat_border
        JP fire_step

;; --------------------------------------------
;; 5. lava plasma
;; --------------------------------------------
init_plasma:
        CALL scene_start
        CALL checker_fill
        LD A, high tile_fire
        LD (pl_pal), A
        RET

frm_plasma:
        JP plasma_frame

;; --------------------------------------------
;; 6. tunnel
;; --------------------------------------------
init_tunnel:
        CALL scene_start
        LD A, high ttex_fire
        LD (tun_tex), A
        LD A, 1
        LD (tun_speed), A
        RET

frm_tunnel:
        JP tunnel_frame

;; --------------------------------------------
;; 7. 3D dot rune over the lava
;; --------------------------------------------
init_dots:
        CALL scene_start
        CALL cls_bitmap
        LD B, 18
        LD C, 6
        CALL copy_buf_rows
        LD B, 18
        CALL ruins_patch
        LD HL, dots_attr
        LD DE, $5800
        LD BC, 18 * 32
        CALL s_copy8
        CALL attr_snapshot
        JP dots_clear_list

frm_dots:
        CALL dots_frame
        LD B, 18
        JP lava_shimmer

;; --------------------------------------------
;; 8. logo zoomer
;; --------------------------------------------
init_zoom:
        CALL scene_start
        JP checker_fill

frm_zoom:
        JP zoom_frame

;; --------------------------------------------
;; 9. ruins, sparks and the scroller
;; --------------------------------------------
init_ruins:
        CALL scene_start
        CALL cls_bitmap
        LD B, 11
        LD C, 13
        CALL copy_buf_rows
        LD B, 11
        CALL ruins_patch
        CALL scroll_init
        LD A, 48
        LD (sp_ymin), A
        LD A, 140
        LD (sp_ymax), A
        LD A, 16
        LD (sp_count), A
        CALL attr_snapshot
        JP sp_init

frm_ruins:
        CALL scroll_step
        CALL scroll_step
        CALL scroll_colors
        CALL sp_update
        LD B, 18
        JP lava_shimmer

;; --------------------------------------------
;; 10. twisted nail
;; --------------------------------------------
init_twister:
        CALL scene_start
        CALL cls_bitmap
        LD B, 18
        LD C, 6
        CALL copy_buf_rows
        LD B, 18
        CALL ruins_patch
        CALL twister_attrs
        JP attr_snapshot

frm_twister:
        CALL twister_frame
        LD B, $07
        LD C, 0
        CALL beat_border
        LD B, 18
        JP lava_shimmer

;; --------------------------------------------
;; 11. QUAD DAMAGE: blue cuts on every beat
;; --------------------------------------------
QK_TUN          EQU 0
QK_PLA          EQU 1
QK_FIRE         EQU 2
QK_ZOOM         EQU 3

qd_last:        DB $FF
qd_seq:         DB QK_TUN, QK_PLA, QK_FIRE, QK_ZOOM
                DB QK_TUN, QK_PLA, QK_FIRE, QK_TUN

init_quad:
        CALL scene_start
        CALL checker_fill
        LD A, $FF
        LD (qd_last), A
        LD A, high ttex_quad
        LD (tun_tex), A
        LD A, high tile_quad
        LD (pl_pal), A
        CALL fire_clear
        LD A, 6
        LD (fire_r0), A
        LD A, 18
        LD (fire_nr), A
        LD A, $FF
        LD (fire_int), A
        LD A, high dec_tall
        LD C, high ramp_quad
        JP fire_setup

frm_quad:
        LD B, $07
        LD C, $01
        CALL beat_border
        ; beat index
        LD A, (t_now)
        LD B, 0
qd_div:
        CP 24
        JR C, qd_divok
        SUB 24
        INC B
        JR qd_div
qd_divok:
        LD A, B
        LD HL, qd_last
        CP (HL)
        JR Z, qd_run
        LD (HL), A
        ; new cut: tunnel twice as fast in the second half
        AND 4
        RRCA
        RRCA
        INC A
        LD (tun_speed), A
        XOR A
        CALL fill_attrs
qd_run:
        LD A, (qd_last)
        LD HL, qd_seq
        ADD A, L
        LD L, A
        JR NC, qk_nc
        INC H
qk_nc:
        LD A, (HL)
        CP QK_TUN
        JP Z, tunnel_frame
        CP QK_PLA
        JP Z, plasma_frame
        CP QK_FIRE
        JP Z, fire_step
        JP zoom_frame

;; --------------------------------------------
;; 12. finale: the full picture, credits, fade out
;; --------------------------------------------
init_finale:
        CALL scene_start
        LD HL, SCRBUF
        LD DE, $4000
        LD BC, 6144
        CALL s_copy8
        LD A, 24
        LD (fin_row), A
        XOR A
        LD (fin_txt), A
        LD HL, SCRBUF + 6144
        JP attr_snap_from

fin_row:        DB 24
fin_txt:        DB 0

frm_finale:
        LD A, (t_now)
        CP 150
        JR NC, fin_fade
        ; reveal rows from the bottom: row r visible when t >= (23-r)*2
fin_rev:
        LD A, (fin_row)
        OR A
        JR Z, fin_shim
        DEC A
        LD B, A
        LD A, 23
        SUB B
        ADD A, A
        LD C, A
        LD A, (t_now)
        CP C
        JR C, fin_shim
        LD A, B
        LD (fin_row), A
        CALL sA
        CALL copy_attr_row
        CALL sB
        JR fin_rev
fin_shim:
        LD A, (t_now)
        CP 48
        RET C
        LD B, 18
        CALL lava_shimmer
        ; credits, printed once each
        LD A, (t_now)
        CP 60
        RET C
        LD A, (fin_txt)
        OR A
        JR NZ, fin_t2
        INC A
        LD (fin_txt), A
        LD A, $46
        LD B, 0
        LD C, 1
        CALL fill_attr_rows
        LD A, $42
        LD B, 23
        LD C, 1
        CALL fill_attr_rows
        LD HL, txt_end1
        LD DE, $0300
        JP print_str
fin_t2:
        DEC A
        RET NZ
        LD A, (t_now)
        CP 90
        RET C
        LD A, 2
        LD (fin_txt), A
        LD HL, txt_end2
        LD DE, $0617
        JP print_str
fin_fade:
        AND 7
        RET NZ
        JP fade_all

;; copy attributes of char row B from SCRBUF
copy_attr_row:
        LD L, B
        LD H, 0
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        ADD HL, HL
        LD DE, $5800
        ADD HL, DE
        PUSH HL
        LD DE, SCRBUF + 6144 - $5800
        ADD HL, DE
        POP DE
        LD BC, 32
        JP s_copy8

;; --------------------------------------------
;; 13. silence, then the demo loops
;; --------------------------------------------
init_silence:
        CALL scene_start
        JP cls_bitmap

frm_silence:
        RET
