; ----------------------------------------------------------------------
;  string.h.  C calling convention: arguments at 2,s up, the result in
;  D, keep Y and U.
; ----------------------------------------------------------------------

            export  _strlen,_strcpy,_strcat,_strcmp,_strncmp
            export  _strchr,_strrchr
            export  _memcpy,_memmove,_memset,_memcmp

; size_t strlen(char *s)
_strlen:    ldx     2,s
            ldd     #0
sl1:        tst     ,x+
            beq     sl9
            addd    #1
            bra     sl1
sl9:        rts

; char *strcpy(char *d, char *s)
_strcpy:    pshs    u
            ldu     4,s
            ldx     6,s
sc1:        lda     ,x+
            sta     ,u+
            bne     sc1
            ldd     4,s
            puls    u,pc

; char *strcat(char *d, char *s)
_strcat:    pshs    u
            ldu     4,s
sa1:        tst     ,u+
            bne     sa1
            leau    -1,u
            ldx     6,s
            bra     sc1

; int strcmp(char *a, char *b): the difference of the first unequal
; bytes, as unsigned chars
_strcmp:    pshs    u
            ldu     4,s
            ldx     6,s
scm1:       ldb     ,u+
            cmpb    ,x+
            bne     scm8
            tstb
            bne     scm1
            clra
            puls    u,pc
scm8:       clra                    ; D = *a - *b
            subb    -1,x
            sbca    #0
            puls    u,pc

; int strncmp(char *a, char *b, size_t n)
_strncmp:   pshs    y,u
            ldu     6,s
            ldx     8,s
            ldy     10,s
            beq     snc0
snc1:       ldb     ,u+
            cmpb    ,x+
            bne     snc8
            tstb
            beq     snc0
            leay    -1,y
            bne     snc1
snc0:       clra
            clrb
            puls    y,u,pc
snc8:       clra
            subb    -1,x
            sbca    #0
            puls    y,u,pc

; char *strchr(char *s, int c): the first c, or NULL.  c = 0 finds the
; end.
_strchr:    ldx     2,s
            ldb     5,s
sch1:       cmpb    ,x
            beq     sch8
            tst     ,x+
            bne     sch1
            ldd     #0
            rts
sch8:       tfr     x,d
            rts

; char *strrchr(char *s, int c): the last c, or NULL
_strrchr:   ldx     2,s
            ldd     #0
            pshs    d               ; the last one found
            ldb     7,s
src1:       cmpb    ,x
            bne     src2
            stx     ,s
src2:       tst     ,x+
            bne     src1
            puls    d,pc

; void *memcpy(void *d, void *s, size_t n)
_memcpy:    pshs    y,u
            ldu     6,s
            ldx     8,s
            ldy     10,s
            beq     mc9
mc1:        lda     ,x+
            sta     ,u+
            leay    -1,y
            bne     mc1
mc9:        ldd     6,s
            puls    y,u,pc

; void *memmove(void *d, void *s, size_t n): copies backwards when d is
; above s
_memmove:   ldd     2,s
            cmpd    4,s
            bls     _memcpy
            pshs    y,u
            ldu     6,s
            ldx     8,s
            ldd     10,s
            beq     mc9
            leau    d,u             ; from the ends
            leax    d,x
            tfr     d,y
mm1:        lda     ,-x
            sta     ,-u
            leay    -1,y
            bne     mm1
            bra     mc9

; void *memset(void *d, int c, size_t n)
_memset:    pshs    y
            ldx     4,s
            ldy     8,s
            beq     ms9
            ldb     7,s
ms1:        stb     ,x+
            leay    -1,y
            bne     ms1
ms9:        ldd     4,s
            puls    y,pc

; int memcmp(void *a, void *b, size_t n)
_memcmp:    pshs    y,u
            ldu     6,s
            ldx     8,s
            ldy     10,s
            lbeq    snc0
mcm1:       ldb     ,u+
            cmpb    ,x+
            lbne    snc8
            leay    -1,y
            bne     mcm1
            lbra    snc0
