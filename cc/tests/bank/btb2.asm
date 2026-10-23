; Banked-code runtime test: bank two
            section code
            export  _f2,_fact2,_lng2
            import  __bcall,__bank
_f2:        jsr     __bcall
            fcb     __bank
            fdb     B_f2
_fact2:     jsr     __bcall
            fcb     __bank
            fdb     B_fact2
_lng2:      jsr     __bcall
            fcb     __bank
            fdb     B_lng2
            endsection

            section banked
            import  _fact1,__mul
B_f2:       ldd     2,s             ; int f2(int x): x + 100
            addd    #100
            rts
B_fact2:    pshs    u               ; int fact2(int n): n ? n * fact1(n - 1) : 1
            tfr     s,u
            ldd     4,u
            bne     fb1
            ldd     #1
            bra     fb9
fb1:        subd    #1
            pshs    d
            jsr     _fact1
            leas    2,s
            ldx     4,u
            jsr     __mul
fb9:        leas    ,u
            puls    u,pc
B_lng2:     ldx     #$1234          ; long lng2(void)
            ldd     #$5678
            rts
            rmb     9000
            endsection
