; Video/sound chip demo for MINI09 (needs the Pico 6809 chip on J4).
; Load it with the shell's L command (paste vdpdemo.s19), then: G 1000
; Plays a tune timed by video frames, bounces a ball along row 4 of the
; HDMI screen for 240 frames, then reports how many 100 Hz ticks that
; took (about 400 if frames really arrive at 60 Hz).

            include "syscalls.inc"
            include "vdp.inc"

BALLROW     equ     4

            org     $1000
start:      ldb     #V_ID+VREG_RD
            OS      SYS_VREG
            lbcs    novdp
            cmpa    #VDP_IDV
            lbne    novdp
            ldx     #title
            jsr     print

; ---- tune: tone A through a decaying envelope, retriggered per note
            ldx     #sndinit
si1:        ldd     ,x++            ; A = value, B = register, $FF ends
            cmpb    #$FF
            beq     si2
            OS      SYS_SOUND
            bra     si1
si2:        ldy     #tune
tn1:        ldd     ,y++            ; tone period, 0 ends
            beq     tn3
            pshs    a
            tfr     b,a
            clrb                    ; register 0: fine period
            OS      SYS_SOUND
            puls    a
            ldb     #1              ; register 1: coarse period
            OS      SYS_SOUND
            ldd     #$000D          ; register 13 = 0: restart the decay
            OS      SYS_SOUND
            lda     ,y+             ; length in frames
            sta     count
tn2:        OS      SYS_VSYNC
            dec     count
            bne     tn2
            bra     tn1

; ---- bouncing ball, one step per frame
tn3:        OS      SYS_TIME
            std     t0
            lda     #1
            sta     ballx
            sta     balldx
            ldd     #240
            std     nframes
an1:        ldb     ballx           ; cells x-1 .. x+1 of the ball row
            decb
            lda     #2
            mul
            addd    #BALLROW*160
            std     blk+1
            clr     blk
            ldd     #cells
            std     blk+3
            ldd     #6
            std     blk+5
            ldx     #blk
            OS      SYS_VCOPY
            OS      SYS_VSYNC
            lda     ballx
            adda    balldx
            sta     ballx
            cmpa    #1
            beq     an2
            cmpa    #78
            bne     an3
an2:        neg     balldx
an3:        ldd     nframes
            subd    #1
            std     nframes
            bne     an1

            ldd     #$3F07          ; mixer: everything off
            OS      SYS_SOUND
            OS      SYS_TIME
            subd    t0
            pshs    d
            ldx     #msg_done1
            jsr     print
            puls    d
            jsr     printdec
            ldx     #msg_done2
            jsr     print
            OS      SYS_EXIT

novdp:      ldx     #msg_novdp
            jsr     print
            OS      SYS_EXIT

print:      lda     ,x+
            beq     pr1
            OS      SYS_PUTC
            bra     print
pr1:        rts

; D as unsigned decimal
printdec:   ldy     #pow10
            clr     started
pd1:        clr     digit
pd2:        cmpd    ,y
            blo     pd3
            subd    ,y
            inc     digit
            bra     pd2
pd3:        pshs    d
            lda     digit
            bne     pd4
            tst     started
            bne     pd4
            cmpy    #pow10+8        ; always print the last digit
            bne     pd5
pd4:        adda    #'0
            OS      SYS_PUTC
            inc     started
pd5:        puls    d
            leay    2,y
            cmpy    #pow10+10
            bne     pd1
            rts
pow10:      fdb     10000,1000,100,10,1

sndinit:    fcb     $3E,7           ; mixer: tone A only
            fcb     $10,8           ; A follows the envelope
            fcb     $00,11          ; envelope period $0800: ~0.25 s decay
            fcb     $08,12
            fcb     $00,$FF

; period (2 MHz / 16 / Hz), frames
tune:       fdb     239
            fcb     12              ; C5
            fdb     190
            fcb     12              ; E5
            fdb     159
            fcb     12              ; G5
            fdb     119
            fcb     24              ; C6
            fdb     159
            fcb     12              ; G5
            fdb     119
            fcb     36              ; C6
            fdb     0

cells:      fcb     $20,$07,'O,$0E,$20,$07  ; space, yellow O, space

title:      fcb     ESC
            fcc     "[2J"
            fcb     ESC
            fcc     "[H"
            fcb     ESC
            fcc     "[1;33mMINI09"
            fcb     ESC
            fcc     "[0;36m on the Pico 6809 video chip"
            fcb     ESC
            fcc     "[0m"
            fcb     CR,LF
            fcc     "A tune, then a ball for 240 frames..."
            fcb     CR,LF,0
msg_done1:  fcb     ESC
            fcc     "[7;1H240 frames took "
            fcb     0
msg_done2:  fcc     " ticks (about 400 at 60 Hz)"
            fcb     CR,LF,0
msg_novdp:  fcc     "No video chip"
            fcb     CR,LF,0

count:      rmb     1
ballx:      rmb     1
balldx:     rmb     1
nframes:    rmb     2
t0:         rmb     2
blk:        rmb     7
started:    rmb     1
digit:      rmb     1

            end     start
