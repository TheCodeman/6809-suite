; ----------------------------------------------------------------------
;  16-bit helpers for what the 6809 can't do in one instruction.
;  Left operand in X, right in D, result in D.  Keep Y and U.
; ----------------------------------------------------------------------

            export  __mul,__divs,__divu,__mods,__modu
            export  __shl,__shrs,__shru

; D = X * D (the low 16 bits; the same for signed and unsigned)
__mul:      pshs    d,x             ; 0,s rhs hi, 1,s rhs lo, 2,s lhs hi, 3,s lhs lo
            lda     3,s             ; lo * lo, B is still rhs lo
            mul
            pshs    d               ; the product; the operands move up 2
            lda     5,s             ; + (lhs lo * rhs hi) << 8
            ldb     2,s
            mul
            addb    ,s
            stb     ,s
            lda     4,s             ; + (lhs hi * rhs lo) << 8
            ldb     3,s
            mul
            addb    ,s
            stb     ,s
            puls    d
            leas    4,s
            rts

; Unsigned X / D -> D = quotient, X = remainder.  Dividing by 0 gives
; $FFFF and X back.
udiv:       pshs    d,x             ; 0,s divisor, 2,s dividend -> quotient
            ldb     #16
            pshs    b               ; 0,s count, 1,s divisor, 3,s dividend
            clra                    ; D = remainder
            clrb
ud1:        lsl     4,s             ; remainder:dividend <<= 1
            rol     3,s
            rolb
            rola
            bcs     ud2             ; over 16 bits: bigger than the divisor
            cmpd    1,s
            blo     ud3
ud2:        subd    1,s
            inc     4,s             ; quotient bit (the lsl left a 0)
ud3:        dec     ,s
            bne     ud1
            tfr     d,x
            ldd     3,s
            leas    5,s
            rts

; Signed X / D -> D = quotient, X = remainder.  C rules: the quotient
; rounds towards 0, the remainder has the dividend's sign.
sdiv:       pshs    d               ; 2,s divisor
            tfr     x,d
            eora    ,s
            pshs    a               ; 1,s bit 7: negate the quotient
            tfr     x,d
            pshs    a               ; 0,s bit 7: negate the remainder
            tsta
            bpl     sd1
            nega
            negb
            sbca    #0
sd1:        tfr     d,x
            ldd     2,s
            bpl     sd2
            nega
            negb
            sbca    #0
sd2:        bsr     udiv
            tst     1,s
            bpl     sd3
            nega
            negb
            sbca    #0
sd3:        exg     d,x
            tst     ,s
            bpl     sd4
            nega
            negb
            sbca    #0
sd4:        exg     d,x
            leas    4,s
            rts

__divu:     bra     udiv
__modu:     bsr     udiv
            tfr     x,d
            rts
__divs:     bra     sdiv
__mods:     bsr     sdiv
            tfr     x,d
            rts

; D = X << D.  A count of 16 or more gives 0.
__shl:      exg     d,x             ; D = value, X = count
            cmpx    #16
            bhs     shz
            leax    ,x
            beq     sh9
shl1:       lslb
            rola
            leax    -1,x
            bne     shl1
sh9:        rts
shz:        clra
            clrb
            rts

; D = X >> D, unsigned.  16 or more gives 0.
__shru:     exg     d,x
            cmpx    #16
            bhs     shz
            leax    ,x
            beq     sh9
shru1:      lsra
            rorb
            leax    -1,x
            bne     shru1
            rts

; D = X >> D, signed.  16 or more gives 0 or -1.
__shrs:     exg     d,x
            cmpx    #16
            blo     shrs0
            ldx     #15
shrs0:      leax    ,x
            beq     sh9
shrs1:      asra
            rorb
            leax    -1,x
            bne     shrs1
            rts
