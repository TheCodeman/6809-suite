; Banked-code runtime test: bank one.  The stubs are in common memory.
            section code
            export  _f1,_fact1,_rdf1
            import  __bcall,__bank
_f1:        jsr     __bcall
            fcb     __bank
            fdb     B_f1
_fact1:     jsr     __bcall
            fcb     __bank
            fdb     B_fact1
_rdf1:      jsr     __bcall
            fcb     __bank
            fdb     B_rdf1
            endsection

            section strings         ; strings stay in common memory
s_name:     fcn     "BT.TXT"
s_r:        fcn     "r"
s_hi:       fcn     "in bank one"
            endsection

            section banked
            import  _f2,_fact2,_fopen,_fgetc,_fclose,_puts,__mul
; int f1(int x): 3x + f2(x) + f3()
B_f1:       pshs    u
            tfr     s,u
            ldd     4,u
            addd    4,u
            addd    4,u
            pshs    d
            ldd     4,u
            pshs    d
            jsr     _f2             ; in bank two
            leas    2,s
            addd    ,s++
            pshs    d
            jsr     B_f3            ; the same bank: a direct call
            addd    ,s++
            leas    ,u
            puls    u,pc
B_f3:       ldd     #7
            rts
; int fact1(int n): n ? n * fact2(n - 1) : 1
B_fact1:    pshs    u
            tfr     s,u
            ldd     4,u
            bne     fa1
            ldd     #1
            bra     fa9
fa1:        subd    #1
            pshs    d
            jsr     _fact2
            leas    2,s
            ldx     4,u
            jsr     __mul
fa9:        leas    ,u
            puls    u,pc
; int rdf1(void): says where it is, returns BT.TXT's first character
B_rdf1:     pshs    u
            tfr     s,u
            ldx     #s_hi
            pshs    x
            jsr     _puts
            leas    2,s
            ldx     #s_r
            pshs    x
            ldx     #s_name
            pshs    x
            jsr     _fopen
            leas    4,s
            pshs    d
            jsr     _fgetc
            puls    x
            pshs    d
            pshs    x
            jsr     _fclose
            leas    2,s
            puls    d
            leas    ,u
            puls    u,pc
            rmb     9000            ; too big to share a page with bank two
            endsection
