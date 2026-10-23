; ----------------------------------------------------------------------
;  Console and file I/O over the MINI09 system calls.
;
;  The flash drive has one file open at a time, for every task, and no
;  seek.  So a file opened for reading is read whole into banked RAM and
;  closed again at once, and a file opened for writing is collected in
;  banked RAM and written when it is closed.  They share pages
;  PFIRST-PLAST (400K):
;
;    files open for reading   from PFIRST up, allocated like a stack:
;                             closing the newest gives its RAM back
;    the one file open for    from PLAST down, a page at a time (each
;    writing                  page in order from $8000)
;
;  A file being written can use whatever reading leaves, and the other
;  way round.
;  Pages 3-6 are left for the program (bank() switches the window).
;  LIBC puts the program's page back before it returns, so a program can
;  keep its own data in the window while it reads and writes files.
; ----------------------------------------------------------------------

            export  __iob,_fopen,_fclose,_fgetc,_fputc,_ungetc,_fputs
            export  _putchar,_getchar,_puts,_exit,_bank,_remove
            export  _fread,_fwrite
            export  __rpage,__curbank,__ubank   ; for banked code (crt0b)

NFILE       equ     8               ; stdin, stdout, stderr and 5 more
FSIZE       equ     15
F_KIND      equ     0               ; K_xxx
F_PAGE      equ     1               ; where the next byte is
F_PTR       equ     2
F_EPAGE     equ     4               ; reading: where the file ends;
                                    ; writing: nonzero if bytes were lost
F_EPTR      equ     5
F_SPAGE     equ     7               ; reading: where it starts
F_SPTR      equ     8
F_UNGET     equ     10              ; ungetc's character, $FFFF if none
F_TPAGE     equ     12              ; reading: the pool top after it
F_TPTR      equ     13

K_CIN       equ     1
K_COUT      equ     2
K_READ      equ     3
K_WRITE     equ     4

PFIRST      equ     7
PLAST       equ     31
WINDOW      equ     $8000
WINEND      equ     $C000

            section data
__iob:      fcb     K_CIN,0,0,0,0,0,0,0,0,0,$FF,$FF,0,0,0
            fcb     K_COUT,0,0,0,0,0,0,0,0,0,$FF,$FF,0,0,0
            fcb     K_COUT,0,0,0,0,0,0,0,0,0,$FF,$FF,0,0,0
            fcb     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
            fcb     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
            fcb     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
            fcb     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
            fcb     0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
rpage:      fcb     PFIRST          ; the read pool's top
__rpage     equ     rpage           ; (crt0b moves it past the code banks)
wlow:       fcb     PLAST+1         ; the lowest page being written
raddr:      fdb     WINDOW
zero2:      fdb     0
            endsection

            section bss
curbank:    rmb     1               ; the page in the window, 0 = unknown
ubank:      rmb     1               ; the program's page (bank()), 0 = none
__curbank   equ     curbank
__ubank     equ     ubank
wopen:      rmb     1               ; a file is open for writing
wname:      rmb     64              ; its name
wcnt:       rmb     2
vblk:       rmb     7               ; SYS_VCOPY/SYS_VREAD block
            endsection

            section code

; ---- console ----------------------------------------------------------

; int putchar(int c): '\n' goes out as CR LF
_putchar:   lda     3,s
            cmpa    #LF
            bne     pc1
            lda     #CR
            OS      SYS_PUTC
            lda     #LF
pc1:        OS      SYS_PUTC
            clra
            ldb     3,s
            rts

; int getchar(void): waits for a key, no echo.  CR comes back as '\n',
; ^D as EOF.
_getchar:   OS      SYS_GETC
            tfr     a,b
            clra
            cmpb    #CR
            bne     gc1
            ldb     #LF
gc1:        cmpb    #4
            bne     gc2
            ldd     #-1
gc2:        rts

; int puts(char *s): s and '\n'
_puts:      ldx     2,s
pu1:        ldb     ,x+
            beq     pu2
            pshs    x
            pshs    d
            bsr     _putchar
            leas    2,s
            puls    x
            bra     pu1
pu2:        ldd     #LF
            pshs    d
            bsr     _putchar
            leas    2,s
            ldd     #0
            rts

; void exit(int status): close a file open for writing, so it is
; written, then end the task
_exit:      ldx     #__iob
ex1:        lda     F_KIND,x
            cmpa    #K_WRITE
            bne     ex2
            pshs    x
            lbsr    _fclose
            puls    x
ex2:        leax    FSIZE,x
            cmpx    #__iob+NFILE*FSIZE
            blo     ex1
            OS      SYS_EXIT

; int bank(int page): map page into $8000-$BFFF; -> the previous page.
; Programs use pages 3-6.
_bank:      ldb     3,s
            cmpb    curbank         ; there already: no system call
            bne     bk0
            stb     ubank
            clra
            rts
bk0:        OS      SYS_BANK
            bcs     bk1             ; not a page: nothing changed
            stb     curbank
            stb     ubank
bk1:        tfr     a,b
            clra
            rts

; B = page into the window, if it isn't there already.  Keeps B, X, Y, U.
setbank:    cmpb    curbank
            beq     sb9
            stb     curbank
            OS      SYS_BANK
sb9:        rts

; Put the program's page back in the window.  Keeps D, X, Y, U.
putback:    pshs    d
            ldb     ubank
            beq     pb9
            bsr     setbank
pb9:        puls    d,pc

; ---- the flash drive --------------------------------------------------

; Copy D bytes between RAM at X and the mailbox at U (VRAM page VF_BANK).
; Clobber A, B, X.
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

; Name at X -> VF_NAME (64 bytes at most).  Clobber A, B, X, U.
setname:    pshs    x
            ldd     #1              ; the length with its NUL
sn1:        tst     ,x+
            beq     sn2
            addd    #1
            bra     sn1
sn2:        cmpd    #64
            bls     sn3
            ldd     #64             ; cut: the command fails, it isn't ended
sn3:        puls    x
            ldu     #VF_NAME
            bra     vput

; ---- files ------------------------------------------------------------

; int remove(char *name): 0, or -1 if it couldn't be deleted
_remove:    pshs    u
            ldx     4,s
            lbsr    setname
            lda     #VCMD_FDELETE
            OS      SYS_FCMD
            bcs     rm1
            ldd     #0
            puls    u,pc
rm1:        ldd     #-1
            puls    u,pc

; FILE *fopen(char *name, char *mode): mode "r" or "w"
_fopen:     pshs    y,u
            ldy     #__iob+3*FSIZE  ; a free FILE
fo1:        tst     F_KIND,y
            beq     fo2
            leay    FSIZE,y
            cmpy    #__iob+NFILE*FSIZE
            blo     fo1
            lbra    fonull
fo2:        ldx     8,s
            lda     ,x
            cmpa    #'r
            beq     fo_r
            cmpa    #'w
            lbne    fonull
            tst     wopen           ; one file at a time for writing
            lbne    fonull
            ldx     6,s
            ldu     #wname
fow1:       lda     ,x+
            sta     ,u+
            beq     fow2
            cmpu    #wname+63
            blo     fow1
            clr     ,u
fow2:       lda     #K_WRITE
            sta     F_KIND,y
            sta     wopen
            lda     #PLAST
            sta     F_PAGE,y
            sta     wlow
            clr     F_EPAGE,y
            ldd     #WINDOW
            std     F_PTR,y
            lbra    fook

fo_r:       ldx     6,s
            lbsr    setname
            lda     #VCMD_FOPEN
            OS      SYS_FCMD
            lbcs    fonull
            lda     rpage           ; it starts at the pool top
            sta     F_SPAGE,y
            sta     F_PAGE,y
            ldd     raddr
            std     F_SPTR,y
            std     F_PTR,y
for1:       ldx     #zero2          ; VF_LEN = 0: 512 bytes
            ldu     #VF_LEN
            ldd     #2
            lbsr    vput
            lda     #VCMD_FREAD
            OS      SYS_FCMD
            bcs     forerr          ; (an error gives the drive back)
            cmpx    #0
            beq     for3
            ldb     rpage
            cmpb    wlow
            bhs     forful
            lbsr    setbank
            tfr     x,d
            pshs    d               ; the count
            ldx     raddr
            ldu     #VF_DATA
            lbsr    vget
            puls    d
            addd    raddr           ; reads are 512 bytes until the last,
            cmpd    #WINEND         ; so one never crosses $C000
            blo     for2
            subd    #WINEND-WINDOW
            inc     rpage
for2:       std     raddr
            bra     for1
for3:       lda     #VCMD_FCLOSE
            OS      SYS_FCMD
            lda     rpage           ; the end
            sta     F_EPAGE,y
            ldd     raddr
            std     F_EPTR,y
            addd    #511            ; the pool top, up to 512 bytes
            clrb
            anda    #$FE
            cmpd    #WINEND
            blo     for4
            ldd     #WINDOW
            inc     rpage
for4:       std     raddr
            lda     rpage
            sta     F_TPAGE,y
            ldd     raddr
            std     F_TPTR,y
            lda     #K_READ
            sta     F_KIND,y
            lbsr    putback
fook:       ldd     #-1
            std     F_UNGET,y
            tfr     y,d
            puls    y,u,pc
forful:     lda     #VCMD_FCLOSE    ; out of memory
            OS      SYS_FCMD
forerr:     lbsr    putback
            lda     F_SPAGE,y       ; give the pool back
            sta     rpage
            ldd     F_SPTR,y
            std     raddr
fonull:     ldd     #0
            puls    y,u,pc

; int fclose(FILE *f): 0, or EOF if a file being written couldn't be
; written whole
_fclose:    pshs    y,u
            ldy     6,s
            lda     F_KIND,y
            cmpa    #K_READ
            beq     fcr
            cmpa    #K_WRITE
            beq     fcw
            tsta
            bne     fcok            ; the console: nothing to do
            lbra    fcerr
fcr:        lda     F_TPAGE,y       ; the newest file: give its RAM back
            cmpa    rpage
            bne     fcr1
            ldd     F_TPTR,y
            cmpd    raddr
            bne     fcr1
            lda     F_SPAGE,y
            sta     rpage
            ldd     F_SPTR,y
            std     raddr
fcr1:       clr     F_KIND,y
fcok:       ldd     #0
            puls    y,u,pc

fcw:        clr     F_KIND,y
            clr     wopen
            lda     #PLAST+1
            sta     wlow
            ldx     #wname
            lbsr    setname
            lda     #VCMD_FCREATE
            OS      SYS_FCMD
            bcs     fcerr
            ldx     #WINDOW
            ldb     #PLAST
            pshs    b,x             ; 0,s page, 1,s address: what's written
fcw1:       ldb     ,s              ; bytes left on this page
            cmpb    F_PAGE,y
            bne     fcw2
            ldd     F_PTR,y
            subd    1,s
            beq     fcw9            ; all of it
            bra     fcw3
fcw2:       ldd     #WINEND
            subd    1,s
fcw3:       cmpd    #512
            bls     fcw4
            ldd     #512
fcw4:       std     wcnt
            ldb     ,s
            lbsr    setbank
            ldx     1,s
            ldu     #VF_DATA
            ldd     wcnt
            lbsr    vput
            ldx     #wcnt
            ldu     #VF_LEN
            ldd     #2
            lbsr    vput
            lda     #VCMD_FWRITE
            OS      SYS_FCMD
            bcs     fcwerr
            ldd     1,s
            addd    wcnt
            cmpd    #WINEND
            blo     fcw5
            ldd     #WINDOW
            dec     ,s
fcw5:       std     1,s
            bra     fcw1
fcw9:       leas    3,s
            lbsr    putback
            lda     #VCMD_FCLOSE
            OS      SYS_FCMD
            bcs     fcerr
            tst     F_EPAGE,y       ; did it all fit?
            lbeq    fcok
            bra     fcerr
fcwerr:     leas    3,s
            lbsr    putback
fcerr:      ldd     #-1
            puls    y,u,pc

; int fgetc(FILE *f): the next byte, or EOF
_fgetc:     ldx     2,s
            tst     F_UNGET,x
            bne     fg1
            ldd     F_UNGET,x       ; an ungetc'd character
            pshs    d
            ldd     #-1
            std     F_UNGET,x
            puls    d,pc
fg1:        lda     F_KIND,x
            cmpa    #K_READ
            beq     fgr
            cmpa    #K_CIN
            lbeq    _getchar
fgeof:      ldd     #-1
            rts
fgr:        pshs    y
            ldb     F_PAGE,x
            ldy     F_PTR,x
            cmpb    F_EPAGE,x
            bne     fgr1
            cmpy    F_EPTR,x
            beq     fgr3
fgr1:       bsr     setbank0
            lda     ,y+
            cmpy    #WINEND
            blo     fgr2
            ldy     #WINDOW
            inc     F_PAGE,x
fgr2:       sty     F_PTR,x
            tfr     a,b
            clra
            lbsr    putback
            puls    y,pc
fgr3:       ldd     #-1
            puls    y,pc
setbank0:   lbra    setbank

; int ungetc(int c, FILE *f): one character back
_ungetc:    ldd     2,s
            cmpd    #-1
            beq     ug9
            ldx     4,s
            clra
            std     F_UNGET,x
ug9:        rts

; int fputc(int c, FILE *f): c, or EOF
_fputc:     ldx     4,s
            lda     F_KIND,x
            cmpa    #K_WRITE
            beq     fpw
            cmpa    #K_COUT
            bne     fgeof
            ldd     2,s
            pshs    d
            lbsr    _putchar
            leas    2,s
            rts
fpw:        pshs    y
            ldb     F_PAGE,x
            cmpb    rpage
            bls     fpwful          ; full
            bsr     setbank0
            ldy     F_PTR,x
            lda     5,s
            sta     ,y+
            cmpy    #WINEND
            blo     fpw1
            bsr     wnext
fpw1:       sty     F_PTR,x
            lbsr    putback
            clra
            ldb     5,s
            puls    y,pc

fpwful:     lda     #1              ; lost
            sta     F_EPAGE,x
            bra     fgr3

; the file being written at X goes on to the next page down.  Y = $8000.
wnext:      ldy     #WINDOW
            dec     F_PAGE,x
            ldb     F_PAGE,x
            stb     wlow
            rts

; int fputs(char *s, FILE *f): 0, or EOF
_fputs:     pshs    y
            ldy     4,s
fps1:       ldb     ,y+
            beq     fps9
            clra
            ldx     6,s
            pshs    d,x
            bsr     _fputc
            leas    4,s
            cmpd    #-1
            bne     fps1
            puls    y,pc
fps9:       ldd     #0
            puls    y,pc

            ; size_t fread(void *buf, size_t size, size_t n, FILE *f): items read.
; buf must be below $8000 (the window holds the file).
_fread:     pshs    y,u
            ldx     8,s
            ldd     10,s
            lbsr    __mul           ; the bytes wanted
            pshs    d               ; 0,s left; buf 8,s size 10,s f 14,s
            ldu     8,s
            ldx     14,s
            lda     F_KIND,x
            cmpa    #K_READ
            bne     frw0
            ldd     ,s
            beq     frw8
            tst     F_UNGET,x
            bne     frd1
            lda     F_UNGET+1,x     ; an ungetc'd character first
            sta     ,u+
            ldd     #-1
            std     F_UNGET,x
            ldd     ,s
            subd    #1
            std     ,s
frd1:       ldy     F_PTR,x
frd2:       ldd     ,s
            beq     frd7
            ldb     F_PAGE,x
            cmpb    F_EPAGE,x
            bne     frd3
            cmpy    F_EPTR,x
            beq     frd7            ; the end of the file
frd3:       lbsr    setbank
            lda     ,y+
            sta     ,u+
            cmpy    #WINEND
            blo     frd4
            ldy     #WINDOW
            inc     F_PAGE,x
frd4:       ldd     ,s
            subd    #1
            std     ,s
            bra     frd2
frd7:       sty     F_PTR,x
            lbsr    putback
frw8:       tfr     u,d             ; bytes done / size
            subd    8,s
            ldx     10,s
            cmpx    #1
            beq     frw9
            exg     d,x
            lbsr    __divu
frw9:       leas    2,s
            puls    y,u,pc
frw0:       ldd     #0
            bra     frw9

; size_t fwrite(void *buf, size_t size, size_t n, FILE *f): items written.
; buf must be below $8000.
_fwrite:    pshs    y,u
            ldx     8,s
            ldd     10,s
            lbsr    __mul
            pshs    d
            ldu     8,s
            ldx     14,s
            lda     F_KIND,x
            cmpa    #K_COUT
            beq     fwc1
            cmpa    #K_WRITE
            bne     frw0
            ldy     F_PTR,x
fww1:       ldd     ,s
            beq     fww7
            ldb     F_PAGE,x
            cmpb    rpage
            bhi     fww3
            lda     #1              ; full: lost
            sta     F_EPAGE,x
            bra     fww7
fww3:       lbsr    setbank
            lda     ,u+
            sta     ,y+
            cmpy    #WINEND
            blo     fww2
            lbsr    wnext
fww2:       ldd     ,s
            subd    #1
            std     ,s
            bra     fww1
fww7:       sty     F_PTR,x
            lbsr    putback
            bra     frw8
fwc1:       ldd     ,s              ; the console
            beq     frw8
            ldb     ,u+
            clra
            pshs    d
            lbsr    _putchar
            leas    2,s
            ldd     ,s
            subd    #1
            std     ,s
            bra     fwc1

endsection
