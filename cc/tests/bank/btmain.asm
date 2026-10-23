; Banked-code runtime test, common part: calls into two banks (btb1.asm,
; btb2.asm), nested, recursive, through a pointer, a long result, and a
; banked function that reads a file.  Prints one line per test.
            section code
            export  _main
            import  _f1,_f2,_fact1,_lng2,_rdf1,_putchar
_main:      pshs    u
            tfr     s,u
            ldd     #5              ; f1(5) = 3*5 + f2(5) + f3() = 127
            pshs    d
            jsr     _f1
            leas    2,s
            bsr     hex4
            ldd     #6              ; fact1(6), alternating banks = 720
            pshs    d
            jsr     _fact1
            leas    2,s
            bsr     hex4
            jsr     _lng2           ; a long: $12345678 in X:D
            pshs    d
            tfr     x,d
            bsr     hexd
            puls    d
            bsr     hex4
            ldx     #_f2            ; through a pointer: f2(1) = 101
            ldd     #1
            pshs    d
            jsr     ,x
            leas    2,s
            bsr     hex4
            jsr     _rdf1           ; the file's first character
            bsr     hex4
            ldd     #0
            leas    ,u
            puls    u,pc

; D in hex, then a new line
hex4:       bsr     hexd
            ldd     #10
            pshs    d
            jsr     _putchar
            leas    2,s
            rts
hexd:       pshs    d
            bsr     hexb
            puls    d
            tfr     b,a
hexb:       pshs    a
            lsra
            lsra
            lsra
            lsra
            bsr     hexn
            puls    a
hexn:       anda    #$0F
            adda    #'0
            cmpa    #'9
            bls     hn1
            adda    #7
hn1:        tfr     a,b
            clra
            pshs    d
            jsr     _putchar
            leas    2,s
            rts
            endsection
