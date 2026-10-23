; LIBC test: arguments, string.h, files.  Run by tools/iotest.py as
; IOTEST ONE TWO THREE, with IN.TXT, INC.TXT and BIG.TXT on the
; drive; prints what tests/rt/iotest.out holds and writes OUT.TXT and
; BIG2.TXT.

            section code
            export  _main
            import  _putchar,_puts,_fopen,_fclose,_fgetc,_fputc,_fputs,_ungetc
            import  _strlen,_strcpy,_strcat,_strcmp,_strncmp,_strchr,_strrchr
            import  _memcpy,_memmove,_memset,_memcmp,__iob

; call f(a, b, c): push the arguments right to left, call, pop
CALL1       macro
            ldd     \2
            pshs    d
            jsr     \1
            leas    2,s
            endm
CALL2       macro
            ldd     \3
            pshs    d
            ldd     \2
            pshs    d
            jsr     \1
            leas    4,s
            endm
CALL3       macro
            ldd     \4
            pshs    d
            ldd     \3
            pshs    d
            ldd     \2
            pshs    d
            jsr     \1
            leas    6,s
            endm

; fputc(D, FILE in \1)
PUTC        macro
            ldx     \1
            pshs    d,x
            jsr     _fputc
            leas    4,s
            endm

; main(argc, argv): 4,u argc, 6,u argv after the frame
_main:      pshs    u
            tfr     s,u

; ---- arguments
            ldd     4,u
            jsr     phex4
            ldx     6,u
            leax    2,x             ; argv[1..]
ar1:        ldd     ,x++
            beq     ar2
            pshs    x
            pshs    d
            jsr     _puts
            leas    2,s
            puls    x
            bra     ar1

; ---- string.h
ar2:        CALL1   _strlen,#hello
            jsr     phex4                   ; 000B
            CALL2   _strcpy,#buf,#hello
            CALL1   _puts,#buf              ; hello world
            CALL2   _strcat,#buf,#bang
            CALL1   _puts,#buf              ; hello world!
            CALL2   _strcmp,#hello,#buf
            jsr     phex4                   ; FFDF (0 - '!')
            CALL2   _strcmp,#buf,#hello
            jsr     phex4                   ; 0021
            CALL2   _strcmp,#hello,#hello2
            jsr     phex4                   ; 0000
            CALL3   _strncmp,#hello,#buf,#11
            jsr     phex4                   ; 0000
            CALL3   _strncmp,#hello,#helpme,#4
            jsr     phex4                   ; FFFC ('l' - 'p')
            CALL2   _strchr,#hello,#'o
            subd    #hello
            jsr     phex4                   ; 0004
            CALL2   _strrchr,#hello,#'o
            subd    #hello
            jsr     phex4                   ; 0007
            CALL2   _strchr,#hello,#'z
            jsr     phex4                   ; 0000
            CALL2   _strchr,#hello,#0
            subd    #hello
            jsr     phex4                   ; 000B
            CALL3   _memset,#buf,#'-,#5
            CALL1   _puts,#buf              ; -----world!
            CALL3   _memcpy,#buf,#hello,#5
            CALL1   _puts,#buf              ; hello world!
            CALL3   _memmove,#buf+1,#buf,#5
            CALL1   _puts,#buf              ; hhellorld!   (h e l l o shifted)
            CALL3   _memmove,#buf,#buf+1,#5
            CALL1   _puts,#buf              ; hellooorld!
            CALL3   _memcmp,#buf,#hello,#5
            jsr     phex4                   ; 0000
            CALL3   _memcmp,#buf,#hello,#6
            jsr     phex4                   ; 004F ('o' - ' ')

; ---- files: copy IN.TXT to OUT.TXT, upper case, and read INC.TXT in
; the middle (a second file open for reading while one is being written)
            CALL2   _fopen,#outtxt,#modew
            std     fout
            jsr     phex4nz                 ; 1 if it opened
            CALL2   _fopen,#intxt,#moder
            std     fin
            jsr     phex4nz
            CALL2   _fopen,#outtxt,#modew   ; a second one for writing: NULL
            jsr     phex4nz
            CALL2   _fopen,#nofile,#moder   ; no such file: NULL
            jsr     phex4nz
fc1:        CALL1   _fgetc,fin
            cmpd    #-1
            beq     fc3
            cmpb    #'#                     ; '#': copy INC.TXT here
            bne     fc2
            lbsr    doinc
            bra     fc1
fc2:        cmpb    #'a
            blo     fc2a
            cmpb    #'z
            bhi     fc2a
            subb    #$20
fc2a:       PUTC    fout
            bra     fc1
fc3:        CALL1   _fclose,fin
            jsr     phex4                   ; 0000
            CALL2   _fputs,#tail,fout
            CALL1   _fclose,fout
            jsr     phex4                   ; 0000
            CALL2   _fputs,#tail,#__iob+15  ; to stdout
            ldd     #10
            pshs    d
            jsr     _putchar
            leas    2,s
; read OUT.TXT back
            CALL2   _fopen,#outtxt,#moder
            std     fin
fc4:        CALL1   _fgetc,fin
            cmpd    #-1
            beq     fc5
            pshs    d
            jsr     _putchar
            leas    2,s
            bra     fc4
fc5:        CALL2   _ungetc,#'Q,fin         ; ungetc after the end
            CALL1   _fgetc,fin
            jsr     phex4                   ; 0051
            CALL1   _fgetc,fin
            jsr     phex4                   ; FFFF
            CALL1   _fclose,fin

; ---- a file bigger than one 16K page, copied byte for byte
            CALL2   _fopen,#bigtxt,#moder
            std     fin
            CALL2   _fopen,#big2txt,#modew
            std     fout
bg1:        CALL1   _fgetc,fin
            cmpd    #-1
            beq     bg2
            PUTC    fout
            bra     bg1
bg2:        CALL1   _fclose,fin
            CALL1   _fclose,fout
            jsr     phex4                   ; 0000
            CALL1   _puts,#done
            ldd     #0
            puls    u,pc

doinc:      CALL2   _fopen,#inctxt,#moder
            pshs    d
di1:        ldd     ,s
            pshs    d
            jsr     _fgetc
            leas    2,s
            cmpd    #-1
            beq     di2
            PUTC    fout
            bra     di1
di2:        jsr     _fclose                 ; the FILE is at 0,s: an argument
            leas    2,s
            rts

; print D as 4 hex digits; phex4nz prints 0001 for anything not 0
phex4nz:    cmpd    #0
            beq     phex4
            ldd     #1
phex4:      pshs    d
            jsr     phex2
            puls    d
            tfr     b,a
            jsr     phex2
            ldd     #10
            bra     pch
phex2:      pshs    a
            lsra
            lsra
            lsra
            lsra
            jsr     phex1
            puls    a
            anda    #15
phex1:      adda    #'0
            cmpa    #'9
            bls     ph1
            adda    #7
ph1:        tfr     a,b
            clra
pch:        pshs    d
            jsr     _putchar
            leas    2,s
            rts

hello:      fcn     "hello world"
hello2:     fcn     "hello world"
helpme:     fcn     "help"
bang:       fcn     "!"
tail:       fcn     "the end"
done:       fcn     "done"
intxt:      fcn     "IN.TXT"
inctxt:     fcn     "INC.TXT"
outtxt:     fcn     "OUT.TXT"
bigtxt:     fcn     "BIG.TXT"
big2txt:    fcn     "BIG2.TXT"
nofile:     fcn     "NOFILE.TXT"
moder:      fcn     "r"
modew:      fcn     "w"
            endsection

            section bss
buf:        rmb     64
fin:        rmb     2
fout:       rmb     2
            endsection
