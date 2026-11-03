;; ============================================
;; Continuous beeper engine
;;
;; The speaker is driven by "steps": short routines called from every
;; loop of the program, one call every SLOT_T (224) T-states, alternating
;; sA (channel 1: bass / kick) and sB (channel 2: lead / noise drums).
;; Each step advances a 16-bit phase accumulator and outputs the square
;; wave (phase high byte compared with a duty value = volume/timbre).
;; The speaker never waits for the effects: no 50 Hz chopping.
;;
;; Register contract for ALL main-thread code:
;;   alternate set (BC', DE', HL') and AF' belong to the steps,
;;   IY counts steps (read and cleared by the interrupt),
;;   steps preserve everything else, including flags.
;; Phases: HL' = channel 1, BC' = channel 2, DE' = noise pointer (ROM).
;;
;; The interrupt only counts the frame and redirects the next sA call
;; to tick_entry, which runs the music tick (rows, envelopes, arpeggio,
;; vibrato, drums, patching the steps) in the main thread with steps
;; inside, so even the tick does not interrupt the sound. It also measures steps per frame and rescales the
;; increments, so the pitch stays right when loops run slower
;; (e.g. contended memory on a real 48K).
;;
;; Music rows (6 frames each): bass, lead, drums|arp
;;   note byte: 0 = hold, 1 = off, 2..127 = MIDI note, $FF = end
;;   drums: bit0 kick, bit1 snare, bit2 hat, bit3 crash
;;   bits 4-5: lead arpeggio (1 minor, 2 major, 3 power chord)
;; ============================================

SLOT_T          EQU 224         ; T-states between two steps
SLOT_W          EQU 95          ; work T-states per slot (SLOT_T - step)
STEPS_NOM       EQU 312         ; 69888 / SLOT_T

ROW_FRAMES      EQU 6
BASS_DUTY       EQU 110
BASS_MIN        EQU 64
LEAD_DUTY       EQU 104
LEAD_MIN        EQU 48
ARP_DUTY        EQU 52
VIB_DELAY       EQU 10

;; --------------------------------------------
;; the steps: 129 T each including the CALL
;; --------------------------------------------
sA:
        JP sA_body              ; 10, patched to tick_entry by the interrupt
sA_body:
        EX AF, AF'              ; 4
        EXX                     ; 4
        LD A, L                 ; 4
sA_il:  ADD A, 0                ; 7
        LD L, A                 ; 4
        LD A, H                 ; 4
sA_ih:  ADC A, 0                ; 7
        LD H, A                 ; 4
sA_d:   CP 0                    ; 7
        SBC A, A                ; 4
        AND $10                 ; 7
sA_b:   OR 0                    ; 7
        OUT ($FE), A            ; 11
        EXX                     ; 4
        INC IY                  ; 10
        EX AF, AF'              ; 4
        RET                     ; 10

sB:
        JP sB_tone              ; 10, patched to sB_noise for drums
sB_tone:
        EX AF, AF'
        EXX
        LD A, C
sB_il:  ADD A, 0
        LD C, A
        LD A, B
sB_ih:  ADC A, 0
        LD B, A
sB_d:   CP 0
        SBC A, A
        AND $10
sB_b:   OR 0
        OUT ($FE), A
        EXX
        INC IY
        EX AF, AF'
        RET
sB_noise:
        EX AF, AF'              ; 4
        EXX                     ; 4
        INC DE                  ; 6
        RES 6, D                ; 8  stay inside the ROM
        LD A, (DE)              ; 7
sBn_d:  CP 0                    ; 7
        SBC A, A                ; 4
        AND $10                 ; 7
sBn_b:  OR 0                    ; 7
        OUT ($FE), A            ; 11
        EXX                     ; 4
        INC IY                  ; 10
        EX AF, AF'              ; 4
        JP sBn_ret              ; 10
sBn_ret:
        RET                     ; 10

;; --------------------------------------------
;; border colour A (patched into the steps)
;; --------------------------------------------
set_border:
        LD (border), A
        LD (sA_b + 1), A
        LD (sB_b + 1), A
        LD (sBn_b + 1), A
        OUT ($FE), A
        RET

;; --------------------------------------------
;; wait for the next frame while the steps keep playing
;; --------------------------------------------
snd_idle:
        LD A, (frames)
        LD (si_cmp + 1), A
si_loop:
        LD A, (frames)          ; 13 (+10 jp below)
si_cmp: CP 0                    ; 7
        RET NZ                  ; 5
        LD B, 4                 ; 7
si_w1:  DJNZ si_w1              ; 47
        NOP                     ; 4  = 93
        CALL sA
        LD B, 7                 ; 7
si_w2:  DJNZ si_w2              ; 86 = 93
        CALL sB
        JP si_loop

;; --------------------------------------------
;; variables
;; --------------------------------------------
snd_on:         DB 0
mus_ptr:        DW music_rows
mus_tick:       DB 1
b_inc:          DW 0
b_duty:         DB 0
l_inc:          DW 0
l_duty:         DB 0
l_note:         DB 0
l_arp:          DB 0
l_age:          DB 0
arp_i:          DB 0
kick_cnt:       DB 0
noise_vol:      DB 0
noise_dec:      DB 0
steps_avg:      DW STEPS_NOM * 4
adapt_m:        DB 0            ; signed: increment scale = 1 + m/256

snd_init:
        LD HL, music_rows
        LD (mus_ptr), HL
        LD A, 1
        LD (mus_tick), A
        XOR A
        LD (b_duty), A
        LD (l_duty), A
        LD (kick_cnt), A
        LD (noise_vol), A
        LD (sA_d + 1), A
        LD (sB_d + 1), A
        LD (sBn_d + 1), A
        RET

;; A = MIDI note -> DE = nominal phase increment
note_inc:
        PUSH HL
        ADD A, A
        LD L, A
        LD H, high freq_tab
        LD E, (HL)
        INC L
        LD D, (HL)
        POP HL
        RET

;; --------------------------------------------
;; entered instead of sA once per frame (patched by the interrupt)
;; --------------------------------------------
tick_pending:   DB 0

tick_entry:
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        PUSH IX
te_loop:
        CALL snd_tick
        ; done? (atomic against the interrupt re-arming the tick)
        DI
        LD HL, tick_pending
        DEC (HL)
        JR NZ, te_more
        LD HL, sA_body
        LD (sA + 1), HL
        EI
        POP IX
        POP HL
        POP DE
        POP BC
        POP AF
        JP sA_body              ; the step the caller asked for
te_more:
        EI
        JR te_loop

;; --------------------------------------------
;; music tick (main thread, called via tick_entry)
;; --------------------------------------------
snd_tick:
        ; ---- steps per frame -> pitch correction
        PUSH IY
        POP DE
        LD IY, 0
        LD A, (snd_on)
        OR A
        RET Z
        CALL sA_body
        CALL sB
        ; steps_avg = steps_avg * 3/4 + steps (kept *4)
        LD HL, (steps_avg)
        LD B, H
        LD C, L
        SRL B
        RR C
        SRL B
        RR C
        OR A
        SBC HL, BC
        ADD HL, DE
        LD (steps_avg), HL
        SRL H
        RR L
        SRL H
        RR L                    ; HL = average steps per frame
        LD DE, 220
        OR A
        SBC HL, DE
        JR NC, st_lo_ok
        LD HL, 0
st_lo_ok:
        LD A, H
        OR A
        JR NZ, st_hi
        LD A, L
        CP 120
        JR C, st_idx
st_hi:
        LD A, 119
st_idx:
        LD L, A
        LD H, high adapt_tab
        LD A, (HL)
        LD (adapt_m), A
        CALL sA_body
        CALL sB

        ; ---- music rows
        LD HL, mus_tick
        DEC (HL)
        JP NZ, st_env
        LD (HL), ROW_FRAMES
        LD HL, (mus_ptr)
        LD A, (HL)
        CP $FF
        JR NZ, st_row
        XOR A
        LD (b_duty), A
        LD (l_duty), A
        JP st_env
st_row:
        INC HL
        OR A
        JR Z, st_bass_done
        DEC A
        JR NZ, st_bass_on
        LD (b_duty), A
        JR st_bass_done
st_bass_on:
        INC A
        CALL note_inc
        LD (b_inc), DE
        LD A, BASS_DUTY
        LD (b_duty), A
st_bass_done:
        LD A, (HL)
        INC HL
        OR A
        JR Z, st_lead_done
        DEC A
        JR NZ, st_lead_on
        LD (l_duty), A
        JR st_lead_done
st_lead_on:
        INC A
        LD (l_note), A
        XOR A
        LD (l_age), A
        LD (arp_i), A
        LD A, (HL)
        RRCA
        RRCA
        RRCA
        RRCA
        AND 3
        LD (l_arp), A
        LD A, LEAD_DUTY
        JR Z, st_lead_duty
        LD A, ARP_DUTY
st_lead_duty:
        LD (l_duty), A
st_lead_done:
        LD A, (HL)
        INC HL
        LD (mus_ptr), HL
        LD C, A
        BIT 0, C
        JR Z, st_no_kick
        LD A, 4
        LD (kick_cnt), A
st_no_kick:
        BIT 3, C
        JR Z, st_no_crash
        LD A, 100
        LD B, 6
        JR st_set_noise
st_no_crash:
        BIT 1, C
        JR Z, st_no_snare
        LD A, 110
        LD B, 36
        JR st_set_noise
st_no_snare:
        BIT 2, C
        JR Z, st_env
        LD A, 60
        LD B, 60
st_set_noise:
        LD (noise_vol), A
        LD A, B
        LD (noise_dec), A

st_env:
        CALL sA_body
        CALL sB
        LD A, (b_duty)
        CP BASS_MIN + 1
        JR C, st_benv
        SUB 2
        LD (b_duty), A
st_benv:
        LD A, (l_arp)
        OR A
        JR NZ, st_lenv
        LD A, (l_duty)
        CP LEAD_MIN + 1
        JR C, st_lenv
        SUB 2
        LD (l_duty), A
st_lenv:
        CALL lead_pitch
        CALL sA_body
        CALL sB

        ; ---- channel 1: kick sweep or bass
        LD A, (kick_cnt)
        OR A
        JR Z, st_bass
        DEC A
        LD (kick_cnt), A
        INC A
        ADD A, A
        LD HL, kick_tab
        ADD A, L
        LD L, A
        JR NC, st_k1
        INC H
st_k1:
        LD E, (HL)
        INC HL
        LD D, (HL)
        LD A, 100
        JR st_ch1
st_bass:
        LD DE, (b_inc)
        LD A, (b_duty)
st_ch1:
        LD (sA_d + 1), A
        CALL scale_inc
        LD A, E
        LD (sA_il + 1), A
        LD A, D
        LD (sA_ih + 1), A
        CALL sA_body
        CALL sB

        ; ---- channel 2: noise drum or lead
        LD A, (noise_vol)
        OR A
        JR Z, st_lead
        LD (sBn_d + 1), A
        LD HL, sB_noise
        LD (sB + 1), HL
        LD B, A
        LD A, (noise_dec)
        LD C, A
        LD A, B
        SUB C
        JR NC, st_nv
        XOR A
st_nv:
        LD (noise_vol), A
        RET
st_lead:
        LD HL, sB_tone
        LD (sB + 1), HL
        LD A, (l_duty)
        LD (sB_d + 1), A
        LD DE, (l_inc)
        CALL scale_inc
        LD A, E
        LD (sB_il + 1), A
        LD A, D
        LD (sB_ih + 1), A
        RET

;; DE = DE * (1 + adapt_m / 256), adapt_m signed
scale_inc:
        LD A, (adapt_m)
        OR A
        RET Z
        PUSH AF
        JP P, sc_pos
        NEG
sc_pos:
        LD B, 8
        LD HL, 0
        LD C, A
sc_mul:
        ADD HL, HL
        RL C
        JR NC, sc_noadd
        ADD HL, DE
sc_noadd:
        DJNZ sc_mul
        LD L, H
        LD H, 0
        POP AF
        JP P, sc_add
        EX DE, HL
        OR A
        SBC HL, DE
        EX DE, HL
        RET
sc_add:
        ADD HL, DE
        EX DE, HL
        RET

;; lead pitch for this frame: arpeggio step or vibrato -> l_inc
lead_pitch:
        LD A, (l_duty)
        OR A
        RET Z
        LD A, (l_arp)
        OR A
        JR Z, lp_plain
        LD C, A
        ADD A, A
        ADD A, C
        LD C, A
        LD A, (arp_i)
        INC A
        CP 3
        JR C, lp_ai
        XOR A
lp_ai:
        LD (arp_i), A
        ADD A, C
        LD C, A
        LD B, 0
        LD HL, arp_offs - 3
        ADD HL, BC
        LD A, (l_note)
        ADD A, (HL)
        CALL note_inc
        LD (l_inc), DE
        RET
lp_plain:
        LD A, (l_note)
        CALL note_inc
        LD A, (l_age)
        CP VIB_DELAY
        JR C, lp_young
        LD H, D
        LD L, E
        LD B, 7
lp_shr:
        SRL H
        RR L
        DJNZ lp_shr
        LD A, (frames)
        AND 4
        EX DE, HL
        JR Z, lp_down
        ADD HL, DE
        JR lp_set
lp_down:
        OR A
        SBC HL, DE
lp_set:
        EX DE, HL
        LD (l_inc), DE
        RET
lp_young:
        INC A
        LD (l_age), A
        LD (l_inc), DE
        RET

arp_offs:       DB 0, 3, 7              ; minor
                DB 0, 4, 7              ; major
                DB 0, 7, 12             ; power
