; Expressions: precedence, parentheses, unary operators, every base
            org     $1000
start:      ldd     #2*(16+1)
            ldx     #-(1)
            ldy     #(($1234))
            ldu     #((3+4)*(5-2))/(1+1)
            lda     #(start+$10)&$FF
            ldb     #-(-(7))
            ldd     #~($00FF)
            ldx     #(100/(3+4))%(5)
            ldy     #($F0F0|$0F00)^($FFFF&$00FF)
            ldu     #(%1010+@17)*('A'-'@')
            leax    (tab+2-start),x
            leay    -(tab-start),y
            fdb     2*(16+1),-(1),(start),(end-start)
            fdb     ((((1+2)*3)+4)*5)
            fcb     (3),-(3),(1+1)*(2+2)
tab:        fdb     (tab-start)/(2)
            lda     <(tab&$FF)
            ldb     >($1000+(2*3))
end:        rts
            end     start
