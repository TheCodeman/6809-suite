; ----------------------------------------------------------------------
;  CRT0 - C startup for MINI09.  Link it first: LINK OUT.PRG
;  CRT0.O PROG.O LIBC.O, so its init section starts at $1000.
;
;  Zeroes bss, splits the shell's arguments into argc/argv, moves S onto the
;  program's own stack (the kernel's task stack is only 256 bytes),
;  calls main(argc, argv) and passes its result to exit().
; ----------------------------------------------------------------------

            include "syscalls.inc"

STKSIZE     equ     2048            ; the C stack
MAXARGV     equ     16              ; argv[0] (empty) + up to 15 words

            section init

            export  __start,__heap
            import  _main,_exit,s_bss,l_bss
            ifdef   BANKED
            export  __bcall,__bret
            import  _fopen,_fread,_fclose,_bank,_puts
            import  __rpage,__curbank,__ubank,__nbank
            endc

__start:    ldx     #s_bss          ; zero bss, on the kernel's stack
            ldy     #l_bss
            beq     st2
st1:        clr     ,x+
            leay    -1,y
            bne     st1
st2:        lds     #stktop
            ldd     #s_bss          ; malloc's RAM starts after bss
            addd    #l_bss
            std     __heap
            ldx     #argtext        ; save the shell's arguments, if there are any
            ldd     ARGS
            cmpd    #ARGMARK
            bne     st4
            clr     ARGS            ; seen: a later start mustn't see them
            ifdef   BANKED
            inc     gotargs
            endc
            ldu     #ARGS+2
            ldb     #ARGMAX
st3:        lda     ,u+
            sta     ,x+
            beq     st4
            decb
            bne     st3
st4:        clr     ,x              ; (no-op if a NUL was copied)
            ldx     #argtext        ; split at spaces into argv[1..]
            ldu     #argv
            ldd     #empty
            std     ,u++            ; argv[0] = "": the name isn't known
            ldy     #1              ; argc
st5:        lda     ,x              ; skip spaces
            beq     st8
            cmpa    #$20
            bne     st6
            leax    1,x
            bra     st5
st6:        cmpy    #MAXARGV
            bhs     st8
            stx     ,u++            ; a word starts here
            leay    1,y
st7:        lda     ,x+             ; find its end
            beq     st8
            cmpa    #$20
            bne     st7
            clr     -1,x            ; end the word
            bra     st5
st8:        clr     ,u              ; argv[argc] = NULL
            clr     1,u
            ifdef   BANKED
            pshs    y
            lbsr    bload           ; the code banks, before main
            puls    y
            endc
            ldd     #argv
            pshs    d
            tfr     y,d
            pshs    d
            ldu     #0              ; no frame above main
            jsr     _main
            leas    4,s
            pshs    d               ; exit(result)
            jsr     _exit
            OS      SYS_EXIT        ; (exit doesn't come back)

empty:      fcb     0

            ifdef   BANKED
; ----------------------------------------------------------------------
;  Banked code (cc.md): crt0b.asm is this file with BANKED defined.
;
;  LINK puts each object's "banked" section in a RAM page from FIRSTBANK
;  up, at $8000-$BFFF, and appends the pages to the .PRG after the normal
;  part: "B9", the count, then for each page its number, length (2) and
;  bytes.  The shell loads only the normal part.  bload reads the rest
;  from the same file, whose path the shell still holds in fname while
;  it waits for the program to end.
;
;  A call into a bank goes through a stub in common memory:
;      _name   jsr     __bcall
;              fcb     __bank          ; the page (LINK)
;              fdb     B_name          ; the function, in the bank
;  __bcall keeps the stack as a normal call has it (arguments at 4,u in
;  the callee), saves the caller's return address and page on its own
;  stack, and returns through __bret, which switches back.  The window is
;  switched by writing the MMU and the task's page in its TCB directly
;  (about 70 cycles; SYS_BANK costs about 300), with IRQ masked so a task
;  switch can't come between the two.
; ----------------------------------------------------------------------
FIRSTBANK   equ     7
DEFPAGE     equ     2
FNAME       equ     $0258           ; os.asm: the shell's file name
CURTCB      equ     $01             ; os.asm: -> the running task's TCB
TCB_PAGE    equ     1               ; os.asm: its page in the window
MMU_WIN2    equ     $D802           ; os.asm: the window's page register
BSTKN       equ     128             ; banked calls in progress, at most
CHUNK       equ     256

bload:      tst     gotargs         ; started by the shell: fname is the path
            lbeq    bl_err
            ldb     #FIRSTBANK      ; files are read above the banks
            addb    #__nbank
            stb     __rpage
            ldx     #s_r
            pshs    x
            ldx     #FNAME
            pshs    x
            jsr     _fopen
            leas    4,s
            std     bfile
            lbeq    bl_err
            ldd     #36             ; the header
            lbsr    bread
            cmpd    #36
            lbne    bl_err
            ldd     bbuf+28         ; skip the normal part
            subd    #36
            std     bleft
bl1:        ldd     bleft
            beq     bl2
            lbsr     bchunk
            lbsr    bread
            lbeq     bl_err
            ldd     bleft
            subd    bgot
            std     bleft
            bra     bl1
bl2:        ldd     #3              ; "B9", the count
            lbsr    bread
            cmpd    #3
            lbne     bl_err
            ldd     bbuf
            cmpd    #$4239
            lbne     bl_err
            lda     bbuf+2
            sta     bcnt
bl3:        ldd     #3              ; a page: its number and length
            lbsr    bread
            cmpd    #3
            lbne     bl_err
            lda     bbuf
            sta     bpage
            ldd     bbuf+1
            std     bleft
            ldd     #$8000
            std     bdest
bl4:        ldd     bleft           ; its bytes, CHUNK at a time
            beq     bl6
            lbsr     bchunk
            lbsr    bread
            lbeq     bl_err
            ldb     bpage           ; into the page (fread puts it back)
            clra
            pshs    d
            jsr     _bank
            leas    2,s
            ldx     #bbuf
            ldy     bdest
            ldd     bgot
bl5:        pshs    d
            lda     ,x+
            sta     ,y+
            puls    d
            subd    #1
            bne     bl5
            sty     bdest
            ldd     bleft
            subd    bgot
            std     bleft
            bra     bl4
bl6:        dec     bcnt
            bne     bl3
            ldd     #DEFPAGE        ; the window as it was
            pshs    d
            jsr     _bank
            leas    2,s
            clr     __ubank
            ldd     bfile
            pshs    d
            jsr     _fclose
            leas    2,s
            ldx     #bstk
            stx     bsp
            rts
bl_err:     ldx     #s_noload
            pshs    x
            jsr     _puts
            ldd     #1
            pshs    d
            jsr     _exit

; D = the smaller of bleft and CHUNK
bchunk:     ldd     bleft
            cmpd    #CHUNK
            bls     bc9
            ldd     #CHUNK
bc9:        rts

; Read D bytes into bbuf -> D = bgot, the bytes read (Z if none)
bread:      ldx     bfile
            pshs    x
            pshs    d
            ldd     #1
            pshs    d
            ldx     #bbuf
            pshs    x
            jsr     _fread
            leas    8,s
            std     bgot
            rts

; The stub's jsr: [S] -> its page and the function's address
__bcall:    puls    x
            ldy     bsp
            cmpy    #bstkend
            bhs     bc_full
            ldd     ,s              ; the caller's return address
            std     ,y
            pshs    x
            ldx     <CURTCB
            lda     TCB_PAGE,x      ; the window now, and LIBC's page
            ldb     __ubank
            std     2,y
            leay    4,y
            sty     bsp
            puls    x
            ldd     #__bret         ; the function returns to __bret
            std     ,s
            lda     ,x              ; the function's page
            sta     __curbank
            sta     __ubank
            ldy     <CURTCB
            orcc    #$10
            sta     TCB_PAGE,y
            sta     MMU_WIN2
            andcc   #$EF
            jmp     [1,x]
bc_full:    ldx     #s_deep
            pshs    x
            jsr     _puts
            ldd     #1
            pshs    d
            jsr     _exit

; Back from a banked function: the caller's page, then its return
; address.  Keeps D and X (the result).
__bret:     pshs    d,x
            ldy     bsp
            leay    -4,y
            sty     bsp
            ldd     2,y
            stb     __ubank
            sta     __curbank
            ldx     <CURTCB
            orcc    #$10
            sta     TCB_PAGE,x
            sta     MMU_WIN2
            andcc   #$EF
            ldy     ,y
            puls    d,x
            jmp     ,y

s_r:        fcn     "r"
s_noload:   fcn     "Can't load the code banks"
s_deep:     fcn     "Banked calls nested too deep"
            endc

            endsection

            section bss
__heap:     rmb     2               ; char *_heap: the end of the program
argtext:    rmb     ARGMAX+1
argv:       rmb     MAXARGV*2+2     ; (no parentheses: see cc.md)
stack:      rmb     STKSIZE
stktop:
            ifdef   BANKED
gotargs:    rmb     1               ; started by the shell
bfile:      rmb     2
bleft:      rmb     2
bgot:       rmb     2
bdest:      rmb     2
bcnt:       rmb     1
bpage:      rmb     1
bbuf:       rmb     CHUNK
bsp:        rmb     2
bstk:       rmb     BSTKN*4
bstkend:
            endc
            endsection
