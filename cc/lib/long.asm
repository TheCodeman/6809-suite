; ----------------------------------------------------------------------
;  32-bit helpers.  A long is in X:D (X the high word).  For the binary
;  operators the left operand is on the stack, high word first (pushed
;  with pshs d then pshs x), so it is at 2,s (high) and 4,s (low) when
;  the helper starts.  The right operand is in X:D, or D for a shift
;  count.  The result is in X:D.  The caller pops the left (leas 4,s).
;  Keep Y and U.
; ----------------------------------------------------------------------

            export  __ladd,__lsub,__land,__lor,__lxor,__lneg
            export  __lmul,__ldivs,__ldivu,__lmods,__lmodu
            export  __lshl,__lshrs,__lshru,__lcmp,__lcmpu,__sext

__ladd:     addd    4,s
            exg     d,x             ; exg keeps the carry
            adcb    3,s
            adca    2,s
            exg     d,x
            rts

; left - right
__lsub:     pshs    d,x             ; 0,s right lo, 2,s right hi, 6,s left
            ldd     8,s
            subd    ,s
            std     ,s
            ldd     6,s             ; ldd keeps the borrow
            sbcb    3,s
            sbca    2,s
            tfr     d,x
            puls    d
            leas    2,s
            rts

__land:     anda    4,s
            andb    5,s
            exg     d,x
            anda    2,s
            andb    3,s
            exg     d,x
            rts

__lor:      ora     4,s
            orb     5,s
            exg     d,x
            ora     2,s
            orb     3,s
            exg     d,x
            rts

__lxor:     eora    4,s
            eorb    5,s
            exg     d,x
            eora    2,s
            eorb    3,s
            exg     d,x
            rts

; X:D = -X:D
__lneg:     coma
            comb
            exg     d,x
            coma
            comb
            exg     d,x
            addd    #1
            exg     d,x
            adcb    #0
            adca    #0
            exg     d,x
            rts

; X * D -> X:D, unsigned 16 x 16 = 32
umul16:     pshs    d,x
            leas    -4,s            ; 0-3,s product, 4,s b hi, 5,s b lo,
            lda     7,s             ; 6,s a hi, 7,s a lo
            ldb     5,s
            mul
            std     2,s
            lda     6,s
            ldb     4,s
            mul
            std     ,s
            lda     7,s             ; the two middle products, at 1,s
            ldb     4,s
            mul
            addd    1,s
            std     1,s
            bcc     um1
            inc     ,s
um1:        lda     6,s
            ldb     5,s
            mul
            addd    1,s
            std     1,s
            bcc     um2
            inc     ,s
um2:        ldx     ,s
            ldd     2,s
            leas    8,s
            rts

; left * right, the low 32 bits
__lmul:     pshs    d,x             ; 0,s b lo, 2,s b hi, 6,s a hi, 8,s a lo
            ldx     8,s
            bsr     umul16          ; a lo * b lo (D is still b lo)
            pshs    d,x             ; 0,s lo, 2,s hi; b lo 4,s, b hi 6,s,
            ldx     10,s            ; a hi 10,s, a lo 12,s
            ldd     4,s
            lbsr    __mul           ; + (a hi * b lo) << 16
            addd    2,s
            std     2,s
            ldx     12,s
            ldd     6,s
            lbsr    __mul           ; + (a lo * b hi) << 16
            addd    2,s
            tfr     d,x
            puls    d
            leas    6,s
            rts

; Division.  The work area, at 0,u:
;   0  dividend, becomes the quotient     8  remainder
;   4  divisor                           12  0 = quotient, 1 = remainder
;  13  signs: bit 7 negate the quotient, bit 6 the remainder
; After pshs u and leas -14,s the left operand is at 18,s and 20,s.
LDFRAME     equ     14

__ldivu:    pshs    u
            ldu     #$0000          ; the mode word for 12,u and 13,u
            bra     ldent
__lmodu:    pshs    u
            ldu     #$0100
            bra     ldent
__ldivs:    pshs    u
            ldu     #$00FF          ; $FF: signed, worked out by ldsign
            bra     ldent
__lmods:    pshs    u
            ldu     #$01FF
ldent:      pshs    u
            leas    -12,s
            tfr     s,u
            stx     4,u
            std     6,u
            ldd     LDFRAME+4,u
            std     ,u
            ldd     LDFRAME+6,u
            std     2,u
            tst     13,u
            beq     ld4
            bsr     ldsign
ld4:        bsr     udiv32
            leax    ,u
            lda     13,u
            tst     12,u
            beq     ld5
            leax    8,u
            lsla                    ; bit 6 -> bit 7
ld5:        tsta
            bpl     ld6
            bsr     neg32
ld6:        ldd     2,x
            ldx     ,x
            leas    LDFRAME,s
            puls    u,pc

; Make the dividend and divisor positive; set the sign bits.
ldsign:     clr     13,u
            lda     ,u
            bpl     ls1
            lda     #$C0
            sta     13,u
            leax    ,u
            bsr     neg32
ls1:        lda     4,u
            bpl     ls2
            lda     13,u
            eora    #$80
            sta     13,u
            leax    4,u
            bsr     neg32
ls2:        rts

; Negate the long at X.
neg32:      ldd     #0
            subd    2,x
            std     2,x
            ldd     #0              ; ldd keeps the borrow
            sbcb    1,x
            sbca    ,x
            std     ,x
            rts

; Unsigned 32-bit divide of the work area at U.  Dividing by 0 gives
; $FFFFFFFF and the dividend as the remainder.
udiv32:     ldb     #32
            pshs    b
            ldd     #0
            std     8,u
            std     10,u
dv1:        lsl     3,u
            rol     2,u
            rol     1,u
            rol     ,u
            rol     11,u
            rol     10,u
            rol     9,u
            rol     8,u
            bcs     dv2             ; over 32 bits: bigger than the divisor
            ldd     8,u
            cmpd    4,u
            bhi     dv2
            blo     dv3
            ldd     10,u
            cmpd    6,u
            blo     dv3
dv2:        ldd     10,u
            subd    6,u
            std     10,u
            ldd     8,u
            sbcb    5,u
            sbca    4,u
            std     8,u
            inc     3,u
dv3:        dec     ,s
            bne     dv1
            leas    1,s
            rts

; left << D.  A count of 32 or more gives 0.
__lshl:     cmpd    #32
            bhs     lsz
            ldx     2,s
            pshs    b               ; count; the left moves to 3,s and 5,s
            ldd     5,s
            tst     ,s
            beq     lsx
lsl1:       lslb
            rola
            exg     d,x
            rolb
            rola
            exg     d,x
            dec     ,s
            bne     lsl1
lsx:        leas    1,s
            rts
lsz:        ldx     #0
            ldd     #0
            rts

; left >> D, unsigned.
__lshru:    cmpd    #32
            bhs     lsz
            ldx     2,s
            pshs    b
            ldd     5,s
            tst     ,s
            beq     lsx
lsr1:       exg     d,x
            lsra
            rorb
            exg     d,x
            rora
            rorb
            dec     ,s
            bne     lsr1
            bra     lsx

; left >> D, signed.  32 or more gives 0 or -1.
__lshrs:    cmpd    #32
            blo     lsa0
            ldb     #31
lsa0:       ldx     2,s
            pshs    b
            ldd     5,s
            tst     ,s
            beq     lsx
lsa1:       exg     d,x
            asra
            rorb
            exg     d,x
            rora
            rorb
            dec     ,s
            bne     lsa1
            bra     lsx

; Compare left with right: D = -1, 0 or 1, and the flags set from it, so
; the caller can branch straight after the call (blt, beq, bgt ...).
__lcmp:     pshs    d,x             ; 0,s right lo, 2,s right hi, 6,s left
            ldd     6,s
            cmpd    2,s
            bne     lc1
            ldd     8,s
            cmpd    ,s
            beq     lceq
            blo     lclt
            bra     lcgt
lc1:        blt     lclt
lcgt:       ldd     #1
            bra     lcx
lclt:       ldd     #-1
            bra     lcx
lceq:       ldd     #0
lcx:        leas    4,s             ; leas keeps the flags
            rts

__lcmpu:    pshs    d,x
            ldd     6,s
            cmpd    2,s
            beq     lcu1
            blo     lclt
            bra     lcgt
lcu1:       ldd     8,s
            cmpd    ,s
            beq     lceq
            blo     lclt
            bra     lcgt

; X:D = D sign-extended to 32 bits; D is kept
__sext:     ldx     #0
            tsta
            bpl     sx1
            leax    -1,x
sx1:        rts
