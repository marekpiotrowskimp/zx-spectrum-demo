;; ============================================
;; zxQ - ZX Spectrum 48K demo
;; ~46 s, 12 scenes of 192 frames (3.84 s) with continuous beeper music
;; Assemble with pasmo: pasmo --bin src/main.asm build/zxQ_demo.bin
;;
;; Sound contract (see sound.asm): every loop calls the steps sA / sB
;; every 224 T; AF', BC', DE', HL' and IY belong to the sound engine.
;; ============================================

;; ---- memory map ----------------------------
;; $4000-$5AFF  screen
;; $5B00-$75FF  copy of the loading screen (finale picture)
;; $7600-$769F  particles
;; $7700-$78DF  3D dots erase list
;; $7900-$7BFF  attribute snapshot (lava shimmer source)
;; $8000-$F6FF  code + data
;; $F700-$F97F  fire buffer (32 x 20)
;; $FA00-$FAFF  plasma / zoom work tables
;; $FD00-$FDFC  stack
;; $FDFD        JP isr
;; $FE00-$FF00  IM2 vector table (257 x $FD)

SCRBUF          EQU $5B00
PARTS           EQU $7600
DOTSOLD         EQU $7700
ATTRSNAP        EQU $7900
FIREBUF         EQU $F700
WORKBUF         EQU $FA00
IM2JP           EQU $FDFD
IM2TAB          EQU $FE00
STACKTOP        EQU $FDFD

SCENE_LEN       EQU 192
N_SCENES        EQU 13

        ORG $8000

start:
        DI
        LD SP, STACKTOP

        ; keep the loading screen for the finale
        LD HL, $4000
        LD DE, SCRBUF
        LD BC, 6912
        LDIR

        ; IM2 table: 257 bytes of $FD -> vector $FDFD on any bus value
        LD HL, IM2TAB
        LD DE, IM2TAB + 1
        LD BC, 256
        LD (HL), $FD
        LDIR
        LD A, $C3                       ; JP isr
        LD (IM2JP), A
        LD HL, isr
        LD (IM2JP + 1), HL
        LD A, high IM2TAB
        LD I, A
        IM 2

        ; sound registers: phases and noise pointer
        EXX
        LD HL, 0
        LD BC, 0
        LD DE, $0500
        EXX
        LD IY, 0

        CALL snd_init
        XOR A
        CALL set_border
        EI

        ; fade the loading screen out (music not running yet)
        LD B, 7
fade_in_loop:
        PUSH BC
        HALT
        HALT
        HALT
        CALL fade_all
        POP BC
        DJNZ fade_in_loop

restart:
        DI
        LD HL, 0
        LD (frames), HL
        XOR A
        LD (scene_no), A
        LD (scene_t), A
        LD A, $FF
        LD (cur_scene), A
        CALL snd_init
        LD A, 1
        LD (snd_on), A
        EI

main_loop:
idle_halt:
        CALL snd_idle           ; steps keep playing until the next frame
        LD A, (scene_no)
        LD HL, cur_scene
        CP (HL)
        JR Z, ml_same
        LD (HL), A
        CP N_SCENES
        JR NC, restart
        LD HL, init_tab
        CALL call_tab
ml_same:
        CALL sA
        LD A, (scene_t)
        LD (t_now), A
        LD A, (cur_scene)
        LD HL, frame_tab
        CALL call_tab
        CALL sB
        JR main_loop

;; call routine number A from word table HL
call_tab:
        ADD A, A
        ADD A, L
        LD L, A
        JR NC, ct_nc
        INC H
ct_nc:
        LD A, (HL)
        INC HL
        LD H, (HL)
        LD L, A
        JP (HL)

;; ============================================
;; Interrupt: frame counters, then the next sA call runs the music
;; tick. Must not touch AF', the alternate registers or IY.
;; ============================================
isr:
        PUSH AF
        PUSH HL

        LD HL, (frames)
        INC HL
        LD (frames), HL
        LD A, (scene_t)
        INC A
        CP SCENE_LEN
        JR C, isr_t
        LD HL, scene_no
        INC (HL)
        XOR A
isr_t:
        LD (scene_t), A

        ; run the music tick at the next sA call (main thread)
        LD HL, tick_pending
        INC (HL)
        LD HL, tick_entry
        LD (sA + 1), HL

        POP HL
        POP AF
        EI
        RET

;; ============================================
;; Global variables
;; ============================================
frames:         DW 0
scene_no:       DB 0
scene_t:        DB 0
cur_scene:      DB $FF
t_now:          DB 0
border:         DB 0
pad_dummy:      DB 0

        INCLUDE "src/scenes.asm"
        INCLUDE "src/util.asm"
        INCLUDE "src/sound.asm"
        INCLUDE "src/sparks.asm"
        INCLUDE "src/fx_attr.asm"
        INCLUDE "src/fx_bitmap.asm"
        INCLUDE "src/texts.asm"
        INCLUDE "src/gen/fx_loops.asm"
        INCLUDE "src/gen/music.asm"
        INCLUDE "src/gen/tables.asm"

code_end:
