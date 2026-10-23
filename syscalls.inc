; ----------------------------------------------------------------------
;  MINI09 system call interface
;
;  A system call is a SWI followed by a one-byte function code:
;          swi
;          fcb   SYS_xxx
;  Arguments are passed in registers; results come back in registers.
;  All registers not listed as outputs are preserved.  Carry set = error.
; ----------------------------------------------------------------------

SYS_EXIT    equ     0       ; terminate calling task
SYS_PUTC    equ     1       ; A = char to send to console
SYS_GETC    equ     2       ; -> A = char (blocks until one arrives)
SYS_YIELD   equ     3       ; give up rest of time slice
SYS_SLEEP   equ     4       ; D = ticks to sleep (100 ticks/s)
SYS_SPAWN   equ     5       ; X = entry point -> B = new pid, C=1 if full
SYS_KILL    equ     6       ; B = pid to kill, C=1 if no such task
SYS_GETPID  equ     7       ; -> B = own pid
SYS_TIME    equ     8       ; -> D = tick counter, X = seconds up
SYS_BANK    equ     9       ; B = RAM page 2-31 for $8000-$BFFF ($FF = ask)
                            ; -> A = previous page, C=1 if B is invalid

; Video/sound chip calls (vdp.inc has the register numbers).  All return
; C=1 when no chip is fitted.
SYS_VSYNC   equ     10      ; wait for the next video frame -> D = frame count
SYS_SOUND   equ     11      ; A = value, B = sound register (0-13 AY, 14 DAC,
                            ; 15 master volume)
SYS_VREG    equ     12      ; B = video register, A = value; B+VREG_RD reads
                            ; -> A (STATUS can't be read: the kernel owns it)
SYS_VCOPY   equ     13      ; X -> block: VRAM address (3 bytes, high first),
                            ; source address (2), byte count (2).  The block
                            ; is used up: address/source advance, count -> 0
SYS_VREAD   equ     14      ; same block, copies VRAM to RAM
SYS_FCMD    equ     15      ; A = file command (VCMD_Fxxx in vdp.inc) on the
                            ; USB flash drive, mailbox filled with SYS_VCOPY
                            ; -> A = result (0 OK), X = byte count, C=1 if
                            ; A is not 0.  Waits while the drive is busy or
                            ; another task has a file open.  The drive is
                            ; yours from the first call until FCLOSE,
                            ; FDELETE or an error
SYS_POLL    equ     16      ; -> A = char if one is waiting, else C=1
SYS_BREAK   equ     17      ; C=0 if a ^C was typed: the input up to and
                            ; including it is dropped.  C=1 if not

; A program's arguments: the shell puts ARGMARK at ARGS, then the text after the file
; name (NUL-terminated, up to ARGMAX characters).  A program that uses
; them should clear ARGMARK so a later start doesn't see them again.
ARGS        equ     $0E00
ARGMARK     equ     $A55A
ARGMAX      equ     62

CR          equ     $0D
LF          equ     $0A
BS          equ     $08
DEL         equ     $7F
ESC         equ     $1B

OS          macro
            swi
            fcb     \1
            endm
