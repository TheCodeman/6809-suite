; Example user program for MINI09.
; Load it with the shell's L command (paste hello.s19), then: G 1000
; It talks to the kernel only through system calls.

            include "syscalls.inc"

            org     $1000
start:      lda     #3              ; B = our pid, set up by the kernel
            pshs    a,b             ; 0,s = lines left, 1,s = pid
h1:         ldx     #msg
h2:         lda     ,x+
            beq     h3
            OS      SYS_PUTC
            bra     h2
h3:         lda     1,s
            adda    #'0
            OS      SYS_PUTC
            lda     #CR
            OS      SYS_PUTC
            lda     #LF
            OS      SYS_PUTC
            ldd     #50             ; half a second
            OS      SYS_SLEEP
            dec     ,s
            bne     h1
            OS      SYS_EXIT

msg:        fcn     "Hello from a loaded program, I am task "

            end     start
