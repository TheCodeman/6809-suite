; ----------------------------------------------------------------------
;  MINI09 BASIC - a BASIC interpreter for MINI09
;
;  Copy basic.prg to the flash drive as BASIC.PRG and type BASIC.PRG
;  in the shell.  BYE goes back to the shell.  Programs are kept in RAM
;  while the shell runs, so BASIC.PRG again finds them still there.
;
;  Assembled with -D ROMBASIC it is the ROM version instead: code at
;  $8000-$BFFF in the 28C256's ROM bank (the shell's BASIC command), and
;  the program text from $1000 in RAM.  The code never writes to itself.
;
;  Floating-point numbers in single (5 bytes, 9 digits) and double
;  precision (8 bytes, 16 digits), whole numbers and strings up to 255
;  characters.  Variable
;  names are a letter and an optional letter or digit (more letters are
;  allowed but ignored); $ makes a string.  One-dimensional arrays of
;  both.  Programs are saved on the flash
;  drive as plain text (LIST format), so EDIT can change them too.
;
;  Memory: code from $1000 (ROM version: at $8000, program from $1000),
;  then the program text, then the variable table, growing up.  The
;  string space grows down from the work area: stack and buffers at
;  $B000-$BFFF (ROM version: $7000-$7FFF).  So programs get about 25K
;  (ROM version: 24K).
;
;  Variable table entries: 2-byte name, 2-byte entry size, then the data.
;  Name: first letter, its top bits giving the type ($40 single, $C0
;  string $, $00 whole number %, $80 double #), second letter or digit or
;  0 (+$80 for an array).  A DEF FN adds $20.  Data: a number (2 bytes), a string descriptor
;  (length, address in the string space), or for an array the element
;  count (2 bytes), the number of dimensions (1), the size of each
;  (2 bytes each) and the elements, last subscript varying fastest.
; ----------------------------------------------------------------------

            include "syscalls.inc"
            include "vdp.inc"

; The work area (stack, buffers, string stack): 4K at the top of the RAM
; we can use.  The disk version puts it at $B000-$BFFF, the top of its
; task page at $8000, so programs get $8000-$AFFF too.  The ROM version's
; code is at $8000, so its work area stays at $7000-$7FFF.
            ifdef   ROMBASIC
WRK         equ     $7000
            else
WRK         equ     $B000
            endc
HEAPEND     equ     WRK             ; end of program, variables and strings
STKTOP      equ     WRK+$200        ; our own stack: the work area's first 512 bytes
curline     equ     WRK+$2A0        ; -> line being run, 0 = direct mode
progend     equ     WRK+$2A2        ; end of the program text
vartop      equ     WRK+$2A4        ; end of the variable table
ssp         equ     WRK+$2A6        ; string stack pointer
cstkp       equ     WRK+$2A8        ; FOR/GOSUB stack pointer
datap       equ     WRK+$2AA        ; next DATA item, 0 = start over
datal       equ     WRK+$2AC        ; line holding datap
seed        equ     WRK+$2AE        ; RND state
outv        equ     WRK+$2B0        ; output routine (console or file)
fpos        equ     WRK+$2B2        ; bytes in fbuf
lnum        equ     WRK+$2B4        ; line number being entered
tlen        equ     WRK+$2B6        ; its stored length
stmp        equ     WRK+$2B8
inptr       equ     WRK+$2BA        ; INPUT: position in lbuf
lcnt        equ     WRK+$2BC        ; LOAD: bytes left in fbuf
lptr        equ     WRK+$2BE        ; LOAD: position in fbuf
lstlo       equ     WRK+$2C0        ; LIST range
lsthi       equ     WRK+$2C2
vblk        equ     WRK+$2C4        ; SYS_VCOPY / SYS_VREAD block (7)
vtype       equ     WRK+$2CB        ; 0 number, 1 string; 2 a % variable (lvalue)
col         equ     WRK+$2CC        ; console column
nsgn        equ     WRK+$2CD
ntmp        equ     WRK+$2CE
lastcr      equ     WRK+$2D1        ; last key was CR (ignore a LF after it)
fopenf      equ     WRK+$2D2        ; a file or directory is open
slen        equ     WRK+$2D4
lastc       equ     WRK+$2D5        ; LIST: last character sent
llen        equ     WRK+$2D6        ; LOAD: length of the line in lbuf
fext        equ     WRK+$2D7        ; add .BAS to a name without a dot
sa_n1       equ     WRK+$2D8        ; LEFT$, RIGHT$, MID$ numbers
sa_n2       equ     WRK+$2DA
strtop      equ     WRK+$2DC        ; lowest byte of the string space
gcnew       equ     WRK+$2E0        ; GC: strings below this are packed
gcbnd       equ     WRK+$2E2        ; GC: next string must be below this
gcbest      equ     WRK+$2E4        ; GC: highest string found so far
gcdesc      equ     WRK+$2E6        ; GC: its descriptor
nbuf        equ     WRK+$2E8        ; number -> text (16)
nbufend     equ     WRK+$2F8
magic       equ     WRK+$2FE        ; MAGIC: program text is valid
lbuf        equ     WRK+$300        ; input line (128)
LBMAX       equ     127
tokbuf      equ     WRK+$380        ; tokenized input line (128)
cstk        equ     WRK+$800        ; FOR/GOSUB stack, 24 entries
CSSZ        equ     24              ; bytes an entry
CSTKEND     equ     cstk+24*CSSZ
fnbuf       equ     WRK+$540        ; file name (64)
dirbuf      equ     WRK+$580        ; DIR entry (72)
vbuf        equ     WRK+$5C8        ; VAL work buffer (24)
dmode       equ     WRK+$5E0        ; data file: 0 none, 1 output, 2 input
dnum        equ     WRK+$5E1        ; its number
dcol        equ     WRK+$5E2        ; output: its column
concol      equ     WRK+$5E3        ; the console's column meanwhile
deof        equ     WRK+$5E4        ; input: the file has ended
dfpos       equ     WRK+$5E5        ; position in fbuf
dfcnt       equ     WRK+$5E7        ; bytes in fbuf
dllen       equ     WRK+$5E9        ; LINE INPUT: line length
dlany       equ     WRK+$5EA        ; a character was read
fbuf        equ     WRK+$600        ; file buffer (512)
sstk        equ     WRK+$C00        ; string stack
SSTKEND     equ     WRK+$1000
MAGIC       equ     $B462
MAXDIM      equ     4               ; array dimensions
SCRCOLS     equ     80              ; PRINT @: the screen
SCRROWS     equ     30
MAXEL       equ     8000            ; array elements

; Control stack entries (CSSZ bytes): 0 type ('F' or 'G'), 1 variable,
; 3 limit, 11 step (8-byte doubles), 19 text pointer, 21 line pointer,
; 23 the variable's type.
CS_LIM      equ     3
CS_STEP     equ     11
CS_TXT      equ     19
CS_LN       equ     21
CS_TYP      equ     23

; Floating point work area
fexp        equ     WRK+$400        ; FAC: exponent
fm0         equ     WRK+$401        ; mantissa, 7 bytes
fm1         equ     WRK+$402
fm2         equ     WRK+$403
fm3         equ     WRK+$404
fm4         equ     WRK+$405
fm5         equ     WRK+$406
fm6         equ     WRK+$407
fmg         equ     WRK+$408        ; guard byte
fsgn        equ     WRK+$409        ; sign: 0 or $FF
fprec       equ     WRK+$40A        ; precision: 0 single, 1 double
aexp        equ     WRK+$410        ; ARG: the same, 16 bytes on
am0         equ     WRK+$411
am1         equ     WRK+$412
am2         equ     WRK+$413
am3         equ     WRK+$414
am4         equ     WRK+$415
am5         equ     WRK+$416
am6         equ     WRK+$417
amg         equ     WRK+$418
asgn        equ     WRK+$419
aprec       equ     WRK+$41A
prod        equ     WRK+$420        ; multiply: 14-byte product
dv0         equ     WRK+$430        ; divide: remainder (9)
dv1         equ     dv0+1
dv2         equ     dv0+2
dv3         equ     dv0+3
dv4         equ     dv0+4
dv5         equ     dv0+5
dv6         equ     dv0+6
dv7         equ     dv0+7
dv8         equ     dv0+8
df0         equ     WRK+$439        ; and divisor (9)
df1         equ     df0+1
df2         equ     df0+2
df3         equ     df0+3
df4         equ     df0+4
df5         equ     df0+5
df6         equ     df0+6
df7         equ     df0+7
df8         equ     df0+8
qe          equ     WRK+$442        ; result exponent (16 bits)
qi          equ     WRK+$444
qj          equ     WRK+$445
qa          equ     WRK+$446
qoff        equ     WRK+$447        ; SIN/COS quadrant
atsg        equ     WRK+$448        ; ATN sign
atfl        equ     WRK+$449        ; ATN: 1 inverted, 2 shifted by PI/6
sqcnt       equ     WRK+$44A
lge         equ     WRK+$44B        ; LOG/EXP: power of 2 (16 bits)
pwn         equ     WRK+$44D        ; ^: the power
pwk         equ     WRK+$44F
dexp        equ     WRK+$451        ; decimal exponent (16 bits)
ndig        equ     WRK+$453
fseen       equ     WRK+$454
fdot        equ     WRK+$455
fnsg        equ     WRK+$456
fdbl        equ     WRK+$457        ; the number being read is double
fdflt       equ     WRK+$458        ; read the next number as double
oprec       equ     WRK+$459        ; precision of the number printed
ndmax       equ     WRK+$45A        ; its digits: 9 or 16
dcnt        equ     WRK+$45B
pwp         equ     WRK+$45C        ; ^ and MOD: the result's precision
pcnt        equ     WRK+$45D
pptr        equ     WRK+$45E
optr        equ     WRK+$460
ptop        equ     WRK+$462
dptr        equ     WRK+$464
nint        equ     WRK+$468        ; 64-bit whole number
ntmp8       equ     WRK+$470
ft1         equ     WRK+$478        ; 5-byte temporaries
ft2         equ     WRK+$47D
ft3         equ     WRK+$482
ft4         equ     WRK+$487
ft5         equ     WRK+$48C
ft6         equ     WRK+$491
ft7         equ     WRK+$496        ; 8-byte: MOD
ft8         equ     WRK+$49E
ftf         equ     WRK+$4A6        ; INT, ^
ftf2        equ     WRK+$4AE
pz          equ     WRK+$4B6        ; polynomial variable (5)
forlim      equ     WRK+$4BB        ; FOR limit, then step (8 each)
forstp      equ     WRK+$4C3
pwb         equ     WRK+$4CB        ; ^: base, power, result (8 each)
pwe         equ     WRK+$4D3
pwr         equ     WRK+$4DB
ftu         equ     WRK+$4E3        ; PRINT USING: the value (8 + precision)
curfn       equ     WRK+$4EC        ; FN being run: its parameters, 0 = none
fbase       equ     WRK+$4EE        ; FN call being set up
stmp2       equ     WRK+$4F0
fntyp       equ     WRK+$4F2
dbuf        equ     WRK+$A40        ; printed digits (16)
gmode       equ     WRK+$A50        ; SCREEN: 0 text, 1 320x240, 2 256x192
gw          equ     WRK+$A51        ; its width and height
gh          equ     WRK+$A53
gcol        equ     WRK+$A55        ; the colour drawn
px          equ     WRK+$A56        ; a pixel to plot
py          equ     WRK+$A58
gx          equ     WRK+$A5A        ; a coordinate pair just read
gy          equ     WRK+$A5C
gx1         equ     WRK+$A5E        ; LINE: from
gy1         equ     WRK+$A60
gx2         equ     WRK+$A62        ; to
gy2         equ     WRK+$A64
glx         equ     WRK+$A66        ; the last point drawn
gly         equ     WRK+$A68
gdx         equ     WRK+$A6A        ; LINE: Bresenham's dx, dy, steps, error
gdy         equ     WRK+$A6C
gsx         equ     WRK+$A6E
gsy         equ     WRK+$A70
gerr        equ     WRK+$A72
ge2         equ     WRK+$A74
gcx         equ     WRK+$A76        ; CIRCLE: centre, x, y
gcy         equ     WRK+$A78
gox         equ     WRK+$A7A
goy         equ     WRK+$A7C
gn          equ     WRK+$A7E        ; span length
gpix        equ     WRK+$A80        ; POINT: the byte read
gbuf        equ     WRK+$A90        ; 32 bytes of the colour, for spans
ntext       equ     WRK+$B00        ; number as text (32)
uflen       equ     WRK+$B30        ; PRINT USING: format length
upos        equ     WRK+$B31        ; position in the format
uwrap       equ     WRK+$B32        ; went back to the start once
uflags      equ     WRK+$B33        ; 1 +lead, 2 **, 4 $, 8 commas, $10 -trail, $20 +trail, $40 ^^^^
uint        equ     WRK+$B34        ; places before the point
udec        equ     WRK+$B35        ; after it
udot        equ     WRK+$B36        ; there is a point
uw          equ     WRK+$B37        ; field width
ublen       equ     WRK+$B38
uneg        equ     WRK+$B39
ucnt        equ     WRK+$B3A
uni         equ     WRK+$B3B        ; ^^^^: digits before the point
usig        equ     WRK+$B3C        ; digits shown
uexp        equ     WRK+$B3D        ; the exponent shown
ufmt        equ     WRK+$B40        ; the format (128)
ubuf        equ     WRK+$BC0        ; 10 digits
ubody       equ     WRK+$BD0        ; the number as printed (40)

; ---- tokens ----------------------------------------------------------
T_END       equ     $80
T_PRINT     equ     $81
T_LET       equ     $82
T_INPUT     equ     $83
T_IF        equ     $84
T_GOTO      equ     $85
T_GOSUB     equ     $86
T_RETURN    equ     $87
T_FOR       equ     $88
T_NEXT      equ     $89
T_REM       equ     $8A
T_STOP      equ     $8B
T_DIM       equ     $8C
T_POKE      equ     $8D
T_CLS       equ     $8E
T_LIST      equ     $8F
T_RUN       equ     $90
T_NEW       equ     $91
T_LOAD      equ     $92
T_SAVE      equ     $93
T_DIR       equ     $94
T_BYE       equ     $95
T_ON        equ     $96
T_SLEEP     equ     $97
T_SOUND     equ     $98
T_LOCATE    equ     $99
T_DATA      equ     $9A
T_READ      equ     $9B
T_RESTORE   equ     $9C
T_KILL      equ     $9D
T_CLEAR     equ     $9E
T_RANDOMIZE equ     $9F
T_OPEN      equ     $A0
T_CLOSE     equ     $A1
T_WRITE     equ     $A2
T_LINE      equ     $A3
T_SCREEN    equ     $A4
T_PSET      equ     $A5
T_CIRCLE    equ     $A6
T_DEF       equ     $A7
T_ELSE      equ     $A8         ; last token that starts a statement
T_THEN      equ     $A9
T_TO        equ     $AA
T_STEP      equ     $AB
T_AND       equ     $AC
T_OR        equ     $AD
T_NOT       equ     $AE
T_MOD       equ     $AF
T_TAB       equ     $B0
T_SPC       equ     $B1
T_FN        equ     $B2
T_USING     equ     $B3
T_ABS       equ     $B4         ; first function
T_RND       equ     $B5
T_PEEK      equ     $B6
T_LEN       equ     $B7
T_ASC       equ     $B8
T_VAL       equ     $B9
T_SGN       equ     $BA
T_TIMER     equ     $BB
T_FRE       equ     $BC
T_INT       equ     $BD
T_FIX       equ     $BE
T_SQR       equ     $BF
T_SIN       equ     $C0
T_COS       equ     $C1
T_TAN       equ     $C2
T_ATN       equ     $C3
T_EXP       equ     $C4
T_LOG       equ     $C5
T_CINT      equ     $C6
T_CSNG      equ     $C7
T_CDBL      equ     $C8
T_EOF       equ     $C9
T_POINT     equ     $CA
T_INSTR     equ     $CB
T_CHR       equ     $CC
T_STR       equ     $CD
T_HEX       equ     $CE
T_LEFT      equ     $CF
T_RIGHT     equ     $D0
T_MID       equ     $D1
T_INKEY     equ     $D2         ; last function
T_AS        equ     $D3         ; after the functions, so ASC is found first
T_OUTPUT    equ     $D4
T_APPEND    equ     $D5

            ifdef   ROMBASIC
            org     $8000
            fcc     "BA"            ; the shell's BASIC command looks for it
            else
            org     $1000
            endc

; ======================================================================
;  Start, the OK prompt and line entry
; ======================================================================
start:      lds     #STKTOP
            ldx     #conout
            stx     outv
            clr     col
            clr     lastcr
            clr     fopenf
            OS      SYS_TIME        ; seed RND from the clock
            ora     #$01
            std     seed
            jsr     warm            ; keep a program left from last time
            bcc     st1
            jsr     newprog
st1:        jsr     clrvars
            ldx     #msg_hello
            jsr     puts
            jsr     gc
            ldd     strtop
            subd    vartop
            jsr     putunum
            ldx     #msg_free
            jsr     puts

ready:      lds     #STKTOP
            ldx     #conout
            stx     outv
            ldx     curline         ; a program stopped: close its file
            beq     rd00
            jsr     dclose
rd00:       tst     gmode           ; graphics end with the program
            beq     rd01
            jsr     gtext
rd01:       ldd     #0
            std     curline
            std     curfn
            std     fbase
            tst     fopenf
            beq     rd0
            clr     fopenf
            lda     #VCMD_FCLOSE
            OS      SYS_FCMD
rd0:        jsr     newln
            ldx     #msg_ok
            jsr     puts
rd1:        ldd     #0
            std     curline
            jsr     getline
            bcs     rd1             ; ^C: just a fresh line
            jsr     tokenize
            ldy     #tokbuf
            lda     ,y
            beq     rd1
            jsr     isdig
            bcs     rd2
            jsr     edline          ; a numbered line: store it
            bra     rd1
rd2:        jmp     newstmt         ; anything else: run it now

; Is the program text from a previous run still intact?  C=1 if not.
warm:       ldd     magic
            cmpd    #MAGIC
            bne     wm8
            ldx     #progbase
wm1:        cmpx    progend
            beq     wm9
            bhi     wm8
            ldb     2,x
            cmpb    #4
            blo     wm8
            abx
            cmpx    #HEAPEND
            blo     wm1
wm8:        orcc    #$01
            rts
wm9:        andcc   #$FE
            rts

newprog:    ldx     #progbase
            stx     progend
            ldd     #MAGIC
            std     magic
            rts

; Forget all variables, arrays, FOR/GOSUB and DATA positions.
clrvars:    ldd     progend
            std     vartop
            ldd     #HEAPEND
            std     strtop
            ldd     #cstk
            std     cstkp
            ldd     #0
            std     datap
            ldd     #sstk
            std     ssp
            rts

; Y -> tokbuf with a line number: add, replace or delete that line.
edline:     tfr     y,x
            jsr     parsenum
            tfr     x,y
            cmpd    #0
            lbeq    snerr
            std     lnum
            jsr     clrvars
            tfr     y,x             ; body length, with its NUL
el0:        tst     ,x+
            bne     el0
            tfr     x,d
            pshs    y
            subd    ,s++
            addd    #3              ; + line number and length
            std     tlen
            ldd     lnum
            jsr     findln
            bcs     el2
            jsr     delline         ; replacing: drop the old one
el2:        tst     ,y
            beq     el9             ; only a number: that was a delete
            ldd     progend         ; room for it below the arrays?
            addd    tlen
            addd    #128
            cmpd    #HEAPEND
            lbhi    omerr
            pshs    x
            ldu     progend
            ldd     progend
            addd    tlen
            std     progend
            tfr     d,x
el3:        cmpu    ,s              ; open a gap at the insert point
            beq     el4
            lda     ,-u
            sta     ,-x
            bra     el3
el4:        puls    x
            ldd     lnum
            std     ,x
            ldb     tlen+1
            stb     2,x
            leax    3,x
el5:        lda     ,y+
            sta     ,x+
            bne     el5
el9:        jmp     clrvars         ; the variables start after it

; Delete the line at X.  Keeps X.
delline:    pshs    x
            ldu     ,s
            ldb     2,x
            abx
dl1:        cmpx    progend
            beq     dl2
            lda     ,x+
            sta     ,u+
            bra     dl1
dl2:        stu     progend
            puls    x,pc

; Find line D -> X = it, or the line after where it would be.  C=0 if
; it exists.
findln:     ldx     #progbase
fl1:        cmpx    progend
            bhs     fl8
            cmpd    ,x
            beq     fl9
            blo     fl8
            pshs    d
            ldb     2,x
            abx
            puls    d
            bra     fl1
fl8:        orcc    #$01
            rts
fl9:        andcc   #$FE
            rts

; ======================================================================
;  Tokenizer: lbuf -> tokbuf.  Keywords become one byte each, letters
;  are upper-cased and spaces dropped, except in strings, REM and DATA.
; ======================================================================
tokenize:   pshs    y
            ldx     #lbuf
            ldu     #tokbuf
tk1:        lda     ,x
            beq     tk9
            cmpa    #$20
            beq     tk2
            cmpa    #'"
            beq     tk4
            ldb     #T_PRINT
            cmpa    #'?
            beq     tk3
            ldb     #T_REM
            cmpa    #$27            ; ' is REM
            beq     tk3
            jsr     kwmatch
            bcc     tk5
            lda     ,x
            jsr     upcase
            sta     ,u+
tk2:        leax    1,x
            bra     tk1
tk3:        leax    1,x
            tfr     b,a
tk5:        sta     ,u+
            cmpa    #T_REM          ; the rest of the line as it is
            beq     tk7
            cmpa    #T_DATA
            beq     tk7
            bra     tk1
tk4:        sta     ,u+             ; a string, up to the closing quote
            leax    1,x
            lda     ,x
            beq     tk9
            cmpa    #'"
            bne     tk4
            sta     ,u+
            leax    1,x
            bra     tk1
tk7:        lda     ,x+
            sta     ,u+
            bne     tk7
            puls    y,pc
tk9:        clr     ,u
            puls    y,pc

; Keyword at X?  -> A = token, X past it, C=0.  C=1 if none.
kwmatch:    pshs    x,y
            ldy     #kwtab
            ldb     #$80
km1:        ldx     ,s
km2:        lda     ,x+
            bsr     upcase
            eora    ,y
            beq     km3             ; same, and more to come
            cmpa    #$80
            beq     km5             ; same, and it was the last letter
km4:        tst     ,y+             ; differs: skip to the next keyword
            bpl     km4
            incb
            tst     ,y
            bne     km1
            orcc    #$01
            puls    x,y,pc
km3:        leay    1,y
            bra     km2
km5:        stx     ,s
            tfr     b,a
            andcc   #$FE
            puls    x,y,pc

upcase:     cmpa    #'a
            blo     uc9
            cmpa    #'z
            bhi     uc9
            suba    #$20
uc9:        rts

; C=0 if A is a digit
isdig:      cmpa    #'0
            blo     id8
            cmpa    #'9
            bhi     id8
            andcc   #$FE
            rts
id8:        orcc    #$01
            rts

; C=0 if A is a letter A-Z
isalpha:    cmpa    #'A
            blo     id8
            cmpa    #'Z
            bhi     id8
            andcc   #$FE
            rts

kwtab:      fcs     "END"
            fcs     "PRINT"
            fcs     "LET"
            fcs     "INPUT"
            fcs     "IF"
            fcs     "GOTO"
            fcs     "GOSUB"
            fcs     "RETURN"
            fcs     "FOR"
            fcs     "NEXT"
            fcs     "REM"
            fcs     "STOP"
            fcs     "DIM"
            fcs     "POKE"
            fcs     "CLS"
            fcs     "LIST"
            fcs     "RUN"
            fcs     "NEW"
            fcs     "LOAD"
            fcs     "SAVE"
            fcs     "DIR"
            fcs     "BYE"
            fcs     "ON"
            fcs     "SLEEP"
            fcs     "SOUND"
            fcs     "LOCATE"
            fcs     "DATA"
            fcs     "READ"
            fcs     "RESTORE"
            fcs     "KILL"
            fcs     "CLEAR"
            fcs     "RANDOMIZE"
            fcs     "OPEN"
            fcs     "CLOSE"
            fcs     "WRITE"
            fcs     "LINE"
            fcs     "SCREEN"
            fcs     "PSET"
            fcs     "CIRCLE"
            fcs     "DEF"
            fcs     "ELSE"
            fcs     "THEN"
            fcs     "TO"
            fcs     "STEP"
            fcs     "AND"
            fcs     "OR"
            fcs     "NOT"
            fcs     "MOD"
            fcs     "TAB"
            fcs     "SPC"
            fcs     "FN"
            fcs     "USING"
            fcs     "ABS"
            fcs     "RND"
            fcs     "PEEK"
            fcs     "LEN"
            fcs     "ASC"
            fcs     "VAL"
            fcs     "SGN"
            fcs     "TIMER"
            fcs     "FRE"
            fcs     "INT"
            fcs     "FIX"
            fcs     "SQR"
            fcs     "SIN"
            fcs     "COS"
            fcs     "TAN"
            fcs     "ATN"
            fcs     "EXP"
            fcs     "LOG"
            fcs     "CINT"
            fcs     "CSNG"
            fcs     "CDBL"
            fcs     "EOF"
            fcs     "POINT"
            fcs     "INSTR"
            fcs     "CHR$"
            fcs     "STR$"
            fcs     "HEX$"
            fcs     "LEFT$"
            fcs     "RIGHT$"
            fcs     "MID$"
            fcs     "INKEY$"
            fcs     "AS"
            fcs     "OUTPUT"
            fcs     "APPEND"
            fcb     0

; ======================================================================
;  Running statements.  Y is the text pointer everywhere.
; ======================================================================
newstmt:    ldx     #sstk           ; no strings live across statements
            stx     ssp
            jsr     chkbrk
            lda     ,y+
            beq     eol
            cmpa    #':
            beq     newstmt
            cmpa    #T_ELSE         ; reached ELSE after a true THEN part
            beq     ns_rem
            cmpa    #$80
            blo     ns_let
            cmpa    #T_ELSE
            lbhi    snerr
            suba    #$80
            asla
            ldx     #stmttab
            jsr     [a,x]
after:      lda     ,y              ; the statement must end here
            beq     newstmt
            cmpa    #':
            beq     newstmt
            cmpa    #T_ELSE
            lbne    snerr
ns_rem:     jsr     st_rem
            bra     newstmt
ns_let:     leay    -1,y
            jsr     st_let
            bra     after

; End of a line: on to the next one, or back to OK.
eol:        ldx     curline
            lbeq    ready
            ldb     2,x
            abx
            cmpx    progend
            lbhs    ready
            stx     curline
            leay    3,x
            bra     newstmt

; Carry on at the start of line X.
goline:     stx     curline
            leay    3,x
            lds     #STKTOP
            bra     newstmt

stmttab:    fdb     st_end,st_print,st_let,st_input,st_if,st_goto
            fdb     st_gosub,st_return,st_for,st_next,st_rem,st_stop
            fdb     st_dim,st_poke,st_cls,st_list,st_run,st_new
            fdb     st_load,st_save,st_dir,st_bye,st_on,st_sleep
            fdb     st_sound,st_locate,st_rem,st_read,st_restore
            fdb     st_kill,st_clear,st_random,st_open,st_close,st_write
            fdb     st_line,st_screen,st_pset,st_circle,st_def

; Z=1 if the statement ends at Y (end of line, : or ELSE).  A = ,y
endst:      lda     ,y
            beq     es9
            cmpa    #':
            beq     es9
            cmpa    #T_ELSE
es9:        rts

; Stop if ^C was typed.  Other keys stay queued for INPUT and INKEY$.
chkbrk:     OS      SYS_BREAK
            bcc     brk
            rts

brk:        jsr     newln
            ldx     #msg_break
            jmp     err2

; ---- statements ------------------------------------------------------
st_end:     jmp     ready

st_stop:    ldx     #msg_break
            jsr     newln
            jmp     err2

st_rem:     lda     ,y+             ; skip the rest of the line
            bne     st_rem
            leay    -1,y
            rts

st_bye:     OS      SYS_EXIT

st_new:     jsr     dclose
            jsr     newprog
            jsr     clrvars
            jmp     ready

st_clear:   jmp     clrvars

st_restore: ldd     #0
            std     datap
            rts

st_random:  jsr     endst
            beq     sr1
            jsr     iexpr
            bra     sr2
sr1:        OS      SYS_TIME
sr2:        cmpd    #0
            bne     sr3
            incb
sr3:        std     seed
            rts

; LET v = expr
st_let:     jsr     lvalue
            lda     vtype
            pshs    a,x
            jsr     need
            fcb     '=
            jsr     expr
            puls    a,x             ; the variable's type
            cmpa    #1
            beq     let1
            tst     vtype
            lbne    tmerr
            jmp     setnum
let1:       tst     vtype
            lbeq    tmerr
            bra     setsvar

; Store FAC in the number variable at X of type A (0 single, 2 %, 3
; double).
setnum:     tsta
            lbeq    fst
            cmpa    #3
            lbeq    fstd
            pshs    x
            jsr     fac2i
            puls    x
            std     ,x
            rts

; Load the number variable at X of type A into FAC.
getnum:     tsta
            lbeq    fld
            cmpa    #3
            lbeq    fldd
            ldd     ,x
            jmp     fltd

; Pop the top string into the variable slot at X.
setsvar:    pshs    x
            jsr     spop
            puls    u
; Copy B characters from X into the string space for the descriptor at
; U.  X must not point into the string space (a GC may move it).
setstr:     tstb
            bne     ss0
            clr     ,u
            rts
ss0:        pshs    b,x,u
            jsr     salloc          ; D = room for B bytes
            ldu     3,s
            std     1,u
            ldb     ,s
            stb     ,u
            ldu     1,u
            ldx     1,s
ss1:        lda     ,x+
            sta     ,u+
            decb
            bne     ss1
            puls    b,x,u
ss2:        rts

; B bytes in the string space -> D = their address.  Packs the strings
; if there isn't room.
salloc:     pshs    b
            bsr     sal1
            bcc     sal9
            jsr     gc
            ldb     ,s
            bsr     sal1
            lbcs    omerr
sal9:       leas    1,s
            rts
sal1:       pshs    b               ; strtop - B, C=1 if below vartop
            ldd     strtop
            subb    ,s+
            sbca    #0
            cmpd    vartop
            blo     sal8
            std     strtop
            andcc   #$FE
            rts
sal8:       orcc    #$01
            rts

; Pack the strings at the top of the string space, dropping the ones no
; variable uses any more.  Each pass moves the highest string below
; gcbnd up against the ones already packed.  Keeps all registers.
gc:         pshs    d,x,y,u
            ldd     #HEAPEND
            std     gcnew
            std     gcbnd
gc1:        ldd     #0
            std     gcbest
            std     gcdesc
            ldx     progend
gc2:        cmpx    vartop
            bhs     gc6
            lda     ,x
            bita    #$20
            bne     gc5             ; a DEF FN
            anda    #$C0
            cmpa    #$C0
            bne     gc5             ; not strings
            leau    4,x
            ldd     #1
            tst     1,x
            bpl     gc3
            ldb     6,x             ; a string array: skip the sizes
            aslb
            leau    b,x
            leau    7,u
            ldd     4,x
gc3:        pshs    d
gc4:        tst     ,u
            beq     gc4a
            ldd     1,u
            cmpd    gcbnd
            bhs     gc4a
            cmpd    gcbest
            bls     gc4a
            std     gcbest
            stu     gcdesc
gc4a:       leau    3,u
            ldd     ,s
            subd    #1
            std     ,s
            bne     gc4
            leas    2,s
gc5:        ldd     2,x
            leax    d,x
            bra     gc2
gc6:        ldu     gcdesc
            beq     gc9
            ldb     ,u              ; move it up to gcnew - length
            clra
            pshs    d
            ldd     gcnew
            subd    ,s
            std     gcnew
            ldx     1,u
            stx     gcbnd
            std     1,u
            addd    ,s++            ; copy from the end (it moves up)
            tfr     d,y
            ldb     ,u
            abx
gc7:        lda     ,-x
            sta     ,-y
            decb
            bne     gc7
            lbra    gc1
gc9:        ldd     gcnew
            std     strtop
            puls    d,x,y,u,pc

; PRINT [item {; | , item}] [; | ,]
st_print:   jsr     endst
            lbeq    pr_nl
            cmpa    #'#
            lbeq    pr_file
            cmpa    #'@
            lbeq    pr_at
            cmpa    #T_USING
            lbeq    pr_using
pr1:        cmpa    #';
            beq     pr_semi
            cmpa    #',
            beq     pr_comma
            cmpa    #T_TAB
            beq     pr_tab
            cmpa    #T_SPC
            beq     pr_spc
            jsr     expr
            tst     vtype
            bne     pr2
            jsr     fout
            jsr     putsb
            bra     st_print
pr2:        jsr     spop
            jsr     putsb
            bra     st_print
pr_semi:    leay    1,y
            jsr     endst
            bne     pr1
            rts
pr_comma:   leay    1,y
            ldx     outv            ; (no line width in a file)
            cmpx    #conout
            bne     pr_c1
            lda     col             ; no room for another zone: new line
            cmpa    #70
            blo     pr_c1
            jsr     crlf
            bra     pr_c3
pr_c1:      jsr     space           ; to the next 10-column zone
            lda     col
pr_c2:      suba    #10
            bhi     pr_c2
            bne     pr_c1
pr_c3:      jsr     endst
            bne     pr1
            rts
pr_tab:     leay    1,y
            jsr     parg
            tfr     b,a
pr_t1:      cmpa    col
            bls     st_print
            pshs    a
            jsr     space
            puls    a
            bra     pr_t1
pr_spc:     leay    1,y             ; SPC(n): n spaces
            jsr     parg
            tsta
            bmi     pr_s9
            beq     pr_s1
            ldb     #255
pr_s1:      tstb
            beq     pr_s9
            jsr     space
            decb
            bra     pr_s1
pr_s9:      jmp     st_print
pr_nl:      jmp     newln_f

; INPUT ["prompt";] v [,v ...]
st_input:   lda     ,y
            cmpa    #'#
            lbeq    in_file
            cmpa    #'"
            bne     in1
            jsr     expr
            jsr     spop
            jsr     putsb
            lda     ,y+
            cmpa    #',
            beq     in2
            cmpa    #';
            lbne    snerr
in1:        ldx     #msg_quest
            jsr     puts
in2:        pshs    y
in3:        jsr     getline
            lbcs    brk
            ldx     #lbuf
            stx     inptr
in4:        jsr     lvalue
            lda     vtype
            cmpa    #1
            beq     in6
            pshs    a,x
            cmpa    #3
            bne     in4a
            inc     fdflt           ; a # variable gets all the digits
in4a:       ldx     inptr
            jsr     fin
            bcs     in_redo
            jsr     skipspx
            stx     inptr
            tsta
            beq     in5
            cmpa    #',
            bne     in_redo
in5:        puls    a,x
            jsr     setnum
            bra     in7
in6:        tfr     x,u             ; a string: up to a comma if more
            ldx     inptr           ; variables follow, else the rest
            jsr     skipspx
            pshs    x
            clrb
in6a:       lda     ,x
            beq     in6b
            cmpa    #',
            bne     in6c
            lda     ,y
            cmpa    #',
            beq     in6b
in6c:       leax    1,x
            incb
            bra     in6a
in6b:       stx     inptr
            puls    x
            jsr     setstr
in7:        lda     ,y
            cmpa    #',
            bne     in9
            leay    1,y
            ldx     inptr
            jsr     skipspx
            lda     ,x
            beq     in8
            leax    1,x             ; past the comma
            stx     inptr
            bra     in4
in8:        ldx     #msg_quest2     ; more variables than items: ask again
            jsr     puts
            jsr     getline
            lbcs    brk
            ldx     #lbuf
            stx     inptr
            lbra    in4
in9:        leas    2,s
            rts
in_redo:    leas    3,s
            ldx     #msg_redo
            jsr     puts
            ldy     ,s
            ldx     #msg_quest
            jsr     puts
            lbra    in3

skipspx:    lda     ,x
            cmpa    #$20
            bne     sx9
            leax    1,x
            bra     skipspx
sx9:        rts

; IF expr THEN stmt | line [ELSE stmt | line]
st_if:      jsr     nexpr
            tst     fexp
            beq     if_f
            lda     ,y
            cmpa    #T_GOTO
            beq     if_go
            jsr     need
            fcb     T_THEN
if_ln:      lda     ,y              ; THEN 100 means THEN GOTO 100
            jsr     isdig
            lbcc    st_goto
if_go:      lds     #STKTOP
            jmp     newstmt
if_f:       lda     ,y+             ; false: look for ELSE on this line
            beq     if_f9
            cmpa    #'"
            beq     if_q
            cmpa    #T_REM
            beq     if_f9
            cmpa    #T_DATA
            beq     if_f9
            cmpa    #T_ELSE
            bne     if_f
            bra     if_ln
if_q:       lda     ,y+
            beq     if_f9
            cmpa    #'"
            bne     if_q
            bra     if_f
if_f9:      leay    -1,y
            rts

st_goto:    jsr     iexpr
            jsr     findln
            lbcs    ulerr
            jmp     goline

st_gosub:   jsr     iexpr
            jsr     findln
            lbcs    ulerr
            pshs    x
            jsr     pushg
            puls    x
            jmp     goline

; Push a GOSUB entry returning to Y.
pushg:      ldu     cstkp
            cmpu    #CSTKEND
            lbhs    cserr
            lda     #'G
            sta     ,u
            sty     CS_TXT,u
            ldx     curline
            stx     CS_LN,u
            leau    CSSZ,u
            stu     cstkp
            rts

st_return:  ldu     cstkp
rt1:        cmpu    #cstk
            lbeq    rgerr
            leau    -CSSZ,u         ; FOR loops inside the subroutine go too
            lda     ,u
            cmpa    #'G
            bne     rt1
            stu     cstkp
            ldy     CS_TXT,u
            ldx     CS_LN,u
            stx     curline
            rts

; ON expr GOTO | GOSUB line, line ...
st_on:      jsr     iexpr
            pshs    d               ; 3,s = n, counted down
            lda     ,y+
            cmpa    #T_GOTO
            beq     on1
            cmpa    #T_GOSUB
            lbne    snerr
on1:        pshs    a               ; 2,s = GOTO or GOSUB
            ldx     #0
            pshs    x               ; 0,s = line picked, 0 = none
on2:        ldd     3,s
            subd    #1
            std     3,s
            jsr     iexpr
            ldx     3,s
            bne     on3
            std     ,s
on3:        lda     ,y
            cmpa    #',
            bne     on4
            leay    1,y
            bra     on2
on4:        ldd     ,s
            beq     on9             ; out of range: carry on
            jsr     findln
            lbcs    ulerr
            lda     2,s
            cmpa    #T_GOSUB
            bne     on5
            pshs    x
            jsr     pushg           ; returns after the whole list
            puls    x
on5:        jmp     goline
on9:        leas    5,s
            rts

; FOR v = a TO b [STEP c]
st_for:     jsr     lvalue
            lda     vtype
            cmpa    #1
            lbeq    tmerr
            ldb     -1,y
            cmpb    #')
            lbeq    snerr           ; no array elements
            pshs    a,x             ; the variable and its type
            jsr     need
            fcb     '=
            jsr     nexpr
            ldx     1,s
            lda     ,s
            jsr     setnum
            jsr     need
            fcb     T_TO
            jsr     nexpr
            ldx     #forlim
            jsr     fstd
            ldx     #c_one
            jsr     fld
            lda     ,y
            cmpa    #T_STEP
            bne     fr0
            leay    1,y
            jsr     nexpr
fr0:        ldx     #forstp
            jsr     fstd
            ldx     #forlim         ; already past the limit: skip it
            jsr     argldd
            ldx     1,s
            lda     ,s
            jsr     getnum
            jsr     fcmp
            tst     forstp+1        ; the step's sign
            bmi     fr0b
            bitb    #1              ; limit < value
            bne     fskip
            bra     fr0c
fr0b:       bitb    #4              ; limit > value
            bne     fskip
fr0c:       ldu     cstkp           ; a loop on the same variable ends
fr1:        cmpu    #cstk
            beq     fr3
            leau    -CSSZ,u
            lda     ,u
            cmpa    #'F
            bne     fr3
            ldx     1,u
            cmpx    1,s
            bne     fr1
            stu     cstkp
fr3:        ldu     cstkp
            cmpu    #CSTKEND
            lbhs    cserr
            lda     #'F
            sta     ,u
            puls    a,x
            stx     1,u
            sta     CS_TYP,u
            ldx     #forlim         ; limit and step
            leau    CS_LIM,u
            ldb     #16
fr4:        lda     ,x+
            sta     ,u+
            decb
            bne     fr4
            sty     ,u              ; CS_TXT
            ldx     curline
            stx     2,u             ; CS_LN
            leau    CSSZ-CS_TXT,u
            stu     cstkp
            rts

; Skip the body of a FOR loop that runs 0 times: on after its NEXT.
fskip:      leas    3,s
            lda     #1
            pshs    a               ; loops open
fs1:        lda     ,y+
            beq     fs7
            cmpa    #'"
            beq     fs5
            cmpa    #T_REM
            beq     fs6
            cmpa    #T_DATA
            beq     fs6
            cmpa    #T_FOR
            bne     fs2
            inc     ,s
            bra     fs1
fs2:        cmpa    #T_NEXT
            bne     fs1
fs3:        dec     ,s              ; each variable after NEXT closes one
            beq     fs4
            lda     ,y
            jsr     isalpha
            bcs     fs1
            jsr     varname
            lda     ,y
            cmpa    #',
            bne     fs1
            leay    1,y
            bra     fs3
fs4:        leas    1,s             ; found it
            lda     ,y
            jsr     isalpha
            bcs     fs9
            jsr     varname
            lda     ,y
            cmpa    #',             ; NEXT I,J: J's loop goes on as usual
            bne     fs9
            leay    1,y
            bra     st_next
fs9:        rts
fs5:        lda     ,y+
            beq     fs7
            cmpa    #'"
            bne     fs5
            bra     fs1
fs6:        lda     ,y+
            bne     fs6
fs7:        ldx     curline         ; on to the next line
            beq     fs8
            ldb     2,x
            abx
            cmpx    progend
            lbhs    fnerr
            stx     curline
            leay    3,x
            bra     fs1
fs8:        leay    -1,y            ; direct mode: just this line
            leas    1,s
            rts

; NEXT [v [,v ...]]
st_next:    ldx     #0
            jsr     endst
            beq     nx0
            jsr     lvalue
nx0:        pshs    x
            ldu     cstkp
nx1:        cmpu    #cstk
            lbeq    nferr
            leau    -CSSZ,u
            lda     ,u
            cmpa    #'F
            lbne    nferr
            ldx     ,s
            beq     nx2
            cmpx    1,u
            bne     nx1             ; inner loops left open are dropped
nx2:        ldx     1,u             ; variable + step
            lda     CS_TYP,u
            jsr     getnum
            pshs    u
            leax    CS_STEP,u
            jsr     argldd
            jsr     fadd
            ldu     ,s
            ldx     1,u
            lda     CS_TYP,u
            jsr     setnum
            ldu     ,s
            ldx     1,u             ; compare the value as stored
            lda     CS_TYP,u
            jsr     getnum
            ldu     ,s
            leax    CS_LIM,u
            jsr     argldd
            jsr     fcmp
            puls    u
            tst     CS_STEP+1,u     ; the step's sign
            bmi     nx3
            bitb    #1              ; limit < value: done
            bne     nx5
            bra     nx4
nx3:        bitb    #4              ; limit > value: done
            bne     nx5
nx4:        ldy     CS_TXT,u        ; loop again
            ldx     CS_LN,u
            stx     curline
            leau    CSSZ,u
            stu     cstkp
            leas    2,s
            rts
nx5:        stu     cstkp           ; done with this loop
            leas    2,s
            lda     ,y
            cmpa    #',
            bne     nx9
            leay    1,y
            jsr     lvalue
            lbra    nx0
nx9:        rts

; DIM v(n [,m ...]) [, w$(...) ...]
st_dim:     jsr     varname
            orb     #$80            ; an array
            pshs    d               ; 9,s name
            leas    -9,s            ; 0,s dimensions, 1,s sizes
            clr     ,s
            jsr     need
            fcb     '(
dm1:        lda     ,s
            cmpa    #MAXDIM
            lbhs    snerr
            jsr     iexpr
            addd    #1              ; 0 to n is n+1 elements
            pshs    d
            ldb     2,s
            aslb
            leax    3,s
            abx
            puls    d
            std     ,x
            inc     ,s
            lda     ,y+
            cmpa    #',
            beq     dm1
            cmpa    #')
            lbne    snerr
            ldd     9,s
            tfr     s,x
            bsr     dimarr
            leas    11,s
            lda     ,y
            cmpa    #',
            bne     dm9
            leay    1,y
            bra     st_dim
dm9:        rts

; Make array D (name).  X -> its dimensions (1 byte) and their sizes
; (2 bytes each).  -> X = its entry.
dimarr:     pshs    d,x             ; 0,s name, 2,s sizes
            jsr     srchvar
            lbcc    dderr
            ldx     2,s
            ldb     ,x+
            pshs    b               ; 0,s dimensions
            ldd     #1
            pshs    d               ; 0,s elements so far
            ldb     2,s
            pshs    b,x             ; 0,s left to do, 1,s -> next size
da1:        ldx     1,s
            ldd     ,x++
            stx     1,s
            cmpd    #0
            lble    bserr
            cmpd    #MAXEL
            lbhi    bserr
            pshs    d
            ldx     #MAXEL          ; would elements * size be too many?
            jsr     udiv
            cmpd    5,s
            lblo    bserr
            puls    d
            ldx     3,s
            jsr     imul
            std     3,s
            dec     ,s
            bne     da1
            leas    3,s             ; 0,s elements, 2,s dimensions, 3,s name
            lda     3,s             ; data: count, dimensions, sizes and
            jsr     ntype           ; the elements
            ldx     #esize
            lda     a,x
            ldx     ,s
            jsr     mulsz
            addd    #3
            pshs    d
            ldb     4,s
            clra
            aslb
            addd    ,s++
            tfr     d,x
            ldd     3,s
            jsr     newvar
            ldd     ,s
            std     4,x
            ldu     5,s
            ldb     ,u+
            stb     6,x
            pshs    x
            leax    7,x
            aslb
da3:        lda     ,u+
            sta     ,x+
            decb
            bne     da3
            puls    x
            leas    7,s
            rts

; Find variable D (name) -> X = its entry, C=0.  C=1 if there is none.
; Keeps D.
srchvar:    pshs    d
            ldx     progend
vs1:        cmpx    vartop
            bhs     vs8
            ldd     ,x
            cmpd    ,s
            beq     vs9
            ldd     2,x
            leax    d,x
            bra     vs1
vs8:        puls    d
            orcc    #$01
            rts
vs9:        puls    d
            andcc   #$FE
            rts

; Find variable D (not an array), making it if it is new -> X = its
; entry.  Keeps D.
findvar:    bsr     srchvar
            bcc     fv9
            pshs    d
            jsr     ntype
            ldx     #esize
            ldb     a,x
            clra
            tfr     d,x
            ldd     ,s
fv1:        jsr     newvar
            puls    d,pc
fv9:        rts

; New variable D (name) with X bytes of data, all 0 -> X = its entry.
newvar:     pshs    d,x             ; 2,s name, 4,s data size
            tfr     x,d
            addd    #4
            pshs    d               ; 0,s entry size
            addd    vartop
            bcs     nv0
            cmpd    strtop
            bls     nv1
nv0:        jsr     gc              ; no room: pack the strings first
            ldd     ,s
            addd    vartop
            lbcs    omerr
            cmpd    strtop
            lbhi    omerr
nv1:        ldx     vartop
            ldd     2,s
            std     ,x
            ldd     ,s
            std     2,x
            leau    4,x
            ldd     4,s
nv2:        clr     ,u+
            subd    #1
            bne     nv2
            stu     vartop
            leas    6,s
            rts

; POKE addr, value
st_poke:    jsr     iexpr
            pshs    d
            jsr     need
            fcb     ',
            jsr     iexpr
            stb     [,s++]
            rts

st_cls:     ldx     #msg_cls
            jsr     puts
            clr     col
            tst     gmode
            lbne    gclear
            rts

; LOCATE row, column (1-based) - VT100 cursor position
st_locate:  jsr     iexpr
            pshs    d
            jsr     need
            fcb     ',
            jsr     iexpr
            pshs    d
            lda     #ESC
            jsr     outch
            lda     #'[
            jsr     outch
            ldd     2,s
            jsr     putnum
            lda     #';
            jsr     outch
            ldd     ,s
            jsr     putnum
            lda     #'H
            jsr     outch
            puls    d
            subd    #1
            stb     col
            puls    d,pc

; SLEEP ticks (100 a second)
st_sleep:   jsr     iexpr
            cmpd    #0
            ble     sl9
            OS      SYS_SLEEP
sl9:        rts

; SOUND register, value
st_sound:   jsr     iexpr
            pshs    b
            jsr     need
            fcb     ',
            jsr     iexpr
            tfr     b,a
            puls    b
            OS      SYS_SOUND
            rts

; READ v [, v ...]
st_read:    jsr     lvalue
            lda     vtype
            pshs    a,x
            jsr     nextdata        ; X -> the item
            lda     ,s
            cmpa    #1
            beq     rd_s
            cmpa    #3
            bne     rd_n
            inc     fdflt
rd_n:       jsr     fin
            lbcs    snerr
            pshs    x
            ldx     3,s
            lda     2,s
            jsr     setnum
            puls    x
            bra     rd_e
rd_s:       jsr     skipspx         ; "quoted" or up to a comma
            tfr     x,u
            cmpa    #'"
            bne     rd_s3
            leax    1,x
            tfr     x,u
rd_s1:      lda     ,u
            beq     rd_s2
            cmpa    #'"
            beq     rd_s2
            leau    1,u
            bra     rd_s1
rd_s3:      lda     ,u
            beq     rd_s2
            cmpa    #',
            beq     rd_s2
            leau    1,u
            bra     rd_s3
rd_s2:      pshs    u               ; 0,s end, 3,s the variable
            tfr     u,d
            pshs    x
            subd    ,s++
            tsta
            lbne    lserr
            ldu     3,s
            jsr     setstr
            puls    x
            lda     ,x
            cmpa    #'"
            bne     rd_e
            leax    1,x             ; the closing quote
rd_e:       jsr     skipspx         ; must be at a comma or the end
            tsta
            beq     rd_e1
            cmpa    #',
            lbne    snerr
            leax    1,x
rd_e1:      stx     datap
            leas    3,s
            lda     ,y
            cmpa    #',
            bne     rd9
            leay    1,y
            lbra    st_read
rd9:        rts

; -> X = next DATA item.  Error if there is none.
nextdata:   ldx     datap
            beq     nd1
            tst     ,x
            bne     nd9
            ldx     datal           ; end of that line: search on
            ldb     2,x
            abx
            bra     nd2
nd1:        ldx     #progbase
nd2:        cmpx    progend
            lbhs    oderr
            stx     datal
            leau    3,x
nd3:        lda     ,u+
            beq     nd5
            cmpa    #'"
            beq     nd4
            cmpa    #T_REM
            beq     nd5
            cmpa    #T_DATA
            bne     nd3
            stu     datap
            tfr     u,x
            tst     ,x
            beq     nd5a
nd9:        rts
nd4:        lda     ,u+
            beq     nd5
            cmpa    #'"
            bne     nd4
            bra     nd3
nd5:
nd5a:       ldx     datal
            ldb     2,x
            abx
            bra     nd2

; ======================================================================
;  LIST, RUN, LOAD, SAVE, DIR, KILL
; ======================================================================
; LIST [n | n- | -n | n-m]
st_list:    ldd     #0
            std     lstlo
            ldd     #$FFFF
            std     lsthi
            lda     ,y
            jsr     isdig
            bcs     ls1
            tfr     y,x
            jsr     parsenum
            tfr     x,y
            std     lstlo
            std     lsthi
ls1:        lda     ,y
            cmpa    #'-
            bne     ls2
            leay    1,y
            ldd     #$FFFF
            std     lsthi
            lda     ,y
            jsr     isdig
            bcs     ls2
            tfr     y,x
            jsr     parsenum
            tfr     x,y
            std     lsthi
ls2:        pshs    y
            ldx     #progbase
ls3:        cmpx    progend
            bhs     ls9
            ldd     ,x
            cmpd    lstlo
            blo     ls4
            cmpd    lsthi
            bhi     ls9
            pshs    x
            jsr     chkbrk
            puls    x
            jsr     listln
ls4:        ldb     2,x
            abx
            bra     ls3
ls9:        puls    y,pc

; Send line X through outv.  Keeps X.
listln:     pshs    x,y
            ldd     ,x
            jsr     putunum
            jsr     space
            lda     #$20
            sta     lastc
            ldy     ,s
            leay    3,y
ll1:        lda     ,y+
            beq     ll9
            bmi     ll2
            sta     lastc
            jsr     outch
            cmpa    #'"
            bne     ll1
ll1a:       lda     ,y+             ; a string, as it is
            beq     ll9
            sta     lastc
            jsr     outch
            cmpa    #'"
            bne     ll1a
            bra     ll1
ll2:        pshs    a               ; a keyword: a space before it after
            lda     lastc           ; a letter, digit, " or )
            jsr     wordch
            bcs     ll3
            jsr     space
ll3:        puls    a
            jsr     putkw
            cmpa    #T_FN           ; FNA, not FN A
            lbeq    ll1
            cmpa    #T_REM
            beq     ll5
            cmpa    #T_DATA
            beq     ll5
            lda     ,y              ; and a space after it before one
            jsr     wordch
            bcc     ll4
            ldb     -1,y            ; - or & only after a statement word
            cmpb    #T_ABS          ; (STEP -1), not a function (TIMER-T)
            bhs     ll1
            cmpa    #'(             ; ( after a statement word, not TAB(
            bne     ll3a
            cmpb    #T_TAB
            blo     ll4
            bra     ll1
ll3a:       cmpa    #'-
            beq     ll4
            cmpa    #'&
            bne     ll1
ll4:        jsr     space
            lda     #$20
            sta     lastc
            bra     ll1
ll5:        lda     ,y+             ; REM and DATA: the rest as it is
            beq     ll9
            jsr     outch
            bra     ll5
ll9:        jsr     crlf
            puls    x,y,pc

; C=0 if A is a letter, digit, quote, ), $, #, % or @
wordch:     jsr     isdig
            bcc     wc9
            jsr     isalpha
            bcc     wc9
            cmpa    #'"
            beq     wc8
            cmpa    #')
            beq     wc8
            cmpa    #'$
            beq     wc8
            cmpa    #'#
            beq     wc8
            cmpa    #'%
            beq     wc8
            cmpa    #'@
            beq     wc8
            orcc    #$01
wc9:        rts
wc8:        andcc   #$FE
            rts

; Print keyword A.  lastc = its last letter.  Keeps A, Y.
putkw:      pshs    a
            ldx     #kwtab
            suba    #$80
            beq     pk2
pk1:        tst     ,x+
            bpl     pk1
            deca
            bne     pk1
pk2:        lda     ,x+
            pshs    a
            anda    #$7F
            sta     lastc
            jsr     outch
            tst     ,s+
            bpl     pk2
            puls    a,pc

; RUN [line | "file"]
st_run:     jsr     endst
            beq     ru2
            jsr     isdig
            bcc     ru1
            lda     #1
            jsr     fnarg           ; RUN "file": LOAD it first
            jsr     loadprog
            bra     ru2
ru1:        jsr     iexpr
            pshs    d
            jsr     dclose
            jsr     clrvars
            puls    d
            jsr     findln
            lbcs    ulerr
            jmp     goline
ru2:        jsr     dclose
            jsr     clrvars
            ldx     #progbase
            cmpx    progend
            lbeq    ready
            jmp     goline

; LOAD "file" - read a program saved as text (.BAS if no extension)
st_load:    lda     #1
            jsr     fnarg
            jsr     loadprog
            jmp     ready

loadprog:   lda     #VCMD_FOPEN
            jsr     fcmdc
            inc     fopenf
            jsr     newprog
            jsr     clrvars
            clr     llen
lp1:        jsr     fread
            beq     lp9
            stx     lcnt
            ldx     #fbuf
            stx     lptr
lp2:        ldx     lptr
            lda     ,x+
            stx     lptr
            cmpa    #LF
            beq     lp4
            cmpa    #9
            bne     lp2a
            lda     #$20
lp2a:       cmpa    #$20
            blo     lp3             ; CR and other control characters
            ldb     llen
            cmpb    #LBMAX
            bhs     lp3
            ldx     #lbuf
            abx
            sta     ,x
            inc     llen
            bra     lp3
lp4:        jsr     ldline
lp3:        ldx     lcnt
            leax    -1,x
            stx     lcnt
            bne     lp2
            bra     lp1
lp9:        jsr     ldline          ; a last line without LF
            clr     fopenf
            lda     #VCMD_FCLOSE
            jmp     fcmdc

; Enter the line in lbuf (llen long) as if typed.  Lines without a
; number are skipped.
ldline:     ldx     #lbuf
            ldb     llen
            clr     b,x
            clr     llen
            jsr     tokenize
            ldy     #tokbuf
            lda     ,y
            jsr     isdig
            bcs     ldl9
            jmp     edline
ldl9:       rts

; SAVE "file" - write the program as text
st_save:    lda     #1
            jsr     fnarg
            lda     #VCMD_FCREATE
            jsr     fcmdc
            inc     fopenf
            ldd     #0
            std     fpos
            ldx     #fputc
            stx     outv
            pshs    y
            ldx     #progbase
sv1:        cmpx    progend
            bhs     sv2
            jsr     listln
            ldb     2,x
            abx
            bra     sv1
sv2:        puls    y
            ldx     #conout
            stx     outv
            jsr     fflush
            clr     fopenf
            lda     #VCMD_FCLOSE
            jmp     fcmdc

; DIR ["path"]
st_dir:     tst     dmode
            lbne    faerr
            jsr     endst
            bne     dr1
            clr     fnbuf
            ldd     #1
            jsr     setfn
            bra     dr2
dr1:        clra
            jsr     fnarg
dr2:        lda     #VCMD_DIR
            jsr     fcmdc
            inc     fopenf
dr3:        ldx     #dirbuf
            ldu     #VF_NAME
            ldd     #VF_ATTR+1-VF_NAME
            jsr     vget
            tst     dirbuf
            beq     dr9
            ldx     #dirbuf
            jsr     puts
dr4:        jsr     space           ; name in 14 columns
            lda     col
            cmpa    #14
            blo     dr4
            lda     dirbuf+VF_ATTR-VF_NAME
            bita    #$10
            beq     dr5
            ldx     #msg_dir
            jsr     puts
            bra     dr8
dr5:        ldd     dirbuf+VF_SIZE-VF_NAME
            bne     dr6
            ldd     dirbuf+VF_SIZE-VF_NAME+2
            jsr     putunum
            bra     dr8
dr6:        ldb     #10             ; 64K and up: in K
dr7:        lsr     dirbuf+VF_SIZE-VF_NAME
            ror     dirbuf+VF_SIZE-VF_NAME+1
            ror     dirbuf+VF_SIZE-VF_NAME+2
            decb
            bne     dr7
            ldd     dirbuf+VF_SIZE-VF_NAME+1
            jsr     putunum
            lda     #'K
            jsr     outch
dr8:        jsr     crlf
            jsr     chkbrk
            lda     #VCMD_DIRNEXT
            jsr     fcmdc
            bra     dr3
dr9:        clr     fopenf
            lda     #VCMD_FCLOSE
            jmp     fcmdc

; KILL "file" - delete a file (the name exactly as given)
st_kill:    clra
            jsr     fnarg
            lda     #VCMD_FDELETE
            jmp     fcmdc

; File name from a string expression -> fnbuf and VF_NAME.  A=1 adds
; .BAS to a name without a dot.
fnarg:      tst     dmode           ; the drive is busy with a data file
            lbne    faerr
            sta     fext
            jsr     sexpr
            jsr     spop
            cmpb    #58
            lbhi    lserr
            ldu     #fnbuf
            clr     ,-s             ; dot seen
fa1:        tstb
            beq     fa3
            lda     ,x+
            jsr     upcase
            sta     ,u+
            cmpa    #'.
            bne     fa2
            inc     ,s
fa2:        cmpa    #'/             ; a dot in a directory name doesn't count
            bne     fa2a
            clr     ,s
fa2a:       decb
            bra     fa1
fa3:        tst     ,s+
            bne     fa5
            tst     fext
            beq     fa5
            ldx     #s_bas
fa4:        lda     ,x+
            sta     ,u+
            bne     fa4
            leau    -1,u
fa5:        clr     ,u+
            tfr     u,d
            subd    #fnbuf
setfn:      ldx     #fnbuf
            ldu     #VF_NAME
            jmp     vput

s_bas:      fcn     ".BAS"

; Read up to 512 bytes of the open file into fbuf -> X = count, Z=1 at
; the end.
fread:      ldd     #0
            std     fpos
            ldx     #fpos
            ldu     #VF_LEN
            ldd     #2
            jsr     vput
            lda     #VCMD_FREAD
            jsr     fcmdc
            stx     fpos
            beq     fr9
            ldx     #fbuf
            ldu     #VF_DATA
            ldd     fpos
            jsr     vget
            ldx     fpos
fr9:        rts

; Output to the file buffer, written out every 512 bytes.
fputc:      pshs    d,x,y,u
            ldx     #fbuf
            ldd     fpos
            leax    d,x
            lda     ,s
            sta     ,x
            ldd     fpos
            addd    #1
            std     fpos
            cmpd    #512
            blo     fpc9
            bsr     fflush
fpc9:       puls    d,x,y,u,pc

fflush:     ldd     fpos
            beq     ffl9
            ldx     #fbuf
            ldu     #VF_DATA
            jsr     vput
            ldx     #fpos
            ldu     #VF_LEN
            ldd     #2
            jsr     vput
            lda     #VCMD_FWRITE
            jsr     fcmdc
            cmpx    fpos
            beq     ffl1
            lda     #7              ; short write: disk full
            bra     ferr
ffl1:       ldd     #0
            std     fpos
ffl9:       rts

; File command A; errors stop the program with a message.  -> X = count
fcmdc:      OS      SYS_FCMD
            bcs     ferr
            cmpx    #0
            rts

ferr:       ldx     #msg_fnodrv
            cmpa    #3
            beq     fe9
            ldx     #msg_fnofile
            cmpa    #4
            beq     fe9
            ldx     #msg_fnopath
            cmpa    #5
            beq     fe9
            ldx     #msg_fdenied
            cmpa    #7
            beq     fe9
            ldx     #msg_fexist
            cmpa    #8
            beq     fe9
            ldx     #msg_fnofat
            cmpa    #13
            beq     fe9
            ldx     #msg_ferr
fe9:        jmp     error

; X = VRAM copy source, U = mailbox address, D = count
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

; ======================================================================
;  Expressions.  The result is in FAC (vtype 0) or on the string stack
;  (vtype 1).  Precedence, lowest first: OR, AND, NOT, comparisons,
;  + -, * / \ MOD, unary minus, ^.  Pending numbers wait on the stack.
; ======================================================================
nexpr:      bsr     expr
numchk:     tst     vtype
            lbne    tmerr
            rts

; A number expression -> D (-32768 to 65535)
iexpr:      bsr     nexpr
            jmp     fac2w

sexpr:      bsr     expr
            tst     vtype
            lbeq    tmerr
            rts

; AND, OR and NOT work on 16-bit whole numbers.
expr:       bsr     andx
ex1:        lda     ,y
            cmpa    #T_OR
            bne     ex9
            leay    1,y
            bsr     numchk
            jsr     fac2w
            pshs    d
            bsr     andx
            bsr     numchk
            jsr     fac2w
            ora     ,s+
            orb     ,s+
            jsr     fltd
            bra     ex1
ex9:        rts

andx:       bsr     notx
an1:        lda     ,y
            cmpa    #T_AND
            bne     an8
            leay    1,y
            bsr     numchk
            jsr     fac2w
            pshs    d
            bsr     notx
            bsr     numchk
            jsr     fac2w
            anda    ,s+
            andb    ,s+
            jsr     fltd
            bra     an1
an8:        rts

notx:       lda     ,y
            cmpa    #T_NOT
            bne     relx
            leay    1,y
            bsr     notx
            bsr     numchk
            jsr     fac2w
            coma
            comb
            jmp     fltd

; Comparisons give -1 (true) or 0 (false).
relx:       jsr     addx
            clrb                    ; B: 1 <, 2 =, 4 >
rl1:        lda     ,y
            cmpa    #'<
            bne     rl2
            orb     #1
            bra     rl4
rl2:        cmpa    #'=
            bne     rl3
            orb     #2
            bra     rl4
rl3:        cmpa    #'>
            bne     rl5
            orb     #4
rl4:        leay    1,y
            bra     rl1
rl5:        tstb
            bne     rl6
            rts
rl6:        pshs    b
            tst     vtype
            bne     rl7
            jsr     fpush
            jsr     addx
            jsr     numchk
            jsr     fpopa
            jsr     fcmp
            bra     rl8
rl7:        jsr     addx
            tst     vtype
            lbeq    tmerr
            jsr     scmp
rl8:        clr     vtype
            andb    ,s+
            lbeq    fzero
            ldd     #-1
            jmp     fltd

addx:       bsr     mulx
ad1:        lda     ,y
            cmpa    #'+
            beq     ad2
            cmpa    #'-
            beq     ad3
            rts
ad2:        leay    1,y
            tst     vtype
            bne     ad4
            jsr     fpush
            bsr     mulx
            jsr     numchk
            jsr     fpopa
            jsr     fadd
            bra     ad1
ad3:        leay    1,y
            jsr     numchk
            jsr     fpush
            bsr     mulx
            jsr     numchk
            jsr     fpopa
            jsr     fsub
            bra     ad1
ad4:        bsr     mulx            ; string + string
            tst     vtype
            lbeq    tmerr
            jsr     sconcat
            bra     ad1

mulx:       bsr     unary
ml1:        lda     ,y
            cmpa    #'*
            beq     ml2
            cmpa    #'/
            beq     ml2
            cmpa    #$5C            ; \ whole-number division
            beq     ml2
            cmpa    #T_MOD
            beq     ml2
            rts
ml2:        leay    1,y
            pshs    a
            jsr     numchk
            jsr     fpush
            bsr     unary
            jsr     numchk
            jsr     fpopa
            puls    a
            cmpa    #'*
            bne     ml3
            jsr     fmul
            bra     ml1
ml3:        cmpa    #'/
            bne     ml4
            jsr     fdiv
            bra     ml1
ml4:        cmpa    #$5C
            bne     ml5
            jsr     fdiv
            jsr     ffix
            bra     ml1
ml5:        jsr     fmod
            bra     ml1

unary:      lda     ,y
            cmpa    #'-
            bne     un1
            leay    1,y
            bsr     unary
            jsr     numchk
            jmp     fneg
un1:        cmpa    #'+
            bne     powx
            leay    1,y
            bra     unary

powx:       bsr     prim
px1:        lda     ,y
            cmpa    #'^
            bne     px9
            leay    1,y
            jsr     numchk
            jsr     fpush
            lda     ,y              ; the power may have a minus sign
            cmpa    #'-
            bne     px2
            leay    1,y
            bsr     prim
            jsr     numchk
            jsr     fneg
            bra     px3
px2:        bsr     prim
            jsr     numchk
px3:        jsr     fpopa
            jsr     fpow
            bra     px1
px9:        rts

prim:       clr     vtype
            lda     ,y
            cmpa    #'(
            bne     pr_1
            leay    1,y
            jsr     expr
            jsr     need
            fcb     ')
            rts
pr_1:       cmpa    #'&
            beq     pr_2
            cmpa    #'.
            beq     pr_2
            jsr     isdig
            bcs     pr_3
pr_2:       tfr     y,x             ; a number
            jsr     fin
            lbcs    snerr
            tfr     x,y
            rts
pr_3:       cmpa    #'"
            bne     pr_5
            leay    1,y             ; "string"
            tfr     y,x
            clrb
pr_4:       lda     ,y
            beq     pr_4a
            leay    1,y
            cmpa    #'"
            beq     pr_4a
            incb
            bra     pr_4
pr_4a:      jmp     spush
pr_5:       jsr     isalpha
            bcs     pr_7
            jsr     lvalue          ; a variable
            lda     vtype
            cmpa    #1
            beq     pr_6
            clr     vtype
            cmpa    #4
            lbne    getnum
            jsr     fldd            ; a FN parameter: its value and
            lda     8,x             ; precision
            sta     fprec
            rts
pr_6:       ldb     ,x              ; copy it from the string space
            ldx     1,x
            jmp     spush
pr_7:       cmpa    #T_FN
            bne     pr_8
            leay    1,y
            jmp     fn_call
pr_8:       cmpa    #T_ABS
            lblo    snerr
            cmpa    #T_INKEY
            lbhi    snerr
            leay    1,y
            suba    #T_ABS
            asla
            ldx     #fntab
            jmp     [a,x]

fntab:      fdb     fn_abs,fn_rnd,fn_peek,fn_len,fn_asc,fn_val,fn_sgn
            fdb     fn_timer,fn_fre,fn_int,fn_fix,fn_sqr,fn_sin,fn_cos
            fdb     fn_tan,fn_atn,fn_exp,fn_log,fn_cint,fn_csng,fn_cdbl,fn_eof,fn_point,fn_instr,fn_chr,fn_str,fn_hex,fn_left
            fdb     fn_right,fn_mid,fn_inkey

; Variable at Y -> X = its address (string: its descriptor), vtype.
lvalue:     jsr     varname
            pshs    a
            lda     ,y
            cmpa    #'(
            puls    a
            beq     lv_a
            ldx     curfn           ; inside a FN: its parameters first
            beq     lv1
            jsr     fnparm
            bcc     lv2
lv1:        jsr     findvar
            jsr     settype
            leax    4,x
            rts
lv2:        pshs    a               ; a FN parameter: 1 a string,
            jsr     ntype           ; 4 a number
            cmpa    #1
            beq     lv3
            lda     #4
lv3:        sta     vtype
            puls    a,pc
lv_a:       leay    1,y             ; an array element
            orb     #$80
            pshs    d               ; 9,s name
            leas    -9,s            ; 0,s subscripts, 1,s their values
            clr     ,s
la1:        lda     ,s
            cmpa    #MAXDIM
            lbhs    snerr
            jsr     iexpr
            pshs    d
            ldb     2,s
            aslb
            leax    3,s
            abx
            puls    d
            std     ,x
            inc     ,s
            lda     ,y+
            cmpa    #',
            beq     la1
            cmpa    #')
            lbne    snerr
            ldd     9,s
            jsr     srchvar
            bcc     la2
            leas    -9,s            ; new: 0 to 10 in each dimension
            lda     9,s
            sta     ,s
            ldd     #11
            std     1,s
            std     3,s
            std     5,s
            std     7,s
            ldd     18,s
            tfr     s,x
            jsr     dimarr
            leas    9,s
la2:        lda     6,x             ; as many subscripts as dimensions?
            cmpa    ,s
            lbne    bserr
            pshs    x               ; 2,s subscripts, 3,s values
            ldd     #0
            pshs    d               ; 0,s element number
            ldx     2,s
            leax    7,x             ; -> sizes
            leau    5,s             ; -> subscripts
            ldb     4,s
            pshs    b               ; 0,s left to do, 1,s element number
la3:        ldd     ,u++
            cmpd    ,x
            lbhs    bserr           ; (negative ones too)
            pshs    d,x
            ldd     5,s             ; element number * size + subscript
            ldx     ,x
            jsr     imul
            addd    ,s
            std     5,s
            puls    d,x
            leax    2,x
            dec     ,s
            bne     la3
            leas    1,s
            puls    d,x             ; D = element number, X = entry
            jsr     settype
            pshs    x
            tfr     d,x             ; element number * element size
            lda     vtype
            ldu     #esize
            lda     a,u
            jsr     mulsz
            puls    x
            addd    #7
            pshs    d
            ldb     6,x             ; and the sizes
            aslb
            abx
            puls    d
            leax    d,x
            leas    11,s
            rts

; vtype from the entry at X.  Keeps D.
settype:    pshs    a
            lda     ,x
            bsr     ntype
            sta     vtype
            puls    a,pc

; Name byte A -> its type in A: 0 single, 1 string, 2 %, 3 double
ntype:      anda    #$C0
            beq     nty2
            cmpa    #$40
            beq     nty0
            cmpa    #$80
            beq     nty3
            lda     #1
            rts
nty0:       clra
            rts
nty2:       lda     #2
            rts
nty3:       lda     #3
            rts
esize:      fcb     5,3,2,8         ; bytes a value, by type

; D = X * A (an element count times an element size)
mulsz:      pshs    a,x
            ldb     2,s
            mul
            pshs    d
            lda     2,s
            ldb     3,s
            mul
            tfr     b,a
            clrb
            addd    ,s++
            leas    3,s
            rts

; Variable name at Y -> D: A = letter (+$80 for $, -$40 for %, +$40
; for #), B = second letter or digit, else 0.  Y moves past it.
varname:    lda     ,y
            jsr     isalpha
            lbcs    snerr
            leay    1,y
            clrb
            pshs    d
            lda     ,y
            bsr     isalnum
            bcs     vn2
            sta     1,s
vn1:        leay    1,y             ; more letters and digits don't count
            lda     ,y
            bsr     isalnum
            bcc     vn1
vn2:        cmpa    #'$
            bne     vn3
            leay    1,y
            lda     ,s
            ora     #$80
            sta     ,s
            puls    d,pc
vn3:        cmpa    #'%
            bne     vn4
            leay    1,y
            lda     ,s
            anda    #$BF
            sta     ,s
            puls    d,pc
vn4:        cmpa    #'#
            bne     vn5
            leay    1,y
            lda     ,s
            anda    #$BF
            ora     #$80
            sta     ,s
vn5:        puls    d,pc

; C=0 if A is a letter or digit
isalnum:    jsr     isdig
            bcc     an9
            jmp     isalpha
an9:        rts

; ( numeric expression ) -> D (parg) or FAC (fparg)
parg:       bsr     fparg
            jmp     fac2w
fparg:      jsr     need
            fcb     '(
            jsr     nexpr
            jsr     need
            fcb     ')
            rts

; ( string expression ) -> X, B popped
psarg:      jsr     need
            fcb     '(
            jsr     sexpr
            jsr     need
            fcb     ')
            jmp     spop

; Check that the next byte is the one after the JSR, and skip both.
need:       pshs    d,x
            ldx     4,s
            lda     ,x+
            stx     4,s
            cmpa    ,y+
            lbne    snerr
            puls    d,x,pc

; ---- functions -------------------------------------------------------
fn_abs:     bsr     fparg
            clr     fsgn
            rts

fn_sgn:     bsr     fparg
            tst     fexp
            beq     sg9
            ldd     #1
            tst     fsgn
            bpl     sg1
            ldd     #-1
sg1:        jmp     fltd
sg9:        rts

fn_peek:    bsr     parg
            tfr     d,x
            ldb     ,x
            clra
            jmp     fltud

fn_int:     bsr     fparg
            jmp     ffloor
fn_fix:     bsr     fparg
            jmp     ffix
fn_sqr:     bsr     fparg           ; these give single precision
            jsr     fsqr
            bra     fnsgl
fn_sin:     bsr     fparg
            jsr     fsinf
            bra     fnsgl
fn_cos:     bsr     fparg
            jsr     fcosf
            bra     fnsgl
fn_tan:     bsr     fparg
            jsr     ftanf
            bra     fnsgl
fn_atn:     bsr     fparg
            jsr     fatnf
            bra     fnsgl
fn_exp:     bsr     fparg
            jsr     fexpf
            bra     fnsgl
fn_log:     jsr     fparg
            jsr     flogf
fnsgl:      clr     fprec
            jmp     fsingle

fn_cint:    jsr     fparg           ; CINT: rounded to a whole number
            jsr     fac2i
            jmp     fltd
fn_csng:    jsr     fparg           ; CSNG: single precision
            bra     fnsgl
fn_cdbl:    jsr     fparg           ; CDBL: double precision
            lda     #1
            sta     fprec
            rts

; RND(n): a whole number 0 to n-1 (n >= 1); RND(0): 0 <= x < 1
fn_rnd:     jsr     fparg
            tst     fexp
            beq     rn5
            tst     fsgn
            bmi     rn5
            jsr     fac2w
            pshs    d
            bsr     rnd16
            tfr     d,x
            puls    d
            jsr     udiv
            tfr     x,d
            jmp     fltud
rn5:        bsr     rnd16
            std     nint
            bsr     rnd16
            std     nint+2
            jsr     flt32
            lda     fexp
            suba    #32
            lbls    fzero
            sta     fexp
            rts

; Next 16-bit random number -> D (xorshift: x ^= x<<7, x>>9, x<<8)
rnd16:      ldd     seed
            pshs    d
            lda     1,s             ; x << 7
            clrb
            lsra
            rorb
            pshs    a
            lda     1,s
            lsra                    ; bit 0 of the high byte
            puls    a
            bcc     rn1
            ora     #$80
rn1:        eora    ,s
            eorb    1,s
            std     ,s
            lda     ,s              ; x >> 9
            lsra
            eora    1,s
            sta     1,s
            eora    ,s              ; x << 8
            sta     ,s
            puls    d
            std     seed
            rts

fn_len:     jsr     psarg
            clra
            clr     vtype
            jmp     fltud

fn_asc:     jsr     psarg
            clr     vtype
            clra
            tstb
            beq     as9
            ldb     ,x
as9:        jmp     fltud

fn_val:     jsr     psarg
            clr     vtype
            cmpb    #20
            bls     va1
            ldb     #20
va1:        ldu     #vbuf
va2:        tstb
            beq     va3
            lda     ,x+
            sta     ,u+
            decb
            bra     va2
va3:        clr     ,u
            ldx     #vbuf
            jsr     fin
            lbcs    fzero
            rts

fn_timer:   OS      SYS_TIME
            jmp     fltud

fn_fre:     jsr     gc
            ldd     strtop
            subd    vartop
            jmp     fltud

; INSTR([start,] s$, t$): where t$ is in s$ (1 = the first character),
; looking from position start on; 0 if it isn't there
fn_instr:   jsr     need
            fcb     '(
            jsr     expr
            ldd     #1
            tst     vtype
            bne     is1
            jsr     fac2w           ; a start position first
            cmpd    #0
            lble    fcerr
            pshs    d
            jsr     need
            fcb     ',
            jsr     sexpr
            puls    d
is1:        pshs    d               ; start
            jsr     need
            fcb     ',
            jsr     sexpr
            jsr     need
            fcb     ')
            clr     vtype
            jsr     spop            ; t$
            pshs    b,x
            jsr     spop            ; s$
            pshs    b,x             ; 0 s len, 1 s, 3 t len, 4 t, 6 start
            ldd     6,s
            subd    #1
            tsta
            bne     is9             ; starts past 256
            pshs    b               ; 0 offset, 1 s len, 2 s, 4 t len, 5 t
is2:        lda     ,s              ; t$ must fit in what is left
            adda    4,s
            bcs     is8
            cmpa    1,s
            bhi     is8
            ldx     2,s
            ldb     ,s
            abx
            ldu     5,s
            ldb     4,s
is3:        tstb
            beq     is7
            lda     ,x+
            cmpa    ,u+
            bne     is4
            decb
            bra     is3
is4:        inc     ,s
            bra     is2
is7:        ldb     ,s              ; found
            clra
            addd    #1
            leas    9,s
            jmp     fltud
is8:        leas    1,s
is9:        leas    8,s
            ldd     #0
            jmp     fltud

fn_chr:     jsr     parg
            stb     nbuf
            ldx     #nbuf
            ldb     #1
            jmp     spush

; HEX$(n): n as hex digits, no leading zeros; negative n as 16 bits
fn_hex:     jsr     parg
            ldx     #nbufend
hx1:        pshs    d
            andb    #$0F
            addb    #'0
            cmpb    #'9
            bls     hx2
            addb    #7
hx2:        stb     ,-x
            puls    d
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            cmpd    #0
            bne     hx1
            pshs    x
            ldd     #nbufend
            subd    ,s
            puls    x
            jmp     spush

fn_str:     jsr     fparg
            jsr     fout
            jmp     spush

; ( string, number [, number] ) -> X, B popped, sa_n1, sa_n2 ($7FFF
; if left out).  Stored only after all the nested evaluation is done.
sargs:      jsr     need
            fcb     '(
            jsr     sexpr
            jsr     need
            fcb     ',
            jsr     iexpr
            pshs    d
            lda     ,y
            cmpa    #',
            bne     sa1
            leay    1,y
            jsr     iexpr
            bra     sa2
sa1:        ldd     #$7FFF
sa2:        pshs    d
            jsr     need
            fcb     ')
            puls    d
            std     sa_n2
            puls    d
            std     sa_n1
            jmp     spop

; Clip D to 0..255 -> B
clip:       tsta
            bmi     cl0
            beq     cl9
            ldb     #255
cl9:        rts
cl0:        clrb
            rts

; Clip D to 0..len (0,s after the return address) -> B
clipl:      bsr     clip
            cmpb    2,s
            bls     cp9
            ldb     2,s
cp9:        rts

fn_left:    bsr     sargs
            pshs    b
            ldd     sa_n1
            bsr     clipl
            leas    1,s
            jmp     spush

fn_right:   bsr     sargs
            pshs    b
            ldd     sa_n1
            bsr     clipl
            pshs    b
            ldb     1,s             ; skip len - n
            subb    ,s
            abx
            puls    b
            leas    1,s
            jmp     spush

fn_mid:     bsr     sargs
            pshs    b
            ldd     sa_n1
            cmpd    #1
            lblt    fcerr
            subd    #1
            bsr     clipl           ; B = start - 1
            abx
            negb
            addb    ,s              ; what is left
            stb     ,s
            ldd     sa_n2
            bsr     clipl
            leas    1,s
            jmp     spush

fn_inkey:   ldx     #nbuf
            clrb
            OS      SYS_POLL
            bcs     ik9
            sta     ,x
            incb
ik9:        jmp     spush

; ---- string stack ----------------------------------------------------
; Each string is its characters followed by its length byte.

; Push B characters from X.  vtype = 1.
spush:      pshs    b,x
            ldd     ssp
            addb    ,s
            adca    #0
            addd    #1
            cmpd    #SSTKEND
            lbhi    sterr
            ldu     ssp
            ldb     ,s
            ldx     1,s
sp1:        tstb
            beq     sp2
            lda     ,x+
            sta     ,u+
            decb
            bra     sp1
sp2:        lda     ,s
            sta     ,u+
            stu     ssp
            lda     #1
            sta     vtype
            puls    b,x,pc

; Pop the top string -> X = its characters, B = length.  They stay
; readable until the next push.
spop:       ldu     ssp
            ldb     ,-u
            stb     slen
            clra
            std     stmp
            tfr     u,d
            subd    stmp
            tfr     d,x
            stx     ssp
            ldb     slen
            rts

; Join the top two strings.
sconcat:    bsr     spop            ; right
            leau    -1,x            ; U -> left's length byte
            lda     ,u
            pshs    b
            adda    ,s
            lbcs    lserr
            pshs    a               ; 0,s total, 1,s right length
sc1:        tstb
            beq     sc2
            lda     ,x+
            sta     ,u+
            decb
            bra     sc1
sc2:        lda     ,s
            sta     ,u+
            stu     ssp
            lda     #1
            sta     vtype
            leas    2,s
            rts

; Compare (and pop) the top two strings -> B: 1 left < right, 2 equal,
; 4 left > right
scmp:       bsr     spop
            pshs    b,x             ; 0,s right length, 1,s right
            bsr     spop
            ldu     1,s
cm1:        tstb
            beq     cm3
            tst     ,s
            beq     cm5
            lda     ,x+
            cmpa    ,u+
            blo     cm4
            bhi     cm5
            decb
            dec     ,s
            bra     cm1
cm3:        tst     ,s
            bne     cm4
            ldb     #2
            bra     cm9
cm4:        ldb     #1
            bra     cm9
cm5:        ldb     #4
cm9:        leas    3,s
            rts

; ======================================================================
;  Arithmetic
; ======================================================================
dneg:       coma
            comb
            addd    #1
            rts

; D = D * X (low 16 bits; the same for signed numbers)
imul:       pshs    d,x             ; 0 a hi, 1 a lo, 2 b hi, 3 b lo
            lda     1,s
            ldb     3,s
            mul
            pshs    d               ; 0,s product
            lda     3,s
            ldb     4,s
            mul
            addb    ,s
            stb     ,s
            lda     2,s
            ldb     5,s
            mul
            addb    ,s
            stb     ,s
            puls    d
            leas    4,s
            rts

; D = X / D, X = remainder (signed; the remainder has X's sign)
idiv:       cmpd    #0
            lbeq    dzerr
            pshs    d,x             ; 0 divisor, 2 dividend
            lda     2,s
            tfr     a,b
            eorb    ,s
            pshs    d               ; 0 remainder sign, 1 quotient sign
            ldd     2,s
            bpl     iv1
            bsr     dneg
iv1:        pshs    d
            ldd     6,s
            bpl     iv2
            bsr     dneg
iv2:        tfr     d,x
            puls    d
            bsr     udiv
            tst     1,s
            bpl     iv3
            bsr     dneg
iv3:        exg     d,x
            tst     ,s
            bpl     iv4
            bsr     dneg
iv4:        exg     d,x
            leas    6,s
            rts

; D = X / D, X = remainder (unsigned)
udiv:       pshs    d,x             ; 0 divisor, 2 dividend -> quotient
            ldd     #0
            ldx     #16
ud1:        lsl     3,s
            rol     2,s
            rolb
            rola
            cmpd    ,s
            blo     ud2
            subd    ,s
            inc     3,s
ud2:        leax    -1,x
            bne     ud1
            tfr     d,x
            ldd     2,s
            leas    4,s
            rts

; Number at X -> D, X past it.  Leading spaces and a sign are allowed;
; &H starts a hex number.  C=1 if there are no digits.
parsenum:   clr     nsgn
            jsr     skipspx
            cmpa    #'-
            bne     pn1
            inc     nsgn
            bra     pn1a
pn1:        cmpa    #'+
            bne     pn2
pn1a:       leax    1,x
pn2:        lda     ,x
            cmpa    #'&
            beq     pnhex
            jsr     isdig
            bcs     pn9
            ldd     #0
pn3:        pshs    d
            lda     ,x
            suba    #'0
            cmpa    #9
            bhi     pn4
            leax    1,x
            sta     ntmp
            ldd     ,s
            aslb
            rola
            std     ,s
            aslb
            rola
            aslb
            rola
            addd    ,s++
            addb    ntmp
            adca    #0
            bra     pn3
pn4:        puls    d
pn5:        tst     nsgn
            beq     pn6
            jsr     dneg
pn6:        andcc   #$FE
            rts
pn9:        orcc    #$01
            rts
pnhex:      lda     1,x
            jsr     upcase
            cmpa    #'H
            bne     pn9
            leax    2,x
            ldd     #0
ph1:        pshs    d
            lda     ,x
            jsr     upcase
            suba    #'0
            cmpa    #9
            bls     ph2
            suba    #7
            cmpa    #10
            blo     ph3
            cmpa    #15
            bhi     ph3
ph2:        leax    1,x
            sta     ntmp
            ldd     ,s
            aslb
            rola
            aslb
            rola
            aslb
            rola
            aslb
            rola
            orb     ntmp
            std     ,s
            puls    d
            bra     ph1
ph3:        puls    d
            bra     pn5

; D -> text in nbuf: X = start, B = length.  numstr is signed.
numstr:     clr     nsgn
            tsta
            bpl     nm1
            inc     nsgn
            jsr     dneg
            bra     nm1
unumstr:    clr     nsgn
nm1:        ldu     #nbufend
nm2:        tfr     d,x
            ldd     #10
            pshs    u
            jsr     udiv
            puls    u
            pshs    d
            tfr     x,d
            addb    #'0
            stb     ,-u
            puls    d
            cmpd    #0
            bne     nm2
            tst     nsgn
            beq     nm3
            lda     #'-
            sta     ,-u
nm3:        tfr     u,x
            ldd     #nbufend
            pshs    x
            subd    ,s++
            rts

; ======================================================================
;  Graphics on the video chip's bitmap screens: SCREEN, PSET, LINE,
;  CIRCLE, POINT.  Pixels are bytes (palette colours 0-255), written
;  with SYS_VCOPY.  Coordinates -8191 to 8191; what is off the screen is
;  not drawn.
; ======================================================================
; SCREEN 0 (text) | 1 (320x240) | 2 (256x192)
st_screen:  jsr     iexpr
            cmpd    #2
            lbhi    fcerr
            tstb
            beq     gtext
            stb     gmode
            ldx     #320
            ldu     #240
            lda     #1              ; chip mode 1 or 4
            cmpb    #1
            beq     scr1
            ldx     #256
            ldu     #192
            lda     #4
scr1:       stx     gw
            stu     gh
            ldb     #V_MODE
            OS      SYS_VREG
            lbcs    novid
            clra                    ; the picture from VRAM 0
            ldb     #V_BASEL
            OS      SYS_VREG
            clra
            ldb     #V_BASEH
            OS      SYS_VREG
            ldd     #0
            std     glx
            std     gly
            bra     gclear
; Back to the text screen, cleared
gtext:      clr     gmode
            clra
            ldb     #V_MODE
            OS      SYS_VREG
            lbcs    novid
            lda     #VCMD_CLRTEXT
            ldb     #V_CMD
            OS      SYS_VREG
            rts
novid:      clr     gmode
            jmp     fcerr

; Clear the bitmap to colour 0
gclear:     lda     gcol
            pshs    a
            clr     gcol
            ldd     #0
            std     py
gcl1:       ldd     #0
            std     gx1
            ldd     gw
            subd    #1
            std     gx2
            jsr     hspan
            ldd     py
            addd    #1
            std     py
            cmpd    gh
            blo     gcl1
            puls    a
            sta     gcol
            rts

; Must be on a bitmap screen
gchk:       tst     gmode
            lbeq    fcerr
            lda     #15             ; colour 15 (white) unless given
            sta     gcol
            rts

; (x, y) -> gx, gy
gcoord:     jsr     need
            fcb     '(
            bsr     gnum
            std     gx
            jsr     need
            fcb     ',
            bsr     gnum
            std     gy
            jsr     need
            fcb     ')
            rts
gnum:       jsr     iexpr
            cmpd    #-8191
            lblt    fcerr
            cmpd    #8191
            lbgt    fcerr
            rts

; [, colour]: an empty one (",,") or none keeps gcol
gcolarg:    lda     ,y
            cmpa    #',
            bne     gca9
            lda     1,y
            cmpa    #',
            beq     gca8            ; leave the second comma for B
            leay    1,y
            jsr     iexpr
            cmpd    #255
            lbhi    fcerr
            stb     gcol
gca9:       rts
gca8:       leay    1,y
            rts

; VRAM address of px, py -> vblk+0..2
gaddr:      ldd     py              ; py * 256
            sta     vblk
            stb     vblk+1
            clr     vblk+2
            lda     gmode
            cmpa    #1
            bne     gad1
            ldd     py              ; + py * 64 = py * 320
            aslb
            rola
            aslb
            rola
            aslb
            rola
            aslb
            rola
            aslb
            rola
            aslb
            rola
            addd    vblk+1
            std     vblk+1
            bcc     gad1
            inc     vblk
gad1:       ldd     px
            addd    vblk+1
            std     vblk+1
            bcc     gad2
            inc     vblk
gad2:       rts

; Plot px, py in colour gcol, if it is on the screen
plot:       ldd     py
            bmi     plt9
            cmpd    gh
            bge     plt9
            ldd     px
            bmi     plt9
            cmpd    gw
            bge     plt9
            bsr     gaddr
            ldx     #gcol
            stx     vblk+3
            ldd     #1
            std     vblk+5
            ldx     #vblk
            OS      SYS_VCOPY
plt9:       rts

; Row py from gx1 to gx2 (gx1 <= gx2) in colour gcol, clipped
hspan:      ldd     py
            bmi     hsp9
            cmpd    gh
            bge     hsp9
            ldd     gx1
            bpl     hsp1
            ldd     #0
hsp1:       std     px
            ldd     gx2
            cmpd    gw
            blt     hsp2
            ldd     gw
            subd    #1
hsp2:       subd    px              ; the length - 1
            bmi     hsp9
            addd    #1
            std     gn
            lda     gcol              ; a buffer of the colour
            ldx     #gbuf
            ldb     #32
hsp3:       sta     ,x+
            decb
            bne     hsp3
            jsr     gaddr
hsp4:       ldd     gn              ; 32 bytes at a time
            beq     hsp9
            cmpd    #32
            bls     hsp5
            ldd     #32
hsp5:       std     vblk+5
            pshs    d
            ldd     gn
            subd    ,s++
            std     gn
            ldx     #gbuf
            stx     vblk+3
            ldx     #vblk
            OS      SYS_VCOPY       ; (it moves the VRAM address on)
            bra     hsp4
hsp9:       rts

; PSET (x, y) [, colour]
st_pset:    jsr     gchk
            jsr     gcoord
            jsr     gcolarg
            ldd     gx
            std     px
            std     glx
            ldd     gy
            std     py
            std     gly
            jmp     plot

; LINE [(x1, y1)] - (x2, y2) [, [colour] [, B[F]]]: from the last point
; if the first is left out; B a box, BF a filled one
st_gline:   jsr     gchk
            ldd     glx
            std     gx1
            ldd     gly
            std     gy1
            lda     ,y
            cmpa    #'-
            beq     gln1
            jsr     gcoord
            ldd     gx
            std     gx1
            ldd     gy
            std     gy1
gln1:        jsr     need
            fcb     '-
            jsr     gcoord
            ldd     gx
            std     gx2
            std     glx
            ldd     gy
            std     gy2
            std     gly
            jsr     gcolarg
            lda     ,y
            cmpa    #',
            bne     gline
            leay    1,y
            lda     ,y+
            cmpa    #'B
            lbne    snerr
            lda     ,y
            cmpa    #'F
            lbne    gbox
            leay    1,y
            lbra    gfill

; The line gx1, gy1 - gx2, gy2 (Bresenham)
gline:      ldd     #1
            std     gsx
            ldd     gx2
            subd    gx1
            bpl     gli1
            jsr     dneg
            pshs    d
            ldd     #-1
            std     gsx
            puls    d
gli1:       std     gdx             ; dx = |x2 - x1|
            ldd     #1
            std     gsy
            ldd     gy2
            subd    gy1
            bmi     gli2
            jsr     dneg            ; dy = -|y2 - y1|
            bra     gli3
gli2:       pshs    d
            ldd     #-1
            std     gsy
            puls    d
gli3:       std     gdy
            addd    gdx
            std     gerr
gli4:       ldd     gx1
            std     px
            ldd     gy1
            std     py
            jsr     plot
            ldd     gx1
            cmpd    gx2
            bne     gli5
            ldd     gy1
            cmpd    gy2
            beq     gli9
gli5:       ldd     gerr            ; e2 = 2 * err
            aslb
            rola
            std     ge2
            cmpd    gdy
            blt     gli6
            ldd     gerr            ; e2 >= dy: step x
            addd    gdy
            std     gerr
            ldd     gx1
            addd    gsx
            std     gx1
gli6:       ldd     ge2
            cmpd    gdx
            bgt     gli4
            ldd     gerr            ; e2 <= dx: step y
            addd    gdx
            std     gerr
            ldd     gy1
            addd    gsy
            std     gy1
            bra     gli4
gli9:       rts

; Put gx1 <= gx2 and gy1 <= gy2
gorder:     ldd     gx1
            cmpd    gx2
            ble     gor1
            ldx     gx2
            std     gx2
            stx     gx1
gor1:       ldd     gy1
            cmpd    gy2
            ble     gor2
            ldx     gy2
            std     gy2
            stx     gy1
gor2:       rts

; A filled box: a span for every row
gfill:      bsr     gorder
            ldd     gy1
            std     py
gfi1:       jsr     hspan
            ldd     py
            cmpd    gy2
            bge     gfi9
            addd    #1
            std     py
            bra     gfi1
gfi9:       rts

; A box: two spans and two columns
gbox:       bsr     gorder
            ldd     gy1
            std     py
            jsr     hspan
            ldd     gy2
            std     py
            jsr     hspan
            ldd     gy1
            std     py
gbx1:       ldd     gx1
            std     px
            jsr     plot
            ldd     gx2
            std     px
            jsr     plot
            ldd     py
            cmpd    gy2
            bge     gbx9
            addd    #1
            std     py
            bra     gbx1
gbx9:       rts

; CIRCLE (x, y), r [, colour] (midpoint circle)
st_circle:  jsr     gchk
            jsr     gcoord
            ldd     gx
            std     gcx
            std     glx
            ldd     gy
            std     gcy
            std     gly
            jsr     need
            fcb     ',
            jsr     gnum
            tsta
            lbmi    fcerr
            std     gox             ; x = r, y = 0, err = 1 - r
            ldd     #0
            std     goy
            ldd     #1
            subd    gox
            std     gerr
            jsr     gcolarg
gci1:       ldd     gox
            cmpd    goy
            blt     gci9
            bsr     plot8
            ldd     goy             ; y += 1
            addd    #1
            std     goy
            ldd     gerr
            bmi     gci2
            ldd     gox             ; err >= 0: x -= 1, err += 2(y-x)+1
            subd    #1
            std     gox
            ldd     goy
            subd    gox
            aslb
            rola
            addd    #1
            addd    gerr
            std     gerr
            bra     gci1
gci2:       ldd     goy             ; err < 0: err += 2y+1
            aslb
            rola
            addd    #1
            addd    gerr
            std     gerr
            bra     gci1
gci9:       rts

; The 8 points cx +- x, cy +- y and cx +- y, cy +- x
plot8:      ldx     gox
            ldu     goy
            bsr     plot4
            ldx     goy
            ldu     gox
plot4:      pshs    x,u             ; 0 dx, 2 dy
            ldd     gcx
            addd    ,s
            std     px
            ldd     gcy
            addd    2,s
            std     py
            jsr     plot
            ldd     gcy
            subd    2,s
            std     py
            jsr     plot
            ldd     gcx
            subd    ,s
            std     px
            jsr     plot
            ldd     gcy
            addd    2,s
            std     py
            jsr     plot
            puls    x,u,pc

; POINT(x, y): the colour there, -1 off the screen
fn_point:   jsr     gcoord
            ldd     gx
            std     px
            ldd     gy
            std     py
            tst     gmode
            beq     pnt8
            ldd     py
            bmi     pnt8
            cmpd    gh
            bge     pnt8
            ldd     px
            bmi     pnt8
            cmpd    gw
            bge     pnt8
            jsr     gaddr
            ldx     #gpix
            stx     vblk+3
            ldd     #1
            std     vblk+5
            ldx     #vblk
            OS      SYS_VREAD
            ldb     gpix
            clra
            jmp     fltud
pnt8:       ldd     #-1
            jmp     fltd

; ======================================================================
;  Data files: OPEN, CLOSE, PRINT #, WRITE, INPUT #, LINE INPUT, EOF.
;  One file at a time (the drive gives a task one), through fbuf.
; ======================================================================
; OPEN "file" FOR INPUT | OUTPUT | APPEND AS [#]n
st_open:    clra                    ; the name as it is
            jsr     fnarg
            jsr     need
            fcb     T_FOR
            lda     ,y+
            ldb     #2
            cmpa    #T_INPUT
            beq     op1
            ldb     #1
            cmpa    #T_OUTPUT
            beq     op1
            ldb     #3              ; (3 = append, then mode 1)
            cmpa    #T_APPEND
            lbne    snerr
op1:        pshs    b
            jsr     need
            fcb     T_AS
            lda     ,y
            cmpa    #'#
            bne     op2
            leay    1,y
op2:        jsr     iexpr
            cmpd    #1
            lblo    fcerr
            cmpd    #15
            lbhi    fcerr
            stb     dnum
            lda     ,s
            cmpa    #3
            beq     op4
            cmpa    #1
            beq     op3
            lda     #VCMD_FOPEN
            jsr     fcmdc
            clr     deof
            ldd     #0
            std     dfpos
            std     dfcnt
            bra     op9
op4:        clr     vbuf            ; does the firmware have FAPPEND?
            ldx     #vbuf           ; clear VF_CAPS, run a command that
            ldu     #VF_CAPS        ; does nothing, and look: new firmware
            ldd     #1              ; sets it after every command
            jsr     vput
            lda     #VCMD_FCLOSE
            jsr     fcmdc
            ldx     #vbuf
            ldu     #VF_CAPS
            ldd     #1
            jsr     vget
            lda     vbuf
            bita    #$01
            lbeq    aperr
            lda     #1              ; append: write after what is there
            sta     ,s
            lda     #VCMD_FAPPEND
            bra     op3a
op3:        lda     #VCMD_FCREATE
op3a:       jsr     fcmdc
            ldd     #0
            std     fpos
            clr     dcol
op9:        puls    a
            sta     dmode
            rts

; CLOSE [[#]n]
st_close:   jsr     endst
            beq     dclose
            lda     ,y
            cmpa    #'#
            bne     cl1
            leay    1,y
cl1:        jsr     iexpr
; Close the data file, writing out what is left.
dclose:     lda     dmode
            beq     dcl9
            clr     dmode
            cmpa    #1
            bne     dcl1
            jsr     fflush
dcl1:       lda     #VCMD_FCLOSE
            jmp     fcmdc
dcl9:       rts

; [#]n: the open file's number, open in mode A
fnum:       pshs    a
            lda     ,y
            cmpa    #'#
            bne     fnm1
            leay    1,y
fnm1:       jsr     iexpr
            tst     dmode
            lbeq    fnoerr
            cmpb    dnum
            lbne    fnoerr
            puls    a
            cmpa    dmode
            lbne    bmerr
            rts

; Send the output to the file, and back
redir:      lda     col
            sta     concol
            lda     dcol
            sta     col
            ldx     #dputc
            stx     outv
            rts
unredir:    lda     col
            sta     dcol
            lda     concol
            sta     col
            ldx     #conout
            stx     outv
            rts
dputc:      pshs    a               ; into the file, counting the column
            cmpa    #CR
            bne     dpc1
            clr     col
            bra     dpc2
dpc1:       cmpa    #$20
            blo     dpc2
            inc     col
dpc2:       puls    a
            jmp     fputc

; PRINT @pos, ...: print from screen position pos = row * 80 + column
; (0 to 2399 on the 80x30 screen), with the VT100 cursor sequence
pr_at:      leay    1,y
            ldx     outv
            cmpx    #conout
            lbne    bmerr           ; not into a file
            jsr     iexpr
            cmpd    #SCRCOLS*SCRROWS
            lbhs    fcerr
            tfr     d,x
            ldd     #SCRCOLS
            jsr     udiv            ; D = row, X = column
            pshs    x
            pshs    d
            lda     #ESC
            jsr     outch
            lda     #'[
            jsr     outch
            puls    d
            addd    #1
            jsr     putnum
            lda     #';
            jsr     outch
            ldd     ,s
            addd    #1
            jsr     putnum
            lda     #'H
            jsr     outch
            puls    d
            stb     col
            jsr     endst
            lbeq    st_print        ; just the position
            jsr     need
            fcb     ',
            jmp     st_print

; PRINT #n, ... (USING too)
pr_file:    lda     #1
            jsr     fnum
            jsr     endst
            beq     pf1
            jsr     need
            fcb     ',
            jsr     redir
            jsr     st_print
            jmp     unredir
pf1:        jsr     redir           ; PRINT #n: an empty line
            jsr     crlf
            jmp     unredir

; WRITE [#n,] a, b$ ...: commas between, strings in quotes
st_write:   lda     ,y
            cmpa    #'#
            bne     wr1
            lda     #1
            jsr     fnum
            jsr     need
            fcb     ',
            jsr     redir
            bsr     wr1
            jmp     unredir
wr1:        jsr     endst
            beq     wr9
wr2:        jsr     expr
            tst     vtype
            bne     wr3
            jsr     fout
            jsr     putsb
            bra     wr4
wr3:        lda     #'"
            jsr     outch
            jsr     spop
            jsr     putsb
            lda     #'"
            jsr     outch
wr4:        jsr     endst
            beq     wr9
            cmpa    #',
            beq     wr5
            cmpa    #';
            lbne    snerr
wr5:        leay    1,y
            lda     #',
            jsr     outch
            bra     wr2
wr9:        jmp     crlf

; Next character of the input file -> A, C=1 at the end
dgetc:      bsr     dfill
            bcs     dgc9
            ldx     #fbuf
            ldd     dfpos
            leax    d,x
            addd    #1
            std     dfpos
            lda     ,x
            andcc   #$FE
dgc9:       rts
; Make sure fbuf has a character to read.  C=1 at the end of the file.
dfill:      ldd     dfpos
            cmpd    dfcnt
            blo     dfl8
            tst     deof
            bne     dfl9
            jsr     fread
            stx     dfcnt
            beq     dfl1
            ldd     #0
            std     dfpos
dfl8:       andcc   #$FE
            rts
dfl1:       inc     deof
dfl9:       orcc    #$01
            rts

; Next line of the input file -> lbuf (NUL-terminated, CR dropped, at
; most 127 characters kept), dllen.  C=1 if the file has ended.
dline:      clr     dllen
            clr     dlany
dln1:       bsr     dgetc
            bcs     dln8
            inc     dlany
            cmpa    #LF
            beq     dln9
            cmpa    #CR
            beq     dln1
            ldb     dllen
            cmpb    #LBMAX
            bhs     dln1
            ldx     #lbuf
            abx
            sta     ,x
            inc     dllen
            bra     dln1
dln8:       tst     dlany
            bne     dln9
            clr     lbuf
            orcc    #$01
            rts
dln9:       ldx     #lbuf
            ldb     dllen
            clr     b,x
            andcc   #$FE
            rts

; EOF(n): -1 if the input file has no more characters
fn_eof:     jsr     need
            fcb     '(
            lda     #2
            jsr     fnum
            jsr     need
            fcb     ')
            bsr     dfill
            ldd     #0
            bcc     eo1
            ldd     #-1
eo1:        jmp     fltd

; INPUT #n, v [, v ...]: items separated by commas, across lines;
; strings may be in quotes
in_file:    lda     #2
            jsr     fnum
            jsr     need
            fcb     ',
            jsr     dline
            lbcs    iperr
            ldx     #lbuf
            stx     inptr
if1:        jsr     lvalue
            lda     vtype
            pshs    a,x
            ldx     inptr
            jsr     skipspx
            tsta
            bne     if2
            jsr     dline           ; this line is used up: the next one
            lbcs    iperr
            ldx     #lbuf
            jsr     skipspx
if2:        lda     ,s
            cmpa    #1
            beq     if_s
            cmpa    #3
            bne     if2a
            inc     fdflt
if2a:       jsr     fin
            lbcs    tmerr
            pshs    x
            ldx     3,s
            lda     2,s
            jsr     setnum
            puls    x
            bra     if5
if_s:       lda     ,x              ; "quoted" or up to a comma
            cmpa    #'"
            bne     if_s2
            leax    1,x
            tfr     x,u
if_s1:      lda     ,u
            beq     if_s3
            cmpa    #'"
            beq     if_s3
            leau    1,u
            bra     if_s1
if_s2:      tfr     x,u
if_s4:      lda     ,u
            beq     if_s3
            cmpa    #',
            beq     if_s3
            leau    1,u
            bra     if_s4
if_s3:      pshs    u
            tfr     u,d
            pshs    x
            subd    ,s++
            ldu     3,s
            jsr     setstr
            puls    x
            lda     ,x
            cmpa    #'"
            bne     if5
            leax    1,x
if5:        jsr     skipspx
            cmpa    #',
            bne     if6
            leax    1,x
if6:        stx     inptr
            leas    3,s
            lda     ,y
            cmpa    #',
            bne     if9
            leay    1,y
            lbra    if1
if9:        rts

; LINE INPUT ["prompt";] v$  /  LINE INPUT #n, v$: a whole line
st_line:    lda     ,y
            cmpa    #T_INPUT
            lbne    st_gline
            leay    1,y
            lda     ,y
            cmpa    #'#
            beq     li5
            cmpa    #'"
            bne     li2
            jsr     expr            ; the prompt
            jsr     spop
            jsr     putsb
            lda     ,y+
            cmpa    #';
            beq     li2
            cmpa    #',
            lbne    snerr
li2:        jsr     lvalue
            lda     vtype
            cmpa    #1
            lbne    tmerr
            pshs    x
            jsr     getline
            lbcs    brk
            ldx     #lbuf           ; its length
            clrb
li3:        tst     b,x
            beq     li4
            incb
            bra     li3
li4:        puls    u
            jmp     setstr
li5:        lda     #2
            jsr     fnum
            jsr     need
            fcb     ',
            jsr     lvalue
            lda     vtype
            cmpa    #1
            lbne    tmerr
            pshs    x
            jsr     dline
            lbcs    iperr
            puls    u
            ldx     #lbuf
            ldb     dllen
            jmp     setstr

; ======================================================================
;  DEF FN and PRINT USING
; ======================================================================
; DEF FNname[(p1 [,p2 ...])] = expression.  A function is a variable
; table entry, name + $20: 4 parameter count, 5 their names (4 x 2), 13
; -> the expression in the program text.
st_def:     ldx     curline
            lbeq    iderr           ; the text must stay put
            jsr     need
            fcb     T_FN
            jsr     varname
            ora     #$20
            jsr     srchvar
            bcc     dz1             ; defined again: replaced
            ldx     #11
            jsr     newvar
dz1:        clr     4,x
            pshs    x
            lda     ,y
            cmpa    #'(
            bne     dz4
            leay    1,y
dz2:        jsr     varname
            pshs    d
            ldx     2,s
            ldb     4,x
            cmpb    #4
            lbhs    snerr
            aslb
            abx
            puls    d
            std     5,x
            ldx     ,s
            inc     4,x
            lda     ,y+
            cmpa    #',
            beq     dz2
            cmpa    #')
            lbne    snerr
dz4:        jsr     need
            fcb     '=
            puls    x
            sty     13,x
dz5:        lda     ,y              ; skip the expression
            beq     dz9
            cmpa    #':
            beq     dz9
            cmpa    #T_ELSE
            beq     dz9
            leay    1,y
            cmpa    #'"
            bne     dz5
dz6:        lda     ,y
            beq     dz9
            leay    1,y
            cmpa    #'"
            bne     dz6
            bra     dz5
dz9:        rts

; FNname(args).  The arguments go on the stack as 11-byte slots (name,
; a double and its precision, or a string descriptor); curfn -> their count and the slots while
; the expression runs.  String arguments stay on the string stack.
fn_call:    cmps    #STKTOP-$1A0    ; too deep (a FN calling itself)
            lblo    omerr
            jsr     varname
            ora     #$20
            jsr     srchvar
            lbcs    uferr
            ldd     fbase
            pshs    d
            ldd     curfn
            pshs    d
            ldd     ssp
            pshs    d
            pshs    x
            clr     ,-s
            sts     fbase           ; 0 arg number, 1 entry, 3 ssp, 5 curfn, 7 fbase
            ldb     4,x
            beq     fc5
            jsr     need
            fcb     '(
fc1:        jsr     expr
            jsr     fcpar
            lda     5,x             ; the parameter's type
            jsr     ntype
            cmpa    #1
            beq     fc2
            tst     vtype
            lbne    tmerr
            cmpa    #2
            bne     fc1b
            jsr     fac2i           ; a % parameter: a whole number
            jsr     fltd
            bra     fc1a
fc1b:       cmpa    #3
            bne     fc1c
            lda     #1              ; a # parameter: double
            sta     fprec
            bra     fc1a
fc1c:       clr     fprec           ; a single one
            jsr     fsingle
fc1a:       jsr     fpush
            bra     fc3
fc2:        tst     vtype
            lbeq    tmerr
            leas    -9,s            ; descriptor of the string on top
            ldx     ssp
            ldb     -1,x
            stb     ,s
            clra
            std     stmp2
            tfr     x,d
            subd    #1
            subd    stmp2
            std     1,s
fc3:        jsr     fcpar           ; and the parameter's name
            ldd     5,x
            pshs    d
            ldx     fbase
            inc     ,x
            ldb     ,x
            ldx     1,x
            cmpb    4,x
            bhs     fc4
            jsr     need
            fcb     ',
            bra     fc1
fc4:        jsr     need
            fcb     ')
fc5:        ldx     fbase
            ldx     1,x
            lda     4,x
            pshs    a
            sts     curfn
            pshs    y
            ldy     13,x
            jsr     expr
            puls    y
            ldu     fbase           ; back to the caller's state
            ldd     5,u
            std     curfn
            ldd     3,u
            std     stmp2
            ldx     1,u
            lda     ,x
            sta     fntyp
            ldd     7,u
            std     fbase
            leas    9,u
            lda     fntyp
            jsr     ntype
            cmpa    #1
            beq     fc6
            tst     vtype
            lbne    tmerr
            ldd     stmp2           ; drop the string arguments
            std     ssp
            lda     fntyp
            jsr     ntype
            cmpa    #2
            bne     fc5a
            jsr     fac2i           ; a % function: a whole number
            jmp     fltd
fc5a:       cmpa    #3
            bne     fc5b
            lda     #1              ; a # function: double
            sta     fprec
            rts
fc5b:       clr     fprec
            jmp     fsingle
fc6:        tst     vtype
            lbeq    tmerr
            jsr     spop            ; move the result down over them
            ldu     stmp2
            stu     ssp
            jmp     spush

; X = entry + 2 * the argument number being set up
fcpar:      ldx     fbase
            ldb     ,x
            ldx     1,x
            aslb
            abx
            rts

; Parameter D of the FN being run -> X = its value, C=0.  C=1 if none.
fnparm:     pshs    d
            ldx     curfn
            ldb     ,x+
            pshs    b               ; 0 left, 1 name
fp1:        tst     ,s
            beq     fp8
            ldd     ,x
            cmpd    1,s
            beq     fp9
            leax    11,x
            dec     ,s
            bra     fp1
fp8:        leas    1,s
            puls    d
            orcc    #$01
            rts
fp9:        leax    2,x
            leas    1,s
            puls    d
            andcc   #$FE
            rts

; PRINT USING format$; value [; value ...] [;]
pr_using:   leay    1,y
            jsr     sexpr
            jsr     spop
            cmpb    #127
            lbhi    lserr
            stb     uflen
            ldu     #ufmt
wu1:        tstb
            beq     wu2
            lda     ,x+
            sta     ,u+
            decb
            bra     wu1
wu2:        clr     ,u
            clrb                    ; it must have a field somewhere
wu2a:       cmpb    uflen
            lbhs    fcerr
            jsr     isfld
            bcc     wu2b
            incb
            bra     wu2a
wu2b:       lda     ,y+
            cmpa    #';
            beq     wu3
            cmpa    #',
            lbne    snerr
wu3:        clr     upos
wu4:        jsr     expr
            bsr     wfield
            lda     ,y
            cmpa    #';
            beq     wu5
            cmpa    #',
            beq     wu5
            jsr     wlits           ; the text after the last field
            jmp     crlf
wu5:        leay    1,y
            jsr     endst
            bne     wu4
            jmp     wlits

; Print the format's text up to the next field, then the value in it.
; At the end of the format, start again from the beginning.
wfield:     clr     uwrap
wf1:        jsr     wlits
            bcc     wf2
            tst     uwrap
            lbne    fcerr           ; a format with no fields
            inc     uwrap
            clr     upos
            bra     wf1
wf2:        ldx     #ufmt
            ldb     upos
            abx
            lda     ,x
            cmpa    #'!
            beq     wf3
            cmpa    #'&
            beq     wf3
            cmpa    #$5C
            beq     wf3
            tst     vtype
            lbne    tmerr
            jmp     wnum
wf3:        tst     vtype
            lbeq    tmerr
            pshs    a
            jsr     spop
            puls    a
            cmpa    #'!             ; ! the first character
            bne     wf4
            inc     upos
            lda     #$20
            tstb
            beq     wf3a
            lda     ,x
wf3a:       jmp     outch
wf4:        cmpa    #'&             ; & all of it
            bne     wf5
            inc     upos
            jmp     putsb
wf5:        pshs    b,x             ; \  \ as many characters as it is wide
            ldx     #ufmt
            ldb     upos
            abx
            leax    1,x
            lda     #1
wf6:        inca
            ldb     ,x+
            cmpb    #$5C
            bne     wf6
            sta     uw
            adda    upos
            sta     upos
            ldx     1,s
wf7:        tst     uw
            beq     wf9
            lda     #$20
            tst     ,s
            beq     wf8
            lda     ,x+
            dec     ,s
wf8:        jsr     outch
            dec     uw
            bra     wf7
wf9:        leas    3,s
            rts

; Print the format from upos up to a field.  C=0 there, C=1 at the end.
wlits:      ldb     upos
wl1:        cmpb    uflen
            bhs     wl9
            stb     upos
            bsr     isfld
            bcc     wl8
            ldx     #ufmt
            abx
            lda     ,x
            cmpa    #'_             ; _ prints the next character as it is
            bne     wl2
            incb
            cmpb    uflen
            bhs     wl2
            lda     1,x
wl2:        jsr     outch
            incb
            bra     wl1
wl8:        rts
wl9:        stb     upos
            orcc    #$01
            rts

; Does a field start at format position B?  C=0 if so.  Keeps B, X.
isfld:      pshs    b,x
            ldx     #ufmt
            abx
            lda     ,x
            cmpa    #'#
            beq     wi8
            cmpa    #'!
            beq     wi8
            cmpa    #'&
            beq     wi8
            cmpa    #'.
            bne     wi1
            lda     1,x
            cmpa    #'#
            beq     wi8
            bra     wi9
wi1:        cmpa    #'+
            bne     wi3
            lda     1,x
            cmpa    #'#
            beq     wi8
            cmpa    #'.
            beq     wi2
            cmpa    #'*
            beq     wi2a
            cmpa    #'$
            bne     wi9
            lda     2,x
            cmpa    #'$
            beq     wi8
            bra     wi9
wi2:        lda     2,x
            cmpa    #'#
            beq     wi8
            bra     wi9
wi2a:       lda     2,x
            cmpa    #'*
            beq     wi8
            bra     wi9
wi3:        cmpa    #'*
            bne     wi4
            lda     1,x
            cmpa    #'*
            beq     wi8
            bra     wi9
wi4:        cmpa    #'$
            bne     wi5
            lda     1,x
            cmpa    #'$
            beq     wi8
            bra     wi9
wi5:        cmpa    #$5C
            bne     wi9
            leax    1,x
wi6:        lda     ,x+
            cmpa    #$20
            beq     wi6
            cmpa    #$5C
            beq     wi8
wi9:        puls    b,x
            orcc    #$01
            rts
wi8:        puls    b,x
            andcc   #$FE
            rts

; A number field at upos: [+] [** | $$ | **$] #,#.## [- | +]
wnum:       lda     fprec           ; the value, and its precision
            sta     ftu+8
            ldx     #ftu
            jsr     fstd
            clr     uflags
            clr     uint
            clr     udec
            clr     udot
            ldx     #ufmt
            ldb     upos
            abx
            lda     ,x
            cmpa    #'+
            bne     wn1
            lda     #1
            sta     uflags
            leax    1,x
wn1:        lda     ,x
            cmpa    #'*
            bne     wn2
            lda     1,x
            cmpa    #'*
            bne     wn3
            lda     uflags
            ora     #2
            sta     uflags
            leax    2,x
            lda     uint
            adda    #2
            sta     uint
            lda     ,x
            cmpa    #'$
            bne     wn3
            lda     uflags
            ora     #4
            sta     uflags
            inc     uint
            leax    1,x
            bra     wn3
wn2:        cmpa    #'$
            bne     wn3
            lda     1,x
            cmpa    #'$
            bne     wn3
            lda     uflags
            ora     #4
            sta     uflags
            lda     uint
            adda    #2
            sta     uint
            leax    2,x
wn3:        lda     ,x
            cmpa    #'#
            bne     wn4
            inc     uint
            leax    1,x
            bra     wn3
wn4:        cmpa    #',
            bne     wn5
            lda     uflags
            ora     #8
            sta     uflags
            inc     uint
            leax    1,x
            bra     wn3
wn5:        cmpa    #'.
            bne     wn7
            inc     udot
            leax    1,x
wn6:        lda     ,x
            cmpa    #'#
            bne     wn7
            inc     udec
            leax    1,x
            bra     wn6
wn7:        lda     ,x              ; ^^^^: E notation
            cmpa    #'^
            bne     wn7b
            lda     1,x
            cmpa    #'^
            bne     wn7b
            lda     2,x
            cmpa    #'^
            bne     wn7b
            lda     3,x
            cmpa    #'^
            bne     wn7b
            lda     uflags
            ora     #$40
            sta     uflags
            leax    4,x
wn7b:       lda     ,x
            cmpa    #'-
            bne     wn8
            lda     uflags
            ora     #$10
            sta     uflags
            leax    1,x
            bra     wn9
wn8:        cmpa    #'+
            bne     wn9
            lda     uflags
            bita    #1
            bne     wn9
            ora     #$20
            sta     uflags
            leax    1,x
wn9:        tfr     x,d
            subd    #ufmt
            pshs    b
            subb    upos
            stb     uw
            puls    b
            stb     upos
            lda     udec
            cmpa    #9
            lbhi    fcerr
            lda     uflags
            bita    #$40
            lbne    wexp
            ldx     #ftu            ; |value| * 10^decimals, rounded
            jsr     fldd
            lda     fsgn
            sta     uneg
            clr     fsgn
            lda     udec
            sta     ucnt
wn10:       tst     ucnt
            beq     wn11
            jsr     fmul10
            dec     ucnt
            bra     wn10
wn11:       ldx     #c_half
            jsr     argld
            jsr     fadd
            jsr     ffix
            lda     fexp
            cmpa    #160
            lbhi    wovf            ; 2^32 or more
            jsr     fac2u64
            ldd     nint+4          ; rounded to 0: no minus sign
            bne     wn12
            ldd     nint+6
            bne     wn12
            clr     uneg
wn12:       jsr     u32dec
            ldu     #ubody
            lda     uflags
            bita    #1
            beq     wb1
            lda     #'+             ; leading sign
            tst     uneg
            beq     wb0
            lda     #'-
wb0:        sta     ,u+
            bra     wb2
wb1:        bita    #$30            ; else a minus, unless one comes after
            bne     wb2
            tst     uneg
            beq     wb2
            lda     #'-
            sta     ,u+
wb2:        lda     uflags
            bita    #4
            beq     wb3
            lda     #'$
            sta     ,u+
wb3:        lda     #10             ; the whole part, without leading zeros
            suba    udec
            sta     ucnt
            ldx     #ubuf
wb4:        tst     ucnt
            beq     wb5
            lda     ,x
            cmpa    #'0
            bne     wb6
            leax    1,x
            dec     ucnt
            bra     wb4
wb5:        tst     uint            ; 0: shown if the field has places
            beq     wb8
            lda     #'0
            sta     ,u+
            bra     wb8
wb6:        lda     ,x+
            sta     ,u+
            dec     ucnt
            beq     wb8
            lda     uflags
            bita    #8
            beq     wb6
            lda     ucnt            ; a comma before each group of 3
wb7:        suba    #3
            bhi     wb7
            bne     wb6
            lda     #',
            sta     ,u+
            bra     wb6
wb8:        tst     udot
            beq     wb10
            lda     #'.
            sta     ,u+
            ldb     udec
            beq     wb10
wb9:        lda     ,x+
            sta     ,u+
            decb
            bne     wb9
wb10:       lda     uflags
            bita    #$10
            beq     wb11
            lda     #$20            ; trailing minus
            tst     uneg
            beq     wb10a
            lda     #'-
wb10a:      sta     ,u+
            bra     wb12
wb11:       bita    #$20
            beq     wb12
            lda     #'+             ; trailing sign
            tst     uneg
            beq     wb11a
            lda     #'-
wb11a:      sta     ,u+
wb12:       tfr     u,d
            subd    #ubody
            stb     ublen
            lda     uw              ; fill on the left
            suba    ublen
            bcs     wovf2
            beq     wb14
            sta     ucnt
            lda     #$20
            ldb     uflags
            bitb    #2
            beq     wb13
            lda     #'*
wb13:       jsr     outch
            dec     ucnt
            bne     wb13
wb14:       ldx     #ubody
            ldb     ublen
            jmp     putsb
wovf2:      lda     #'%             ; too wide: % and then the number
            jsr     outch
            bra     wb14
wovf:       lda     #'%
            jsr     outch
            ldx     #ftu
            jsr     fldd
            lda     ftu+8
            sta     fprec
            jsr     fout
            jmp     putsb

; ^^^^: the value as d.ddE+nn in the field.  The #s before the point
; are digits, but for one kept for the sign unless the field has its own.
wexp:       lda     uint
            ldb     uflags
            bitb    #$31
            bne     we1
            tsta
            beq     we1
            deca
we1:        sta     uni
            adda    udec
            cmpa    #16
            lbhi    fcerr
            tsta
            bne     we2
            lda     #1              ; at least one digit
            sta     uni
we2:        sta     usig
            ldx     #ftu
            jsr     fldd
            lda     ftu+8
            sta     fprec
            sta     oprec
            lda     fsgn
            sta     uneg
            clr     fsgn
            tst     fexp
            bne     we3
            clr     uneg            ; 0: zeros, exponent 0
            lda     uni
            deca
            sta     dexp
            ldx     #dbuf
            bra     we4d
we3:        jsr     fdig
            lda     usig            ; round to usig digits
            cmpa    ndmax
            bhs     we4e
            ldx     #dbuf
            ldb     usig
            lda     b,x
            cmpa    #'5
            blo     we4e
            abx
we4:        cmpx    #dbuf
            beq     we4c
            lda     ,-x
            inca
            cmpa    #'9
            bls     we4b
            lda     #'0
            sta     ,x
            bra     we4
we4b:       sta     ,x
            bra     we4e
we4c:       lda     #'1             ; 9.99 -> 10.0: one power up
            sta     dbuf
            inc     dexp
we4e:       ldx     #dbuf           ; zeros after the digits shown
            ldb     usig
            abx
we4d:       cmpx    #dbuf+16
            bhs     we5
            lda     #'0
            sta     ,x+
            bra     we4d
we5:        lda     dexp            ; the exponent: one per place moved
            suba    uni
            inca
            sta     uexp
            ldu     #ubody
            lda     uflags
            bita    #1
            beq     we6
            lda     #'+             ; leading sign
            tst     uneg
            beq     we5a
            lda     #'-
we5a:       sta     ,u+
            bra     we7
we6:        bita    #$30
            bne     we7
            lda     uint            ; the place kept for the sign
            cmpa    uni
            beq     we7
            lda     #$20
            tst     uneg
            beq     we6a
            lda     #'-
we6a:       sta     ,u+
we7:        ldx     #dbuf
            ldb     uni
            beq     we8
we7a:       lda     ,x+
            sta     ,u+
            decb
            bne     we7a
we8:        tst     udot
            beq     we9
            lda     #'.
            sta     ,u+
            ldb     udec
            beq     we9
we8a:       lda     ,x+
            sta     ,u+
            decb
            bne     we8a
we9:        lda     #'E
            tst     oprec
            beq     we9a
            lda     #'D
we9a:       sta     ,u+
            lda     #'+
            ldb     uexp
            bpl     we10
            lda     #'-
            negb
we10:       sta     ,u+
            lda     #'0
we11:       cmpb    #10
            blo     we12
            subb    #10
            inca
            bra     we11
we12:       sta     ,u+
            addb    #'0
            stb     ,u+
            lda     uflags
            bita    #$10
            beq     we13
            lda     #$20            ; trailing minus
            tst     uneg
            beq     we12a
            lda     #'-
we12a:      sta     ,u+
            jmp     wb12
we13:       bita    #$20
            lbeq    wb12
            lda     #'+             ; trailing sign
            tst     uneg
            beq     we13a
            lda     #'-
we13a:      sta     ,u+
            jmp     wb12

; nint (its low 32 bits) -> 10 decimal digits in ubuf
u32dec:     ldx     #p10t10
            ldu     #ubuf
wq1:        clr     ,u
wq2:        ldd     nint+6
            subd    2,x
            std     ntmp8+6
            ldd     nint+4
            sbcb    1,x
            sbca    ,x
            bcs     wq3
            std     nint+4
            ldd     ntmp8+6
            std     nint+6
            inc     ,u
            bra     wq2
wq3:        lda     ,u
            adda    #'0
            sta     ,u+
            leax    4,x
            cmpu    #ubuf+10
            blo     wq1
            rts

; ======================================================================
;  Floating point.  Numbers are kept in Microsoft BASIC's formats: single
;  precision in 5 bytes (exponent +128, 0 for zero, then a 32-bit
;  mantissa 0.1xxx... whose top bit, always 1, is replaced by the sign),
;  double precision in 8 (a 56-bit mantissa).  FAC and ARG hold them
;  unpacked: 7 mantissa bytes, a guard byte, the sign and the precision
;  (0 single, 1 double).  Operations work on 56 bits and round the result
;  to single when both operands are single.  None of these use Y.
; ======================================================================

; FAC = the single at X.  Keeps X.
fld:        clr     fprec
            lda     ,x
            sta     fexp
            beq     fzero
            ldb     1,x
            sex
            sta     fsgn
            orb     #$80
            stb     fm0
            ldd     2,x
            std     fm1
            lda     4,x
            sta     fm3
            clra
            clrb
            std     fm4
            std     fm6
            rts
fzero:      clr     fexp
            clr     fsgn
            rts

; FAC = the double at X.  Keeps X.
fldd:       lda     #1
            sta     fprec
            lda     ,x
            sta     fexp
            beq     fzero
            ldb     1,x
            sex
            sta     fsgn
            orb     #$80
            stb     fm0
            ldd     2,x
            std     fm1
            ldd     4,x
            std     fm3
            ldd     6,x
            std     fm5
            clr     fmg
            rts

; ARG = the single / the double at X.  Keeps X.
argld:      clr     aprec
            lda     ,x
            sta     aexp
            beq     qal9
            ldb     1,x
            sex
            sta     asgn
            orb     #$80
            stb     am0
            ldd     2,x
            std     am1
            lda     4,x
            sta     am3
            clra
            clrb
            std     am4
            std     am6
            rts
qal9:       clr     asgn
            rts
argldd:     lda     #1
            sta     aprec
            lda     ,x
            sta     aexp
            beq     qal9
            ldb     1,x
            sex
            sta     asgn
            orb     #$80
            stb     am0
            ldd     2,x
            std     am1
            ldd     4,x
            std     am3
            ldd     6,x
            std     am5
            clr     amg
            rts

; Round FAC to single precision and store it at X.  Keeps X.
fst:        bsr     fround
            jsr     fround32
            lda     fexp
            sta     ,x
            beq     qst2
            bsr     fsgnb
            sta     1,x
            ldd     fm1
            std     2,x
            lda     fm3
            sta     4,x
            rts
qst2:       clr     1,x
            clr     2,x
            clr     3,x
            clr     4,x
            rts

; Store FAC as a double at X.  Keeps X.
fstd:       bsr     fround
            lda     fexp
            sta     ,x
            beq     qsd2
            bsr     fsgnb
            sta     1,x
            ldd     fm1
            std     2,x
            ldd     fm3
            std     4,x
            ldd     fm5
            std     6,x
            rts
qsd2:       clr     1,x
            clr     2,x
            clr     3,x
            clr     4,x
            clr     5,x
            clr     6,x
            clr     7,x
            rts

; A = the top mantissa byte with the sign in bit 7
fsgnb:      lda     fm0
            anda    #$7F
            tst     fsgn
            bpl     qsb9
            ora     #$80
qsb9:       rts

; Round the guard byte into FAC's 56-bit mantissa.  Keeps X.
fround:     tst     fexp
            beq     qrd9
            tst     fmg
            bpl     qrd9
            inc     fm6
            bne     qrd9
            inc     fm5
            bne     qrd9
            inc     fm4
            bne     qrd9
            inc     fm3
            bne     qrd9
            inc     fm2
            bne     qrd9
            inc     fm1
            bne     qrd9
            inc     fm0
            bne     qrd9
            lda     #$80            ; carried out of the top
            sta     fm0
            inc     fexp
            lbeq    overr
qrd9:       clr     fmg
            rts

; Round FAC to 32 bits (fround32), or only if it is single (fsingle)
fsingle:    tst     fprec
            bne     qr39
fround32:   tst     fexp
            beq     qr39
            tst     fm4
            bpl     qr38
            inc     fm3
            bne     qr38
            inc     fm2
            bne     qr38
            inc     fm1
            bne     qr38
            inc     fm0
            bne     qr38
            lda     #$80
            sta     fm0
            inc     fexp
            lbeq    overr
qr38:       clr     fm4
            clr     fm5
            clr     fm6
            clr     fmg
qr39:       rts

; Swap FAC and ARG, copy FAC to ARG, copy ARG to FAC
fswap:      ldx     #fexp
            ldb     #11
qsw1:       lda     ,x
            pshs    a
            lda     16,x
            sta     ,x+
            puls    a
            sta     15,x
            decb
            bne     qsw1
            rts
fcopyfa:    ldx     #fexp
            ldb     #11
qcf1:       lda     ,x+
            sta     15,x
            decb
            bne     qcf1
            rts
fcopyaf:    ldx     #aexp
            ldb     #11
qca1:       lda     ,x+
            sta     -17,x
            decb
            bne     qca1
            rts

fneg:       tst     fexp
            beq     qng9
            com     fsgn
qng9:       rts

; Shift FAC left until the top bit of the mantissa is 1.
fnorm:      tst     fm0
            bne     qnm3
            lda     fm1             ; a whole byte at a time
            ora     fm2
            ora     fm3
            ora     fm4
            ora     fm5
            ora     fm6
            ora     fmg
            lbeq    fzero
            ldd     fm1
            std     fm0
            ldd     fm3
            std     fm2
            ldd     fm5
            std     fm4
            lda     fmg
            sta     fm6
            clr     fmg
            lda     fexp
            suba    #8
            lbls    fzero
            sta     fexp
            bra     fnorm
qnm3:       bmi     qnm9
qnm4:       asl     fmg
            rol     fm6
            rol     fm5
            rol     fm4
            rol     fm3
            rol     fm2
            rol     fm1
            rol     fm0
            dec     fexp
            lbeq    fzero
            tst     fm0
            bpl     qnm4
qnm9:       rts

; Shift ARG's mantissa right B bits.
ashr:       cmpb    #8
            blo     qsr2
            lda     am6
            sta     amg
            lda     am5
            sta     am6
            lda     am4
            sta     am5
            lda     am3
            sta     am4
            lda     am2
            sta     am3
            lda     am1
            sta     am2
            lda     am0
            sta     am1
            clr     am0
            subb    #8
            bra     ashr
qsr2:       tstb
            beq     qsr9
qsr3:       lsr     am0
            ror     am1
            ror     am2
            ror     am3
            ror     am4
            ror     am5
            ror     am6
            ror     amg
            decb
            bne     qsr3
qsr9:       rts

; FAC's mantissa += ARG's
madd:       ldx     #fmg+1
            ldu     #amg+1
            ldb     #8
            andcc   #$FE
qma1:       lda     ,-x
            adca    ,-u
            sta     ,x
            decb
            bne     qma1
            bcc     qma9
            ror     fm0
            ror     fm1
            ror     fm2
            ror     fm3
            ror     fm4
            ror     fm5
            ror     fm6
            ror     fmg
            inc     fexp
            lbeq    overr
qma9:       rts

; FAC = ARG - FAC, FAC = ARG + FAC
fsub:       com     fsgn
fadd:       lda     fprec
            ora     aprec
            sta     fprec
            sta     aprec
            tst     aexp
            beq     qad8
            tst     fexp
            bne     qad0
            jsr     fcopyaf
            bra     qad8
qad0:       lda     aexp
            cmpa    fexp
            bls     qad1
            jsr     fswap           ; FAC has the bigger exponent
qad1:       ldb     fexp
            subb    aexp
            cmpb    #64
            bhs     qad8            ; ARG is too small to matter
            jsr     ashr
            lda     fsgn
            eora    asgn
            bmi     qad2
            bsr     madd
            bra     qad8
qad2:       ldx     #fmg+1          ; different signs: subtract
            ldu     #amg+1
            ldb     #8
            andcc   #$FE
qad2a:      lda     ,-x
            sbca    ,-u
            sta     ,x
            decb
            bne     qad2a
            bcc     qad3
            ldx     #fm0            ; went below 0: negate it
            ldb     #8
qad2b:      com     ,x+
            decb
            bne     qad2b
            ldb     #8
            orcc    #$01
qad2c:      lda     ,-x
            adca    #0
            sta     ,x
            decb
            bne     qad2c
            com     fsgn
qad3:       jsr     fnorm
qad8:       jmp     fsingle

; FAC = ARG * FAC: 56 x 56 bits, a byte at a time, zero bytes skipped
fmul:       lda     fprec
            ora     aprec
            sta     fprec
            tst     fexp
            lbeq    qmu9
            tst     aexp
            lbeq    fzero
            lda     fsgn
            eora    asgn
            sta     fsgn
            clra
            ldb     aexp
            addb    fexp
            adca    #0
            subd    #128
            std     qe
            ldx     #prod
            ldb     #14
qmu1:       clr     ,x+
            decb
            bne     qmu1
            lda     #6
            sta     qi
qmu2:       ldx     #am0
            lda     qi
            lda     a,x
            beq     qmu6
            sta     qa
            lda     #6
            sta     qj
qmu3:       ldx     #fm0
            ldb     qj
            ldb     b,x
            beq     qmu5
            lda     qa
            mul
            pshs    d
            lda     qi
            adda    qj
            ldx     #prod+1
            leax    a,x
            puls    d
            addb    ,x
            stb     ,x
            adca    -1,x
            sta     -1,x
            bcc     qmu5
            leax    -1,x
qmu4:       leax    -1,x
            inc     ,x
            beq     qmu4
qmu5:       dec     qj
            bpl     qmu3
qmu6:       dec     qi
            bpl     qmu2
            ldd     prod
            std     fm0
            ldd     prod+2
            std     fm2
            ldd     prod+4
            std     fm4
            ldd     prod+6
            std     fm6
            tst     fm0
            bmi     qmu7
            asl     prod+8
            rol     fmg
            rol     fm6
            rol     fm5
            rol     fm4
            rol     fm3
            rol     fm2
            rol     fm1
            rol     fm0
            ldd     qe
            subd    #1
            std     qe
qmu7:       ldd     qe
            lble    fzero
            cmpd    #255
            lbgt    overr
            stb     fexp
qmu9:       jmp     fsingle

; FAC = ARG / FAC: 40 quotient bits for single, 64 for double
fdiv:       lda     fprec
            ora     aprec
            sta     fprec
            tst     fexp
            lbeq    dzerr
            tst     aexp
            lbeq    fzero
            lda     fsgn
            eora    asgn
            sta     fsgn
            clra
            ldb     aexp
            subb    fexp
            sbca    #0
            addd    #128
            std     qe
            clr     dv0             ; R = ARG, F = FAC (9 bytes each)
            ldd     am0
            std     dv1
            ldd     am2
            std     dv3
            ldd     am4
            std     dv5
            ldd     am6
            std     dv7
            clr     df0
            ldd     fm0
            std     df1
            ldd     fm2
            std     df3
            ldd     fm4
            std     df5
            lda     fm6
            sta     df7
            clr     df8
            jsr     dcmp            ; R >= F: halve R, so R/F < 1
            bcs     qdv1
            lsr     dv1
            ror     dv2
            ror     dv3
            ror     dv4
            ror     dv5
            ror     dv6
            ror     dv7
            ror     dv8
            ldd     qe
            addd    #1
            std     qe
qdv1:       lda     #40
            tst     fprec
            beq     qdv1a
            lda     #64
qdv1a:      sta     qi
            ldd     #0
            std     fm0
            std     fm2
            std     fm4
            std     fm6
qdv2:       asl     dv8
            rol     dv7
            rol     dv6
            rol     dv5
            rol     dv4
            rol     dv3
            rol     dv2
            rol     dv1
            rol     dv0
            asl     fmg
            rol     fm6
            rol     fm5
            rol     fm4
            rol     fm3
            rol     fm2
            rol     fm1
            rol     fm0
            jsr     dcmp
            bcs     qdv3
            lda     dv8
            suba    df8
            sta     dv8
            lda     dv7
            sbca    df7
            sta     dv7
            lda     dv6
            sbca    df6
            sta     dv6
            lda     dv5
            sbca    df5
            sta     dv5
            lda     dv4
            sbca    df4
            sta     dv4
            lda     dv3
            sbca    df3
            sta     dv3
            lda     dv2
            sbca    df2
            sta     dv2
            lda     dv1
            sbca    df1
            sta     dv1
            lda     dv0
            sbca    df0
            sta     dv0
            inc     fmg
qdv3:       dec     qi
            lbne    qdv2
            tst     fprec
            bne     qdv4
            ldd     fm3             ; 40 bits: move them to the top
            std     fm0
            ldd     fm5
            std     fm2
            lda     fmg
            sta     fm4
            clr     fm5
            clr     fm6
            clr     fmg
qdv4:       ldd     qe
            lble    fzero
            cmpd    #255
            lbgt    overr
            stb     fexp
            jmp     fsingle

; C=1 if R < F
dcmp:       ldx     #dv0
            ldu     #df0
            ldb     #9
qdc1:       lda     ,x+
            cmpa    ,u+
            bne     qdc9
            decb
            bne     qdc1
qdc9:       rts

; Compare ARG with FAC -> B: 1 ARG < FAC, 2 equal, 4 ARG > FAC.  fcmp
; rounds FAC first; fcmpn doesn't, and counts the guard bytes too.
fcmp:       jsr     fround
fcmpn:      ldb     fexp
            beq     qcm1
            ldb     fsgn
qcm1:       lda     aexp
            beq     qcm2
            lda     asgn
qcm2:       pshs    a
            cmpb    ,s+
            beq     qcm3
            tsta                    ; different signs
            bmi     qcm8
            bra     qcm7
qcm3:       pshs    a               ; same sign: compare the sizes
            lda     aexp
            cmpa    fexp
            bne     qcm5
            tsta
            beq     qcm6            ; both 0
            ldx     #am0
            ldu     #fm0
            ldb     #8
qcm4:       lda     ,x+
            cmpa    ,u+
            bne     qcm5
            decb
            bne     qcm4
qcm6:       puls    a
            ldb     #2
            rts
qcm5:       puls    a               ; (keeps the flags)
            blo     qcm5a
            tsta                    ; |ARG| > |FAC|
            bmi     qcm8
            bra     qcm7
qcm5a:      tsta
            bmi     qcm7
qcm8:       ldb     #1
            rts
qcm7:       ldb     #4
            rts

; FAC = D, signed or unsigned (single precision)
fltd:       clr     fsgn
            tsta
            bpl     qfl1
            com     fsgn
            jsr     dneg
            bra     qfl1
fltud:      clr     fsgn
qfl1:       std     fm0
            ldd     #0
            std     fm2
            std     fm4
            std     fm6
            clr     fprec
            lda     #144
            sta     fexp
            jmp     fnorm

; FAC = the 32-bit / 64-bit unsigned number in nint
flt32:      ldd     nint
            std     fm0
            ldd     nint+2
            std     fm2
            ldd     #0
            std     fm4
            std     fm6
            clr     fsgn
            clr     fprec
            lda     #160
            sta     fexp
            jmp     fnorm
flt64:      ldd     nint
            std     fm0
            ldd     nint+2
            std     fm2
            ldd     nint+4
            std     fm4
            ldd     nint+6
            std     fm6
            clr     fsgn
            lda     #192
            sta     fexp
            jmp     fnorm

; FAC (rounded toward 0) -> D.  -32768 to 65535, else an error.
fac2w:      jsr     fround
            lda     fexp
            cmpa    #129
            blo     qfw0
            cmpa    #144
            lbhi    fcerr
            nega
            adda    #144
            sta     qi
            ldd     fm0
qfw1:       tst     qi
            beq     qfw2
            lsra
            rorb
            dec     qi
            bra     qfw1
qfw2:       tst     fsgn
            bpl     qfw9
            cmpd    #32768
            lbhi    fcerr
            jmp     dneg
qfw0:       ldd     #0
qfw9:       rts

; FAC rounded to the nearest whole number -> D, -32768 to 32767, else
; an OVERFLOW (for % variables)
fac2i:      jsr     fround
            tst     fexp
            beq     qfi9
            lda     fsgn
            pshs    a
            clr     fsgn
            ldx     #c_half
            jsr     argld
            jsr     fadd
            puls    a
            sta     fsgn
            lda     fexp
            cmpa    #144
            blo     qfi1
            lbhi    overr
            tst     fsgn            ; 32768 or more: only -32768 fits
            lbpl    overr
            ldd     fm0
            cmpd    #$8000
            lbne    overr
qfi1:       jsr     fac2w
qfi9:       rts

; FAC (a whole number below 2^56) -> nint, 64 bits
fac2u64:    clr     nint
            ldd     fm0
            std     nint+1
            ldd     fm2
            std     nint+3
            ldd     fm4
            std     nint+5
            lda     fm6
            sta     nint+7
            lda     #184
            suba    fexp
            bls     qfu9
qfu0:       cmpa    #8
            blo     qfu2
            ldb     nint+6
            stb     nint+7
            ldb     nint+5
            stb     nint+6
            ldb     nint+4
            stb     nint+5
            ldb     nint+3
            stb     nint+4
            ldb     nint+2
            stb     nint+3
            ldb     nint+1
            stb     nint+2
            ldb     nint
            stb     nint+1
            clr     nint
            suba    #8
            bra     qfu0
qfu2:       tsta
            beq     qfu9
qfu3:       lsr     nint
            ror     nint+1
            ror     nint+2
            ror     nint+3
            ror     nint+4
            ror     nint+5
            ror     nint+6
            ror     nint+7
            deca
            bne     qfu3
qfu9:       rts

; FAC = FIX(FAC): drop the fraction
ffix:       lda     fexp
            cmpa    #129
            lblo    fzero
            suba    #128            ; bits before the point
            cmpa    #64
            bhs     qfx9
            ldx     #fm0
            ldb     #8
qfx1:       cmpa    #8
            blo     qfx2
            suba    #8
            leax    1,x
            decb
            bne     qfx1
            rts
qfx2:       pshs    b
            nega
            adda    #8
            ldb     #$FF
qfx3:       aslb
            deca
            bne     qfx3
            andb    ,x
            stb     ,x+
            puls    b
            decb
            beq     qfx9
qfx4:       clr     ,x+
            decb
            bne     qfx4
qfx9:       rts

; FAC = INT(FAC): the whole number at or below it
ffloor:     tst     fsgn
            bpl     ffix
            jsr     fround
            ldx     #ftf
            jsr     fstd
            bsr     ffix
            ldx     #ftf2
            jsr     fstd
            ldx     #ftf
            ldu     #ftf2
            ldb     #8
qfl2:       lda     ,x+
            cmpa    ,u+
            bne     qfl3
            decb
            bne     qfl2
            rts
qfl3:       jsr     fcopyfa         ; it had a fraction: one less
            ldx     #c_one
            jsr     fld
            jmp     fsub

; FAC = FAC * 10, FAC = FAC / 10 (both keep the precision)
fmul10:     tst     fexp
            beq     qmt9
            jsr     fcopyfa         ; x*8 + x*2 = (x + x/4) * 8
            ldb     #2
            jsr     ashr
            jsr     madd
            lda     fexp
            adda    #3
            lbcs    overr
            sta     fexp
qmt9:       rts
fdiv10:     jsr     fcopyfa
            ldx     #c_ten
            jsr     fld
            jmp     fdiv

; Push FAC on the stack (9 bytes, under the return address: a double
; and the precision); pop it into ARG
fpush:      puls    x
            leas    -9,s
            pshs    x
            leax    2,s
            jsr     fstd
            lda     fprec
            sta     8,x
            rts
fpopa:      leax    2,s
            jsr     argldd
            lda     8,x
            sta     aprec
            puls    x
            leas    9,s
            jmp     ,x

; nint = nint * 10 + A (64 bits)
n10:        pshs    a,x,u
            bsr     n2x
            ldx     #nint
            ldu     #ntmp8
            ldb     #8
qn1:        lda     ,x+
            sta     ,u+
            decb
            bne     qn1
            bsr     n2x
            bsr     n2x
            ldx     #nint+8         ; + the copy (x*8 + x*2)
            ldu     #ntmp8+8
            ldb     #8
            andcc   #$FE
qn2:        lda     ,-x
            adca    ,-u
            sta     ,x
            decb
            bne     qn2
            ldx     #nint+8         ; + the digit
            ldb     #8
            lda     ,s
            andcc   #$FE
qn3:        adca    ,-x
            sta     ,x
            lda     #0
            decb
            bne     qn3
            puls    a,x,u,pc
n2x:        asl     nint+7
            rol     nint+6
            rol     nint+5
            rol     nint+4
            rol     nint+3
            rol     nint+2
            rol     nint+1
            rol     nint
            rts

; Number at X -> FAC, X past it.  A sign, &H hex, digits with a point,
; E or D and an exponent, a # after it.  Double precision if it has
; more than 9 digits, a D or a #, or fdflt was set; otherwise single.
; C=1 if there is no number.
fin:        lda     fdflt
            sta     fdbl
            clr     fdflt
            clr     fnsg
            jsr     skipspx
            cmpa    #'-
            bne     qin1
            com     fnsg
            bra     qin1a
qin1:       cmpa    #'+
            bne     qin2
qin1a:      leax    1,x
qin2:       lda     ,x
            cmpa    #'&
            bne     qin3
            jsr     parsenum        ; &H: a whole number
            lbcs    qin9x
            jsr     fltud
            lbra    qin8
qin3:       ldd     #0
            std     nint
            std     nint+2
            std     nint+4
            std     nint+6
            std     dexp
            sta     ndig
            sta     fseen
            sta     fdot
qin4:       lda     ,x
            cmpa    #'.
            bne     qin5
            tst     fdot
            bne     qin6
            inc     fdot
            leax    1,x
            bra     qin4
qin5:       jsr     isdig
            bcs     qin6
            inc     fseen
            leax    1,x
            suba    #'0
            ldb     ndig            ; 17 digits are kept, the rest only
            cmpb    #17             ; move the point
            bhs     qin5b
            tsta
            bne     qin5a
            ldb     nint+7          ; leading zeros don't count
            orb     nint+6
            orb     nint+5
            orb     nint+4
            orb     nint+3
            orb     nint+2
            orb     nint+1
            orb     nint
            beq     qin5c
qin5a:      jsr     n10
            inc     ndig
qin5c:      tst     fdot
            beq     qin4
            ldd     dexp
            subd    #1
            std     dexp
            bra     qin4
qin5b:      tst     fdot
            bne     qin4
            ldd     dexp
            addd    #1
            std     dexp
            bra     qin4
qin6:       tst     fseen
            lbeq    qin9x
            lda     ,x
            jsr     upcase
            cmpa    #'E
            beq     qin6a
            cmpa    #'D
            bne     qin7
qin6a:      pshs    a,x             ; E or D [+|-] digits
            leax    1,x
            clr     ntmp
            lda     ,x
            cmpa    #'-
            bne     qxe1
            inc     ntmp
            bra     qxe1a
qxe1:       cmpa    #'+
            bne     qxe2
qxe1a:      leax    1,x
qxe2:       lda     ,x
            jsr     isdig
            bcs     qxe9
            clrb
qxe3:       lda     ,x
            suba    #'0
            cmpa    #9
            bhi     qxe4
            leax    1,x
            cmpb    #24             ; big enough to overflow anyway
            bhs     qxe3
            pshs    a
            lda     #10
            mul
            addb    ,s+
            bra     qxe3
qxe4:       lda     ,s              ; D: double precision
            cmpa    #'D
            bne     qxe4a
            inc     fdbl
qxe4a:      leas    3,s
            clra
            tst     ntmp
            beq     qxe5
            jsr     dneg
qxe5:       addd    dexp
            std     dexp
            bra     qin7
qxe9:       puls    a,x             ; not an exponent after all
qin7:       lda     ,x              ; a # after it: double
            cmpa    #'#
            bne     qin7a
            leax    1,x
            inc     fdbl
qin7a:      lda     ndig
            cmpa    #9
            bls     qin7b
            inc     fdbl
qin7b:      pshs    x
            jsr     flt64
            lda     #1              ; exact while scaling
            sta     fprec
qsc1:       ldd     dexp            ; times 10^dexp
            beq     qsc9
            bmi     qsc2
            subd    #1
            std     dexp
            jsr     fmul10
            bra     qsc1
qsc2:       addd    #1
            std     dexp
            jsr     fdiv10
            bra     qsc1
qsc9:       puls    x
            tst     fdbl
            bne     qin8
            clr     fprec           ; single: round to 32 bits
            jsr     fround
            jsr     fround32
qin8:       tst     fnsg
            beq     qin8a
            jsr     fneg
qin8a:      andcc   #$FE
            rts
qin9x:      orcc    #$01
            rts

; nint >= the 64-bit number at X?  C=0 if so.  Keeps X.
ge64:       pshs    x
            ldu     #nint
            ldb     #8
qg1:        lda     ,u+
            cmpa    ,x+
            bne     qg2
            decb
            bne     qg1
qg2:        puls    x,pc
; nint -= the 64-bit number at X.  Keeps X.
sub64:      pshs    x
            leax    8,x
            ldu     #nint+8
            ldb     #8
            andcc   #$FE
qsb1:       lda     ,-u
            sbca    ,-x
            sta     ,u
            decb
            bne     qsb1
            puls    x,pc

; FAC -> text: X = ntext, B = length.  Up to 9 digits for single
; precision, 16 for double; E (or D) notation from 10^digits up and
; below 0.0001.
fout:       lda     fprec
            sta     oprec
            ldu     #ntext
            tst     fexp
            bne     qot1
            lda     #'0
            sta     ,u+
            lbra    qot9
qot1:       tst     fsgn
            bpl     qot2
            lda     #'-
            sta     ,u+
            clr     fsgn
qot2:       stu     optr
            jsr     fdig
            ldb     ndmax           ; drop the trailing zeros
            ldx     #dbuf
            abx
            leax    -1,x
qot8:       cmpb    #1
            beq     qot8a
            lda     ,x
            cmpa    #'0
            bne     qot8a
            leax    -1,x
            decb
            bra     qot8
qot8a:      stb     ndig
            lda     dexp            ; decimal exponent of the first digit
            ldu     optr
            ldx     #dbuf
            tsta
            bmi     qotn
            ldb     ndmax
            decb
            pshs    b
            cmpa    ,s+
            bhi     qots
            ldb     dexp            ; d..d[.d..d]
            incb
qot10:      lda     ,x+
            sta     ,u+
            decb
            bne     qot10
            ldb     ndig
            subb    dexp
            decb
            ble     qot9
            lda     #'.
            sta     ,u+
qot11:      lda     ,x+
            sta     ,u+
            decb
            bne     qot11
            bra     qot9
qotn:       cmpa    #-4             ; -4 to -1: 0.000d..d
            blt     qots
            lda     #'0
            sta     ,u+
            lda     #'.
            sta     ,u+
            ldb     dexp
            negb
            decb
            beq     qot13
qot12:      lda     #'0
            sta     ,u+
            decb
            bne     qot12
qot13:      ldb     ndig
qot14:      lda     ,x+
            sta     ,u+
            decb
            bne     qot14
            bra     qot9
qots:       lda     ,x+             ; d[.d..d]E+nn
            sta     ,u+
            ldb     ndig
            decb
            beq     qot15
            lda     #'.
            sta     ,u+
qot16:      lda     ,x+
            sta     ,u+
            decb
            bne     qot16
qot15:      lda     #'E
            tst     oprec
            beq     qot15a
            lda     #'D
qot15a:     sta     ,u+
            lda     #'+
            ldb     dexp
            bpl     qot17
            lda     #'-
            negb
qot17:      sta     ,u+
            lda     #'0
qot18:      cmpb    #10
            blo     qot19
            subb    #10
            inca
            bra     qot18
qot19:      sta     ,u+
            addb    #'0
            stb     ,u+
qot9:       tfr     u,d
            subd    #ntext
            ldx     #ntext
            rts

; |FAC| (not 0) -> dbuf: its first 9 digits (16 if it is double),
; rounded; ndmax = how many; dexp = the power of 10 of the first.
fdig:       lda     fprec
            sta     oprec
            clr     dexp
            lda     #9
            ldx     #p10_64+7*8     ; 1E9
            tst     oprec
            beq     qot2a
            lda     #16
            ldx     #p10_64         ; 1E16
qot2a:      sta     ndmax
            stx     ptop
            lda     #1              ; scale it exactly
            sta     fprec
qot3:       ldx     #c_1e9          ; to 10^(digits-1) <= FAC < 10^digits
            jsr     argld
            tst     oprec
            beq     qot3a
            ldx     #c_1e16
            jsr     argldd
qot3a:      jsr     fcmpn
            bitb    #4
            bne     qot4
            jsr     fdiv10
            inc     dexp
            bra     qot3
qot4:       ldx     #c_1e8
            jsr     argld
            tst     oprec
            beq     qot4a
            ldx     #c_1e15
            jsr     argldd
qot4a:      jsr     fcmpn
            bitb    #4
            beq     qot5
            jsr     fmul10
            dec     dexp
            bra     qot4
qot5:       ldx     #c_half         ; round to a whole number
            jsr     argld
            jsr     fadd
            jsr     ffix
            jsr     fac2u64
            ldx     ptop            ; rounded up to 10^digits?
            jsr     ge64
            bcs     qot6
            leax    8,x
            ldb     #8
            ldu     #nint
qot5a:      lda     ,x+
            sta     ,u+
            decb
            bne     qot5a
            inc     dexp
qot6:       ldx     ptop            ; the digits
            leax    8,x
            ldd     #dbuf
            std     dptr
            lda     ndmax
            sta     dcnt
qot7:       clr     ,-s
qot7a:      jsr     ge64
            bcs     qot7b
            jsr     sub64
            inc     ,s
            bra     qot7a
qot7b:      puls    a
            adda    #'0
            ldu     dptr
            sta     ,u+
            stu     dptr
            leax    8,x
            dec     dcnt
            bne     qot7
            lda     dexp
            adda    ndmax
            deca
            sta     dexp
            rts

p10t10:     fdb     $3B9A,$CA00     ; 32-bit powers of 10, for PRINT USING
            fdb     $05F5,$E100,$0098,$9680,$000F,$4240,$0001,$86A0
            fdb     $0000,$2710,$0000,$03E8,$0000,$0064,$0000,$000A
            fdb     $0000,$0001

; ARG MOD FAC: ARG - FAC * FIX(ARG / FAC)
fmod:       ldx     #ft7
            jsr     fstd
            lda     fprec
            sta     pwp
            jsr     fswap
            ldx     #ft8
            jsr     fstd
            lda     fprec
            ora     pwp
            sta     pwp
            ldx     #ft8
            jsr     argldd
            ldx     #ft7
            jsr     fldd
            jsr     fdiv
            jsr     ffix
            ldx     #ft7
            jsr     argldd
            jsr     fmul
            ldx     #ft8
            jsr     argldd
            jsr     fsub
            lda     pwp
            sta     fprec
            jmp     fsingle

; ARG ^ FAC
fpow:       ldx     #pwe
            jsr     fstd
            jsr     fswap
            ldx     #pwb
            jsr     fstd
            lda     fprec           ; the base's precision
            sta     pwp
            ldx     #pwe            ; a whole power: multiply
            jsr     fldd
            lda     fexp
            cmpa    #128+15
            lbhi    qpw8
            jsr     ffix
            ldx     #ftf
            jsr     fstd
            ldx     #ftf
            ldu     #pwe
            ldb     #8
qpw0:       lda     ,x+
            cmpa    ,u+
            lbne    qpw8
            decb
            bne     qpw0
            jsr     fac2w
            std     pwn
            bpl     qpw1
            jsr     dneg
qpw1:       std     pwk
            ldx     #c_one
            jsr     fld
            ldx     #pwr
            jsr     fstd
qpw2:       ldd     pwk
            beq     qpw4
            lsra
            rorb
            std     pwk
            bcc     qpw3
            ldx     #pwr
            jsr     fldd
            ldx     #pwb
            jsr     argldd
            jsr     fmul
            ldx     #pwr
            jsr     fstd
qpw3:       ldd     pwk
            beq     qpw4
            ldx     #pwb
            jsr     fldd
            ldx     #pwb
            jsr     argldd
            jsr     fmul
            ldx     #pwb
            jsr     fstd
            bra     qpw2
qpw4:       ldx     #pwr
            jsr     fldd
            ldd     pwn
            bpl     qpw9
            ldx     #c_one          ; a negative power: 1 / that
            jsr     argld
            jsr     fdiv
qpw9:       lda     pwp
            sta     fprec
            jmp     fsingle
qpw8:       ldx     #pwb            ; otherwise EXP(e * LOG(b))
            jsr     fld
            tst     fexp
            beq     qpw9
            tst     fsgn
            lbmi    fcerr
            jsr     flogf
            ldx     #pwe
            jsr     argld
            jsr     fmul
            jsr     fexpf
            clr     fprec
            jmp     fsingle

; FAC = P(pz), X -> a count byte and the coefficients, highest first
poly:       ldb     ,x+
            stb     pcnt
            stx     pptr
            jsr     fld
qpl1:       dec     pcnt
            beq     qpl9
            ldx     #pz
            jsr     argld
            jsr     fmul
            ldx     pptr
            leax    5,x
            stx     pptr
            jsr     argld
            jsr     fadd
            bra     qpl1
qpl9:       rts

; ---- math functions on FAC ---------------------------------------------
fsqr:       tst     fexp
            beq     qsq9
            tst     fsgn
            lbmi    fcerr
            ldx     #ft1            ; Newton: g = (g + a/g) / 2
            jsr     fst
            lda     fexp            ; first guess: half the exponent
            suba    #128
            asra
            adda    #128
            sta     fexp
            lda     #6
            sta     sqcnt
qsq1:       ldx     #ft2
            jsr     fst
            ldx     #ft1
            jsr     argld
            jsr     fdiv
            ldx     #ft2
            jsr     argld
            jsr     fadd
            dec     fexp
            dec     sqcnt
            bne     qsq1
qsq9:       rts

; LOG(x) = e*LN 2 + LN m, LN m = 2t(1 + t^2/3 + ...), t = (m-1)/(m+1)
flogf:      tst     fexp
            lbeq    fcerr
            tst     fsgn
            lbmi    fcerr
            ldb     fexp
            subb    #128
            sex
            std     lge
            lda     #128            ; m = 0.5 to 1
            sta     fexp
            ldx     #c_sqh
            jsr     argld
            jsr     fcmp
            bitb    #4
            beq     qlg1
            inc     fexp            ; now 0.71 to 1.41
            ldd     lge
            subd    #1
            std     lge
qlg1:       ldx     #ft1
            jsr     fst
            ldx     #ft1
            jsr     argld
            ldx     #c_one
            jsr     fld
            jsr     fsub
            ldx     #ft2
            jsr     fst
            ldx     #ft1
            jsr     argld
            ldx     #c_one
            jsr     fld
            jsr     fadd
            ldx     #ft2
            jsr     argld
            jsr     fdiv
            ldx     #ft3
            jsr     fst
            ldx     #ft3
            jsr     argld
            jsr     fmul
            ldx     #pz
            jsr     fst
            ldx     #p_log
            jsr     poly
            ldx     #ft3
            jsr     argld
            jsr     fmul
            tst     fexp
            beq     qlg2
            inc     fexp
qlg2:       ldx     #ft4
            jsr     fst
            ldd     lge
            jsr     fltd
            ldx     #c_ln2
            jsr     argld
            jsr     fmul
            ldx     #ft4
            jsr     argld
            jmp     fadd

; EXP(x) = 2^n * EXP(r), x/LN 2 = n + f, r = f * LN 2
fexpf:      lda     fexp
            cmpa    #128+8
            blo     qex1
            tst     fsgn
            lbpl    overr
            jmp     fzero
qex1:       ldx     #c_log2e
            jsr     argld
            jsr     fmul
            ldx     #ft1
            jsr     fst
            ldx     #c_half
            jsr     argld
            jsr     fadd
            jsr     ffloor
            ldx     #ft2
            jsr     fst
            jsr     fac2w
            std     lge
            ldx     #ft1
            jsr     argld
            ldx     #ft2
            jsr     fld
            jsr     fsub
            ldx     #c_ln2
            jsr     argld
            jsr     fmul
            ldx     #pz
            jsr     fst
            ldx     #p_exp
            jsr     poly
            ldb     fexp
            clra
            addd    lge
            lble    fzero
            cmpd    #255
            lbgt    overr
            stb     fexp
            rts

; SIN and COS: x * 2/PI = n + f, r = f * PI/2, then by the quadrant
fsinf:      clr     qoff
            bra     qsc0
fcosf:      lda     #1
            sta     qoff
qsc0:       ldx     #c_2pi
            jsr     argld
            jsr     fmul
            ldx     #ft1
            jsr     fst
            ldx     #c_half
            jsr     argld
            jsr     fadd
            jsr     ffloor
            ldx     #ft2
            jsr     fst
            jsr     fac2w
            addb    qoff
            andb    #3
            stb     qoff
            ldx     #ft1
            jsr     argld
            ldx     #ft2
            jsr     fld
            jsr     fsub
            ldx     #c_pi2
            jsr     argld
            jsr     fmul
            ldx     #ft3
            jsr     fst
            ldx     #ft3
            jsr     argld
            jsr     fmul
            ldx     #pz
            jsr     fst
            lda     qoff
            bita    #1
            bne     qsc1x
            ldx     #p_sin
            jsr     poly
            ldx     #ft3
            jsr     argld
            jsr     fmul
            bra     qsc2x
qsc1x:      ldx     #p_cos
            jsr     poly
qsc2x:      lda     qoff
            bita    #2
            lbne    fneg
            rts

ftanf:      ldx     #ft5
            jsr     fst
            jsr     fcosf
            ldx     #ft6
            jsr     fst
            ldx     #ft5
            jsr     fld
            jsr     fsinf
            jsr     fcopyfa
            ldx     #ft6
            jsr     fld
            jmp     fdiv

; ATN: 1/x above 1, then (x*SQR 3 - 1)/(x + SQR 3) above TAN(PI/12)
fatnf:      lda     fsgn
            sta     atsg
            clr     fsgn
            clr     atfl
            ldx     #c_one
            jsr     argld
            jsr     fcmp
            bitb    #1
            beq     qat1
            inc     atfl
            ldx     #c_one
            jsr     argld
            jsr     fdiv
qat1:       ldx     #c_tan15
            jsr     argld
            jsr     fcmp
            bitb    #1
            beq     qat2
            lda     atfl
            ora     #2
            sta     atfl
            ldx     #ft1
            jsr     fst
            ldx     #c_sqr3
            jsr     argld
            jsr     fmul
            jsr     fcopyfa
            ldx     #c_one
            jsr     fld
            jsr     fsub
            ldx     #ft2
            jsr     fst
            ldx     #ft1
            jsr     fld
            ldx     #c_sqr3
            jsr     argld
            jsr     fadd
            ldx     #ft2
            jsr     argld
            jsr     fdiv
qat2:       ldx     #ft3
            jsr     fst
            ldx     #ft3
            jsr     argld
            jsr     fmul
            ldx     #pz
            jsr     fst
            ldx     #p_atn
            jsr     poly
            ldx     #ft3
            jsr     argld
            jsr     fmul
            lda     atfl
            bita    #2
            beq     qat3
            ldx     #c_pi6
            jsr     argld
            jsr     fadd
qat3:       lda     atfl
            bita    #1
            beq     qat4
            ldx     #c_pi2
            jsr     argld
            jsr     fsub
qat4:       lda     atsg
            lbmi    fneg
            rts

c_1e15      fcb     $B2,$63,$5F,$A9,$31,$A0,$00,$00   ; 1D15
c_1e16      fcb     $B6,$0E,$1B,$C9,$BF,$04,$00,$00   ; 1D16
p10_64      equ     *               ; 1D16 down to 1, 64 bits each
            fcb     $00,$23,$86,$F2,$6F,$C1,$00,$00
            fcb     $00,$03,$8D,$7E,$A4,$C6,$80,$00
            fcb     $00,$00,$5A,$F3,$10,$7A,$40,$00
            fcb     $00,$00,$09,$18,$4E,$72,$A0,$00
            fcb     $00,$00,$00,$E8,$D4,$A5,$10,$00
            fcb     $00,$00,$00,$17,$48,$76,$E8,$00
            fcb     $00,$00,$00,$02,$54,$0B,$E4,$00
            fcb     $00,$00,$00,$00,$3B,$9A,$CA,$00
            fcb     $00,$00,$00,$00,$05,$F5,$E1,$00
            fcb     $00,$00,$00,$00,$00,$98,$96,$80
            fcb     $00,$00,$00,$00,$00,$0F,$42,$40
            fcb     $00,$00,$00,$00,$00,$01,$86,$A0
            fcb     $00,$00,$00,$00,$00,$00,$27,$10
            fcb     $00,$00,$00,$00,$00,$00,$03,$E8
            fcb     $00,$00,$00,$00,$00,$00,$00,$64
            fcb     $00,$00,$00,$00,$00,$00,$00,$0A
            fcb     $00,$00,$00,$00,$00,$00,$00,$01
c_one       fcb     $81,$00,$00,$00,$00   ; 1
c_half      fcb     $80,$00,$00,$00,$00   ; 0.5
c_ten       fcb     $84,$20,$00,$00,$00   ; 10
c_1e8       fcb     $9B,$3E,$BC,$20,$00   ; 1E8
c_1e9       fcb     $9E,$6E,$6B,$28,$00   ; 1E9
c_2pi       fcb     $80,$22,$F9,$83,$6E   ; 2/PI
c_pi2       fcb     $81,$49,$0F,$DA,$A2   ; PI/2
c_pi6       fcb     $80,$06,$0A,$91,$C1   ; PI/6
c_ln2       fcb     $80,$31,$72,$17,$F8   ; LN 2
c_log2e     fcb     $81,$38,$AA,$3B,$29   ; 1/LN 2
c_sqh       fcb     $80,$35,$04,$F3,$34   ; SQR 0.5
c_sqr3      fcb     $81,$5D,$B3,$D7,$43   ; SQR 3
c_tan15     fcb     $7F,$09,$30,$A2,$F5   ; TAN(PI/12)
p_sin       fcb     6               ; SIN r = r * P(r*r)
            fcb     $67,$D7,$32,$2B,$40
            fcb     $6E,$38,$EF,$1D,$2B
            fcb     $74,$D0,$0D,$00,$D0
            fcb     $7A,$08,$88,$88,$89
            fcb     $7E,$AA,$AA,$AA,$AB
            fcb     $81,$00,$00,$00,$00
p_cos       fcb     7               ; COS r = P(r*r)
            fcb     $64,$0F,$76,$C7,$80
            fcb     $6B,$93,$F2,$7D,$BC
            fcb     $71,$50,$0D,$00,$D0
            fcb     $77,$B6,$0B,$60,$B6
            fcb     $7C,$2A,$AA,$AA,$AB
            fcb     $80,$80,$00,$00,$00
            fcb     $81,$00,$00,$00,$00
p_exp       fcb     11               ; EXP r = P(r)
            fcb     $6B,$13,$F2,$7D,$BC
            fcb     $6E,$38,$EF,$1D,$2B
            fcb     $71,$50,$0D,$00,$D0
            fcb     $74,$50,$0D,$00,$D0
            fcb     $77,$36,$0B,$60,$B6
            fcb     $7A,$08,$88,$88,$89
            fcb     $7C,$2A,$AA,$AA,$AB
            fcb     $7E,$2A,$AA,$AA,$AB
            fcb     $80,$00,$00,$00,$00
            fcb     $81,$00,$00,$00,$00
            fcb     $81,$00,$00,$00,$00
p_log       fcb     7               ; LN m = 2t * P(t*t)
            fcb     $7D,$1D,$89,$D8,$9E
            fcb     $7D,$3A,$2E,$8B,$A3
            fcb     $7D,$63,$8E,$38,$E4
            fcb     $7E,$12,$49,$24,$92
            fcb     $7E,$4C,$CC,$CC,$CD
            fcb     $7F,$2A,$AA,$AA,$AB
            fcb     $81,$00,$00,$00,$00
p_atn       fcb     8               ; ATN x = x * P(x*x)
            fcb     $7D,$88,$88,$88,$89
            fcb     $7D,$1D,$89,$D8,$9E
            fcb     $7D,$BA,$2E,$8B,$A3
            fcb     $7D,$63,$8E,$38,$E4
            fcb     $7E,$92,$49,$24,$92
            fcb     $7E,$4C,$CC,$CC,$CD
            fcb     $7F,$AA,$AA,$AA,$AB
            fcb     $81,$00,$00,$00,$00

; ======================================================================
;  Console
; ======================================================================
; Output A through outv.  Keeps all registers.
outch:      jmp     [outv]

conout:     pshs    a
            cmpa    #CR
            bne     co1
            clr     col
            bra     co2
co1:        cmpa    #$20
            blo     co2
            inc     col
co2:        OS      SYS_PUTC
            puls    a,pc

putnum:     pshs    x
            jsr     numstr
            bra     pu1
putunum:    pshs    x
            jsr     unumstr
pu1:        bsr     putsb
            puls    x,pc

; Print B characters at X
putsb:      tstb
            beq     pb9
            lda     ,x+
            bsr     outch
            decb
            bra     putsb
pb9:        rts

; Print the NUL-terminated string at X
puts:       lda     ,x+
            beq     ps9
            bsr     outch
            bra     puts
ps9:        rts

space:      pshs    a
            lda     #$20
            bsr     outch
            puls    a,pc

crlf:       pshs    a
            lda     #CR
            bsr     outch
            lda     #LF
            bsr     outch
            puls    a,pc

; New line unless the cursor is already at the start of one
newln:      tst     col
            beq     nl9
newln_f:    bra     crlf
nl9:        rts

getkey:     OS      SYS_GETC
            rts

; Read a line into lbuf (NUL-terminated).  C=1 if ^C was pressed.
getline:    ldx     #lbuf
            clrb
gl1:        jsr     getkey
            cmpa    #CR
            beq     gl8
            cmpa    #LF
            bne     gl2
            tst     lastcr          ; the LF of a CR LF
            beq     gl9
            clr     lastcr
            bra     gl1
gl2:        clr     lastcr
            cmpa    #3
            beq     glc
            cmpa    #ESC            ; skip ESC [ ... / ESC O x sequences
            beq     gle
            cmpa    #BS
            beq     glb
            cmpa    #DEL
            beq     glb
            cmpa    #$20
            blo     gl1
            cmpb    #LBMAX
            bhs     gl1
            sta     ,x+
            incb
            jsr     outch
            bra     gl1
glb:        tstb
            beq     gl1
            decb
            leax    -1,x
            pshs    x
            ldx     #msg_bs
            jsr     puts
            dec     col
            dec     col
            puls    x
            bra     gl1
gle:        jsr     getkey          ; the [ or O
gle1:       jsr     getkey          ; parameters, up to the final byte
            cmpa    #$40
            blo     gle1
            bra     gl1
gl8:        inc     lastcr
gl9:        clr     ,x
            jsr     crlf
            andcc   #$FE
            rts
glc:        ldx     #msg_ctlc
            jsr     puts
            orcc    #$01
            rts

; ======================================================================
;  Errors
; ======================================================================
snerr:      ldx     #msg_sn
            bra     error
ulerr:      ldx     #msg_ul
            bra     error
rgerr:      ldx     #msg_rg
            bra     error
nferr:      ldx     #msg_nf
            bra     error
omerr:      ldx     #msg_om
            bra     error
dzerr:      ldx     #msg_dz
            bra     error
tmerr:      ldx     #msg_tm
            bra     error
lserr:      ldx     #msg_ls
            bra     error
bserr:      ldx     #msg_bs2
            bra     error
oderr:      ldx     #msg_od
            bra     error
dderr:      ldx     #msg_dd
            bra     error
cserr:      ldx     #msg_cs
            bra     error
fnerr:      ldx     #msg_fn
            bra     error
sterr:      ldx     #msg_st
            bra     error
fcerr:      ldx     #msg_fc
            bra     error
overr:      ldx     #msg_ov
            bra     error
uferr:      ldx     #msg_uf
            bra     error
iderr:      ldx     #msg_id
            bra     error
faerr:      ldx     #msg_fao
            bra     error
fnoerr:     ldx     #msg_fno
            bra     error
bmerr:      ldx     #msg_bm
            bra     error
iperr:      ldx     #msg_ip
            bra     error
aperr:      ldx     #msg_ap

; Print ?message [IN line] and go back to OK.
error:      pshs    x
            ldx     outv            ; stopped writing to a file
            cmpx    #dputc
            bne     err1
            lda     concol
            sta     col
err1:       ldx     #conout
            stx     outv
            jsr     newln
            lda     #'?
            jsr     outch
            puls    x
err2:       jsr     puts
            ldx     curline
            beq     er9
            pshs    x
            ldx     #msg_in
            jsr     puts
            ldd     [,s++]
            jsr     putunum
er9:        jsr     crlf
            jmp     ready

; ======================================================================
;  Messages
; ======================================================================
msg_hello:  fcc     "MINI09 BASIC 1.0"
            fcb     CR,LF,0
msg_free:   fcc     " bytes free"
            fcb     CR,LF,0
msg_ok:     fcc     "OK"
            fcb     CR,LF,0
msg_break:  fcn     "BREAK"
msg_in:     fcn     " IN "
msg_quest:  fcn     "? "
msg_quest2: fcn     "?? "
msg_redo:   fcc     "?REDO FROM START"
            fcb     CR,LF,0
msg_bs:     fcb     BS,$20,BS,0
msg_ctlc:   fcc     "^C"
            fcb     CR,LF,0
msg_cls:    fcb     ESC
            fcc     "[2J"
            fcb     ESC
            fcn     "[H"
msg_dir:    fcn     "<DIR>"
msg_sn:     fcn     "SYNTAX ERROR"
msg_ul:     fcn     "UNDEFINED LINE"
msg_rg:     fcn     "RETURN WITHOUT GOSUB"
msg_nf:     fcn     "NEXT WITHOUT FOR"
msg_fn:     fcn     "FOR WITHOUT NEXT"
msg_om:     fcn     "OUT OF MEMORY"
msg_dz:     fcn     "DIVISION BY ZERO"
msg_tm:     fcn     "TYPE MISMATCH"
msg_ls:     fcn     "STRING TOO LONG"
msg_bs2:    fcn     "BAD SUBSCRIPT"
msg_od:     fcn     "OUT OF DATA"
msg_dd:     fcn     "ARRAY ALREADY DIMENSIONED"
msg_cs:     fcn     "TOO MANY FOR/GOSUB"
msg_st:     fcn     "STRING TOO COMPLEX"
msg_fc:     fcn     "ILLEGAL FUNCTION CALL"
msg_ov:     fcn     "OVERFLOW"
msg_uf:     fcn     "UNDEFINED FUNCTION"
msg_id:     fcn     "ILLEGAL DIRECT"
msg_fao:    fcn     "FILE ALREADY OPEN"
msg_fno:    fcn     "FILE NOT OPEN"
msg_bm:     fcn     "BAD FILE MODE"
msg_ip:     fcn     "INPUT PAST END"
msg_ap:     fcn     "APPEND NEEDS NEWER VIDEO CARD FIRMWARE"
msg_fnodrv: fcn     "NO FLASH DRIVE"
msg_fnofile: fcn    "FILE NOT FOUND"
msg_fnopath: fcn    "PATH NOT FOUND"
msg_fdenied: fcn    "ACCESS DENIED OR DISK FULL"
msg_fexist: fcn     "ALREADY EXISTS"
msg_fnofat: fcn     "NOT A FAT16/FAT32 DRIVE"
msg_ferr:   fcn     "DRIVE ERROR"

            ifdef   ROMBASIC
codeend     equ     *               ; must stay below $C000
progbase    equ     $1000           ; program text starts here, in RAM
            else
progbase    equ     *               ; program text starts here
            endc

            end     start
