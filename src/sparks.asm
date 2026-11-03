;; ============================================
;; Sparks: XOR plotted particles rising from the lava
;; particle = x, y, speed, phase (4 bytes) at PARTS
;; the per-particle loop (sparks_loop) is generated with sound steps
;; ============================================

N_SPARKS        EQU 40

sp_ymin:        DB 8
sp_ymax:        DB 156
sp_count:       DB N_SPARKS

;; XOR a 1x2 pixel spark at D = x, E = y (keeps D, E)
xor_spark:
        LD L, E
        LD H, high line_lo
        LD A, (HL)
        INC H
        LD H, (HL)
        LD L, A
        LD A, D
        RRCA
        RRCA
        RRCA
        AND 31
        ADD A, L
        LD L, A
        LD A, D
        AND 7
        ADD A, low pix_mask
        LD C, A
        LD B, high pix_mask
        LD A, (BC)
        LD C, A
        XOR (HL)
        LD (HL), A
        INC H                   ; next line inside the char cell?
        LD A, H
        AND 7
        JR Z, xs_cross
        LD A, C
        XOR (HL)
        LD (HL), A
        RET
xs_cross:
        LD A, E
        INC A
        CALL line_addr
        LD A, D
        RRCA
        RRCA
        RRCA
        AND 31
        ADD A, L
        LD L, A
        LD A, C
        XOR (HL)
        LD (HL), A
        RET

        IF ($ & 7) != 0
        DS 8 - ($ & 7)
        ENDIF
pix_mask:       DB $80, $40, $20, $10, $08, $04, $02, $01

;; sparks_loop helper: the spark's second line is in the next char row
;; -> HL = screen address of line E+1, column D/8 (keeps C, D, E)
xs_fix:
        LD A, E
        INC A
        CALL line_addr
        LD A, D
        RRCA
        RRCA
        RRCA
        AND 31
        ADD A, L
        LD L, A
        RET

;; respawn particle at IX near the bottom
sp_spawn:
        CALL rnd
        LD (IX+0), A
        LD A, (sp_ymax)
        LD (IX+1), A
        CALL rnd
        AND 3
        INC A
        LD (IX+2), A
        CALL rnd
        LD (IX+3), A
        RET

;; called from sparks_loop when a particle leaves the top: A = new y
sp_respawn:
        PUSH HL
        CALL sp_spawn
        POP HL
        LD A, (IX+1)
        RET

;; spread particles over the whole range and draw them
sp_init:
        LD IX, PARTS
        LD A, (sp_count)
        LD B, A
spi_loop:
        PUSH BC
        CALL sA
        CALL sp_spawn
        LD A, (sp_ymax)
        LD HL, sp_ymin
        SUB (HL)
        LD C, A
        CALL rnd
spi_mod:
        CP C
        JR C, spi_ok
        SUB C
        JR spi_mod
spi_ok:
        ADD A, (HL)
        LD (IX+1), A
        LD D, (IX+0)
        LD E, A
        CALL xor_spark
        LD DE, 4
        ADD IX, DE
        CALL sB
        POP BC
        DJNZ spi_loop
        RET

;; erase, move and redraw all particles
sp_update:
        LD IX, PARTS
        LD A, (sp_count)
        LD B, A
        JP sparks_loop
