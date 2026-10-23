; ----------------------------------------------------------------------
;  ASM - a 6809 macro assembler that runs under MINI09
;
;  Two passes over source held in the banked pages.  It reads the lwasm
;  subset described in asm.md and writes a .PRG program file that is
;  byte for byte what lwasm and tools/mkprg.py make.
;
;     ASM HELLO.ASM [-L]
;
;  writes HELLO.PRG, and with -L a listing, HELLO.LST.  Started without
;  arguments (or by a shell that doesn't pass them on) it asks for them.
;
;  Memory (asm.md has the details):
;     $1000-       this program, its tables and buffers
;     $8000-$BFFF  banked window:
;                  pages OUTPG..OUTPG+3  output image (the 64K address space)
;                  pages SYMPG..SYMPG+1  symbols and macro bodies
;                  pages SRCPG..LASTPG   source cache (each file read once)
; ----------------------------------------------------------------------

            include "syscalls.inc"
            include "vdp.inc"

DEFPAGE     equ     2               ; a task's page at $8000 when it starts
OUTPG       equ     3               ; output image, 4 pages
SYMPG       equ     7               ; symbols and macros, 2 pages
SYMEND      equ     SYMPG+2
SRCPG       equ     9               ; first page of the source cache
LASTPG      equ     31
WIN         equ     $8000           ; banked window
WINEND      equ     $C000
LINEMAX     equ     63              ; typed file names
LBUFSZ      equ     250             ; longest source line kept
PHLEN       equ     36              ; program file header
NAMEMAX     equ     31              ; longest symbol kept
OBSZ        equ     256             ; output buffer
MAXDEPTH    equ     8               ; include / macro nesting
LSTNB       equ     5               ; bytes shown per listing line
MAXERR      equ     20              ; errors before ASM gives up
LSTBSZ      equ     512             ; listing file buffer
ARGSZ       equ     96              ; macro arguments, per level
MAXINC      equ     16              ; files in the source cache
INCSZ       equ     48              ; page, address, name (45)

; Opcode classes (the table at opcodes)
C_INH       equ     0               ; inherent
C_GEN8      equ     1               ; #imm8, direct, indexed, extended
C_GEN16     equ     2               ; #imm16, direct, indexed, extended
C_STORE     equ     3               ; direct, indexed, extended
C_MEM       equ     4               ; direct op, indexed op+$60, ext op+$70
C_LEA       equ     5               ; indexed only
C_IMM       equ     6               ; #imm8 only
C_REL8      equ     7
C_REL16     equ     8
C_PSH       equ     9               ; register list
C_TFR       equ     10              ; register pair
C_DIRL      equ     11              ; directive, a label gets the address
C_DIRN      equ     12              ; directive that handles its own label
C_TFM       equ     13              ; 6309 TFM r+,r+ ...
C_LMEM      equ     14              ; 6309 OIM #imm,mem: C_MEM with a byte
C_BIT       equ     15              ; 6309 BAND r,bit,bit,dp
C_LDQ       equ     16              ; 6309 LDQ: #imm32 is $CD

; Symbol entries in the symbol pages:
;   0 next (page, address)  3 value  5 flags  6 line defined  8 aux  9 name
S_VAL       equ     3
S_FLG       equ     5
S_SEQ       equ     6
S_AUX       equ     8               ; macros: the page of the body
S_NAME      equ     9
F_DEF       equ     $01             ; defined
F_KNOWN     equ     $02             ; value known on pass 1
F_MAC       equ     $04             ; a macro (value -> body)
F_EXP       equ     $08             ; exported
; S_AUX of a symbol that isn't a macro: what its value is relative to
K_IMP       equ     $FF             ; imported (value 0)
K_CPLX      equ     $FE             ; (expressions only) anything else
;                   0: absolute, 1..MAXSECT: offset in that section

; Sections (object output): name, flags, pc, size, place in the image,
; relocations (page and address of the first)
MAXSECT     equ     16
SC_FLG      equ     16              ; 1: bss
SC_PC       equ     17
SC_SIZE     equ     19
SC_BASE     equ     21
SC_RH       equ     23
SECSZ       equ     26
RPNSZ       equ     128             ; an expression for the linker
KSTSZ       equ     32

; Input levels: 0 type (0 file, 1 macro)  1 page  2 address  4 line
;   6 -> file name  8 -> arguments  10 argument count
LVSZ        equ     12

            org     $1000
start:      lds     #stktop
            lda     #$FF
            sta     curbank
            clr     lstflag
            clr     lstfd
            clr     objmode
            clr     nsects
            ldd     #0
            std     errors
            ldx     #msg_hello
            jsr     puts
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
st0:        ldx     #msg_src        ; none: ask
            jsr     puts
            jsr     readline
st0a:       jsr     parseargs
            jsr     mkoutname       ; HELLO.ASM -> HELLO.PRG, HELLO.LST
            jsr     mkdir           ; its directory, for includes
            jsr     initops
            ldx     #symtab         ; no symbols
            ldd     #0
st1:        std     ,x++
            cmpx    #symtab+768
            blo     st1
            lda     #SYMPG
            sta     hpage
            ldx     #WIN
            stx     hptr
            lda     #SRCPG          ; source cache empty
            sta     cpage
            ldx     #WIN
            stx     cptr
            clr     ninc
            ldx     #srcname        ; read the source
            jsr     getfile
            stx     mainent
            lda     #1
            sta     pass
            jsr     runpass
            tst     mdef
            lbne    fat_noendm
            tst     ifdepth
            lbne    fat_noendc
            jsr     secbases
            jsr     clrimage
            lda     #2
            sta     pass
            jsr     lstopen
            jsr     runpass
            jsr     flush
            jsr     lstclose
            tst     objmode
            beq     st0e
            jsr     chkexp
st0e:       ldd     errors
            beq     st1a
            jsr     putdec          ; "N error(s)", no program file
            ldx     #msg_errors
            jsr     puts
            jmp     quit
st1a:       tst     objmode
            lbne    st_obj
            ldx     #outname
            stx     fpname
            jsr     writeprg
            lbcs    ferror
            ldd     seq             ; "N lines, N bytes: NAME.PRG"
            jsr     putdec
            ldx     #msg_lines
            jsr     puts
            ldd     #0
            tst     anyout
            beq     st2
            ldd     hi
            subd    lo
            addd    #1
st2:        jsr     putdec
            ldx     #msg_bytes
            jsr     puts
            ldx     #outname
            jsr     puts
            jsr     crlf
            jmp     quit
st_obj:     jsr     writeobj        ; "N lines, N bytes: NAME.O"
            ldd     seq
            jsr     putdec
            ldx     #msg_lines
            jsr     puts
            ldd     objsize
            jsr     putdec
            ldx     #msg_bytes
            jsr     puts
            ldx     #objname
            jsr     puts
            jsr     crlf
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
;  Passes
; ----------------------------------------------------------------------

runpass:    ldd     #0
            std     pc
            std     seq
            std     entry
            std     lvp
            std     obcnt
            std     hi
            clr     endflag
            clr     skipping
            clr     skipnest
            clr     ifdepth
            clr     mdef
            clr     depth
            clr     anyout
            clr     cursect         ; sections start at 0 again
            ldd     #0
            std     curbase
            std     abspc
            ldx     #sectab
            ldb     nsects
            beq     rpi2
rpi1:       clr     SC_PC,x
            clr     SC_PC+1,x
            leax    SECSZ,x
            decb
            bne     rpi1
rpi2:       lda     #LASTPG+1       ; no relocations yet
            sta     rpage
            ldd     #WINEND
            std     rptr
            clr     rpnon           ; pass 2 of an object: relocations
            lda     pass
            cmpa    #2
            bne     rpi3
            lda     objmode
            sta     rpnon
rpi3:       ldd     #$FFFF
            std     lo
            ldx     mainent
            jsr     pushfile
rp1:        jsr     getline
            bcs     rp9
            ldd     seq
            addd    #1
            std     seq
            clr     lshow
            clr     lnb
            sts     linesp          ; an error in the line comes back
            jsr     doline          ; to rp2 with S as it is here
rp2:        tst     lstfd
            beq     rp3
            jsr     lstline
rp3:        tst     endflag
            beq     rp1
rp9:        clra                    ; the last section's size
            jmp     setsect

; Clear the output image (pass 2 fills it)
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
            rts

; ----------------------------------------------------------------------
;  Input: a stack of files and macro expansions
; ----------------------------------------------------------------------

; Next source line -> lbuf (NUL-terminated, no CR / LF).  Carry set at
; the end of the input.
getline:    ldu     lvp
            bne     gl0
            orcc    #$01
            rts
gl0:        ldy     #lbuf
            ldb     1,u
            jsr     setbank
            ldx     2,u
            clrb                    ; B = length
            lda     ,u
            lbne    glmac
glf1:       jsr     glwrap          ; a file
            lda     ,x+
            beq     glf5
            cmpa    #LF
            beq     glf6
            cmpa    #CR
            beq     glf1
            cmpb    #LBUFSZ
            bhs     glf1            ; too long: the rest is dropped
            sta     ,y+
            incb
            bra     glf1
glf5:       leax    -1,x            ; stay on the NUL
            tstb
            bne     glf6            ; a last line with no LF
            jsr     poplevel        ; the end of this file
            bra     getline
glf6:       clr     ,y
            stx     2,u
            ldd     4,u
            addd    #1
            std     4,u
            andcc   #$FE
            rts

glmac:      jsr     glwrap          ; a macro body, \1..\9 replaced
            lda     ,x
            cmpa    #$FF
            bne     glm1
            jsr     poplevel        ; the end of the body
            bra     getline
glm1:       jsr     glwrap
            lda     ,x+
            beq     glm9
            cmpa    #$5C            ; backslash
            bne     glm4
            jsr     glwrap
            lda     ,x
            cmpa    #'1
            blo     glm3
            cmpa    #'9
            bhi     glm3
            leax    1,x
            suba    #'1             ; argument 0..8
            pshs    x
            cmpa    10,u
            bhs     glm6            ; not given: empty
            ldx     8,u
glm5:       tsta
            beq     glm7
glm5a:      tst     ,x+
            bne     glm5a
            deca
            bra     glm5
glm7:       lda     ,x+
            beq     glm6
            cmpb    #LBUFSZ
            bhs     glm7
            sta     ,y+
            incb
            bra     glm7
glm6:       puls    x
            bra     glm1
glm3:       lda     #$5C
glm4:       cmpb    #LBUFSZ
            bhs     glm1
            sta     ,y+
            incb
            bra     glm1
glm9:       clr     ,y
            stx     2,u
            andcc   #$FE
            rts

; X at $C000 -> the start of the next page of the level at U.  Keeps B.
glwrap:     cmpx    #WINEND
            blo     gw9
            inc     1,u
            pshs    b
            ldb     1,u
            jsr     setbank
            puls    b
            ldx     #WIN
gw9:        rts

; New input level -> U
pushlevel:  lda     depth
            cmpa    #MAXDEPTH
            lbhs    fat_nest
            inc     depth
            ldu     lvp
            bne     pu1
            ldu     #levels
            bra     pu2
pu1:        leau    LVSZ,u
pu2:        stu     lvp
            rts

poplevel:   dec     depth
            beq     pl1
            ldu     lvp
            leau    -LVSZ,u
            stu     lvp
            rts
pl1:        ldu     #0
            stu     lvp
            rts

; Read from the cached file at X
pushfile:   pshs    x
            jsr     pushlevel
            puls    x
            clr     ,u
            lda     ,x              ; page
            sta     1,u
            ldd     1,x             ; address
            std     2,u
            ldd     #0
            std     4,u
            leax    3,x
            stx     6,u
            rts

; ----------------------------------------------------------------------
;  Source cache
;
;  Each file is loaded at a 512-byte boundary in the banked pages, so a
;  512-byte read never runs past $BFFF, and ends with a NUL.  incs holds
;  page, address and name for each one.
; ----------------------------------------------------------------------

; The cache entry for the file named at X, loaded if it isn't there yet
; -> X.  A file error stops the assembly.
getfile:    stx     fpname
            ldx     #incs
            ldb     ninc
gf1:        beq     gf3
            pshs    b,x
            leau    3,x
            ldy     fpname
            jsr     strcmp
            puls    b,x
            beq     gf9
            leax    INCSZ,x
            decb
            bra     gf1
gf3:        lda     ninc            ; a new one
            cmpa    #MAXINC
            lbhs    fat_files
            ldx     fpname
            jsr     loadfile
            lbcs    ferror
            lda     ninc
            ldb     #INCSZ
            mul
            addd    #incs
            tfr     d,x
            inc     ninc
            lda     srcpg
            sta     ,x
            ldd     srcptr
            std     1,x
            pshs    x
            leau    3,x
            ldx     fpname
            ldb     #INCSZ-4
gf4:        lda     ,x+
            sta     ,u+
            beq     gf5
            decb
            bne     gf4
            clr     -1,u
gf5:        puls    x
gf9:        rts

; Load the file named at X into the cache at cpage/cptr -> srcpg/srcptr.
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
lf3:        ldx     cptr            ; the NUL at the end
            lda     cpage
            cmpx    #WINEND
            blo     lf4
            inca
            ldx     #WIN
            cmpa    #LASTPG
            bhi     lf8
            sta     cpage
            tfr     a,b
            jsr     setbank
lf4:        clr     ,x+
            tfr     x,d             ; round up to 512 for the next file
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

; ----------------------------------------------------------------------
;  One line
; ----------------------------------------------------------------------

doline:     tst     mdef
            lbne    dl_mdef
            tst     skipping
            lbne    dl_skip
            clr     haslab
            ldx     #lbuf
            lda     ,x
            beq     dl9
            cmpa    #'*
            beq     dl9
            cmpa    #';
            beq     dl9
            cmpa    #$20
            beq     dl1
            cmpa    #9
            beq     dl1
            ldu     #labname        ; a label
            jsr     getsym
            lbeq    err_syntax
            lda     ,x
            cmpa    #':
            bne     dl0
            leax    1,x
dl0:        inc     haslab
dl1:        jsr     getop           ; opcode -> opname, rawop
            stx     optr
            tst     opname
            bne     dl2
            tst     haslab          ; a label alone
            beq     dl9
            jmp     labpc
dl2:        ldx     #opname
            jsr     findop
            beq     dl_macro
            ldb     2,x             ; class, page, opcode
            stb     opclass
            ldd     3,x
            sta     oppage
            stb     opcode
            lda     opclass
            cmpa    #C_DIRN
            beq     dl3
            tst     haslab
            beq     dl3
            jsr     labpc
dl3:        clr     lmflag
            clr     nsect
            ldb     opclass
            lslb
            ldx     #classtab
            jmp     [b,x]
dl9:        rts

; Not an opcode: a macro?
dl_macro:   ldx     #rawop
            ldu     #name
            jsr     strcpy
            jsr     findsym
            lbeq    err_opcode
            lda     S_FLG,x
            bita    #F_MAC
            lbeq    err_opcode
            ldd     S_VAL,x         ; the body
            std     tmp
            lda     S_AUX,x
            sta     tmp2
            tst     haslab
            beq     dm1
            jsr     labpc
dm1:        jsr     pushlevel
            lda     #1
            sta     ,u
            lda     tmp2
            sta     1,u
            ldd     tmp
            std     2,u
            ldd     #0
            std     4,u
            ldx     #argbufs        ; this level's argument buffer
            lda     depth
dm2:        deca
            beq     dm3
            leax    ARGSZ,x
            bra     dm2
dm3:        stx     8,u
            clr     10,u
            leax    ARGSZ-1,x
            stx     tmp             ; the end of the buffer
            ldx     8,u
            ldy     optr            ; split the operand at the commas
            lda     ,y
            beq     dm8
            cmpa    #$20
            beq     dm8
            cmpa    #9
            beq     dm8
            cmpa    #';
            beq     dm8
            inc     10,u
dm4:        lda     ,y+
            beq     dm8
            cmpa    #$20
            beq     dm8
            cmpa    #9
            beq     dm8
            cmpa    #',
            bne     dm5
            inc     10,u
            clra
dm5:        cmpx    tmp
            bhs     dm4
            sta     ,x+
            bra     dm4
dm8:        clr     ,x
            rts

; Inside a macro definition: keep the line until ENDM
dl_mdef:    jsr     scanop
            ldx     #opname
            ldu     #s_endm
            jsr     strcmpx
            beq     dmd8
            lda     pass
            cmpa    #1
            bne     dmd9
            ldx     #lbuf           ; pass 1: into the body
            lda     ,x
            cmpa    #'*
            beq     dmd9
            cmpa    #';
            beq     dmd9
dmd1:       lda     ,x+
            jsr     hput
            tsta
            bne     dmd1
dmd9:       rts
dmd8:       clr     mdef
            lda     pass
            cmpa    #1
            bne     dmd9
            lda     #$FF            ; the end of the body
            jmp     hput

; Skipping a false IFDEF / IFNDEF: only the conditionals matter
dl_skip:    jsr     scanop
            tst     opname
            beq     dsk9
            ldx     #opname
            jsr     findop
            beq     dsk9
            lda     2,x
            cmpa    #C_DIRN
            bne     dsk9
            lda     4,x
            cmpa    #D_IFDEF
            beq     dsk1
            cmpa    #D_IFNDEF
            beq     dsk1
            cmpa    #D_ELSE
            beq     dsk2
            cmpa    #D_ENDC
            bne     dsk9
            tst     skipnest        ; ENDC
            beq     dsk3
            dec     skipnest
            rts
dsk3:       dec     ifdepth
            clr     skipping
            rts
dsk1:       inc     skipnest        ; a nested IF
            rts
dsk2:       tst     skipnest        ; ELSE
            bne     dsk9
            clr     skipping
dsk9:       rts

; The opcode field of lbuf -> opname (upper case), not parsing the label
scanop:     ldx     #lbuf
            clr     opname
            lda     ,x
            cmpa    #'*
            beq     sco9
            cmpa    #';
            beq     sco9
sco1:       lda     ,x              ; past the label
            beq     sco9
            cmpa    #$20
            beq     sco2
            cmpa    #9
            beq     sco2
            leax    1,x
            bra     sco1
sco2:       jmp     getop
sco9:       rts

; Opcode at X (after spaces) -> opname upper case, rawop as written.
; X ends after the spaces that follow it.
getop:      jsr     skipsp
            ldu     #opname
            ldy     #rawop
            clrb
go1:        lda     ,x
            beq     go8
            cmpa    #$20
            beq     go8
            cmpa    #9
            beq     go8
            leax    1,x
            cmpb    #15
            bhs     go1
            sta     ,y+
            jsr     upper
            sta     ,u+
            incb
            bra     go1
go8:        clr     ,u
            clr     ,y
            lda     opname          ; a comment where the opcode would be
            cmpa    #';
            beq     go9
            cmpa    #'*
            bne     skipsp
go9:        clr     opname
            rts

skipsp:     lda     ,x
            cmpa    #$20
            beq     ss1
            cmpa    #9
            bne     ss9
ss1:        leax    1,x
            bra     skipsp
ss9:        rts

; The label is the current address
labpc:      ldd     pc
            jsr     lstat
            lda     cursect
            sta     nsect
            ldx     #labname
            ldu     #name
            jsr     strcpy
            lda     #F_DEF|F_KNOWN
            sta     nflags
            ldd     pc
            jmp     deflabel

classtab:   fdb     c_inh,c_gen,c_gen,c_gen,c_gen,c_gen,c_imm,c_rel8
            fdb     c_rel16,c_psh,c_tfr,c_dir,c_dir,c_tfm,c_lmem,c_bit
            fdb     c_ldq

; ----------------------------------------------------------------------
;  Instructions
; ----------------------------------------------------------------------

c_inh:      lda     opcode
            jmp     emitop

; #immediate only (ANDCC, ORCC, CWAI)
c_imm:      ldx     optr
            lda     ,x+
            cmpa    #'#
            lbne    err_mode
            jsr     expr
            stb     ival+1
            lda     opcode
            jsr     emitop
            ldb     #1
            jsr     relfld
            lda     ival+1
            jmp     emitb

; The memory-reference group
c_gen:      ldx     optr
            clr     indir
            clr     force
            lda     ,x
            cmpa    #'#
            lbeq    g_imm
            cmpa    #'[
            lbeq    g_ind
            jsr     hascomma
            lbcs    g_idx
            lda     opclass         ; direct or extended
            cmpa    #C_LEA
            lbeq    err_mode
            jsr     getforce
            jsr     expr
            std     ival
            lda     force
            cmpa    #'<
            beq     g_dir
            cmpa    #'>
            beq     g_ext
            tst     cursect         ; in a section never, as lwasm
            bne     g_ext
            tst     eknown          ; direct only when known now,
            beq     g_ext           ; absolute and on page 0 (DP is
            tst     ekind           ; taken as 0)
            bne     g_ext
            lda     ival
            bne     g_ext
g_dir:      lda     opcode
            ldb     opclass
            cmpb    #C_MEM
            beq     gd1
            adda    #$10
gd1:        jsr     emitop
            ldb     #1
            jsr     relfld
            lda     ival+1
            jmp     emitb
g_ext:      lda     opcode
            adda    #$30
            ldb     opclass
            cmpb    #C_MEM
            bne     ge1
            adda    #$40
ge1:        jsr     emitop
            ldb     #2
            jsr     relfld
            ldd     ival
            jmp     emitw
g_imm:      lda     opclass
            cmpa    #C_STORE
            lbhs    err_mode
            leax    1,x
            jsr     expr
            std     ival
            lda     opcode
            jsr     emitop
            lda     opclass
            cmpa    #C_GEN16
            beq     gi16
            ldb     #1
            jsr     relfld
            lda     ival+1
            jmp     emitb
gi16:       ldb     #2
            jsr     relfld
            ldd     ival
            jmp     emitw

; [ ... ]: indirect indexed, or [address]
g_ind:      leax    1,x
            inc     indir
            jsr     hascomma
            lbcs    g_idx
            jsr     expr
            std     ival
            jsr     closebr
            jsr     idxop
            jsr     emitop
            lda     #$9F
            jsr     emitb
            ldb     #2
            jsr     relfld
            ldd     ival
            jmp     emitw

; Indexed, X at the operand (after any '[')
g_idx:      lda     ,x
            cmpa    #',
            lbeq    gx_noff
            ldb     1,x             ; A, B or D as the offset?
            cmpb    #',
            bne     gx_off
            jsr     upper
            ldb     #$86
            cmpa    #'A
            beq     gx_acc
            ldb     #$85
            cmpa    #'B
            beq     gx_acc
            ldb     #$8B
            cmpa    #'D
            beq     gx_acc
            ldb     #$87            ; 6309: E, F, W
            cmpa    #'E
            beq     gx_acc
            ldb     #$8A
            cmpa    #'F
            beq     gx_acc
            ldb     #$8E
            cmpa    #'W
            bne     gx_off
gx_acc:     stb     postb
            leax    2,x
            jsr     idxreg
            cmpb    #4
            lbhs    err_mode
            jsr     regbits
            orb     postb
            stb     postb
            jsr     closebr
            lbra    gx_post

gx_off:     jsr     getforce        ; offset,R
            clr     lit0            ; "0," written as such
            lda     ,x
            cmpa    #'0
            bne     gxo1
            lda     1,x
            cmpa    #',
            bne     gxo1
            inc     lit0
gxo1:       jsr     expr
            std     ival
            lda     ,x+
            cmpa    #',
            lbne    err_syntax
            jsr     idxreg
            cmpb    #4
            lbeq    gx_pcr
            lbhi    gx_w
            jsr     regbits
            stb     postb
            jsr     closebr
            lda     force
            cmpa    #'<
            beq     gx_8
            cmpa    #'>
            beq     gx_16
            tst     eknown
            beq     gx_16
            tst     ekind
            bne     gx_16
            ldd     ival
            bne     gxo2            ; a symbol that is 0: ,R
            tst     lit0
            bne     gxo2
            lda     #$84
            jmp     gx_mode
gxo2:       tst     indir
            bne     gx_t8
            cmpd    #-16            ; 5 bits: -16..15, not indirect
            blt     gx_t8
            cmpd    #15
            bgt     gx_t8
            andb    #$1F
            orb     postb
            stb     postb
            lbra    gx_post
gx_t8:      cmpd    #-128
            blt     gx_16
            cmpd    #127
            bgt     gx_16
gx_8:       lda     #$88
            jsr     gx_mode
            ldb     #1
            jsr     relfld
            lda     ival+1
            jmp     emitb
gx_16:      lda     #$89
            jsr     gx_mode
            ldb     #2
            jsr     relfld
            ldd     ival
            jmp     emitw

; ,R  ,R+  ,R++  ,-R  ,--R
gx_noff:    leax    1,x
            lda     ,x
            cmpa    #'-
            bne     gn2
            leax    1,x
            lda     ,x
            cmpa    #'-
            bne     gn1
            leax    1,x
            lda     #$83
            bra     gn5
gn1:        tst     indir
            lbne    err_mode
            lda     #$82
gn5:        sta     postb
            jsr     idxreg
            cmpb    #4
            lbeq    err_mode
            bhi     gnw1
            jsr     regbits
            orb     postb
            stb     postb
            jsr     closebr
            lbra    gx_post
gn2:        jsr     idxreg
            cmpb    #4
            lbeq    err_mode
            bhi     gnw2
            jsr     regbits
            stb     postb
            lda     ,x
            cmpa    #'+
            bne     gn4
            leax    1,x
            lda     ,x
            cmpa    #'+
            bne     gn3
            leax    1,x
            lda     #$81
            bra     gn6
gn3:        tst     indir
            lbne    err_mode
            lda     #$80
            bra     gn6
gn4:        lda     #$84
gn6:        ora     postb
            sta     postb
            jsr     closebr
gx_post:    clra                    ; postb as it is
            jmp     gx_mode

; 6309 W: ,--W  ,W  ,W++  n,W (16 bits, or ,W when known to be 0).  The
; indirect postbyte is one more.
gnw1:       lda     postb
            cmpa    #$83
            lbne    err_mode
            lda     #$EF
            bra     gw_emit
gnw2:       lda     ,x
            cmpa    #'+
            bne     gnw3
            leax    1,x
            lda     ,x+
            cmpa    #'+
            lbne    err_mode
            lda     #$CF
            bra     gw_emit
gnw3:       lda     #$8F
gw_emit:    pshs    a
            jsr     closebr
            puls    a
gw_e1:      tst     indir
            beq     gw_e2
            inca
gw_e2:      sta     postb
            jsr     idxop
            jsr     emitop
            lda     postb
            jmp     emitb
gx_w:       jsr     closebr
            lda     force
            cmpa    #'<
            lbeq    err_mode
            cmpa    #'>
            beq     gw16
            tst     eknown
            beq     gw16
            tst     ekind
            bne     gw16
            ldd     ival
            bne     gw16
            lda     #$8F
            bra     gw_e1
gw16:       lda     #$AF
            bsr     gw_e1
            ldb     #2
            jsr     relfld
            ldd     ival
            jmp     emitw

; offset,PCR: the offset counts from the end of the instruction
gx_pcr:     clr     postb
            jsr     closebr
            jsr     oplen           ; B = opcode bytes
            clra
            addd    pc
            std     tmp             ; the address of the postbyte
            jsr     pcrchk
            lda     force
            cmpa    #'<
            beq     gp8
            cmpa    #'>
            beq     gp16
            tst     pcrel           ; for the linker: 16 bits
            bne     gp16
            tst     eknown
            beq     gp16
            ldd     ival
            subd    tmp
            subd    #2
            cmpd    #-128
            blt     gp16
            cmpd    #127
            bgt     gp16
gp8:        ldd     tmp
            addd    #2
            jsr     pcrfix
            ldd     ival
            subd    tmp
            subd    #2
            stb     ival+1
            lda     #$8C
            jsr     gx_mode
            ldb     #1
            jsr     relfld
            lda     ival+1
            jmp     emitb
gp16:       ldd     tmp
            addd    #3
            jsr     pcrfix
            ldd     ival
            subd    tmp
            subd    #3
            std     ival
            lda     #$8D
            jsr     gx_mode
            ldb     #2
            jsr     relfld
            ldd     ival
            jmp     emitw

; Emit the indexed opcode and the postbyte: postb | A, plus $10 when
; indirect
gx_mode:    ora     postb
            tst     indir
            beq     gm1
            ora     #$10
gm1:        sta     postb
            jsr     idxop
            jsr     emitop
            lda     postb
            jmp     emitb

; The indexed opcode -> A
idxop:      lda     opcode
            ldb     opclass
            cmpb    #C_LEA
            beq     ix9
            adda    #$20
            cmpb    #C_MEM
            bne     ix9
            adda    #$40
ix9:        rts

; Opcode length (1, or 2 with a page byte) -> B
oplen:      ldb     #1
            tst     oppage
            beq     ol1
            incb
ol1:        tst     lmflag
            beq     ol9
            incb
ol9:        rts

; Index register at X -> B: 0 X, 1 Y, 2 U, 3 S, 4 PC / PCR
idxreg:     jsr     regtok
            ldu     #idxregs
            jsr     regfind
            lbcs    err_reg
            tfr     a,b
            rts

; B = 0..3 -> the register bits of a postbyte
regbits:    lslb
            lslb
            lslb
            lslb
            lslb
            rts

; With [, the closing ]
closebr:    tst     indir
            beq     cb9
            lda     ,x+
            cmpa    #']
            lbne    err_syntax
cb9:        rts

; A '<' or '>' at X -> force, X past it
getforce:   lda     ,x
            cmpa    #'<
            beq     gf_1
            cmpa    #'>
            bne     gf_9
gf_1:       sta     force
            leax    1,x
gf_9:       rts

; Carry set if the operand at X has a ',' before its end (space, NUL
; or ']').  Keeps X.
hascomma:   pshs    x
hc1:        lda     ,x+
            beq     hc8
            cmpa    #$20
            beq     hc8
            cmpa    #9
            beq     hc8
            cmpa    #']
            beq     hc8
            cmpa    #$27            ; 'c is a character, whatever it is
            bne     hc2
            tst     ,x+
            beq     hc8
            bra     hc1
hc2:        cmpa    #',
            bne     hc1
            orcc    #$01
            puls    x,pc
hc8:        andcc   #$FE
            puls    x,pc

c_rel8:     ldx     optr
            jsr     expr
            std     ival
            jsr     pcrchk
            lda     opcode
            jsr     emitop
            tst     pcrel           ; another section: the linker's
            beq     r8_0
            ldd     pc
            addd    #1
            jsr     pcrfix
            ldb     #1
            jsr     relfld
            bra     r8_1
r8_0:       lda     pass
            cmpa    #1
            beq     r8_1            ; pass 1: any byte will do
            ldd     ival            ; from the end of the instruction
            subd    pc
            subd    #1
            cmpd    #-128
            blt     r8_2
            cmpd    #127
            bgt     r8_2
            tfr     b,a
r8_1:       jmp     emitb
r8_2:       ldx     #msg_range      ; say so, and keep the size
            jsr     report
            bra     r8_1

c_rel16:    ldx     optr
            jsr     expr
            std     ival
            jsr     pcrchk
            lda     opcode
            jsr     emitop
            ldd     pc
            addd    #2
            jsr     pcrfix
            ldb     #2
            jsr     relfld
            ldd     ival
            subd    pc
            subd    #2
            jmp     emitw

; PSHS / PULS / PSHU / PULU: a register list
c_psh:      ldx     optr
            clr     postb
ps_1:       jsr     regtok
            ldu     #pshregs
            jsr     regfind
            lbcs    err_reg
            cmpa    #$40            ; S or U: the other stack
            bne     ps_3
            ldb     opcode
            andb    #$02            ; PSHU / PULU take S
            bne     ps_2
            ldb     regname
            cmpb    #'U
            lbne    err_reg
            bra     ps_3
ps_2:       ldb     regname
            cmpb    #'S
            lbne    err_reg
ps_3:       ora     postb
            sta     postb
            lda     ,x
            cmpa    #',
            bne     ps_9
            leax    1,x
            bra     ps_1
ps_9:       lda     opcode
            jsr     emitop
            lda     postb
            jmp     emitb

; TFR / EXG r1,r2
c_tfr:      ldx     optr
            jsr     regtok
            ldu     #tfrregs
            jsr     regfind
            lbcs    err_reg
            lsla
            lsla
            lsla
            lsla
            sta     postb
            lda     ,x+
            cmpa    #',
            lbne    err_syntax
            jsr     regtok
            ldu     #tfrregs
            jsr     regfind
            lbcs    err_reg
            ora     postb
            sta     postb
            lda     opcode
            jsr     emitop
            lda     postb
            jmp     emitb

; Register name at X -> regname (upper case, up to 3 letters)
regtok:     ldu     #regname
            clrb
            lda     ,x              ; the 6309 zero register
            cmpa    #'0
            bne     rt1
            sta     ,u+
            leax    1,x
            bra     rt9
rt1:        lda     ,x
            jsr     upper
            cmpa    #'A
            blo     rt9
            cmpa    #'Z
            bhi     rt9
            leax    1,x
            cmpb    #3
            bhs     rt1
            sta     ,u+
            incb
            bra     rt1
rt9:        clr     ,u+
            clr     ,u+
            clr     ,u
            rts

; regname in the table at U (3 characters, NUL-padded, then the value;
; 0 ends it) -> A, carry set if it isn't there
regfind:    lda     ,u
            beq     rf8
            ldd     ,u
            cmpd    regname
            bne     rf1
            lda     2,u
            cmpa    regname+2
            bne     rf1
            lda     3,u
            andcc   #$FE
            rts
rf1:        leau    4,u
            bra     regfind
rf8:        orcc    #$01
            rts

idxregs:    fcc     "X"
            fcb     0,0,0
            fcc     "Y"
            fcb     0,0,1
            fcc     "U"
            fcb     0,0,2
            fcc     "S"
            fcb     0,0,3
            fcc     "PCR"
            fcb     4
            fcc     "PC"
            fcb     0,4
            fcc     "W"
            fcb     0,0,5
            fcb     0
pshregs:    fcc     "CC"
            fcb     0,$01
            fcc     "A"
            fcb     0,0,$02
            fcc     "B"
            fcb     0,0,$04
            fcc     "DP"
            fcb     0,$08
            fcc     "X"
            fcb     0,0,$10
            fcc     "Y"
            fcb     0,0,$20
            fcc     "U"
            fcb     0,0,$40
            fcc     "S"
            fcb     0,0,$40
            fcc     "PC"
            fcb     0,$80
            fcc     "D"
            fcb     0,0,$06
            fcb     0
tfrregs:    fcc     "D"
            fcb     0,0,0
            fcc     "X"
            fcb     0,0,1
            fcc     "Y"
            fcb     0,0,2
            fcc     "U"
            fcb     0,0,3
            fcc     "S"
            fcb     0,0,4
            fcc     "PC"
            fcb     0,5
            fcc     "A"
            fcb     0,0,8
            fcc     "B"
            fcb     0,0,9
            fcc     "CC"
            fcb     0,$0A
            fcc     "DP"
            fcb     0,$0B
            fcc     "W"             ; 6309
            fcb     0,0,6
            fcc     "V"
            fcb     0,0,7
            fcc     "0"
            fcb     0,0,$0C
            fcc     "E"
            fcb     0,0,$0E
            fcc     "F"
            fcb     0,0,$0F
            fcb     0
bitregs:    fcc     "CC"
            fcb     0,0
            fcc     "A"
            fcb     0,0,1
            fcc     "B"
            fcb     0,0,2
            fcb     0

; 6309 TFM r0+,r1+  r0-,r1-  r0+,r1  r0,r1+ (r: D X Y U S)
c_tfm:      ldx     optr
            bsr     tfmreg
            lsla
            lsla
            lsla
            lsla
            sta     postb
            stb     tmp2            ; 0 none, 1 '+', 2 '-'
            lda     ,x+
            cmpa    #',
            lbne    err_syntax
            bsr     tfmreg
            ora     postb
            sta     postb
            lda     tmp2
            cmpa    #1
            bne     tm2
            cmpb    #1              ; r0+,r1+
            beq     tm8
            tstb                    ; r0+,r1
            lbne    err_mode
            lda     #2
            bra     tm9
tm2:        cmpa    #2
            bne     tm3
            cmpb    #2              ; r0-,r1-
            lbne    err_mode
            lda     #1
            bra     tm9
tm3:        cmpb    #1              ; r0,r1+
            lbne    err_mode
            lda     #3
            bra     tm9
tm8:        clra
tm9:        adda    opcode
            jsr     emitop
            lda     postb
            jmp     emitb
; Register at X -> A (0-4), B = 1 after it '+', 2 '-', else 0
tfmreg:     lda     ,x+
            jsr     upper
            ldu     #tfmregs
            clrb
tr1:        cmpa    b,u
            beq     tr2
            incb
            cmpb    #5
            blo     tr1
            jmp     err_reg
tr2:        tfr     b,a
            clrb
            pshs    a
            lda     ,x
            cmpa    #'+
            bne     tr3
            incb
            leax    1,x
            puls    a,pc
tr3:        cmpa    #'-
            bne     tr4
            ldb     #2
            leax    1,x
tr4:        puls    a,pc
tfmregs:    fcc     "DXYUS"

; 6309 OIM / AIM / EIM / TIM [#]imm,addr (or ;addr): the immediate byte
; follows the opcode, then the memory operand as for C_MEM
c_lmem:     ldx     optr
            lda     ,x
            cmpa    #'#
            bne     lm1
            leax    1,x
lm1:        jsr     expr
            stb     lmimm
            tst     ekind
            lbne    err_reloc
            lda     ,x+
            cmpa    #',
            beq     lm2
            cmpa    #';
            lbne    err_syntax
lm2:        stx     optr
            inc     lmflag
            lda     #C_MEM
            sta     opclass
            jmp     c_gen

; 6309 BAND / ... / LDBT / STBT reg,bit,bit,addr (reg CC, A or B; addr
; direct, '<' allowed)
c_bit:      ldx     optr
            jsr     regtok
            ldu     #bitregs
            jsr     regfind
            lbcs    err_reg
            lsla
            lsla
            lsla
            lsla
            lsla
            lsla
            sta     postb
            bsr     bitno
            lslb
            lslb
            lslb
            orb     postb
            stb     postb
            bsr     bitno
            orb     postb
            stb     postb
            lda     ,x+
            cmpa    #',
            lbne    err_syntax
            jsr     getforce
            jsr     expr
            std     ival
            lda     opcode
            jsr     emitop
            lda     postb
            jsr     emitb
            ldb     #1
            jsr     relfld
            lda     ival+1
            jmp     emitb
; ",n" with n 0-7 -> B
bitno:      lda     ,x+
            cmpa    #',
            lbne    err_syntax
            jsr     expr
            cmpd    #7
            lbhi    err_bitno
            rts

; 6309 LDQ: #imm is $CD and 32 bits; the rest as a 16-bit load on page
; $10 ($10DC ...)
c_ldq:      ldx     optr
            lda     ,x
            cmpa    #'#
            beq     lq1
            lda     #C_GEN16
            sta     opclass
            jmp     c_gen
lq1:        leax    1,x
            jsr     ex32
            clr     oppage
            lda     #$CD
            jsr     emitop
            ldd     q32
            jsr     emitw
            ldd     q32+2
            jmp     emitw

; A 32-bit immediate at X -> q32: a number ($hex, %binary, @octal or
; decimal, '-' allowed) on its own, else a 16-bit expression, extended
; with its sign if it starts with '-'
ex32:       ldd     #0
            std     q32
            std     q32+2
            clr     neg32
            pshs    x
            lda     ,x
            cmpa    #'-
            bne     x32a
            inc     neg32
            leax    1,x
x32a:       ldb     #10
            lda     ,x
            cmpa    #'$
            bne     x32b
            ldb     #16
x32b:       cmpa    #'%
            bne     x32c
            ldb     #2
x32c:       cmpa    #'@
            bne     x32d
            ldb     #8
x32d:       cmpb    #10
            beq     x32e
            leax    1,x
x32e:       stb     base
            clr     ndig
x32f:       lda     ,x              ; the digits
            jsr     upper
            suba    #'0
            blo     x32h
            cmpa    #9
            bls     x32g
            suba    #7
            cmpa    #10
            blo     x32h
x32g:       cmpa    base
            bhs     x32h
            bsr     q32dig
            inc     ndig
            leax    1,x
            bra     x32f
x32h:       tst     ndig            ; and nothing after them
            beq     x32x
            lda     ,x
            beq     x32i
            cmpa    #$20
            beq     x32i
            cmpa    #9
            bne     x32x
x32i:       leas    2,s
            tst     neg32
            beq     x32z
            com     q32             ; -q32
            com     q32+1
            com     q32+2
            com     q32+3
            ldd     q32+2
            addd    #1
            std     q32+2
            ldd     q32
            adcb    #0
            adca    #0
            std     q32
x32z:       rts
x32x:       puls    x               ; an expression
            jsr     expr
            tst     ekind
            lbne    err_reloc
            std     q32+2
            ldd     #0
            tst     neg32
            beq     x32y
            tst     q32+2
            bpl     x32y
            ldd     #$FFFF
x32y:       std     q32
            rts
; q32 = q32 * base + A
q32dig:     pshs    a,x
            ldx     q32             ; X:U = q32
            ldu     q32+2
            ldd     #0
            std     q32
            std     q32+2
            ldb     base
            stb     tmp2
qd1:        tfr     u,d             ; add it base times
            addd    q32+2
            std     q32+2
            tfr     x,d
            adcb    q32+1
            adca    q32
            std     q32
            dec     tmp2
            bne     qd1
            ldb     ,s
            clra
            addd    q32+2
            std     q32+2
            ldd     q32
            adcb    #0
            adca    #0
            std     q32
            puls    a,x,pc

; ----------------------------------------------------------------------
;  Directives
; ----------------------------------------------------------------------

D_EQU       equ     0
D_ORG       equ     1
D_FCB       equ     2
D_FDB       equ     3
D_FCC       equ     4
D_FCN       equ     5
D_FCS       equ     6
D_RMB       equ     7
D_END       equ     8
D_INCLUDE   equ     9
D_MACRO     equ     10
D_ENDM      equ     11
D_IFDEF     equ     12
D_IFNDEF    equ     13
D_ELSE      equ     14
D_ENDC      equ     15

c_dir:      ldb     opcode
            lslb
            ldx     #dirtab
            ldu     b,x
            ldx     optr
            jmp     ,u
dirtab:     fdb     d_equ,d_org,d_fcb,d_fdb,d_fcc,d_fcc,d_fcc,d_rmb
            fdb     d_end,d_include,d_macro,d_endm,d_if,d_if,d_else,d_endc
            fdb     d_sect,d_sect,d_endsect,d_endsect,d_export,d_export
            fdb     d_import,d_import,d_import

d_equ:      tst     haslab
            lbeq    err_nolabel
            jsr     expr
            pshs    d
            lda     ekind           ; absolute or in a section
            cmpa    #K_CPLX
            lbhs    err_reloc
            sta     nsect
            lda     #F_DEF
            tst     eknown
            beq     de1
            ora     #F_KNOWN
de1:        sta     nflags
            ldx     #labname
            ldu     #name
            jsr     strcpy
            puls    d
            jsr     lstat           ; the value in the address column
            jmp     deflabel

d_org:      tst     cursect
            lbne    err_insect
            jsr     expr
            tst     eknown
            lbeq    err_known
            std     pc
            jsr     lstat
            tst     haslab
            beq     do9
            jmp     labpc
do9:        rts

d_fcb:      jsr     expr
            pshs    b
            ldb     #1
            jsr     relfld
            puls    a
            jsr     emitb
            lda     ,x+
            cmpa    #',
            beq     d_fcb
            rts

d_fdb:      jsr     expr
            pshs    b
            ldb     #2
            jsr     relfld
            puls    b
            jsr     emitw
            lda     ,x+
            cmpa    #',
            beq     d_fdb
            rts

; FCC, FCN, FCS: a string between two of the same character
d_fcc:      lda     ,x+
            lbeq    err_syntax
            sta     delim
            clr     havec
dc1:        lda     ,x+
            lbeq    err_syntax
            cmpa    delim
            beq     dc5
            tst     havec           ; the one before goes out now
            beq     dc2
            pshs    a
            lda     lastc
            jsr     emitb
            puls    a
dc2:        sta     lastc
            inc     havec
            bra     dc1
dc5:        tst     havec
            beq     dc6
            lda     lastc
            ldb     opcode
            cmpb    #D_FCS
            bne     dc5a
            ora     #$80            ; FCS: bit 7 on the last one
dc5a:       jsr     emitb
dc6:        ldb     opcode
            cmpb    #D_FCN
            bne     dc9
            clra
            jmp     emitb
dc9:        rts

d_rmb:      jsr     expr
            tst     eknown
            lbeq    err_known
            tst     ekind
            lbne    err_known
            pshs    d
            ldd     pc
            jsr     lstat
            puls    d
            addd    pc
            std     pc
            rts

d_end:      lda     ,x
            beq     den1
            cmpa    #';
            beq     den1
            jsr     expr
            std     entry
den1:       inc     endflag
            rts

; INCLUDE "file" (or file): read it there, from the cache on pass 2
d_include:  lda     ,x
            cmpa    #'"
            bne     di1
            leax    1,x
di1:        ldu     #fpath          ; the directory of the source first
            ldy     #dirpfx
            lda     ,x
            cmpa    #'/
            bne     di2
            ldy     #zero2
di2:        lda     ,y+
            beq     di3
            sta     ,u+
            bra     di2
di3:        lda     ,x+
            beq     di4
            cmpa    #'"
            beq     di4
            cmpa    #$20
            beq     di4
            cmpa    #9
            beq     di4
            cmpu    #fpath+INCSZ-4
            bhs     di3
            sta     ,u+
            bra     di3
di4:        clr     ,u
            ldx     #fpath
            jsr     getfile
            jmp     pushfile

; name MACRO ... ENDM
d_macro:    tst     haslab
            lbeq    err_nolabel
            inc     mdef
            lda     pass
            cmpa    #1
            bne     dmc9
            ldx     #labname
            ldu     #name
            jsr     strcpy
            jsr     findsym
            beq     dmc0
            ldx     #msg_dup        ; the body is skipped
            jmp     report
dmc0:       lda     #F_DEF|F_MAC
            sta     nflags
            ldd     #0
            jsr     addsym          ; X -> the entry, its page mapped
            lda     hpage           ; the body starts at the heap
            ldu     hptr
            cmpu    #WINEND
            blo     dmc1
            inca
            ldu     #WIN
            cmpa    #SYMEND
            lbhs    fat_mem
            sta     hpage
            stu     hptr
dmc1:       sta     S_AUX,x
            stu     S_VAL,x
dmc9:       rts

d_endm:     jmp     err_endm

; IFDEF / IFNDEF symbol
d_if:       ldu     #name
            jsr     getsym
            lbeq    err_syntax
            clr     tmp2            ; tmp2 = defined
            jsr     findsym
            beq     dif2
            lda     S_FLG,x
            bita    #F_DEF
            beq     dif2
            lda     pass
            cmpa    #1
            beq     dif1
            ldd     S_SEQ,x         ; pass 2: only if it was before here
            cmpd    seq
            bhi     dif2
dif1:       inc     tmp2
dif2:       inc     ifdepth
            lda     tmp2
            ldb     opcode
            cmpb    #D_IFNDEF
            bne     dif3
            eora    #1
dif3:       tsta
            bne     dif9
            inc     skipping        ; false: skip to ELSE or ENDC
            clr     skipnest
dif9:       rts

d_else:     tst     ifdepth
            lbeq    err_noif
            inc     skipping
            clr     skipnest
            rts

d_endc:     tst     ifdepth
            lbeq    err_noif
            dec     ifdepth
            rts


; ----------------------------------------------------------------------
;  Sections and object files (lwasm's LWOBJ16, for lwlink or LINK)
; ----------------------------------------------------------------------

; SECTION name[,bss|,!bss]
d_sect:     ldu     #secname
            clrb
ds1:        lda     ,x
            beq     ds2
            cmpa    #$20
            beq     ds2
            cmpa    #9
            beq     ds2
            cmpa    #',
            beq     ds2
            leax    1,x
            cmpb    #15
            bhs     ds1
            sta     ,u+
            incb
            bra     ds1
ds2:        clr     ,u
            tstb
            lbeq    err_syntax
            clr     tmp2            ; 1 bss, 2 !bss
            lda     ,x
            cmpa    #',
            bne     ds3
            leax    1,x
            lda     ,x
            cmpa    #'!
            bne     ds2a
            inc     tmp2
            leax    1,x
ds2a:       ldy     #s_bss          ; "bss"
            ldb     #3
ds2b:       lda     ,x+
            jsr     upper
            cmpa    ,y+
            lbne    err_syntax
            decb
            bne     ds2b
            inc     tmp2
ds3:        lda     nsects          ; known?
            beq     ds5
ds4:        jsr     secent
            ldu     #secname
            pshs    a
            jsr     strcmpx
            puls    a
            beq     ds8
            deca
            bne     ds4
ds5:        lda     nsects          ; a new one
            cmpa    #MAXSECT
            lbhs    fat_sects
            inca
            sta     nsects
            ldb     #1
            stb     objmode
            jsr     secent
            pshs    a,x
            ldu     #SECSZ          ; all 0
ds6:        clr     ,x+
            leau    -1,u
            cmpu    #0
            bne     ds6
            ldx     1,s
            tfr     x,u
            ldx     #secname
            jsr     strcpy
            ldb     tmp2            ; bss: asked for, or named so
            cmpb    #1
            beq     ds7
            cmpb    #2
            beq     ds7a
            ldy     #secname
            ldx     #s_bss
            jsr     strcmpi
            beq     ds7
            ldx     #s_dbss
            jsr     strcmpi
            bne     ds7a
ds7:        ldx     1,s
            ldb     #1
            stb     SC_FLG,x
ds7a:       puls    a,x
ds8:        jsr     setsect
            tst     haslab
            beq     ds9
            jmp     labpc
ds9:        rts

d_endsect:  clra
            jmp     setsect

; EXPORT sym[,sym...], or sym EXPORT
d_export:   lda     #1
            bra     dx0
; IMPORT / EXTERN / EXTERNAL sym[,sym...], or sym IMPORT
d_import:   clra
dx0:        sta     tmp2
            lda     pass
            cmpa    #1
            bne     dx9
            sta     objmode
            tst     haslab
            beq     dx2
            ldx     #labname
            ldu     #name
            jsr     strcpy
            bra     dx1
dx2:        ldu     #name
            jsr     getsym
            lbeq    err_syntax
dx1:        pshs    x
            jsr     findsym
            bne     dx4
            ldd     #0              ; new: exported, or imported
            tst     tmp2
            beq     dx3
            lda     #F_EXP
            sta     nflags
            clr     nsect
            jsr     addsym
            bra     dx8
dx3:        lda     #F_DEF
            sta     nflags
            lda     #K_IMP
            sta     nsect
            jsr     addsym
            bra     dx8
dx4:        lda     S_FLG,x         ; already there
            tst     tmp2
            beq     dx5
            ora     #F_EXP
            sta     S_FLG,x
            bra     dx8
dx5:        bita    #F_DEF
            beq     dx6
            ldb     S_AUX,x
            cmpb    #K_IMP
            beq     dx8
            ldx     #msg_dup
            jsr     report
            bra     dx8
dx6:        ora     #F_DEF
            sta     S_FLG,x
            lda     #K_IMP
            sta     S_AUX,x
dx8:        puls    x
            tst     haslab
            bne     dx9
            lda     ,x+
            cmpa    #',
            beq     dx2
dx9:        rts

; Change to section A (0: none).  The one left keeps its pc and size.
; Keeps X.
setsect:    pshs    a,x
            lda     cursect
            beq     sts1
            jsr     secent
            ldd     pc
            std     SC_PC,x
            cmpd    SC_SIZE,x
            bls     sts2
            std     SC_SIZE,x
            bra     sts2
sts1:       ldd     pc
            std     abspc
sts2:       lda     ,s
            sta     cursect
            beq     sts3
            jsr     secent
            ldd     SC_PC,x
            std     pc
            ldd     SC_BASE,x
            std     curbase
            puls    a,x,pc
sts3:       ldd     abspc
            std     pc
            ldd     #0
            std     curbase
            puls    a,x,pc

; Section A (1..) -> X.  Keeps D.
secent:     pshs    d
            deca
            ldb     #SECSZ
            mul
            addd    #sectab
            tfr     d,x
            puls    d,pc

; After pass 1: each section's place in the image, one after the other
secbases:   ldd     #0
            std     objsize
            ldx     #sectab
            ldb     nsects
            beq     sb_9
sb_1:       pshs    b
            ldd     objsize
            std     SC_BASE,x
            addd    SC_SIZE,x
            std     objsize
            puls    b
            leax    SECSZ,x
            decb
            bne     sb_1
sb_9:       rts

; pcrel = 1 if the value (ekind) is relative to something other than this
; line's section, so the linker has to make the offset
pcrchk:     pshs    a
            clr     pcrel
            lda     cursect
            beq     pcc9
            cmpa    ekind
            beq     pcc9
            inc     pcrel
pcc9:       puls    a,pc

; A PC-relative field ending at D: with pcrel, the expression becomes
; value - (section + D) for the linker; without, the offset is ours
pcrfix:     tst     pcrel
            bne     pcf1
            clr     ekind
            rts
pcf1:       pshs    d,x
            lda     #K_CPLX
            sta     ekind
            tst     rpnon
            beq     pcf9
            lda     cursect
            jsr     secent
            ldd     ,s
            jsr     rpnsec
            jsr     rpnsub
pcf9:       puls    d,x,pc

; Kinds of the operands: a stack of the left ones
kpush:      pshs    a,x
            ldx     ksp
            cmpx    #kstk+KSTSZ
            lbhs    err_syntax
            lda     ekind
            sta     ,x+
            stx     ksp
            puls    a,x,pc
kpop:       ldx     ksp             ; -> A
            lda     ,-x
            stx     ksp
            rts
; left + right
kc_add:     pshs    d,x
            bsr     kpop
            tsta
            beq     kc9             ; abs + R = R
            tst     ekind
            beq     kc8             ; L + abs = L
            bra     kc7
; left - right
kc_sub:     pshs    d,x
            bsr     kpop
            tst     ekind
            beq     kc8             ; L - abs = L
            cmpa    ekind
            bne     kc7
            cmpa    #K_CPLX         ; the same section: absolute
            bhs     kc7
            clra
            bra     kc8
; any other operator
kc_oth:     pshs    d,x
            bsr     kpop
            ora     ekind
            beq     kc8
kc7:        lda     #K_CPLX
kc8:        sta     ekind
kc9:        puls    d,x,pc
; unary
kc_un:      tst     ekind
            beq     kcu9
            pshs    a
            lda     #K_CPLX
            sta     ekind
            puls    a
kcu9:       rts

; RPN for the linker, built while pass 2 of an object evaluates.  These
; keep every register.
; A -> rpnbuf
rput:       pshs    b,x
            ldb     rpnlen
            cmpb    #RPNSZ
            bhs     rpu8
            ldx     #rpnbuf
            abx
            sta     ,x
            inc     rpnlen
            puls    b,x,pc
rpu8:       inc     rpnovf
            puls    b,x,pc
; The value D of kind ekind
rpnleaf:    tst     rpnon
            beq     rlf9
            pshs    d,x
            lda     ekind
            beq     rlf1
            cmpa    #K_IMP
            beq     rlf2
            jsr     secent          ; section + offset
            ldd     ,s
            jsr     rpnsec
            bra     rlf8
rlf1:        ldd     ,s
            jsr     rpnint
            bra     rlf8
rlf2:        jsr     rpnimp
rlf8:        puls    d,x
rlf9:        rts
; The number D
rpnint:     tst     rpnon
            beq     ri9
            pshs    a
            lda     #1
            jsr     rput
            lda     ,s
            jsr     rput
            tfr     b,a
            jsr     rput
            puls    a
ri9:        rts
; The imported symbol in name
rpnimp:     pshs    a,x
            lda     #2
            jsr     rput
            ldx     #name
rim1:       lda     ,x+
            jsr     rput
            tsta
            bne     rim1
            puls    a,x,pc
; Section X (its base symbol, "\2name") + D
rpnsec:     pshs    d,x
            lda     #3
            jsr     rput
            lda     #2
            jsr     rput
rs1:        lda     ,x+
            jsr     rput
            tsta
            bne     rs1
            ldd     ,s
            jsr     rpnint
            jsr     rpnop
            fcb     1
            puls    d,x,pc
; Operator: the byte after the JSR
rpnop:      pshs    d,x
            ldx     4,s
            ldb     ,x+
            stx     4,s
            tst     rpnon
            beq     rop9
            lda     #4
            jsr     rput
            tfr     b,a
            jsr     rput
rop9:       puls    d,x,pc
; Negate (* -1)
rpnneg:     pshs    d
            ldd     #$FFFF
            jsr     rpnint
            jsr     rpnop
            fcb     3
            puls    d,pc
; Subtract: + (-right)
rpnsub:     jsr     rpnneg
            jsr     rpnop
            fcb     1
            rts

; A field of B bytes (1 or 2) at pc: in a section of an object, when
; the expression isn't absolute, a relocation for the linker.  Keeps
; every register.
relfld:     pshs    d,x,y,u
            tst     rpnon
            beq     rfl9
            tst     cursect
            beq     rfl9
            tst     ekind
            beq     rfl9
            tst     rpnovf
            beq     rfl1
            ldx     #msg_cplx
            jsr     report
            bra     rfl9
rfl1:        lda     cursect
            jsr     secent
            tfr     x,y             ; Y -> the section
            ldb     rpnlen
            addb    #7
            jsr     ralloc          ; X -> the record, mapped
            lda     SC_RH,y         ; next (page, address)
            sta     ,x
            ldd     SC_RH+1,y
            std     1,x
            lda     1,s             ; size, offset, length, the RPN
            sta     3,x
            ldd     pc
            std     4,x
            ldb     rpnlen
            stb     6,x
            leau    7,x
            pshs    x
            ldx     #rpnbuf
rfl2:        lda     ,x+
            sta     ,u+
            decb
            bne     rfl2
            puls    x
            lda     curbank         ; first in the section's list
            sta     SC_RH,y
            stx     SC_RH+1,y
rfl9:        puls    d,x,y,u,pc

; B bytes for a relocation -> X (mapped): from the last page down, as far
; as the source cache.  A record never crosses into the next page.
ralloc:     pshs    b
            clra
            addd    rptr
            cmpd    #WINEND
            bls     ra1
            lda     rpage
            deca
            cmpa    cpage
            lbls    fat_mem
            sta     rpage
            ldd     #WIN
            std     rptr
            ldb     ,s
            clra
            addd    rptr
ra1:        ldx     rptr
            std     rptr
            ldb     rpage
            jsr     setbank
            puls    b,pc

; Every exported symbol defined?
chkexp:     ldy     #symtab
ce1:        lda     ,y
            ldu     1,y
ce2:        cmpu    #0
            beq     ce8
            tfr     a,b
            jsr     setbank
            lda     S_FLG,u
            anda    #F_EXP|F_DEF|F_MAC
            cmpa    #F_EXP
            bne     ce3
            ldx     #msg_noexp      ; "Undefined export: NAME"
            jsr     puts
            leax    S_NAME,u
            jsr     puts
            jsr     crlf
            ldd     errors
            addd    #1
            std     errors
ce3:        lda     ,u
            ldu     1,u
            bra     ce2
ce8:        leay    3,y
            cmpy    #symtab+768
            blo     ce1
            rts

; Write objname: "LWOBJ16" 0, then each section (the last made first, as
; lwasm does), then 0
writeobj:   ldx     #objname
            jsr     fcreate
            ldx     #s_lwobj
            jsr     lputs
            clra
            jsr     lput
            lda     nsects
            sta     wsec
wo1:        lda     wsec
            lbeq    wo9
            jsr     secent
            stx     wsp
            jsr     lputs           ; name
            clra
            jsr     lput
            lda     SC_FLG,x        ; flags
            beq     wo2
            jsr     lput
wo2:        clra
            jsr     lput
            lda     #2              ; local symbols: "\2name" = 0
            jsr     lput
            jsr     lputs
            clra
            jsr     lput
            jsr     lput
            jsr     lput
            jsr     lput
            jsr     wexports        ; exports
            clra
            jsr     lput
            ldx     wsp             ; relocations
            lda     SC_RH,x
            ldu     SC_RH+1,x
wo3:        cmpu    #0
            beq     wo5
            tfr     a,b
            jsr     setbank
            lda     3,u
            cmpa    #1
            bne     wo4
            lda     #$FF            ; 8 bits
            jsr     lput
            lda     #1
            jsr     lput
wo4:        ldb     6,u
            leax    7,u
wo4a:       lda     ,x+
            jsr     lput
            decb
            bne     wo4a
            clra
            jsr     lput
            lda     4,u
            jsr     lput
            lda     5,u
            jsr     lput
            lda     ,u
            ldu     1,u
            bra     wo3
wo5:        clra
            jsr     lput
            ldx     wsp             ; the length and the bytes
            lda     SC_SIZE,x
            jsr     lput
            lda     SC_SIZE+1,x
            jsr     lput
            tst     SC_FLG,x
            bne     wo8
            ldd     SC_SIZE,x
            std     wleft
            ldd     SC_BASE,x
            std     waddr
wo6:        ldd     wleft
            beq     wo8
            ldd     waddr
            jsr     flpage
            lda     ,u
            jsr     lput
            ldd     waddr
            addd    #1
            std     waddr
            ldd     wleft
            subd    #1
            std     wleft
            bra     wo6
wo8:        dec     wsec
            jmp     wo1
wo9:        clra
            jsr     lput
            jmp     lstclose

; The exported symbols of section wsec: name, 0, value
wexports:   ldy     #symtab
we1:        lda     ,y
            ldu     1,y
we2:        cmpu    #0
            beq     we8
            tfr     a,b
            jsr     setbank
            lda     S_FLG,u
            anda    #F_EXP|F_DEF|F_MAC
            cmpa    #F_EXP|F_DEF
            bne     we3
            lda     S_AUX,u
            cmpa    wsec
            bne     we3
            leax    S_NAME,u
            jsr     lputs
            clra
            jsr     lput
            lda     S_VAL,u
            jsr     lput
            lda     S_VAL+1,u
            jsr     lput
we3:        lda     ,u
            ldu     1,u
            bra     we2
we8:        leay    3,y
            cmpy    #symtab+768
            blo     we1
            rts

; Compare the strings at Y and X, ignoring case: Z set if the same
strcmpi:    pshs    x,y
sci1:       lda     ,y+
            jsr     upper
            sta     tmp
            lda     ,x+
            jsr     upper
            cmpa    tmp
            bne     sci9
            tsta
            bne     sci1
sci9:       puls    x,y,pc

; ----------------------------------------------------------------------
;  Expressions: X -> text, -> D = value, X past it.  eknown = 0 if a
;  symbol in it isn't known yet (pass 1), or wasn't on pass 1.
;  Precedence as lwasm: * / %, then + -, then & | ^ (! is |).
; ----------------------------------------------------------------------

expr:       lda     #1
            sta     eknown
            ldd     #kstk
            std     ksp
            clr     rpnlen
            clr     rpnovf
            clr     ekind
exprb:      bsr     ex_add
ex1:        pshs    d
            lda     ,x
            cmpa    #'&
            beq     ex_and
            cmpa    #'|
            beq     ex_or
            cmpa    #'!
            beq     ex_or
            cmpa    #'^
            beq     ex_xor
            puls    d,pc
ex_and:     leax    1,x
            jsr     kpush
            bsr     ex_add
            jsr     kc_oth
            jsr     rpnop
            fcb     7
            anda    ,s
            andb    1,s
            leas    2,s
            bra     ex1
ex_or:      leax    1,x
            jsr     kpush
            bsr     ex_add
            jsr     kc_oth
            jsr     rpnop
            fcb     8
            ora     ,s
            orb     1,s
            leas    2,s
            bra     ex1
ex_xor:     leax    1,x
            jsr     kpush
            bsr     ex_add
            jsr     kc_oth
            jsr     rpnop
            fcb     9
            eora    ,s
            eorb    1,s
            leas    2,s
            bra     ex1

ex_add:     bsr     ex_mul
ea1:        pshs    d
            lda     ,x
            cmpa    #'+
            beq     ea_plus
            cmpa    #'-
            beq     ea_minus
            puls    d,pc
ea_plus:    leax    1,x
            jsr     kpush
            bsr     ex_mul
            jsr     kc_add
            jsr     rpnop
            fcb     1
            addd    ,s++
            bra     ea1
ea_minus:   leax    1,x
            jsr     kpush
            bsr     ex_mul
            jsr     kc_sub
            jsr     rpnsub
            pshs    d
            ldd     2,s
            subd    ,s++
            leas    2,s
            bra     ea1

ex_mul:     bsr     ex_un
em1:        pshs    d
            lda     ,x
            cmpa    #'*
            beq     em_mul
            cmpa    #'/
            beq     em_div
            cmpa    #'%
            beq     em_mod
            puls    d,pc
em_mul:     leax    1,x
            jsr     kpush
            bsr     ex_un
            jsr     kc_oth
            jsr     rpnop
            fcb     3
            std     mb
            puls    d
            std     ma
            jsr     mul16
            bra     em1
em_div:     leax    1,x
            jsr     kpush
            bsr     ex_un
            jsr     kc_oth
            jsr     rpnop
            fcb     4
            std     mb
            puls    d
            std     ma
            jsr     div16
            bra     em1
em_mod:     leax    1,x
            jsr     kpush
            bsr     ex_un
            jsr     kc_oth
            jsr     rpnop
            fcb     5
            std     mb
            puls    d
            std     ma
            jsr     div16
            ldd     mrem
            bra     em1

ex_un:      lda     ,x
            cmpa    #'-
            bne     eu1
            leax    1,x
            bsr     ex_un
            jsr     kc_un
            jsr     rpnneg
            coma
            comb
            addd    #1
            rts
eu1:        cmpa    #'+
            bne     eu2
            leax    1,x
            bra     ex_un
eu2:        cmpa    #'~
            bne     eu3
            leax    1,x
            bsr     ex_un
            jsr     kc_un
            jsr     rpnop
            fcb     $0D
            coma
            comb
            rts
eu3:        cmpa    #'(
            bne     primary
            leax    1,x
            jsr     exprb
            pshs    a               ; A is the value's high byte
            lda     ,x+
            cmpa    #')
            puls    a
            lbne    err_syntax
            rts

primary:    cmpa    #'$
            beq     p_hex
            cmpa    #'%
            beq     p_bin
            cmpa    #'@
            beq     p_oct
            cmpa    #$27            ; 'c
            beq     p_chr
            cmpa    #'*
            beq     p_pc
            cmpa    #'0
            blo     p_sym
            cmpa    #'9
            bls     p_dec
p_sym:      ldu     #name
            jsr     getsym
            lbeq    err_syntax
            jmp     symval
p_pc:       leax    1,x
            lda     cursect         ; in a section: relative to it
            sta     ekind
            ldd     pc
            jmp     rpnleaf
p_chr:      leax    1,x
            ldb     ,x
            lbeq    err_syntax
            leax    1,x
            clra
            pshs    d
            lda     ,x              ; an optional closing '
            cmpa    #$27
            bne     pc1
            leax    1,x
pc1:        puls    d
            bra     leafabs
p_hex:      ldb     #16
            bra     p_num1
p_bin:      ldb     #2
            bra     p_num1
p_oct:      ldb     #8
p_num1:     leax    1,x
            bra     p_num
p_dec:      ldb     #10
p_num:      stb     base
            ldd     #0
            std     num
            clr     ndig
pn1:        lda     ,x
            jsr     digval
            bcs     pn9
            cmpa    base
            bhs     pn9
            leax    1,x
            inc     ndig
            pshs    a
            ldd     num             ; num = num * base + digit
            std     ma
            ldb     base
            clra
            std     mb
            jsr     mul16
            addb    ,s+
            adca    #0
            std     num
            bra     pn1
pn9:        tst     ndig
            lbeq    err_syntax
            ldd     num
leafabs:    clr     ekind
            jmp     rpnleaf

; A = digit character -> A = its value, carry set if it isn't one
digval:     cmpa    #'0
            blo     dv8
            cmpa    #'9
            bhi     dv1
            suba    #'0
            andcc   #$FE
            rts
dv1:        jsr     upper
            cmpa    #'A
            blo     dv8
            cmpa    #'F
            bhi     dv8
            suba    #'A-10
            andcc   #$FE
            rts
dv8:        orcc    #$01
            rts

; The value of the symbol in name -> D
symval:     pshs    x
            jsr     findsym
            beq     sv8
            lda     S_FLG,x
            bita    #F_MAC
            bne     sv8
            bita    #F_DEF
            beq     sv8
            bita    #F_KNOWN
            beq     sv2
            ldb     pass
            cmpb    #1
            beq     sv3
            ldd     S_SEQ,x         ; pass 2: known on pass 1 only if
            cmpd    seq             ; defined before this line
            bls     sv3
sv2:        clr     eknown
sv3:        lda     S_AUX,x
            sta     ekind
            ldd     S_VAL,x
            jsr     rpnleaf
            puls    x,pc
sv8:        lda     pass
            cmpa    #1
            beq     sv9
            ldx     #msg_undef      ; pass 2: say so, and go on with 0
            jsr     report          ; sized as pass 1 did, a forward one
sv9:        clr     eknown
            clr     ekind
            ldd     #0
            jsr     rpnleaf
            puls    x,pc

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

; ma / mb -> D, remainder in mrem (unsigned)
div16:      ldd     mb
            lbeq    err_div0
            ldd     #0
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

; Symbol name at X -> U (NUL-terminated, up to NAMEMAX kept), X past it.
; Z set if there wasn't one.
getsym:     clrb
            lda     ,x
            bsr     symstart
            bcs     gs8
gs1:        lda     ,x
            bsr     symchar
            bcs     gs8
            leax    1,x
            cmpb    #NAMEMAX
            bhs     gs1
            sta     ,u+
            incb
            bra     gs1
gs8:        clr     ,u
            tstb
            rts

; Carry clear if A can start a symbol: a letter, _ . ?
symstart:   cmpa    #'_
            beq     sy9
            cmpa    #'.
            beq     sy9
            cmpa    #'?
            beq     sy9
            pshs    a
            jsr     upper
            cmpa    #'A
            blo     sy7
            cmpa    #'Z
            bhi     sy7
            puls    a
sy9:        andcc   #$FE
            rts
sy7:        puls    a
            orcc    #$01
            rts
; ... or continue one: also digits $ @
symchar:    cmpa    #'0
            blo     sc1
            cmpa    #'9
            bls     sy9
sc1:        cmpa    #'$
            beq     sy9
            cmpa    #'@
            beq     sy9
            bra     symstart

; ----------------------------------------------------------------------
;  Symbol table: 256 hash chains in symtab (page, address of the first
;  entry), the entries in the symbol pages.
; ----------------------------------------------------------------------

; Hash of the string at X -> B; X ends past its NUL
hashx:      clrb
hx1:        lda     ,x+
            beq     hx9
            lslb
            adcb    #0
            pshs    a
            eorb    ,s+
            bra     hx1
hx9:        rts

; Look up name -> X = entry with its page mapped, Z clear; Z set if it
; isn't there.  bucket -> its chain head, for addsym.
findsym:    ldx     #name
            bsr     hashx
            clra
            pshs    d               ; * 3
            lslb
            rola
            addd    ,s++
            addd    #symtab
            std     bucket
            tfr     d,u
            ldb     ,u              ; the first entry
            ldx     1,u
fs1:        beq     fs9             ; none left
            jsr     setbank
            leau    S_NAME,x
            ldy     #name
            jsr     strcmp
            beq     fs8
            ldb     ,x              ; the next
            ldx     1,x
            bra     fs1
fs8:        andcc   #$FB
fs9:        rts

; New symbol name, value D, flags nflags (after findsym said it isn't
; there) -> X = the entry, its page mapped
addsym:     std     dval
            ldx     #name           ; size: header and name
            clrb
as1:        incb
            tst     ,x+
            bne     as1
            addb    #S_NAME
            jsr     halloc          ; -> X, mapped
            ldu     bucket          ; link it in front
            lda     ,u
            sta     ,x
            ldd     1,u
            std     1,x
            lda     curbank
            sta     ,u
            stx     1,u
            ldd     dval
            std     S_VAL,x
            lda     nflags
            sta     S_FLG,x
            ldd     seq
            std     S_SEQ,x
            lda     nsect
            sta     S_AUX,x
            leau    S_NAME,x
            pshs    x
            ldx     #name
            jsr     strcpy
            puls    x,pc

; Define name = D (flags nflags).  Pass 1 makes it, pass 2 checks it.
deflabel:   std     dval
            jsr     findsym
            bne     dfl1
            ldd     dval
            jmp     addsym
dfl1:       lda     pass
            cmpa    #1
            bne     dfl1a
            lda     S_FLG,x
            bita    #F_DEF
            bne     dfl1b
            ora     nflags          ; named by EXPORT before: define it
            sta     S_FLG,x
            ldd     dval
            std     S_VAL,x
            ldd     seq
            std     S_SEQ,x
            lda     nsect
            sta     S_AUX,x
            rts
dfl1b:      ldx     #msg_dup        ; pass 1: say so, keep the first value
            jmp     report
dfl1a:      ldd     S_SEQ,x         ; pass 2: not the line that defined
            cmpd    seq             ; it, a duplicate pass 1 reported
            bne     dfl9
            lda     S_FLG,x
            bita    #F_KNOWN
            beq     dfl2
            ldd     S_VAL,x
            cmpd    dval
            beq     dfl2
            ldd     errors          ; after an error, lines that were
            lbeq    err_phase       ; dropped move the rest
dfl9:       rts
dfl2:       ldd     dval
            std     S_VAL,x
            rts

; B bytes from the symbol pages -> X (mapped).  An entry never crosses
; into the next page.
halloc:     pshs    b
            clra
            addd    hptr
            cmpd    #WINEND
            bls     ha1
            lda     hpage           ; doesn't fit: the next page
            inca
            cmpa    #SYMEND
            lbhs    fat_mem
            sta     hpage
            ldd     #WIN
            std     hptr
            ldb     ,s
            clra
            addd    hptr
ha1:        ldx     hptr
            std     hptr
            ldb     hpage
            jsr     setbank
            puls    b,pc

; A -> the next byte of the symbol pages (macro bodies).  Keeps A.
hput:       pshs    a,b,x
            ldb     hpage
            ldx     hptr
            cmpx    #WINEND
            blo     hp1
            incb
            cmpb    #SYMEND
            lbhs    fat_mem
            stb     hpage
            ldx     #WIN
hp1:        jsr     setbank
            sta     ,x+
            stx     hptr
            puls    a,b,x,pc

; ----------------------------------------------------------------------
;  Opcode table: hash chains in optab, built at the start
; ----------------------------------------------------------------------

initops:    ldx     #optab
            ldd     #0
io0:        std     ,x++
            cmpx    #optab+256
            blo     io0
            ldx     #opcodes
io1:        lda     2,x
            cmpa    #$FF
            beq     io9
            pshs    x
            leax    5,x
            jsr     hashx
            stx     tmp             ; the next entry
            andb    #$7F
            clra
            lslb
            rola
            addd    #optab
            tfr     d,u
            puls    x
            ldd     ,u
            std     ,x
            stx     ,u
            ldx     tmp
            bra     io1
io9:        rts

; Opcode at X (upper case) -> X = its entry, Z clear; Z set if none
findop:     pshs    x
            jsr     hashx
            andb    #$7F
            clra
            lslb
            rola
            addd    #optab
            tfr     d,u
            ldx     ,u
fo1:        beq     fo9
            leau    5,x
            ldy     ,s
            jsr     strcmp
            beq     fo8
            ldx     ,x
            bra     fo1
fo8:        andcc   #$FB
fo9:        leas    2,s
            rts

; ----------------------------------------------------------------------
;  Output: bytes go through obuf into the image in the output pages
; ----------------------------------------------------------------------

; A -> the next address.  Pass 1 only counts.
emitb:      pshs    d,x
            lda     pass
            cmpa    #2
            lbne    eb8
            tst     objmode         ; an object: only sections are kept,
            beq     eb0             ; each at its place in the image
            tst     cursect
            beq     eb8
eb0:        ldd     pc
            addd    curbase
            std     ipc
            ldd     obcnt
            beq     eb2
            cmpd    #OBSZ
            bhs     eb1
            addd    obaddr
            cmpd    ipc
            beq     eb3
eb1:        jsr     flush
eb2:        ldd     ipc
            std     obaddr
eb3:        ldb     lnb             ; for the listing: the line's address
            bne     eb3a            ; and its first LSTNB bytes
            ldx     pc
            stx     laddr
            inc     lshow
eb3a:       cmpb    #LSTNB
            bhs     eb3b
            ldx     #lbytes
            abx
            lda     ,s
            sta     ,x
            inc     lnb
eb3b:       ldx     #obuf
            ldd     obcnt
            leax    d,x
            lda     ,s
            sta     ,x
            ldd     obcnt
            addd    #1
            std     obcnt
            ldd     ipc             ; lowest and highest written
            tst     anyout
            bne     eb4
            inc     anyout
            std     lo
            std     hi
eb4:        cmpd    lo
            bhs     eb5
            std     lo
eb5:        cmpd    hi
            bls     eb8
            std     hi
eb8:        ldd     pc
            addd    #1
            std     pc
            puls    d,x,pc

emitw:      pshs    d
            jsr     emitb
            lda     1,s
            jsr     emitb
            puls    d,pc

; The opcode in A, after the page byte if there is one
emitop:     pshs    a
            lda     oppage
            beq     eo1
            jsr     emitb
eo1:        puls    a
            jsr     emitb
            tst     lmflag          ; OIM and co: the immediate byte
            beq     eo9
            lda     lmimm
            jmp     emitb
eo9:        rts

; obuf -> the image
flush:      ldy     obcnt
            beq     fl9
            ldx     #obuf
            ldd     obaddr
            bsr     flpage
fl1:        pshs    a
            lda     ,x+
            sta     ,u+
            puls    a
            addd    #1
            leay    -1,y
            beq     fl8
            tstb
            bne     fl1
            bita    #$3F
            bne     fl1
            bsr     flpage          ; a new page
            bra     fl1
fl8:        ldd     #0
            std     obcnt
fl9:        rts

; D = address -> its output page mapped, U -> it in the window.  Keeps D.
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
            bcs     wp9
            ldx     #hdr
            ldd     #PHLEN
            bsr     wblock
            bcs     wp9
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
            bsr     wblock
            bcs     wp9
            ldd     waddr
            addd    tmp
            std     waddr
            ldd     wleft
            subd    tmp
            std     wleft
            bra     wp5
wp8:        lda     #VCMD_FCLOSE
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

; ----------------------------------------------------------------------
;  File names
; ----------------------------------------------------------------------

; srcname with its extension replaced by .PRG -> outname
mkoutname:  ldx     #srcname
            ldu     #outname
            clr     ,-s             ; 0,s: U at the last '.', 0 if none
            clr     ,-s
mo1:        lda     ,x+
            beq     mo3
            cmpa    #'/
            bne     mo2
            clr     ,s              ; a '.' in a directory doesn't count
            clr     1,s
mo2:        cmpa    #'.
            bne     mo2a
            stu     ,s
mo2a:       sta     ,u+
            cmpu    #outname+LINEMAX-4
            blo     mo1
mo3:        ldd     ,s++
            beq     mo4
            tfr     d,u
mo4:        ldx     #s_prg
            jsr     strcpy
            ldx     #outname        ; HELLO.PRG -> HELLO.LST
            ldu     #lstname
            jsr     strcpy
            leau    -4,u
            ldx     #s_lst
            jsr     strcpy
            ldx     #outname        ; HELLO.PRG -> HELLO.O
            ldu     #objname
            jsr     strcpy
            leau    -4,u
            ldx     #s_o
            jmp     strcpy

; lbuf: "FILE [-L]" -> srcname (upper case), lstflag.  Stops on an empty
; line, and with the usage on anything else.
parseargs:  ldx     #lbuf
            jsr     skipsp
            tst     ,x
            lbeq    quit
            ldu     #srcname
pa1:        lda     ,x
            beq     pa2
            cmpa    #$20
            beq     pa2
            cmpa    #9
            beq     pa2
            leax    1,x
            cmpu    #srcname+LINEMAX
            bhs     pa1
            jsr     upper
            sta     ,u+
            bra     pa1
pa2:        clr     ,u
pa3:        jsr     skipsp          ; options
            lda     ,x+
            beq     pa9
            cmpa    #'-
            beq     pa4
            cmpa    #'/
            bne     pa8
pa4:        lda     ,x+
            jsr     upper
            cmpa    #'L
            bne     pa8
            lda     ,x
            beq     pa5
            cmpa    #$20
            beq     pa5
            cmpa    #9
            bne     pa8
pa5:        inc     lstflag
            bra     pa3
pa8:        ldx     #msg_usage
            jsr     puts
            jmp     quit
pa9:        rts

; srcname up to and including its last '/' -> dirpfx
mkdir:      ldx     #srcname
            ldu     #dirpfx
            ldy     #dirpfx         ; Y: after the last '/'
md1:        lda     ,x+
            beq     md9
            sta     ,u+
            cmpa    #'/
            bne     md1
            tfr     u,y
            bra     md1
md9:        clr     ,y
            rts

; X -> the part of the path at X after its last '/'
basename:   tfr     x,u
bn1:        lda     ,u+
            beq     bn9
            cmpa    #'/
            bne     bn1
            tfr     u,x
            bra     bn1
bn9:        rts

; Copy the NUL-terminated string at X to U (NUL included)
strcpy:     lda     ,x+
            sta     ,u+
            bne     strcpy
            rts

; Compare the strings at Y and U: Z set if they are the same
strcmp:     lda     ,y+
            cmpa    ,u+
            bne     sm9
            tsta
            bne     strcmp
sm9:        rts
; ... the strings at X and U
strcmpx:    pshs    y
            tfr     x,y
            bsr     strcmp
            puls    y,pc

; A -> upper case
upper:      cmpa    #'a
            blo     up9
            cmpa    #'z
            bhi     up9
            suba    #$20
up9:        rts

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

; ----------------------------------------------------------------------
;  VRAM mailbox: vput copies D bytes from X to VRAM U, vget from VRAM U
;  to X.
; ----------------------------------------------------------------------
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
;  Listing: pass 2 writes each line to lstname, after its address and
;  first LSTNB bytes, with "*** message" before a line in error
; ----------------------------------------------------------------------

; Create the listing file if -L was given
lstopen:    tst     lstflag
            beq     lo9
            ldx     #lstname
; Create the file named at X, for lput
fcreate:    stx     fpname
            jsr     setname
            lda     #VCMD_FCREATE
            OS      SYS_FCMD
            lbcs    ferror
            lda     #1
            sta     lstfd
            ldd     #0
            std     lstcnt
lo9:        rts

; Write what is left and close it
lstclose:   tst     lstfd
            beq     lc9
            jsr     lflush
            clr     lstfd
            lda     #VCMD_FCLOSE
            OS      SYS_FCMD
lc9:        rts

; D -> the address column of this line.  Keeps every register.
lstat:      std     laddr
            inc     lshow
            rts

; This line: "AAAA BBBBBBBBBB  line"
lstline:    pshs    d,x
            tst     lshow
            beq     ll1
            lda     laddr
            bsr     lhex
            lda     laddr+1
            bsr     lhex
            bra     ll2
ll1:        ldx     #s_sp4
            bsr     lputs
ll2:        lda     #$20
            bsr     lput
            ldx     #lbytes
            clrb
ll3:        cmpb    lnb
            bhs     ll4
            lda     ,x+
            bsr     lhex
            bra     ll5
ll4:        lda     #$20
            bsr     lput
            bsr     lput
ll5:        incb
            cmpb    #LSTNB
            blo     ll3
            lda     #$20
            bsr     lput
            bsr     lput
            ldx     #lbuf
            bsr     lputs
            bsr     lcrlf
            puls    d,x,pc

; CR LF to the listing
lcrlf:      lda     #CR
            bsr     lput
            lda     #LF
            bra     lput

; A as two hex digits to the listing
lhex:       pshs    a
            lsra
            lsra
            lsra
            lsra
            bsr     lnib
            puls    a
            anda    #$0F
lnib:       adda    #'0
            cmpa    #'9
            bls     lput
            adda    #7

; A to the listing.  Keeps every register.
lput:       pshs    d,x,u
            ldx     #lstbuf
            ldd     lstcnt
            leax    d,x
            lda     ,s
            sta     ,x
            ldd     lstcnt
            addd    #1
            std     lstcnt
            cmpd    #LSTBSZ
            blo     lp9
            bsr     lflush
lp9:        puls    d,x,u,pc

; The string at X to the listing.  Keeps X.
lputs:      pshs    a,x
lps1:       lda     ,x+
            beq     lps9
            bsr     lput
            bra     lps1
lps9:       puls    a,x,pc

; Write the listing buffer.  Stops on a write error.
lflush:     ldd     lstcnt
            beq     lfl9
            ldx     #lstbuf
            jsr     wblock
            bcs     lfl8
            ldd     #0
            std     lstcnt
lfl9:       rts
lfl8:       clr     lstfd
            jmp     ferror

; ----------------------------------------------------------------------
;  Errors: "FILE:LINE: message" and the line
; ----------------------------------------------------------------------

err_syntax: ldx     #msg_syntax
            bra     error
err_opcode: ldx     #msg_opcode
            bra     error
err_mode:   ldx     #msg_mode
            bra     error
err_bitno:  ldx     #msg_bitno
            bra     error
err_reloc:  ldx     #msg_reloc
            bra     error
err_insect: ldx     #msg_insect
            bra     error
err_reg:    ldx     #msg_reg
            bra     error
err_phase:  ldx     #msg_phase
            bra     error
err_known:  ldx     #msg_known
            bra     error
err_nolabel: ldx    #msg_nolabel
            bra     error
err_div0:   ldx     #msg_div0
            bra     error
err_endm:   ldx     #msg_endm
            bra     error
err_noif:   ldx     #msg_noif

; An error in the line: pass 1 drops the rest of the line quietly (pass
; 2 meets the same error at the same place), pass 2 reports it, and the
; assembly goes on with the next line
error:      lda     pass
            cmpa    #1
            beq     er9
            bsr     report
er9:        lds     linesp
            jmp     rp2

; Errors that stop the assembly
fat_mem:    ldx     #msg_mem
            bra     fatal
fat_nest:   ldx     #msg_nest
            bra     fatal
fat_noendm: ldx     #msg_noendm
            bra     fatal
fat_noendc: ldx     #msg_noendc
            bra     fatal
fat_sects:  ldx     #msg_sects
            bra     fatal
fat_files:  ldx     #msg_files
fatal:      lds     #stktop
            bsr     where
            jsr     lstclose
            jmp     quit

; "FILE:LINE: message" (X) and the line, on the console and in the
; listing; counted
report:     stx     emsg
            bsr     where
            tst     lstfd
            beq     rpt1
            ldx     #s_stars        ; "*** message" before the line
            jsr     lputs
            ldx     emsg
            jsr     lputs
            jsr     lcrlf
rpt1:       ldd     errors
            addd    #1
            std     errors
            cmpd    #MAXERR
            blo     rpt9
            ldx     #msg_toomany
            bra     fatal
rpt9:       rts

; Print where the line is, the message X and the line
where:      pshs    x
            ldu     lvp             ; the innermost file
wh1:        cmpu    #0
            beq     wh3
            tst     ,u
            beq     wh2
            leau    -LVSZ,u
            cmpu    #levels
            bhs     wh1
            bra     wh3
wh2:        ldx     6,u
            jsr     puts
            lda     #':
            OS      SYS_PUTC
            ldd     4,u
            jsr     putdec
            ldx     #s_colon
            jsr     puts
wh3:        puls    x
            jsr     puts
            jsr     crlf
            ldx     #lbuf
            jsr     puts
            jmp     crlf

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

; ----------------------------------------------------------------------
;  Console
; ----------------------------------------------------------------------

; Read a typed line into lbuf (upper-cased, NUL terminated)
readline:   ldx     #lbuf
            clrb
rl1:        OS      SYS_GETC
            cmpa    #CR
            beq     rl9
            cmpa    #LF
            beq     rl9
            cmpa    #BS
            beq     rl2
            cmpa    #DEL
            beq     rl2
            cmpa    #$20
            blo     rl1
            cmpb    #LINEMAX
            bhs     rl1
            jsr     upper
            sta     ,x+
            incb
            OS      SYS_PUTC
            bra     rl1
rl2:        tstb
            beq     rl1
            decb
            leax    -1,x
            pshs    x
            ldx     #bsseq
            bsr     puts
            puls    x
            bra     rl1
rl9:        clr     ,x
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
msg_hello:  fcc     "MINI09 ASM 0.4"
            fcb     CR,LF,0
msg_src:    fcn     "Source file: "
msg_lines:  fcn     " lines, "
msg_bytes:  fcn     " bytes: "
msg_syntax: fcn     "Syntax error"
msg_opcode: fcn     "Unknown opcode"
msg_mode:   fcn     "Bad addressing mode"
msg_reg:    fcn     "Bad register"
msg_undef:  fcn     "Undefined symbol"
msg_dup:    fcn     "Symbol defined twice"
msg_range:  fcn     "Branch out of range"
msg_bitno:  fcn     "Bad bit number"
msg_reloc:  fcn     "Not relocatable"
msg_insect: fcn     "ORG inside a section"
msg_sects:  fcn     "Too many sections"
msg_cplx:   fcn     "Expression too complex"
msg_noexp:  fcn     "Undefined export: "
s_lwobj:    fcn     "LWOBJ16"
s_o:        fcn     "O"
s_bss:      fcn     "BSS"
s_dbss:     fcn     ".BSS"
msg_phase:  fcn     "Phase error"
msg_mem:    fcn     "Out of symbol memory"
msg_nest:   fcn     "Nested too deep"
msg_known:  fcn     "Value must be known"
msg_nolabel: fcn    "Needs a label"
msg_div0:   fcn     "Division by zero"
msg_endm:   fcn     "ENDM without MACRO"
msg_noendm: fcn     "MACRO without ENDM"
msg_noif:   fcn     "ELSE or ENDC without IF"
msg_noendc: fcn     "IF without ENDC"
msg_files:  fcn     "Too many files"
msg_toomany: fcn    "Too many errors"
msg_errors: fcc     " error(s), no program file written"
            fcb     CR,LF,0
msg_usage:  fcc     "Use: ASM FILE.ASM [-L]"
            fcb     CR,LF,0
s_stars:    fcn     "*** "
msg_fnofile: fcn    "File not found"
msg_fnopath: fcn    "Path not found"
msg_fnodrv: fcn     "No drive"
msg_full:   fcn     "Out of memory for source"
msg_ferr:   fcn     "File error "
s_colon:    fcn     ": "
s_prg:      fcn     ".PRG"
s_lst:      fcn     "LST"
s_sp4:      fcn     "    "
s_endm:     fcn     "ENDM"
bsseq:      fcb     BS,$20,BS,0
zero2:      fdb     0

; Program file header (asm.md); name, sizes and addresses are filled in
hdr:        fcc     "M9"
            fcb     1,PHLEN
            rmb     12              ; name
            fcc     "MINI09AS"      ; creator
            fdb     0               ; date unknown
            fcb     0,0
            rmb     2               ; file size
            rmb     2               ; load address
            rmb     2               ; entry
            fdb     0

; ----------------------------------------------------------------------
;  Opcodes: next in the hash chain (filled in), class, page, opcode,
;  name.  Directives have their D_ number as the opcode.
; ----------------------------------------------------------------------
opcodes:
            fdb     0
            fcb     C_INH,$00,$12
            fcn     "NOP"
            fdb     0
            fcb     C_INH,$00,$13
            fcn     "SYNC"
            fdb     0
            fcb     C_INH,$00,$19
            fcn     "DAA"
            fdb     0
            fcb     C_INH,$00,$1D
            fcn     "SEX"
            fdb     0
            fcb     C_INH,$00,$39
            fcn     "RTS"
            fdb     0
            fcb     C_INH,$00,$3A
            fcn     "ABX"
            fdb     0
            fcb     C_INH,$00,$3B
            fcn     "RTI"
            fdb     0
            fcb     C_INH,$00,$3D
            fcn     "MUL"
            fdb     0
            fcb     C_INH,$00,$3F
            fcn     "SWI"
            fdb     0
            fcb     C_INH,$10,$3F
            fcn     "SWI2"
            fdb     0
            fcb     C_INH,$11,$3F
            fcn     "SWI3"
            fdb     0
            fcb     C_INH,$00,$40
            fcn     "NEGA"
            fdb     0
            fcb     C_INH,$00,$43
            fcn     "COMA"
            fdb     0
            fcb     C_INH,$00,$44
            fcn     "LSRA"
            fdb     0
            fcb     C_INH,$00,$46
            fcn     "RORA"
            fdb     0
            fcb     C_INH,$00,$47
            fcn     "ASRA"
            fdb     0
            fcb     C_INH,$00,$48
            fcn     "ASLA"
            fdb     0
            fcb     C_INH,$00,$48
            fcn     "LSLA"
            fdb     0
            fcb     C_INH,$00,$49
            fcn     "ROLA"
            fdb     0
            fcb     C_INH,$00,$4A
            fcn     "DECA"
            fdb     0
            fcb     C_INH,$00,$4C
            fcn     "INCA"
            fdb     0
            fcb     C_INH,$00,$4D
            fcn     "TSTA"
            fdb     0
            fcb     C_INH,$00,$4F
            fcn     "CLRA"
            fdb     0
            fcb     C_INH,$00,$50
            fcn     "NEGB"
            fdb     0
            fcb     C_INH,$00,$53
            fcn     "COMB"
            fdb     0
            fcb     C_INH,$00,$54
            fcn     "LSRB"
            fdb     0
            fcb     C_INH,$00,$56
            fcn     "RORB"
            fdb     0
            fcb     C_INH,$00,$57
            fcn     "ASRB"
            fdb     0
            fcb     C_INH,$00,$58
            fcn     "ASLB"
            fdb     0
            fcb     C_INH,$00,$58
            fcn     "LSLB"
            fdb     0
            fcb     C_INH,$00,$59
            fcn     "ROLB"
            fdb     0
            fcb     C_INH,$00,$5A
            fcn     "DECB"
            fdb     0
            fcb     C_INH,$00,$5C
            fcn     "INCB"
            fdb     0
            fcb     C_INH,$00,$5D
            fcn     "TSTB"
            fdb     0
            fcb     C_INH,$00,$5F
            fcn     "CLRB"
            fdb     0
            fcb     C_MEM,$00,$00
            fcn     "NEG"
            fdb     0
            fcb     C_MEM,$00,$03
            fcn     "COM"
            fdb     0
            fcb     C_MEM,$00,$04
            fcn     "LSR"
            fdb     0
            fcb     C_MEM,$00,$06
            fcn     "ROR"
            fdb     0
            fcb     C_MEM,$00,$07
            fcn     "ASR"
            fdb     0
            fcb     C_MEM,$00,$08
            fcn     "ASL"
            fdb     0
            fcb     C_MEM,$00,$08
            fcn     "LSL"
            fdb     0
            fcb     C_MEM,$00,$09
            fcn     "ROL"
            fdb     0
            fcb     C_MEM,$00,$0A
            fcn     "DEC"
            fdb     0
            fcb     C_MEM,$00,$0C
            fcn     "INC"
            fdb     0
            fcb     C_MEM,$00,$0D
            fcn     "TST"
            fdb     0
            fcb     C_MEM,$00,$0E
            fcn     "JMP"
            fdb     0
            fcb     C_MEM,$00,$0F
            fcn     "CLR"
            fdb     0
            fcb     C_GEN8,$00,$80
            fcn     "SUBA"
            fdb     0
            fcb     C_GEN8,$00,$C0
            fcn     "SUBB"
            fdb     0
            fcb     C_GEN8,$00,$81
            fcn     "CMPA"
            fdb     0
            fcb     C_GEN8,$00,$C1
            fcn     "CMPB"
            fdb     0
            fcb     C_GEN8,$00,$82
            fcn     "SBCA"
            fdb     0
            fcb     C_GEN8,$00,$C2
            fcn     "SBCB"
            fdb     0
            fcb     C_GEN8,$00,$84
            fcn     "ANDA"
            fdb     0
            fcb     C_GEN8,$00,$C4
            fcn     "ANDB"
            fdb     0
            fcb     C_GEN8,$00,$85
            fcn     "BITA"
            fdb     0
            fcb     C_GEN8,$00,$C5
            fcn     "BITB"
            fdb     0
            fcb     C_GEN8,$00,$86
            fcn     "LDA"
            fdb     0
            fcb     C_GEN8,$00,$C6
            fcn     "LDB"
            fdb     0
            fcb     C_GEN8,$00,$88
            fcn     "EORA"
            fdb     0
            fcb     C_GEN8,$00,$C8
            fcn     "EORB"
            fdb     0
            fcb     C_GEN8,$00,$89
            fcn     "ADCA"
            fdb     0
            fcb     C_GEN8,$00,$C9
            fcn     "ADCB"
            fdb     0
            fcb     C_GEN8,$00,$8A
            fcn     "ORA"
            fdb     0
            fcb     C_GEN8,$00,$CA
            fcn     "ORB"
            fdb     0
            fcb     C_GEN8,$00,$8B
            fcn     "ADDA"
            fdb     0
            fcb     C_GEN8,$00,$CB
            fcn     "ADDB"
            fdb     0
            fcb     C_STORE,$00,$87
            fcn     "STA"
            fdb     0
            fcb     C_STORE,$00,$C7
            fcn     "STB"
            fdb     0
            fcb     C_GEN16,$00,$83
            fcn     "SUBD"
            fdb     0
            fcb     C_GEN16,$00,$C3
            fcn     "ADDD"
            fdb     0
            fcb     C_GEN16,$00,$8C
            fcn     "CMPX"
            fdb     0
            fcb     C_GEN16,$00,$8E
            fcn     "LDX"
            fdb     0
            fcb     C_GEN16,$00,$CC
            fcn     "LDD"
            fdb     0
            fcb     C_GEN16,$00,$CE
            fcn     "LDU"
            fdb     0
            fcb     C_GEN16,$10,$83
            fcn     "CMPD"
            fdb     0
            fcb     C_GEN16,$10,$8C
            fcn     "CMPY"
            fdb     0
            fcb     C_GEN16,$10,$8E
            fcn     "LDY"
            fdb     0
            fcb     C_GEN16,$10,$CE
            fcn     "LDS"
            fdb     0
            fcb     C_GEN16,$11,$83
            fcn     "CMPU"
            fdb     0
            fcb     C_GEN16,$11,$8C
            fcn     "CMPS"
            fdb     0
            fcb     C_STORE,$00,$8F
            fcn     "STX"
            fdb     0
            fcb     C_STORE,$00,$CD
            fcn     "STD"
            fdb     0
            fcb     C_STORE,$00,$CF
            fcn     "STU"
            fdb     0
            fcb     C_STORE,$10,$8F
            fcn     "STY"
            fdb     0
            fcb     C_STORE,$10,$CF
            fcn     "STS"
            fdb     0
            fcb     C_STORE,$00,$8D
            fcn     "JSR"
            fdb     0
            fcb     C_LEA,$00,$30
            fcn     "LEAX"
            fdb     0
            fcb     C_LEA,$00,$31
            fcn     "LEAY"
            fdb     0
            fcb     C_LEA,$00,$32
            fcn     "LEAS"
            fdb     0
            fcb     C_LEA,$00,$33
            fcn     "LEAU"
            fdb     0
            fcb     C_IMM,$00,$1A
            fcn     "ORCC"
            fdb     0
            fcb     C_IMM,$00,$1C
            fcn     "ANDCC"
            fdb     0
            fcb     C_IMM,$00,$3C
            fcn     "CWAI"
            fdb     0
            fcb     C_REL8,$00,$20
            fcn     "BRA"
            fdb     0
            fcb     C_REL8,$00,$21
            fcn     "BRN"
            fdb     0
            fcb     C_REL8,$00,$22
            fcn     "BHI"
            fdb     0
            fcb     C_REL8,$00,$23
            fcn     "BLS"
            fdb     0
            fcb     C_REL8,$00,$24
            fcn     "BCC"
            fdb     0
            fcb     C_REL8,$00,$24
            fcn     "BHS"
            fdb     0
            fcb     C_REL8,$00,$25
            fcn     "BCS"
            fdb     0
            fcb     C_REL8,$00,$25
            fcn     "BLO"
            fdb     0
            fcb     C_REL8,$00,$26
            fcn     "BNE"
            fdb     0
            fcb     C_REL8,$00,$27
            fcn     "BEQ"
            fdb     0
            fcb     C_REL8,$00,$28
            fcn     "BVC"
            fdb     0
            fcb     C_REL8,$00,$29
            fcn     "BVS"
            fdb     0
            fcb     C_REL8,$00,$2A
            fcn     "BPL"
            fdb     0
            fcb     C_REL8,$00,$2B
            fcn     "BMI"
            fdb     0
            fcb     C_REL8,$00,$2C
            fcn     "BGE"
            fdb     0
            fcb     C_REL8,$00,$2D
            fcn     "BLT"
            fdb     0
            fcb     C_REL8,$00,$2E
            fcn     "BGT"
            fdb     0
            fcb     C_REL8,$00,$2F
            fcn     "BLE"
            fdb     0
            fcb     C_REL8,$00,$8D
            fcn     "BSR"
            fdb     0
            fcb     C_REL16,$00,$16
            fcn     "LBRA"
            fdb     0
            fcb     C_REL16,$10,$21
            fcn     "LBRN"
            fdb     0
            fcb     C_REL16,$10,$22
            fcn     "LBHI"
            fdb     0
            fcb     C_REL16,$10,$23
            fcn     "LBLS"
            fdb     0
            fcb     C_REL16,$10,$24
            fcn     "LBCC"
            fdb     0
            fcb     C_REL16,$10,$24
            fcn     "LBHS"
            fdb     0
            fcb     C_REL16,$10,$25
            fcn     "LBCS"
            fdb     0
            fcb     C_REL16,$10,$25
            fcn     "LBLO"
            fdb     0
            fcb     C_REL16,$10,$26
            fcn     "LBNE"
            fdb     0
            fcb     C_REL16,$10,$27
            fcn     "LBEQ"
            fdb     0
            fcb     C_REL16,$10,$28
            fcn     "LBVC"
            fdb     0
            fcb     C_REL16,$10,$29
            fcn     "LBVS"
            fdb     0
            fcb     C_REL16,$10,$2A
            fcn     "LBPL"
            fdb     0
            fcb     C_REL16,$10,$2B
            fcn     "LBMI"
            fdb     0
            fcb     C_REL16,$10,$2C
            fcn     "LBGE"
            fdb     0
            fcb     C_REL16,$10,$2D
            fcn     "LBLT"
            fdb     0
            fcb     C_REL16,$10,$2E
            fcn     "LBGT"
            fdb     0
            fcb     C_REL16,$10,$2F
            fcn     "LBLE"
            fdb     0
            fcb     C_REL16,$00,$17
            fcn     "LBSR"
            fdb     0
            fcb     C_PSH,$00,$34
            fcn     "PSHS"
            fdb     0
            fcb     C_PSH,$00,$35
            fcn     "PULS"
            fdb     0
            fcb     C_PSH,$00,$36
            fcn     "PSHU"
            fdb     0
            fcb     C_PSH,$00,$37
            fcn     "PULU"
            fdb     0
            fcb     C_TFR,$00,$1E
            fcn     "EXG"
            fdb     0
            fcb     C_TFR,$00,$1F
            fcn     "TFR"
            fdb     0
            fcb     C_INH,$00,$14
            fcn     "SEXW"
            fdb     0
            fcb     C_INH,$10,$38
            fcn     "PSHSW"
            fdb     0
            fcb     C_INH,$10,$39
            fcn     "PULSW"
            fdb     0
            fcb     C_INH,$10,$3A
            fcn     "PSHUW"
            fdb     0
            fcb     C_INH,$10,$3B
            fcn     "PULUW"
            fdb     0
            fcb     C_INH,$10,$40
            fcn     "NEGD"
            fdb     0
            fcb     C_INH,$10,$43
            fcn     "COMD"
            fdb     0
            fcb     C_INH,$10,$44
            fcn     "LSRD"
            fdb     0
            fcb     C_INH,$10,$46
            fcn     "RORD"
            fdb     0
            fcb     C_INH,$10,$47
            fcn     "ASRD"
            fdb     0
            fcb     C_INH,$10,$48
            fcn     "ASLD"
            fdb     0
            fcb     C_INH,$10,$48
            fcn     "LSLD"
            fdb     0
            fcb     C_INH,$10,$49
            fcn     "ROLD"
            fdb     0
            fcb     C_INH,$10,$4A
            fcn     "DECD"
            fdb     0
            fcb     C_INH,$10,$4C
            fcn     "INCD"
            fdb     0
            fcb     C_INH,$10,$4D
            fcn     "TSTD"
            fdb     0
            fcb     C_INH,$10,$4F
            fcn     "CLRD"
            fdb     0
            fcb     C_INH,$10,$53
            fcn     "COMW"
            fdb     0
            fcb     C_INH,$10,$54
            fcn     "LSRW"
            fdb     0
            fcb     C_INH,$10,$56
            fcn     "RORW"
            fdb     0
            fcb     C_INH,$10,$59
            fcn     "ROLW"
            fdb     0
            fcb     C_INH,$10,$5A
            fcn     "DECW"
            fdb     0
            fcb     C_INH,$10,$5C
            fcn     "INCW"
            fdb     0
            fcb     C_INH,$10,$5D
            fcn     "TSTW"
            fdb     0
            fcb     C_INH,$10,$5F
            fcn     "CLRW"
            fdb     0
            fcb     C_INH,$11,$43
            fcn     "COME"
            fdb     0
            fcb     C_INH,$11,$53
            fcn     "COMF"
            fdb     0
            fcb     C_INH,$11,$4A
            fcn     "DECE"
            fdb     0
            fcb     C_INH,$11,$5A
            fcn     "DECF"
            fdb     0
            fcb     C_INH,$11,$4C
            fcn     "INCE"
            fdb     0
            fcb     C_INH,$11,$5C
            fcn     "INCF"
            fdb     0
            fcb     C_INH,$11,$4D
            fcn     "TSTE"
            fdb     0
            fcb     C_INH,$11,$5D
            fcn     "TSTF"
            fdb     0
            fcb     C_INH,$11,$4F
            fcn     "CLRE"
            fdb     0
            fcb     C_INH,$11,$5F
            fcn     "CLRF"
            fdb     0
            fcb     C_GEN8,$11,$80
            fcn     "SUBE"
            fdb     0
            fcb     C_GEN8,$11,$C0
            fcn     "SUBF"
            fdb     0
            fcb     C_GEN8,$11,$81
            fcn     "CMPE"
            fdb     0
            fcb     C_GEN8,$11,$C1
            fcn     "CMPF"
            fdb     0
            fcb     C_GEN8,$11,$86
            fcn     "LDE"
            fdb     0
            fcb     C_GEN8,$11,$C6
            fcn     "LDF"
            fdb     0
            fcb     C_GEN8,$11,$8B
            fcn     "ADDE"
            fdb     0
            fcb     C_GEN8,$11,$CB
            fcn     "ADDF"
            fdb     0
            fcb     C_STORE,$11,$87
            fcn     "STE"
            fdb     0
            fcb     C_STORE,$11,$C7
            fcn     "STF"
            fdb     0
            fcb     C_GEN8,$11,$8D
            fcn     "DIVD"
            fdb     0
            fcb     C_GEN16,$10,$80
            fcn     "SUBW"
            fdb     0
            fcb     C_GEN16,$10,$81
            fcn     "CMPW"
            fdb     0
            fcb     C_GEN16,$10,$82
            fcn     "SBCD"
            fdb     0
            fcb     C_GEN16,$10,$84
            fcn     "ANDD"
            fdb     0
            fcb     C_GEN16,$10,$85
            fcn     "BITD"
            fdb     0
            fcb     C_GEN16,$10,$86
            fcn     "LDW"
            fdb     0
            fcb     C_GEN16,$10,$88
            fcn     "EORD"
            fdb     0
            fcb     C_GEN16,$10,$89
            fcn     "ADCD"
            fdb     0
            fcb     C_GEN16,$10,$8A
            fcn     "ORD"
            fdb     0
            fcb     C_GEN16,$10,$8B
            fcn     "ADDW"
            fdb     0
            fcb     C_STORE,$10,$87
            fcn     "STW"
            fdb     0
            fcb     C_GEN16,$11,$8E
            fcn     "DIVQ"
            fdb     0
            fcb     C_GEN16,$11,$8F
            fcn     "MULD"
            fdb     0
            fcb     C_LDQ,$10,$CC
            fcn     "LDQ"
            fdb     0
            fcb     C_STORE,$10,$CD
            fcn     "STQ"
            fdb     0
            fcb     C_IMM,$11,$3D
            fcn     "LDMD"
            fdb     0
            fcb     C_IMM,$11,$3C
            fcn     "BITMD"
            fdb     0
            fcb     C_TFR,$10,$30
            fcn     "ADDR"
            fdb     0
            fcb     C_TFR,$10,$31
            fcn     "ADCR"
            fdb     0
            fcb     C_TFR,$10,$32
            fcn     "SUBR"
            fdb     0
            fcb     C_TFR,$10,$33
            fcn     "SBCR"
            fdb     0
            fcb     C_TFR,$10,$34
            fcn     "ANDR"
            fdb     0
            fcb     C_TFR,$10,$35
            fcn     "ORR"
            fdb     0
            fcb     C_TFR,$10,$36
            fcn     "EORR"
            fdb     0
            fcb     C_TFR,$10,$37
            fcn     "CMPR"
            fdb     0
            fcb     C_TFM,$11,$38
            fcn     "TFM"
            fdb     0
            fcb     C_TFR,$11,$38
            fcn     "COPY"
            fdb     0
            fcb     C_TFR,$11,$38
            fcn     "TFRP"
            fdb     0
            fcb     C_TFR,$11,$39
            fcn     "TFRM"
            fdb     0
            fcb     C_TFR,$11,$3A
            fcn     "IMP"
            fdb     0
            fcb     C_TFR,$11,$3A
            fcn     "IMPLODE"
            fdb     0
            fcb     C_TFR,$11,$3A
            fcn     "TFRS"
            fdb     0
            fcb     C_TFR,$11,$3B
            fcn     "EXP"
            fdb     0
            fcb     C_TFR,$11,$3B
            fcn     "EXPAND"
            fdb     0
            fcb     C_TFR,$11,$3B
            fcn     "TFRR"
            fdb     0
            fcb     C_LMEM,$00,$01
            fcn     "OIM"
            fdb     0
            fcb     C_LMEM,$00,$02
            fcn     "AIM"
            fdb     0
            fcb     C_LMEM,$00,$05
            fcn     "EIM"
            fdb     0
            fcb     C_LMEM,$00,$0B
            fcn     "TIM"
            fdb     0
            fcb     C_BIT,$11,$30
            fcn     "BAND"
            fdb     0
            fcb     C_BIT,$11,$31
            fcn     "BIAND"
            fdb     0
            fcb     C_BIT,$11,$32
            fcn     "BOR"
            fdb     0
            fcb     C_BIT,$11,$33
            fcn     "BIOR"
            fdb     0
            fcb     C_BIT,$11,$34
            fcn     "BEOR"
            fdb     0
            fcb     C_BIT,$11,$35
            fcn     "BIEOR"
            fdb     0
            fcb     C_BIT,$11,$36
            fcn     "LDBT"
            fdb     0
            fcb     C_BIT,$11,$37
            fcn     "STBT"
            fdb     0
            fcb     C_DIRN,$00,$00
            fcn     "EQU"
            fdb     0
            fcb     C_DIRN,$00,$01
            fcn     "ORG"
            fdb     0
            fcb     C_DIRL,$00,$02
            fcn     "FCB"
            fdb     0
            fcb     C_DIRL,$00,$03
            fcn     "FDB"
            fdb     0
            fcb     C_DIRL,$00,$04
            fcn     "FCC"
            fdb     0
            fcb     C_DIRL,$00,$05
            fcn     "FCN"
            fdb     0
            fcb     C_DIRL,$00,$06
            fcn     "FCS"
            fdb     0
            fcb     C_DIRL,$00,$07
            fcn     "RMB"
            fdb     0
            fcb     C_DIRL,$00,$08
            fcn     "END"
            fdb     0
            fcb     C_DIRL,$00,$09
            fcn     "INCLUDE"
            fdb     0
            fcb     C_DIRN,$00,$0A
            fcn     "MACRO"
            fdb     0
            fcb     C_DIRN,$00,$0B
            fcn     "ENDM"
            fdb     0
            fcb     C_DIRN,$00,$0C
            fcn     "IFDEF"
            fdb     0
            fcb     C_DIRN,$00,$0D
            fcn     "IFNDEF"
            fdb     0
            fcb     C_DIRN,$00,$0E
            fcn     "ELSE"
            fdb     0
            fcb     C_DIRN,$00,$0F
            fcn     "ENDC"
            fdb     0
            fcb     C_DIRN,$00,$10
            fcn     "SECTION"
            fdb     0
            fcb     C_DIRN,$00,$11
            fcn     "SECT"
            fdb     0
            fcb     C_DIRN,$00,$12
            fcn     "ENDSECTION"
            fdb     0
            fcb     C_DIRN,$00,$13
            fcn     "ENDSECT"
            fdb     0
            fcb     C_DIRN,$00,$14
            fcn     "EXPORT"
            fdb     0
            fcb     C_DIRN,$00,$15
            fcn     ".GLOBL"
            fdb     0
            fcb     C_DIRN,$00,$16
            fcn     "IMPORT"
            fdb     0
            fcb     C_DIRN,$00,$17
            fcn     "EXTERN"
            fdb     0
            fcb     C_DIRN,$00,$18
            fcn     "EXTERNAL"
            fdb     0
            fcb     $FF

; ----------------------------------------------------------------------
;  Variables
; ----------------------------------------------------------------------
curbank:    rmb     1               ; page at $8000 now
pass:       rmb     1               ; 1 or 2
pc:         rmb     2
seq:        rmb     2               ; lines so far in this pass
entry:      rmb     2
lo:         rmb     2               ; lowest and highest address written
hi:         rmb     2
anyout:     rmb     1
endflag:    rmb     1
skipping:   rmb     1               ; in a false IFDEF
skipnest:   rmb     1
ifdepth:    rmb     1
mdef:       rmb     1               ; in a macro definition
haslab:     rmb     1
optr:       rmb     2               ; -> operand
opclass:    rmb     1
oppage:     rmb     1
opcode:     rmb     1
eknown:     rmb     1
force:      rmb     1               ; '<', '>' or 0
indir:      rmb     1
postb:      rmb     1
ival:       rmb     2
delim:      rmb     1
lastc:      rmb     1
havec:      rmb     1
nflags:     rmb     1
dval:       rmb     2
bucket:     rmb     2
hpage:      rmb     1               ; next free byte of the symbol pages
hptr:       rmb     2
ma:         rmb     2
mb:         rmb     2
mres:       rmb     2
mrem:       rmb     2
num:        rmb     2
base:       rmb     1
ndig:       rmb     1
tmp:        rmb     2
tmp2:       rmb     1
obaddr:     rmb     2
obcnt:      rmb     2
waddr:      rmb     2
wleft:      rmb     2
wlen:       rmb     2
vblk:       rmb     7
cpage:      rmb     1               ; where the next cached file goes
cptr:       rmb     2
srcpg:      rmb     1               ; where the last loaded file starts
srcptr:     rmb     2
fpname:     rmb     2
ninc:       rmb     1
mainent:    rmb     2
depth:      rmb     1
lvp:        rmb     2               ; -> the innermost input level
regname:    rmb     6
lmflag:     rmb     1               ; OIM and co: lmimm after the opcode
objmode:    rmb     1               ; sections, export or import seen
nsects:     rmb     1
cursect:    rmb     1               ; 0: not in a section
curbase:    rmb     2               ; its place in the image
abspc:      rmb     2               ; pc outside sections
ipc:        rmb     2               ; image address of the byte
objsize:    rmb     2
nsect:      rmb     1               ; S_AUX for a symbol defined now
ekind:      rmb     1               ; the expression's kind (S_AUX)
ksp:        rmb     2
rpnon:      rmb     1
rpnlen:     rmb     1
rpnovf:     rmb     1
pcrel:      rmb     1
rpage:      rmb     1               ; relocations: the page, the next byte
rptr:       rmb     2
wsec:       rmb     1
wsp:        rmb     2
secname:    rmb     16
lmimm:      rmb     1
lit0:       rmb     1
q32:        rmb     4
neg32:      rmb     1
labname:    rmb     NAMEMAX+1
name:       rmb     NAMEMAX+1
opname:     rmb     16
rawop:      rmb     16
srcname:    rmb     LINEMAX+1
outname:    rmb     LINEMAX+1
lstname:    rmb     LINEMAX+1
objname:    rmb     LINEMAX+1
errors:     rmb     2               ; errors so far
linesp:     rmb     2               ; S at the start of the line
emsg:       rmb     2
lstflag:    rmb     1               ; -L given
lstfd:      rmb     1               ; the listing file is open
lstcnt:     rmb     2               ; bytes in lstbuf
lshow:      rmb     1               ; the line has an address
laddr:      rmb     2
lnb:        rmb     1               ; bytes of the line in lbytes
lbytes:     rmb     LSTNB
lstbuf:     rmb     LSTBSZ
dirpfx:     rmb     LINEMAX+1
fpath:      rmb     INCSZ
lbuf:       rmb     LBUFSZ+2
levels:     rmb     LVSZ*MAXDEPTH
argbufs:    rmb     ARGSZ*MAXDEPTH
incs:       rmb     INCSZ*MAXINC
symtab:     rmb     768
sectab:     rmb     SECSZ*MAXSECT
kstk:       rmb     KSTSZ
rpnbuf:     rmb     RPNSZ
optab:      rmb     256
obuf:       rmb     OBSZ
            rmb     384             ; stack
stktop:

            end     start
