; ----------------------------------------------------------------------
;  CC.PRG - runs all the steps of compiling C on MINI09:
;
;    CC FILE.C [MORE.C|LIB.O ...] [-S] [-C] [-K] [-N] [-B] [-I DIR/]
;
;  For each .C file: CPP, PARSE, SEMA, GEN, then ASM; then LINK makes
;  FILE.PRG (named after the first file) from CRT0.O, the objects, CLIB.O
;  and LIBC.O.  A .O file goes to LINK as it is.
;
;    -S   stop at FILE.ASM          -C   stop at FILE.O, no LINK
;    -K   keep the files in between (.I .A .N .T, .ASM and .O)
;    -N   no CLIB.O (printf, malloc ...): 3K less, as the passes are built
;    -B   link with CRT0B.O: some .O given has banked code
;    -I   CPP's folder for <headers> (INCLUDE/ without it)
;
;  A file with #pragma bank: GEN writes FILE.B beside it (empty), and CC
;  links with CRT0B.O, which loads the code banks, as if -B were given.
;
;  The passes and ASM, LINK, CRT0.O, CLIB.O and LIBC.O are looked for at
;  the top of the drive.  A step that writes nothing (it printed errors)
;  stops CC.
;
;  How: every program loads at $1000, so CC copies itself to RAM page 2
;  (DPAGE) at $8000 and runs there.  For each step it loads the
;  program at $1000 as RUN does, puts the arguments at ARGS, starts it
;  with SYS_SPAWN and waits until the kernel's task table (tcbs at $20 in
;  os.asm) shows the task gone.  The code after `body` is position-
;  independent, and its variables are at fixed addresses in the page.
;  No parentheses in expressions, for ASM (see cc.md).
; ----------------------------------------------------------------------

            include "syscalls.inc"
            include "vdp.inc"

DPAGE       equ     2               ; our page: the default one, which the
                                    ; passes, ASM and LINK leave alone (they
                                    ; use 3-31)
WIN         equ     $8000
TCBS        equ     $20             ; the kernel's task table, TCB_STATE first
TCBSZ       equ     8
MAXFILE     equ     8

; variables, in our page after the code
V           equ     $A000
argbuf      equ     V               ; 64: our arguments, split at spaces
nfile       equ     V+64            ; 1
fflags      equ     V+65            ; 1: F_xxx
wantdir     equ     V+66            ; 1: -I seen, its folder next
curf        equ     V+67            ; 1: the file being compiled
pid         equ     V+68            ; 1: the step's task
first       equ     V+69            ; 1: loading: the first block
incdir      equ     V+70            ; 2: -I's folder, or 0
dotp        equ     V+72            ; 2
sprog       equ     V+74            ; 2: step(): the program
sin         equ     V+76            ; 2: its input's extension, 0 = the C file
sout        equ     V+78            ; 2: its output's extension
cnt         equ     V+80            ; 2: bytes in this block
left        equ     V+82            ; 2: bytes still to load
dest        equ     V+84            ; 2
entry       equ     V+86            ; 2
bend        equ     V+88            ; 2
vblk        equ     V+90            ; 7: SYS_VCOPY / SYS_VREAD block
zero2       equ     V+97            ; 2
files       equ     V+100           ; MAXFILE*2: the file names
base        equ     V+128           ; 64: a file's name without extension
name        equ     V+192           ; 64: a name being made
outname     equ     V+256           ; 64: the .PRG
objs        equ     V+320           ; 256: " A.O B.O ..." for LINK
cargs       equ     V+576           ; 320: a step's arguments
buf         equ     V+1024          ; 512: a block of a program file

F_S         equ     1
F_C         equ     2
F_K         equ     4
F_N         equ     8
F_B         equ     16              ; banked code: CRT0B.O

; ---- at $1000: copy the rest to our page and go there ------------------

            org     $1000
start:      ldb     #DPAGE
            OS      SYS_BANK
            bcs     st9
            ldx     #body
            ldu     #WIN
st1:        lda     ,x+
            sta     ,u+
            cmpx    #bodyend
            blo     st1
            jmp     WIN
st9:        OS      SYS_EXIT

; ---- from here on, at $8000 ------------------------------------------------

body:       ldd     ARGS            ; our arguments
            cmpd    #ARGMARK
            lbne    usage
            clr     ARGS
            ldx     #ARGS+2
            ldu     #argbuf
            ldb     #63
m1:         lda     ,x+
            sta     ,u+
            beq     m2
            decb
            bne     m1
            clr     ,u
m2:         clr     nfile
            clr     fflags
            clr     wantdir
            ldd     #0
            std     incdir
            std     zero2
            ldx     #argbuf
m3:         lda     ,x              ; the next word
            beq     m9
            cmpa    #$20
            bne     m4
            clr     ,x+             ; (ends the word before)
            bra     m3
m4:         tst     wantdir
            beq     m5
            stx     incdir
            clr     wantdir
            bra     m8
m5:         cmpa    #'-
            bne     m7
            lda     1,x
            ldb     #F_S
            cmpa    #'S
            beq     m6
            ldb     #F_C
            cmpa    #'C
            beq     m6
            ldb     #F_K
            cmpa    #'K
            beq     m6
            ldb     #F_N
            cmpa    #'N
            beq     m6
            ldb     #F_B
            cmpa    #'B
            beq     m6
            cmpa    #'I
            lbne    usage
            inc     wantdir
            bra     m8
m6:         orb     fflags
            stb     fflags
            bra     m8
m7:         ldb     nfile           ; a file
            cmpb    #MAXFILE
            lbhs    usage
            lslb
            ldu     #files
            stx     b,u
            inc     nfile
m8:         lda     ,x              ; to the end of the word
            beq     m3
            cmpa    #$20
            beq     m3
            leax    1,x
            bra     m8
m9:         tst     nfile
            lbeq    usage
            tst     wantdir
            lbne    usage

; ---- compile each file ---------------------------------------------------

            clr     objs
            clr     curf
f1:         ldb     curf
            cmpb    nfile
            lbhs    link
            lbsr    curname
            lbsr    getbase
            pshs    a
            tst     curf            ; the first names the .PRG
            bne     f2
            leax    s_prg,pcr
            lbsr    mkname
            ldu     #outname
            lbsr    cpy
f2:         puls    a
            cmpa    #'O
            beq     f3
            lbsr    compile
            lbcs    stop
            lda     fflags
            bita    #F_S
            bne     f4
f3:         leax    s_o,pcr         ; " FILE.O" for LINK
            lbsr    mkname
            ldu     #objs
            lbsr    strend
            lda     #$20
            sta     ,u+
            lbsr    cpy
f4:         inc     curf
            bra     f1

; FILE.C -> FILE.ASM, and FILE.O unless -S.  C=1 if a step failed.
compile:    leax    p_cpp,pcr
            ldy     #0
            leau    s_i,pcr
            lbsr    step
           lbcs    cp9
            leax    s_n,pcr         ; PARSE writes .N too
            lbsr    mkname
            lbsr    fdel
            leax    p_parse,pcr
            leay    s_i,pcr
            leau    s_a,pcr
            lbsr    step
            lbcs    cp9
            leax    p_sema,pcr
            leay    s_a,pcr
            leau    s_t,pcr
            lbsr    step
            lbcs    cp9
            leax    s_b,pcr         ; no FILE.B from before
            lbsr    delext
            leax    p_gen,pcr
            leay    s_t,pcr
            leau    s_asm,pcr
            lbsr    step
            lbcs    cp9
            leax    s_b,pcr         ; FILE.B: GEN found #pragma bank
            lbsr    mkname
            lbsr    exists
            bcs     cp0
            lda     fflags
            ora     #F_B
            sta     fflags
            leax    s_b,pcr
            lbsr    delext
cp0:
            lda     fflags
            bita    #F_K
            bne     cp1
            leax    s_i,pcr         ; the passes' files
            lbsr    delext
            leax    s_a,pcr
            lbsr    delext
            leax    s_n,pcr
            lbsr    delext
            leax    s_t,pcr
            lbsr    delext
cp1:        lda     fflags
            bita    #F_S
            bne     cp8
            leax    p_asm,pcr
            leay    s_asm,pcr
            leau    s_o,pcr
            lbsr    step
            lbcs    cp9
            lda     fflags
            bita    #F_K
            bne     cp8
            leax    s_asm,pcr
            lbsr    delext
cp8:        andcc   #$FE
cp9:        rts

; delete base + the extension at X
delext:     lbsr    mkname
            lbra    fdel

; ---- link -----------------------------------------------------------------

link:       lda     fflags
            bita    #F_S+F_C
            bne     done
            ldx     #outname
            lbsr    fdel
            ldu     #cargs
            ldx     #outname
            lbsr    cpy
            leax    s_crt0,pcr
            lda     fflags
            bita    #F_B
            beq     ln00
            leax    s_crt0b,pcr
ln00:       lbsr    cpy
            ldx     #objs
            lbsr    cpy
            leax    s_libs,pcr
            lda     fflags
            bita    #F_N
            beq     ln0
            leax    s_libn,pcr
ln0:        lbsr    cpy
            leax    p_link,pcr
            lbsr    run
            bcs     stop
            ldx     #outname
            lbsr    exists
            bcc     ln1
            ldx     #outname
            bra     stopn
ln1:        lda     fflags          ; the objects CC made
            bita    #F_K
            bne     done
            clr     curf
ln2:        ldb     curf
            cmpb    nfile
            bhs     done
            lbsr    curname
            lbsr    getbase
            cmpa    #'O
            beq     ln3
            leax    s_o,pcr
            bsr     delext
ln3:        inc     curf
            bra     ln2
done:       OS      SYS_EXIT

; a step wrote nothing: stop (it has said why)
stopn:      pshs    x
            leax    s_stop,pcr
            lbsr    puts
            puls    x
            lbsr    puts
            lbsr    crlf
stop:       OS      SYS_EXIT

usage:      leax    s_usage,pcr
            lbsr    puts
            bra     stop

; ---- one step ---------------------------------------------------------------

; Run program X on base + extension Y (Y = 0: the C file as given, with
; -I), which writes base + extension U.  C=1 if it didn't.
step:       stx     sprog
            sty     sin
            stu     sout
            ldx     sout            ; no old output to be fooled by
            lbsr    mkname
            lbsr    fdel
            ldu     #cargs
            ldx     sin
            bne     sp1
            bsr     curname
            lbsr    cpy
            ldx     incdir
            beq     sp2
            pshs    x
            leax    s_dashi,pcr
            lbsr    cpy
            puls    x
            lbsr    cpy
            bra     sp2
sp1:        pshs    x
            ldx     #base
            lbsr    cpy
            puls    x
            lbsr    cpy
sp2:        ldx     sprog
            bsr     run
            bcs     sp9
            ldx     sout
            lbsr    mkname
            lbsr    exists
            bcc     sp9
            ldx     #name
            bra     stopn
sp9:        rts

; X = the current file's name
curname:    ldb     curf
            lslb
            ldx     #files
            ldx     b,x
            rts

; Run program X with the arguments in cargs, and wait for it.  C=1 if it
; couldn't be started.
run:        pshs    x
            leax    s_run,pcr       ; "RUN PROG ARGS", as if typed
            lbsr    puts
            ldx     ,s
            lbsr    puts
            lda     #$20
            OS      SYS_PUTC
            ldx     #cargs
            lbsr    puts
            lbsr    crlf
            ldx     #cargs          ; the arguments
            ldb     #ARGMAX
            ldu     #ARGS+2
rn1:        lda     ,x+
            sta     ,u+
            beq     rn2
            decb
            bne     rn1
            leax    s_long,pcr
            lbsr    puts
            puls    x
            orcc    #$01
            rts
rn2:        ldd     #ARGMARK
            std     ARGS
            puls    x
            bsr     load
            bcs     rn9
            ldx     entry
            OS      SYS_SPAWN
            bcs     rn8
            stb     pid
rn3:        ldd     #5              ; wait for it to end
            OS      SYS_SLEEP
            ldb     pid
            lda     #TCBSZ
            mul
            tfr     d,x
            tst     TCBS,x
            bne     rn3
            andcc   #$FE
rn9:        rts
rn8:        leax    s_slot,pcr
            lbsr    puts
            orcc    #$01
            rts

; Load program file X at its address, as RUN does; entry -> entry.
; C=1 if it couldn't.
load:       pshs    x
            lbsr    setname
            lda     #VCMD_FOPEN
            OS      SYS_FCMD
           lbcs    ld8
            lda     #1
            sta     first
ld1:        ldx     #zero2          ; VF_LEN = 0: 512 bytes
            ldu     #VF_LEN
            ldd     #2
            lbsr    vput
            lda     #VCMD_FREAD
            OS      SYS_FCMD
           lbcs    ld8
            stx     cnt
            beq     ld6             ; the end
            ldd     cnt
            ldx     #buf
            ldu     #VF_DATA
            lbsr    vget
            ldd     #buf
            addd    cnt
            std     bend
            ldx     #buf
            tst     first
            beq     ld3
            clr     first           ; the header
            ldd     buf
            cmpd    #$4D39          ; "M9"
            bne     ld7
            ldd     buf+30
            cmpd    #$1000
            blo     ld7
            std     dest
            ldd     buf+32
            std     entry
            ldb     buf+3           ; bytes = file size - header length
            clra
            pshs    d
            ldd     buf+28
            subd    ,s
            std     left
            addd    dest            ; and they must fit below $8000
            bcs     ld2
            cmpd    #WIN
            bhi     ld2
            puls    d
            leax    d,x             ; past the header
            bra     ld3
ld2:        leas    2,s
            bra     ld7
ld3:        ldu     dest
ld4:        cmpx    bend
            bhs     ld5
            ldd     left
            beq     ld5
            subd    #1
            std     left
            lda     ,x+
            sta     ,u+
            bra     ld4
ld5:        stu     dest
           lbra    ld1
ld6:        lda     #VCMD_FCLOSE
            OS      SYS_FCMD
            ldd     left
            bne     ld9
            leas    2,s
            andcc   #$FE
            rts
ld7:        lda     #VCMD_FCLOSE
            OS      SYS_FCMD
ld8:
ld9:        leax    s_load,pcr      ; "CC: can't load NAME"
            lbsr    puts
            puls    x
            lbsr    puts
            lbsr    crlf
            orcc    #$01
            rts

; ---- files --------------------------------------------------------------

; delete file X, if it is there
fdel:       lbsr    setname
            lda     #VCMD_FDELETE
            OS      SYS_FCMD
            rts

; C=0 if file X is there
exists:     lbsr    setname
            lda     #VCMD_FOPEN
            OS      SYS_FCMD
            bcs     es9
            lda     #VCMD_FCLOSE
            OS      SYS_FCMD
            andcc   #$FE
es9:        rts

; name X -> VF_NAME
setname:    pshs    x
            ldd     #1              ; its length with the NUL
sn1:        tst     ,x+
            beq     sn2
            addd    #1
            bra     sn1
sn2:        cmpd    #64
            bls     sn3
            ldd     #64
sn3:        puls    x
            ldu     #VF_NAME
            ; (on to vput)

; copy D bytes between RAM at X and the mailbox at U
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

; ---- names ----------------------------------------------------------------

; name X -> base without its extension; A = the extension's first
; letter, 0 if none
getbase:    ldu     #base
            ldd     #0
            std     dotp
gb1:        lda     ,x+
            sta     ,u
            beq     gb3
            cmpa    #'.
            bne     gb2
            stu     dotp
gb2:        cmpa    #'/
            bne     gb2a
            ldd     #0
            std     dotp
gb2a:       leau    1,u
            bra     gb1
gb3:        ldu     dotp
            beq     gb4
            lda     1,u
            clr     ,u
            rts
gb4:        clra
            rts

; name = base + extension X; X = name
mkname:     pshs    x
            ldx     #base
            ldu     #name
            bsr     cpy
            puls    x
            bsr     cpy
            ldx     #name
            rts

; string X to U; U ends at its NUL, so another can follow
cpy:        lda     ,x+
            sta     ,u+
            bne     cpy
            leau    -1,u
            rts

; U = the NUL at the end of the string at U
strend:     tst     ,u+
            bne     strend
            leau    -1,u
            rts

; ---- console --------------------------------------------------------------

puts:       lda     ,x+
            beq     pu9
            OS      SYS_PUTC
            bra     puts
pu9:        rts

crlf:       lda     #CR
            OS      SYS_PUTC
            lda     #LF
            OS      SYS_PUTC
            rts

; ---- strings ------------------------------------------------------------

p_cpp:      fcn     "CPP.PRG"
p_parse:    fcn     "PARSE.PRG"
p_sema:     fcn     "SEMA.PRG"
p_gen:      fcn     "GEN.PRG"
p_asm:      fcn     "ASM.PRG"
p_link:     fcn     "LINK.PRG"
s_i:        fcn     ".I"
s_a:        fcn     ".A"
s_n:        fcn     ".N"
s_t:        fcn     ".T"
s_asm:      fcn     ".ASM"
s_o:        fcn     ".O"
s_prg:      fcn     ".PRG"
s_crt0:     fcn     " CRT0.O"
s_crt0b:    fcn     " CRT0B.O"
s_b:        fcn     ".B"
s_libs:     fcn     " CLIB.O LIBC.O"
s_libn:     fcn     " LIBC.O"
s_dashi:    fcn     " -I "
s_run:      fcn     "RUN "
s_stop:     fcn     "CC: stopped, nothing written to "
s_long:     fcn     "CC: arguments too long"
s_slot:     fcn     "CC: no task slot"
s_load:     fcn     "CC: can't load "
s_usage:    fcc     "Usage: CC FILE.C [MORE.C|LIB.O ...] [-S] [-C] [-K] [-N] [-B] [-I DIR/]"
            fcb     CR,LF
            fcc     "  -S stop at .ASM, -C stop at .O, -K keep the files between,"
            fcb     CR,LF
            fcc     "  -N no CLIB.O, -B banked .O files: CRT0B.O"
            fcb     CR,LF,0
bodyend:

            end     start
