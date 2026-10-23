; ----------------------------------------------------------------------
;  LINK - links lwasm object files (LWOBJ16, from ASM or lwasm) into a
;  MINI09 program file, the way lwlink does with tools/mini09.ld
;
;     LINK OUT.PRG MAIN.O LIB.O ...
;
;  Sections are placed from $1000: every "init", then every "code",
;  then the others that aren't bss, in the order the files have them,
;  all of one name together, then the bss ones.  s_NAME and l_NAME are
;  the start and length of section NAME.  The entry is __start if a file
;  exports it, else $1000.  Started without arguments it asks for them.
;
;  Banked code (cc/cc.md): each file's section "banked" goes into a 16K
;  RAM page at $8000-$BFFF instead, packed first fit from page FIRSTBANK
;  in file order.  In that file, the import __bank is its page; __nbank
;  is the number of pages.  The pages follow the normal part of the
;  .PRG (after the header's file size): "B9", the count, then for each
;  page its number, length (2) and bytes.  Each is built in turn in the
;  image's $8000-$BFFF, which the normal part doesn't use.
;
;  Memory:
;     $1000-       this program, its tables and buffers
;     $8000-$BFFF  banked window:
;                  pages OUTPG..OUTPG+3  the image (the 64K address space)
;                  pages OBJPG..LASTPG   the object files, each read once
; ----------------------------------------------------------------------

            include "syscalls.inc"
            include "vdp.inc"

DEFPAGE     equ     2               ; a task's page at $8000 when it starts
OUTPG       equ     3               ; image, 4 pages
OBJPG       equ     7               ; object files
LASTPG      equ     31
WIN         equ     $8000           ; banked window
WINEND      equ     $C000
LINEMAX     equ     63              ; typed names
PHLEN       equ     36              ; program file header
LOADADR     equ     $1000           ; where the first section goes
NAMEMAX     equ     63              ; longest symbol or section name kept
MAXFILE     equ     16
FNSZ        equ     32              ; a file name, NUL included
MAXINST     equ     64              ; sections, counting each file's own
FIRSTBANK   equ     7               ; the first page for banked code
MAXBANK     equ     16
BANKSZ      equ     $4000
STKSZ       equ     16              ; expression stack (words)

; A file: name, then where it is (page, address)
FI_PG       equ     FNSZ
FI_AD       equ     FNSZ+1
FISZ        equ     FNSZ+3

; A section of a file.  Far pointers are page, address.
SI_FILE     equ     0               ; file number (0..)
SI_NAME     equ     1               ; -> name
SI_FLG      equ     4               ; 1 bss, 2 constant
SI_LOC      equ     5               ; -> local symbols
SI_EXP      equ     8               ; -> exported symbols
SI_REL      equ     11              ; -> relocations
SI_CODE     equ     14              ; -> the bytes
SI_SIZE     equ     17
SI_ADDR     equ     19              ; where it is linked
SI_DONE     equ     21              ; placed
SI_PAGE     equ     22              ; banked: its page, else 0
SISZ        equ     23

            org     $1000
start:      lds     #stktop
            lda     #$FF
            sta     curbank
            ldx     #msg_hello
            jsr     puts
            clr     nfiles
            clr     ninst
            clr     nbank
            clr     buildpg
            ldd     #0
            std     errors
            ldd     ARGS            ; the shell's arguments, if the shell left any
            cmpd    #ARGMARK
            bne     st0
            ldd     #0              ; used up
            std     ARGS
            ldx     #ARGS+2
            jsr     skipsp
            tst     ,x
            beq     st0
            ldu     #lbuf
            jsr     strcpy
            bra     st0a
st0:        ldx     #msg_ask        ; none: ask
            jsr     puts
            jsr     readline
st0a:       jsr     parseargs
            lda     #OBJPG          ; read the objects
            sta     cpage
            ldx     #WIN
            stx     cptr
            clr     curfile
st1:        lda     curfile
            cmpa    nfiles
            bhs     st2
            jsr     fileent
            stx     fpname
            jsr     loadfile
            lbcs    ferror
            jsr     parsefile
            inc     curfile
            bra     st1
st2:        jsr     place           ; where each section goes
            jsr     clrimage
            jsr     copycode        ; the bytes into the image
            jsr     relocate        ; and the linker's fields
            clr     bcur            ; each bank too, for its errors
st2a:       lda     bcur
            cmpa    nbank
            bhs     st2b
            jsr     buildbank
            inc     bcur
            bra     st2a
st2b:       clr     buildpg
            ldx     #s_start        ; the entry
            ldu     #symbuf
            jsr     strcpy
            clr     curfile
            jsr     extsym
            bcc     st3
            ldd     #LOADADR
st3:        std     entry
            ldd     errors
            beq     st4
            jsr     putdec          ; "N error(s)", no program file
            ldx     #msg_errors
            jsr     puts
            jmp     quit
st4:        ldx     #outname
            stx     fpname
            jsr     writeprg
            lbcs    ferror
            ldb     nfiles          ; "N objects, N bytes: NAME.PRG"
            clra
            jsr     putdec
            ldx     #msg_objs
            jsr     puts
            ldd     #0
            tst     anyout
            beq     st5
            ldd     hi
            subd    lo
            addd    #1
st5:        jsr     putdec
            ldx     #msg_bytes
            jsr     puts
            ldx     #outname
            jsr     puts
            ldb     nbank           ; ", N banks"
            beq     st6
            ldx     #s_comma
            jsr     puts
            clra
            jsr     putdec
            ldx     #msg_banks
            jsr     puts
st6:        jsr     crlf
quit:       ldb     #DEFPAGE
            jsr     setbank
            OS      SYS_EXIT

; B = page for $8000-$BFFF.  Skips the call when it is already there.
; Keeps A, B, X, Y, U.
setbank:    cmpb    curbank
            beq     sb9
            stb     curbank
            pshs    a
            OS      SYS_BANK
            puls    a
sb9:        rts

; ----------------------------------------------------------------------
;  Arguments: lbuf = "OUT.PRG A.O B.O ..." -> outname, the file table
; ----------------------------------------------------------------------

parseargs:  ldx     #lbuf
            jsr     skipsp
            tst     ,x
            lbeq    quit
            ldu     #outname
            ldb     #LINEMAX
            bsr     word
pa1:        jsr     skipsp
            tst     ,x
            beq     pa9
            lda     nfiles
            cmpa    #MAXFILE
            lbhs    fat_files
            jsr     fileent
            tfr     x,u
            ldx     tmp
            ldb     #FNSZ-1
            bsr     word
            inc     nfiles
            bra     pa1
pa9:        tst     nfiles
            bne     pa10
            ldx     #msg_usage
            jsr     puts
            jmp     quit
pa10:       rts

; The word at X -> U, upper case, at most B characters, X past it.
; Keeps tmp = X after it.
word:       lda     ,x
            beq     wd9
            cmpa    #$20
            beq     wd9
            cmpa    #9
            beq     wd9
            leax    1,x
            tstb
            beq     word
            jsr     upper
            sta     ,u+
            decb
            bra     word
wd9:        clr     ,u
            stx     tmp
            rts

; File A (0..) -> X.  Keeps D.  (parseargs: with A = nfiles, X saved)
fileent:    pshs    d
            stx     tmp
            ldb     #FISZ
            mul
            addd    #files
            tfr     d,x
            puls    d,pc

; ----------------------------------------------------------------------
;  Far bytes: fpg/fad walk the object files across pages
; ----------------------------------------------------------------------

; Next byte -> A (flags set by it).  Keeps B, X, Y, U.
rdb:        pshs    b,x
            ldb     fpg
            jsr     setbank
            ldx     fad
            lda     ,x+
            cmpx    #WINEND
            blo     rdb1
            inc     fpg
            ldx     #WIN
rdb1:       stx     fad
            tsta
            puls    b,x,pc

; Next two bytes -> D
rdw:        bsr     rdb
            tfr     a,b
            bsr     rdb
            exg     a,b
            rts

; Past the rest of a string (to its NUL)
rds:        bsr     rdb
            bne     rds
            rts

; Forward D bytes
fadv:       addd    fad
            pshs    d
fadv1:      ldd     ,s
            cmpd    #WINEND
            blo     fadv2
            subd    #WINEND-WIN
            std     ,s
            inc     fpg
            bra     fadv1
fadv2:      std     fad
            puls    d,pc

; fpg/fad -> 3 bytes at X, or back.  Keep every register.
fsave:      pshs    a,u
            lda     fpg
            sta     ,x
            ldu     fad
            stu     1,x
            puls    a,u,pc
fload:      pshs    a,u
            lda     ,x
            sta     fpg
            ldu     1,x
            stu     fad
            puls    a,u,pc

; The far string here -> U (low memory, NAMEMAX kept)
fcopy:      pshs    b
            ldb     #NAMEMAX
fc1:        jsr     rdb
            beq     fc2
            tstb
            beq     fc1
            sta     ,u+
            decb
            bra     fc1
fc2:        clr     ,u
            puls    b,pc

; The far string here the same as the string at Y?  Z set if so.  Goes
; past it either way.  Keeps Y.
fcmp:       pshs    y
            clr     ,-s             ; 0: the same so far
fcm1:       jsr     rdb
            cmpa    ,y
            beq     fcm2
            inc     ,s
fcm2:       tsta
            beq     fcm3
            tst     ,y
            beq     fcm4
            leay    1,y
            bra     fcm1
fcm4:       inc     ,s              ; Y ended first
            jsr     rds
fcm3:       tst     ,s+
            puls    y,pc

; ----------------------------------------------------------------------
;  Reading an object file: each section -> the section table
; ----------------------------------------------------------------------

; The file just loaded (srcpg/srcptr)
parsefile:  lda     srcpg
            sta     fpg
            ldx     srcptr
            stx     fad
            ldy     #s_lwobj        ; "LWOBJ16", 0
            jsr     fcmp
            lbne    fat_notobj
pf1:        ldx     #tfp            ; a section, or the 0 at the end
            jsr     fsave
            jsr     rdb
            lbeq    pf9
            lda     ninst
            cmpa    #MAXINST
            lbhs    fat_sects
            ldb     #SISZ
            mul
            addd    #insts
            tfr     d,y             ; Y -> the new entry
            inc     ninst
            lda     curfile
            sta     SI_FILE,y
            lda     tfp             ; its name
            sta     SI_NAME,y
            ldd     tfp+1
            std     SI_NAME+1,y
            jsr     rds
            clr     SI_FLG,y        ; flags
            clr     SI_DONE,y
pf2:        jsr     rdb
            beq     pf3
            ora     SI_FLG,y
            sta     SI_FLG,y
            bra     pf2
pf3:        leax    SI_LOC,y        ; local symbols
            jsr     fsave
            bsr     skipsyms
            leax    SI_EXP,y        ; exports
            jsr     fsave
            bsr     skipsyms
            leax    SI_REL,y        ; relocations
            jsr     fsave
pf4:        jsr     rdb             ; a relocation: terms, 0, offset
            beq     pf6
pf5:        bsr     skipterm
            jsr     rdb
            bne     pf5
            jsr     rdw
            bra     pf4
pf6:        jsr     rdw             ; the bytes
            std     SI_SIZE,y
            leax    SI_CODE,y
            jsr     fsave
            lda     SI_FLG,y
            anda    #3
            bne     pf1
            ldd     SI_SIZE,y
            jsr     fadv
            bra     pf1
pf9:        rts

; Past a list of symbols: name, 0, value, ..., 0
skipsyms:   jsr     rdb
            beq     ss9
            jsr     rds
            jsr     rdw
            bra     skipsyms
ss9:        rts

; Past the rest of the term whose type is in A
skipterm:   cmpa    #1
            bne     sk1
            jmp     rdw
sk1:        cmpa    #2
            beq     sk2
            cmpa    #3
            bne     sk3
sk2:        jmp     rds
sk3:        jmp     rdb             ; 4 operator, $FF flag: one byte

; ----------------------------------------------------------------------
;  Placing the sections
; ----------------------------------------------------------------------

place:      jsr     bankplace
            ldd     #LOADADR
            std     laddr
            ldy     #s_init         ; init, code
            jsr     placename
            ldy     #s_code
            jsr     placename
            clr     tmp2            ; the rest that aren't bss
            bsr     placerest
            lda     #1              ; then the bss ones
            sta     tmp2
; Each section not placed yet whose bss flag is tmp2, with all of its
; name, in file order
placerest:  ldy     #insts
            ldb     ninst
            beq     pr9
pr1:        tst     SI_DONE,y
            bne     pr2
            lda     SI_FLG,y
            bita    #2              ; constant: not placed
            bne     pr2
            anda    #1
            cmpa    tmp2
            bne     pr2
            pshs    b,y
            leax    SI_NAME,y       ; its name -> nbuf
            jsr     fload
            ldu     #nbuf
            jsr     fcopy
            ldy     #nbuf
            lbsr    placename
            puls    b,y
pr2:        leay    SISZ,y
            decb
            bne     pr1
pr9:        tst     nbank           ; with banks, the rest must end
            beq     pr10            ; below the window
            ldd     laddr
            cmpd    #WIN
            lbhi    fat_big
pr10:       rts

; The "banked" sections: each to a page at $8000, first fit, in file
; order -> SI_PAGE and SI_ADDR, bused (bytes used in each), nbank
bankplace:  ldy     #insts
            ldb     ninst
            beq     bp9
bp1:        clr     SI_PAGE,y
            pshs    b
            leax    SI_NAME,y
            jsr     fload
            pshs    y
            ldy     #s_banked
            jsr     fcmp
            puls    y
            bne     bp8
            inc     SI_DONE,y       ; not placed with the rest
            ldd     SI_SIZE,y
            beq     bp8
            cmpd    #BANKSZ
            lbhi    fat_bank
            clr     tmp3            ; the first page with room
bp2:        lda     tmp3
            cmpa    nbank
            bhs     bp4
            lsla
            ldx     #bused
            leax    a,x
            ldd     ,x
            addd    SI_SIZE,y
            cmpd    #BANKSZ
            bls     bp5
            inc     tmp3
            bra     bp2
bp4:        cmpa    #MAXBANK        ; a new page
            lbhs    fat_banks
            inc     nbank
            lsla
            ldx     #bused
            leax    a,x
            ldd     #0
            std     ,x
bp5:        ldd     ,x              ; at $8000 + what it holds already
            addd    #WIN
            std     SI_ADDR,y
            ldd     ,x
            addd    SI_SIZE,y
            std     ,x
            lda     tmp3
            adda    #FIRSTBANK
            sta     SI_PAGE,y
bp8:        puls    b
            leay    SISZ,y
            decb
            bne     bp1
bp9:        rts

; Bank A (0..) into the image's $8000-$BFFF: cleared, then its sections'
; bytes and relocations
buildbank:  adda    #FIRSTBANK
            sta     buildpg
            ldb     #OUTPG+2
            jsr     setbank
            ldx     #WIN
            ldy     #0
bb1:        sty     ,x++
            cmpx    #WINEND
            blo     bb1
            jsr     copycode
            jmp     relocate

; Every section named as at Y, not placed yet, at laddr on
placename:  ldx     #insts
            ldb     ninst
            beq     pn9
pn1:        tst     SI_DONE,x
            bne     pn2
            lda     SI_FLG,x
            bita    #2
            bne     pn2
            pshs    x
            leax    SI_NAME,x
            jsr     fload
            puls    x
            jsr     fcmp
            bne     pn2
            ldu     laddr
            stu     SI_ADDR,x
            pshs    d
            tfr     u,d
            addd    SI_SIZE,x
            std     laddr
            puls    d
            inc     SI_DONE,x
pn2:        leax    SISZ,x
            decb
            bne     pn1
pn9:        rts

; ----------------------------------------------------------------------
;  The image
; ----------------------------------------------------------------------

; Clear it
clrimage:   ldb     #OUTPG
ci1:        jsr     setbank
            ldx     #WIN
            ldy     #0
ci2:        sty     ,x++
            cmpx    #WINEND
            blo     ci2
            incb
            cmpb    #OUTPG+4
            blo     ci1
            clr     anyout
            rts

; Each placed section's bytes to its address; lo and hi written
copycode:   ldy     #insts
            ldb     ninst
            beq     cc9
cc1:        pshs    b
            lda     SI_PAGE,y       ; the common part, or one bank
            cmpa    buildpg
            bne     cc4
            lda     SI_FLG,y
            anda    #3
            bne     cc4
            ldd     SI_SIZE,y
            beq     cc4
            std     wleft
            ldd     SI_ADDR,y
            std     waddr
            tst     buildpg         ; banks aren't in lo..hi
            bne     cc2b
            tst     anyout          ; lo and hi
            bne     cc2
            inc     anyout
            std     lo
            std     hi
cc2:        cmpd    lo
            bhs     cc2a
            std     lo
cc2a:       addd    wleft
            subd    #1
            cmpd    hi
            bls     cc2b
            std     hi
cc2b:       leax    SI_CODE,y
            jsr     fload
cc3:        jsr     rdb             ; byte by byte
            ldx     waddr
            pshs    a
            tfr     x,d
            jsr     flpage
            puls    a
            sta     ,u
            leax    1,x
            stx     waddr
            ldd     wleft
            subd    #1
            std     wleft
            bne     cc3
cc4:        puls    b
            leay    SISZ,y
            decb
            bne     cc1
cc9:        rts

; D = address -> its image page mapped, U -> it in the window.  Keeps D.
flpage:     pshs    d
            lsra
            lsra
            lsra
            lsra
            lsra
            lsra
            adda    #OUTPG
            tfr     a,b
            jsr     setbank
            ldd     ,s
            anda    #$3F
            ora     #$80
            tfr     d,u
            puls    d,pc

; ----------------------------------------------------------------------
;  Relocations: each expression worked out and put in the image
; ----------------------------------------------------------------------

relocate:   ldy     #insts
            clr     cursi
rl1:        lda     cursi
            cmpa    ninst
            bhs     rl9
            sty     sip
            lda     SI_FILE,y
            sta     curfile
            lda     SI_PAGE,y       ; the common part, or one bank
            cmpa    buildpg
            bne     rl8
            lda     SI_FLG,y
            anda    #3
            bne     rl8
            leax    SI_REL,y
            jsr     fload
rl2:        ldx     #estk           ; a relocation: its terms
            stx     esp
            clr     r8bit
            jsr     rdb
            beq     rl8             ; no more
rl3:        bsr     term
            jsr     rdb
            bne     rl3
            ldy     sip             ; the offset
            jsr     rdw
            addd    SI_ADDR,y
            std     waddr
            jsr     pop             ; the value
            tst     r8bit
            bne     rl6
            pshs    d               ; 16 bits (maybe across a page)
            ldd     waddr
            jsr     flpage
            lda     ,s
            sta     ,u
            ldd     waddr
            addd    #1
            jsr     flpage
            lda     1,s
            sta     ,u
            puls    d
            bra     rl2
rl6:        pshs    b               ; 8 bits
            ldd     waddr
            jsr     flpage
            puls    b
            stb     ,u
            bra     rl2
rl8:        ldy     sip
            leay    SISZ,y
            inc     cursi
            lbra    rl1
rl9:        rts

; One term of type A
term:       cmpa    #1              ; a number
            bne     tm2
            jsr     rdw
            jmp     push
tm2:        cmpa    #2              ; an external symbol
            bne     tm3
            bsr     tsym
            jsr     extsym
            bra     tm3a
tm3:        cmpa    #3              ; a local symbol
            bne     tm4
            bsr     tsym
            jsr     locsym
tm3a:       ldx     #rfp            ; back to the relocation
            jsr     fload
            lbcs    undef
            jmp     push
tm4:        cmpa    #4              ; an operator
            bne     tm5
            jsr     rdb
            jmp     oper
tm5:        jsr     rdb             ; $FF 1: 8 bits
            cmpa    #1
            bne     tm9
            inc     r8bit
tm9:        rts

; The symbol's name -> symbuf, and where the relocation goes on -> rfp
tsym:       ldu     #symbuf
            jsr     fcopy
            ldx     #rfp
            jmp     fsave

; D -> the expression stack
push:       ldx     esp
            cmpx    #estk+STKSZ*2
            lbhs    fat_cplx
            std     ,x++
            stx     esp
            rts
; The expression stack -> D
pop:        ldx     esp
            cmpx    #estk
            lbls    fat_cplx
            ldd     ,--x
            stx     esp
            rts

; Operator A
oper:       cmpa    #12             ; unary: -, ~, ~ in 8 bits
            blo     op2
            sta     tmp2
            bsr     pop
            std     ma
            lda     tmp2
            cmpa    #12
            bne     op1
            ldd     #0              ; -
            subd    ma
            bra     push
op1:        ldd     ma
            coma
            comb
            pshs    a
            lda     tmp2
            cmpa    #13
            puls    a
            beq     push
            clra                    ; 8 bits
            bra     push
op2:        sta     tmp2            ; binary: left op right
            bsr     pop
            std     mb
            bsr     pop
            std     ma
            lda     tmp2
            cmpa    #1
            bne     op3
            ldd     ma
            addd    mb
            lbra    push
op3:        cmpa    #2
            bne     op4
            ldd     ma
            subd    mb
            lbra    push
op4:        cmpa    #3
            bne     op5
            jsr     mul16
            lbra    push
op5:        cmpa    #4
            beq     op5a
            cmpa    #6
            bne     op6
op5a:       jsr     div16
            lbra    push
op6:        cmpa    #5
            bne     op7
            jsr     div16
            ldd     mrem
            lbra    push
op7:        cmpa    #7
            bne     op8
            ldd     ma
            anda    mb
            andb    mb+1
            lbra    push
op8:        cmpa    #8
            bne     op9
            ldd     ma
            ora     mb
            orb     mb+1
            lbra    push
op9:        cmpa    #9
            bne     op10
            ldd     ma
            eora    mb
            eorb    mb+1
            lbra    push
op10:       cmpa    #10             ; && and ||
            bne     op11
            ldd     ma
            beq     opf
            ldd     mb
            beq     opf
opt:        ldd     #1
            lbra    push
op11:       cmpa    #11
            lbne    fat_cplx
            ldd     ma
            bne     opt
            ldd     mb
            bne     opt
opf:        ldd     #0
            lbra    push

; ----------------------------------------------------------------------
;  Symbols
; ----------------------------------------------------------------------

; The external symbol in symbuf -> D, carry set if there isn't one.
; __nbank and __bank (curfile's page), s_NAME and l_NAME first, then
; curfile's exports, then every file's.
extsym:     ldx     #symbuf
            ldy     #s_nbank
            jsr     strcmp
            bne     ex1
            ldb     nbank
            clra
            rts                     ; (carry clear from the compare)
ex1:        ldx     #symbuf
            ldy     #s_bank
            jsr     strcmp
            bne     ex3
            ldy     #insts          ; curfile's banked page
            ldb     ninst
            beq     ex2b
ex2:        lda     SI_FILE,y
            cmpa    curfile
            bne     ex2a
            lda     SI_PAGE,y
            beq     ex2a
            tfr     a,b
            clra
            andcc   #$FE
            rts
ex2a:       leay    SISZ,y
            decb
            bne     ex2
ex2b:       orcc    #$01
            rts
ex3:        lda     symbuf+1
            cmpa    #'_
            bne     es2
            lda     symbuf
            cmpa    #'s
            beq     es1
            cmpa    #'l
            bne     es2
es1:        jsr     synsym
            bcc     es9
es2:        lda     curfile         ; this file first
            bsr     filexp
            bcc     es9
            clr     tmp3            ; then all, in order
es3:        lda     tmp3
            cmpa    nfiles
            bhs     es8
            bsr     filexp
            bcc     es9
            inc     tmp3
            bra     es3
es8:        orcc    #$01
es9:        rts

; The exports of file A: symbuf -> D, carry set if not there
filexp:     sta     tmp4
            ldy     #insts
            lda     ninst
            sta     cnt
            beq     fx8
fx1:        lda     SI_FILE,y
            cmpa    tmp4
            bne     fx4
            leax    SI_EXP,y
            jsr     fload
fx2:        jsr     rdb             ; each: name, value
            beq     fx4
            jsr     unrdb
            pshs    y
            ldy     #symbuf
            jsr     fcmp
            puls    y
            beq     fx5
            jsr     rdw
            bra     fx2
fx4:        leay    SISZ,y
            dec     cnt
            bne     fx1
fx8:        orcc    #$01
            rts
fx5:        jsr     rdw             ; offset + where it is linked
            addd    SI_ADDR,y
            andcc   #$FE
            rts

; The local symbol in symbuf: the section's own first, then the other
; sections of its file -> D, carry set if not there
locsym:     ldy     sip
            bsr     seclocal
            bcc     lsm9
            ldy     #insts
            lda     ninst
            sta     cnt
lsm1:       lda     SI_FILE,y
            cmpa    curfile
            bne     lsm2
            bsr     seclocal
            bcc     lsm9
lsm2:       leay    SISZ,y
            dec     cnt
            bne     lsm1
            orcc    #$01
lsm9:       rts

; The local symbols of section Y: symbuf -> D, carry set if not there
seclocal:   leax    SI_LOC,y
            jsr     fload
slc1:       pshs    y
            ldy     #symbuf
            jsr     rdb
            beq     slc8
            jsr     unrdb
            jsr     fcmp
            puls    y
            beq     slc5
            jsr     rdw
            bra     slc1
slc8:       puls    y
            orcc    #$01
            rts
slc5:       jsr     rdw
            pshs    d
            lda     SI_FLG,y        ; constant sections aren't moved
            bita    #2
            puls    d
            bne     slc6
            addd    SI_ADDR,y
slc6:       andcc   #$FE
            rts

; One byte back (after rdb)
unrdb:      pshs    d
            ldd     fad
            cmpd    #WIN
            bhi     ur1
            dec     fpg
            ldd     #WINEND
ur1:        subd    #1
            std     fad
            puls    d,pc

; s_NAME or l_NAME in symbuf: the lowest address, or the total length,
; of the placed sections NAME -> D, carry set if there are none
synsym:     ldd     #0
            std     tmpw            ; length
            ldd     #$FFFF
            std     tmpv            ; lowest
            clr     tmp4            ; found
            ldy     #insts
            ldb     ninst
            beq     sy8
sy1:        tst     SI_DONE,y
            beq     sy3
            pshs    b,y
            leax    SI_NAME,y
            jsr     fload
            ldy     #symbuf+2
            jsr     fcmp
            puls    b,y
            bne     sy3
            inc     tmp4
            pshs    b               ; the count: D is needed below
            ldd     tmpw
            addd    SI_SIZE,y
            std     tmpw
            ldd     SI_ADDR,y
            cmpd    tmpv
            bhs     sy2
            std     tmpv
sy2:        puls    b
sy3:        leay    SISZ,y
            decb
            bne     sy1
sy8:        tst     tmp4
            beq     sy9
            lda     symbuf
            cmpa    #'s
            bne     sy6
            ldd     tmpv
            bra     sy7
sy6:        ldd     tmpw
sy7:        andcc   #$FE
            rts
sy9:        orcc    #$01
            rts

; Not found: "Undefined symbol: NAME (FILE)", counted, 0 used
undef:      ldx     #msg_undef
            jsr     puts
            ldx     #symbuf
            jsr     puts
            ldx     #s_open
            jsr     puts
            lda     curfile
            jsr     fileent
            jsr     puts
            lda     #')
            OS      SYS_PUTC
            jsr     crlf
            ldd     errors
            addd    #1
            std     errors
            ldd     #0
            jmp     push

; ----------------------------------------------------------------------
;  Files
; ----------------------------------------------------------------------

; Load the file named at X into the pages at cpage/cptr -> srcpg/srcptr.
; Carry set and A = result on error.
loadfile:   jsr     setname
            lda     #VCMD_FOPEN
            OS      SYS_FCMD
            lbcs    lf9
            lda     cpage
            ldx     cptr
            sta     srcpg
            stx     srcptr
lf1:        cmpx    #WINEND         ; next page?
            blo     lf2
            inca
            ldx     #WIN
            cmpa    #LASTPG
            bhi     lf8
lf2:        sta     cpage
            stx     cptr
            tfr     a,b
            jsr     setbank
            ldx     #zero2          ; VF_LEN = 0: 512 bytes
            ldu     #VF_LEN
            ldd     #2
            jsr     vput
            lda     #VCMD_FREAD
            OS      SYS_FCMD
            bcs     lf9
            cmpx    #0
            beq     lf3             ; end of file
            stx     tmp
            ldx     cptr            ; into the window at cptr
            ldu     #VF_DATA
            ldd     tmp
            jsr     vget
            ldd     cptr
            addd    tmp
            tfr     d,x
            lda     cpage
            bra     lf1
lf3:        ldd     cptr            ; round up to 512 for the next file
            addd    #511
            clrb
            anda    #$FE
            std     cptr
            lda     #VCMD_FCLOSE
            OS      SYS_FCMD
            andcc   #$FE
            rts
lf8:        lda     #$FD            ; out of pages
lf9:        pshs    a
            lda     #VCMD_FCLOSE
            OS      SYS_FCMD
            puls    a
            orcc    #$01
            rts

; Write outname: the header, then the image from lo to hi.  Carry set
; and A = result on error.
writeprg:   ldx     #outname
            jsr     setname
            ldx     #hdr+4          ; name: outname without directory
            ldb     #12
wp1:        clr     ,x+
            decb
            bne     wp1
            ldx     #outname
            jsr     basename
            ldu     #hdr+4
            ldb     #12
wp2:        lda     ,x+
            beq     wp3
            sta     ,u+
            decb
            bne     wp2
wp3:        ldd     #0              ; bytes
            ldx     #0              ; load address
            tst     anyout
            beq     wp4
            ldd     hi
            subd    lo
            addd    #1
            ldx     lo
wp4:        std     wleft
            stx     waddr
            stx     hdr+30
            addd    #PHLEN
            std     hdr+28
            ldd     entry
            std     hdr+32
            lda     #VCMD_FCREATE
            OS      SYS_FCMD
            lbcs    wp9
            ldx     #hdr
            ldd     #PHLEN
            lbsr    wblock
            lbcs    wp9
wp5:        ldd     wleft           ; the data, up to 512 bytes at a time
            beq     wp8             ; and never across a page
            cmpd    #512
            bls     wp6
            ldd     #512
wp6:        std     tmp
            ldd     waddr
            anda    #$3F
            pshs    d
            ldd     #$4000
            subd    ,s++            ; bytes to the end of its page
            cmpd    tmp
            bhs     wp7
            std     tmp
wp7:        ldd     waddr
            jsr     flpage          ; -> U
            tfr     u,x
            ldd     tmp
            lbsr    wblock
            lbcs    wp9
            ldd     waddr
            addd    tmp
            std     waddr
            ldd     wleft
            subd    tmp
            std     wleft
            bra     wp5
wp8:        ldb     nbank           ; the banks: "B9", the count
            lbeq    wp8z
            stb     bhdr+2
            ldd     #$4239
            std     bhdr
            ldx     #bhdr
            ldd     #3
            jsr     wblock
            bcs     wp9
            clr     bcur
wpb1:       lda     bcur            ; each: page, length, bytes
            cmpa    nbank
            bhs     wp8z
            jsr     buildbank
            lda     buildpg
            sta     bhdr
            lda     bcur
            lsla
            ldx     #bused
            ldd     a,x
            std     bhdr+1
            std     wleft
            ldx     #bhdr
            ldd     #3
            jsr     wblock
            bcs     wp9
            ldx     #WIN
            stx     waddr
wpb2:       ldd     wleft
            beq     wpb3
            cmpd    #512
            bls     wpb2a
            ldd     #512
wpb2a:      std     tmp
            ldb     #OUTPG+2
            jsr     setbank
            ldx     waddr
            ldd     tmp
            jsr     wblock
            bcs     wp9
            ldd     waddr
            addd    tmp
            std     waddr
            ldd     wleft
            subd    tmp
            std     wleft
            bra     wpb2
wpb3:       inc     bcur
            bra     wpb1
wp8z:       lda     #VCMD_FCLOSE
            OS      SYS_FCMD
            rts
wp9:        pshs    a
            lda     #VCMD_FCLOSE
            OS      SYS_FCMD
            puls    a
            orcc    #$01
            rts

; Write D bytes from X to the open file.  Carry set and A = result on
; error.
wblock:     std     wlen
            ldu     #VF_DATA
            jsr     vput
            ldx     #wlen
            ldu     #VF_LEN
            ldd     #2
            jsr     vput
            lda     #VCMD_FWRITE
            OS      SYS_FCMD
            rts

; The name at X -> VF_NAME
setname:    pshs    x
            tfr     x,u
sn1:        tst     ,u+
            bne     sn1
            tfr     u,d
            subd    ,s              ; length with the NUL
            puls    x
            ldu     #VF_NAME
            jmp     vput

; VRAM mailbox: vput copies D bytes from X to VRAM U, vget from VRAM U
; to X
vput:       bsr     vblock
            OS      SYS_VCOPY
            rts
vget:       bsr     vblock
            OS      SYS_VREAD
            rts
vblock:     std     vblk+5
            stx     vblk+3
            stu     vblk+1
            lda     #VF_BANK
            sta     vblk
            ldx     #vblk
            rts

; ----------------------------------------------------------------------
;  Strings, numbers, console
; ----------------------------------------------------------------------

; X -> the part of the path at X after its last '/'
basename:   tfr     x,u
bn1:        lda     ,u+
            beq     bn9
            cmpa    #'/
            bne     bn1
            tfr     u,x
            bra     bn1
bn9:        rts

; The strings at X and Y the same?  Z set if so.
strcmp:     lda     ,x+
            cmpa    ,y+
            bne     scm9
            tsta
            bne     strcmp
scm9:       rts

; Copy the NUL-terminated string at X to U (NUL included)
strcpy:     lda     ,x+
            sta     ,u+
            bne     strcpy
            rts

skipsp:     lda     ,x
            cmpa    #$20
            beq     ssp1
            cmpa    #9
            bne     ssp9
ssp1:       leax    1,x
            bra     skipsp
ssp9:       rts

; A -> upper case
upper:      cmpa    #'a
            blo     up9
            cmpa    #'z
            bhi     up9
            suba    #$20
up9:        rts

; ma * mb -> D (low 16 bits)
mul16:      lda     ma+1
            ldb     mb+1
            mul
            std     mres
            lda     ma
            ldb     mb+1
            mul
            addb    mres
            stb     mres
            lda     ma+1
            ldb     mb
            mul
            addb    mres
            stb     mres
            ldd     mres
            rts

; ma / mb -> D, remainder in mrem (unsigned; / 0 gives 0)
div16:      ldd     mb
            bne     dv16
            std     mrem
            rts
dv16:       ldd     #0
            ldy     #16
dv16a:      lsl     ma+1
            rol     ma
            rolb
            rola
            cmpd    mb
            blo     dv16b
            subd    mb
            inc     ma+1
dv16b:      leay    -1,y
            bne     dv16a
            std     mrem
            ldd     ma
            rts

; Errors that stop the link
fat_files:  ldx     #msg_files
            bra     fatal
fat_sects:  ldx     #msg_sects
            bra     fatal
fat_cplx:   ldx     #msg_cplx
            bra     fatal
fat_banks:  ldx     #msg_banks2
            bra     fatal
fat_big:    ldx     #msg_big
            bra     fatal
fat_bank:   ldx     #msg_bank       ; "Bank too big: FILE"
            jsr     puts
            lda     SI_FILE,y
            jsr     fileent
            bra     fatal
fat_notobj: ldx     #msg_notobj
            jsr     puts
            ldx     fpname
fatal:      jsr     puts
            jsr     crlf
            jmp     quit

; Print the message for file result A and stop
ferror:     ldx     #msg_fnofile
            cmpa    #4
            beq     fe9
            ldx     #msg_fnopath
            cmpa    #5
            beq     fe9
            ldx     #msg_fnodrv
            cmpa    #3
            beq     fe9
            ldx     #msg_full
            cmpa    #$FD
            beq     fe9
            ldx     #msg_ferr
            jsr     puts
            tfr     a,b
            clra
            jsr     putdec
            bra     fe8
fe9:        jsr     puts
fe8:        ldx     #s_colon
            jsr     puts
            ldx     fpname
            jsr     puts
            jsr     crlf
            jmp     quit

; Read a typed line into lbuf (upper-cased, NUL terminated)
readline:   ldx     #lbuf
            clrb
rl_1:       OS      SYS_GETC
            cmpa    #CR
            beq     rl_9
            cmpa    #LF
            beq     rl_9
            cmpa    #BS
            beq     rl_2
            cmpa    #DEL
            beq     rl_2
            cmpa    #$20
            blo     rl_1
            cmpb    #LBUFSZ-1
            bhs     rl_1
            jsr     upper
            sta     ,x+
            incb
            OS      SYS_PUTC
            bra     rl_1
rl_2:       tstb
            beq     rl_1
            decb
            leax    -1,x
            pshs    x
            ldx     #bsseq
            bsr     puts
            puls    x
            bra     rl_1
rl_9:       clr     ,x
            bra     crlf

puts:       pshs    a,x
ps1:        lda     ,x+
            beq     ps9
            OS      SYS_PUTC
            bra     ps1
ps9:        puls    a,x,pc

crlf:       pshs    a
            lda     #CR
            OS      SYS_PUTC
            lda     #LF
            OS      SYS_PUTC
            puls    a,pc

; D as unsigned decimal, no leading zeros
putdec:     pshs    d,x,y
            ldy     #pow10
            clr     ,-s             ; 0,s: a digit has been printed
pd1:        lda     #'0-1
            sta     ,-s
            ldd     2,s
pd2:        inc     ,s
            subd    ,y
            bcc     pd2
            addd    ,y
            std     2,s
            lda     ,s+
            cmpy    #pow10+8        ; always print the last digit
            beq     pd3
            cmpa    #'0
            bne     pd3
            tst     ,s
            beq     pd4
pd3:        OS      SYS_PUTC
            inc     ,s
pd4:        leay    2,y
            cmpy    #pow10+10
            blo     pd1
            leas    1,s
            puls    d,x,y,pc
pow10:      fdb     10000,1000,100,10,1

; ----------------------------------------------------------------------
msg_hello:  fcc     "MINI09 LINK 0.2"
            fcb     CR,LF,0
msg_ask:    fcn     "Output and objects: "
msg_usage:  fcc     "Use: LINK OUT.PRG FILE.O ..."
            fcb     CR,LF,0
msg_objs:   fcn     " objects, "
msg_bytes:  fcn     " bytes: "
msg_errors: fcc     " error(s), no program file written"
            fcb     CR,LF,0
msg_undef:  fcn     "Undefined symbol: "
msg_files:  fcn     "Too many files"
msg_sects:  fcn     "Too many sections"
msg_cplx:   fcn     "Bad expression in an object"
msg_notobj: fcn     "Not an object file: "
msg_fnofile: fcn    "File not found"
msg_fnopath: fcn    "Path not found"
msg_fnodrv: fcn     "No drive"
msg_full:   fcn     "Out of memory for the objects"
msg_ferr:   fcn     "File error "
s_colon:    fcn     ": "
s_open:     fcn     " ("
s_lwobj:    fcn     "LWOBJ16"
s_init:     fcn     "init"
s_code:     fcn     "code"
s_start:    fcn     "__start"
s_banked:   fcn     "banked"
s_bank:     fcn     "__bank"
s_nbank:    fcn     "__nbank"
s_comma:    fcn     ", "
msg_banks:  fcn     " banks"
msg_banks2: fcn     "Too many banks"
msg_bank:   fcn     "Bank too big: "
msg_big:    fcn     "Program too big for banked code"
bsseq:      fcb     BS,$20,BS,0
zero2:      fdb     0

; Program file header; name, sizes and addresses are filled in
hdr:        fcc     "M9"
            fcb     1,PHLEN
            rmb     12              ; name
            fcc     "MINI09LK"      ; creator
            fdb     0               ; date unknown
            fcb     0,0
            rmb     2               ; file size
            rmb     2               ; load address
            rmb     2               ; entry
            fdb     0

; ----------------------------------------------------------------------
;  Variables
; ----------------------------------------------------------------------
LBUFSZ      equ     128
curbank:    rmb     1
errors:     rmb     2
nfiles:     rmb     1
ninst:      rmb     1
curfile:    rmb     1
cursi:      rmb     1
sip:        rmb     2               ; -> the section being relocated
cpage:      rmb     1               ; where the next file goes
cptr:       rmb     2
srcpg:      rmb     1               ; where the last file loaded starts
srcptr:     rmb     2
fpg:        rmb     1               ; the far pointer
fad:        rmb     2
tfp:        rmb     3
rfp:        rmb     3
fpname:     rmb     2
laddr:      rmb     2
entry:      rmb     2
lo:         rmb     2
hi:         rmb     2
anyout:     rmb     1
nbank:      rmb     1               ; banked code: pages used
bcur:       rmb     1
buildpg:    rmb     1               ; the page being built, 0 = common
bused:      rmb     MAXBANK*2       ; bytes in each
bhdr:       rmb     3
waddr:      rmb     2
wleft:      rmb     2
wlen:       rmb     2
vblk:       rmb     7
tmp:        rmb     2
tmp2:       rmb     1
tmp3:       rmb     1
tmp4:       rmb     1
cnt:        rmb     1
tmpv:       rmb     2
tmpw:       rmb     2
ma:         rmb     2
mb:         rmb     2
mres:       rmb     2
mrem:       rmb     2
r8bit:      rmb     1
esp:        rmb     2
estk:       rmb     STKSZ*2
outname:    rmb     LINEMAX+1
lbuf:       rmb     LBUFSZ
symbuf:     rmb     NAMEMAX+1
nbuf:       rmb     NAMEMAX+1
files:      rmb     FISZ*MAXFILE
insts:      rmb     SISZ*MAXINST
            rmb     256             ; stack
stktop:

            end     start
