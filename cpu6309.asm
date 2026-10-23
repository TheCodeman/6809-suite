; HD63C09E(P) CPU test for MINI09.
; Load with the shell's L command (paste cpu6309.s19), then: G 1000
;
; Checks that the CPU is a 6309 and that its extra instructions work in the
; power-up (emulation) mode the kernel uses, then divides by zero to show the
; 6309 trap: the kernel should kill this task and print a trap message.

            include "syscalls.inc"

            org     $1000
start:      ldx     #msg_title
            lbsr    puts

; ---- 1. 6309 or 6809?  $10 $43 is COMD on a 6309, COMA on a 6809 ----------
            ldx     #t_detect
            lbsr    puts
            ldd     #$00FF
            fdb     $1043           ; COMD: $FF00, or COMA: $FFFF
            tstb
            lbne    is6809
            lbsr    pass

; ---- 2. LDQ / STQ, W ----------------------------------------------------
            ldx     #t_ldq
            lbsr    puts
            ldq     #$12345678
            stq     scratch
            cmpd    #$1234
            lbne    fail
            cmpw    #$5678
            lbne    fail
            ldd     scratch+2
            cmpd    #$5678
            lbne    fail
            lbsr    pass

; ---- 3. E and F ------------------------------------------------------------
            ldx     #t_ef
            lbsr    puts
            lde     #$5A
            ldf     #$A5
            cmpw    #$5AA5
            lbne    fail
            lbsr    pass

; ---- 4. MULD: signed 16 x 16 -> Q ------------------------------------------
            ldx     #t_muld
            lbsr    puts
            ldd     #300
            muld    #-7             ; -2100 = $FFFFF7CC
            cmpd    #$FFFF
            lbne    fail
            cmpw    #$F7CC
            lbne    fail
            lbsr    pass

; ---- 5. DIVD: D / 8 bit -> B quotient, A remainder -------------------------
            ldx     #t_divd
            lbsr    puts
            ldd     #500
            divd    #7              ; 71 rem 3
            cmpb    #71
            lbne    fail
            cmpa    #3
            lbne    fail
            lbsr    pass

; ---- 6. DIVQ: Q / 16 bit -> W quotient, D remainder ------------------------
            ldx     #t_divq
            lbsr    puts
            ldq     #100000
            divq    #300            ; 333 rem 100
            cmpw    #333
            lbne    fail
            cmpd    #100
            lbne    fail
            lbsr    pass

; ---- 7. TFM block move -----------------------------------------------------
            ldx     #t_tfm
            lbsr    puts
            ldx     #pattern
            ldy     #scratch
            ldw     #16
            tfm     x+,y+
            tstw                    ; W counts down to 0
            lbne    fail
            ldx     #pattern
            ldy     #scratch
            ldb     #16
tf1:        lda     ,x+
            cmpa    ,y+
            lbne    fail
            decb
            bne     tf1
            lbsr    pass

; ---- 8. Register-to-register ALU (ADDR, CMPR) --------------------------------
            ldx     #t_addr
            lbsr    puts
            ldx     #$1000
            ldy     #$0234
            addr    y,x             ; X = X + Y = $1234
            ldd     #$1234
            cmpr    d,x
            lbne    fail
            lbsr    pass

            ldx     #msg_allok
            lbsr    puts

; ---- 9. Division by zero -> 6309 trap --------------------------------------
            ldx     #t_trap
            lbsr    puts
            ldd     #1
            divd    #0              ; traps through $FFF0; never returns
            ldx     #msg_notrap     ; only reached if there was no trap
            lbsr    puts
            OS      SYS_EXIT

; ---------------------------------------------------------------------------
is6809:     ldx     #msg_6809
            lbsr    puts
            OS      SYS_EXIT

pass:       ldx     #msg_ok
            bra     puts
fail:       ldx     #msg_fail
            lbsr    puts
            OS      SYS_EXIT

puts:       lda     ,x+
            beq     ps9
            OS      SYS_PUTC
            bra     puts
ps9:        rts

msg_title:  fcc     "HD63C09E CPU test"
            fcb     CR,LF,0
t_detect:   fcn     "6309 detect (COMD)....... "
t_ldq:      fcn     "LDQ / STQ / W............ "
t_ef:       fcn     "E and F registers........ "
t_muld:     fcn     "MULD..................... "
t_divd:     fcn     "DIVD..................... "
t_divq:     fcn     "DIVQ..................... "
t_tfm:      fcn     "TFM block move........... "
t_addr:     fcn     "ADDR / CMPR.............. "
t_trap:     fcc     "Divide by zero: expect a trap message, this task is killed"
            fcb     CR,LF,0
msg_ok:     fcc     "ok"
            fcb     CR,LF,0
msg_fail:   fcc     "FAIL"
            fcb     CR,LF,0
msg_allok:  fcc     "All 6309 instruction tests passed"
            fcb     CR,LF,0
msg_6809:   fcc     "no: this CPU is a 6809, not a 6309"
            fcb     CR,LF,0
msg_notrap: fcc     "FAIL: divide by zero did not trap"
            fcb     CR,LF,0
pattern:    fcc     "6309 TFM test!!!"
scratch:    rmb     16

            end     start
