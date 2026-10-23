; ======================================================================
;  MINI09 - a small preemptive multitasking operating system for the
;           Motorola 6809 / Hitachi 6309
;
;  Features
;    * up to 8 tasks, round-robin preemptive scheduling (100 Hz tick)
;    * system calls through SWI + function code byte
;    * interrupt-driven console input with blocking GETC
;    * sleeping tasks, spawn / kill / exit
;    * built-in shell: PS, memory dump/write, S-record loader, ...
;    * DS1232 watchdog strobed from the system tick (DUART OP1, JP2 1-2)
;    * banked RAM: a 74HC670 MMU maps each 16K window to one of 32 pages;
;      every task has its own page in the $8000-$BFFF window
;    * 6309 trap (illegal opcode / divide by zero) kills only the
;      offending task; the shell is restarted if it was the culprit
;    * with the Pico video chip: HDMI console, USB keyboard input and
;      files on a USB flash drive (DIR, TYPE, LOAD, SAVE, DEL)
;      and runs any program file on it by name (NAME runs NAME.PRG)
;
;  The CPU is an HD63C09E.  After reset the 6309 is in 6809 emulation
;  mode, so the kernel is plain 6809 code and the 12-byte interrupt frame
;  layout below holds.  (Native mode would push W as well.)
;
;  Target hardware (any 6809 board with these parts will do)
;    $0000-$BFFF  RAM
;    $C000-$C00F  SCN2681 DUART (28-pin SCN2681AC1N28), 3.6864 MHz crystal
;                 (mirrored to $C7FF)
;                 channel A = console, 9600 8N1, OP0 = RTS for channel A
;                 counter/timer = 100 Hz system tick
;                 /INTR -> 6809 /IRQ
;    $C800-$CFFF  expansion /EXPCS1 (J4 pin 33): optional Pico 6809
;                 video/sound chip (HDMI, see vdp.inc).  If it answers at
;                 boot, the console is mirrored to the HDMI screen and
;                 its vblank interrupt (shared /IRQ) drives SYS_VSYNC.
;                 Its USB keyboard feeds console input next to the DUART,
;                 and its flash drive answers SYS_FCMD
;    $D800-$D803  MMU page registers (write only; bits 0-3 in a 74HC670,
;                 bit 4 in the ATF750C): register n
;                 holds the 16K SRAM page (0-31) for CPU window n
;                 ($0000, $4000, $8000, $C000)
;    $E000-$FFFF  ROM           (this code)
;
;  Assemble:  lwasm --format=srec -o os.s19 os.asm
; ======================================================================

            include "syscalls.inc"
            include "vdp.inc"

; ---- hardware --------------------------------------------------------
DUART       equ     $C000
MMU_REG     equ     $D800           ; 4 page registers, write only
MMU_WIN2    equ     MMU_REG+2       ; page for the $8000-$BFFF window
DEFPAGE     equ     2               ; identity page for that window
MAXPAGE     equ     31              ; 32 pages x 16K = 512K
; Console (make CONSOLE=...): both (default) the serial port and the video
; card's HDMI screen and USB keyboard; serial (-D CON_SERIAL) the serial
; port only, the card still there for graphics, sound and files; vdc
; (-D CON_VDC) the card's screen and keyboard, output not waiting for the
; 9600-baud DUART, falling back to serial if no card answers at boot.
            ifdef   CON_SERIAL
KCTRL       equ     VC_IRQEN|VC_FILEIRQ     ; no key interrupts
            else
KCTRL       equ     VC_KERNEL
            endc

ROMPAGE     equ     $80             ; "page" for the ROM bank (28C256 $0000)
ROMBAS      equ     $8000           ; a BASIC there starts "BA", entry $8002
DU_MRA      equ     DUART+$0        ; MR1A/MR2A (via MR pointer)
DU_SRA      equ     DUART+$1        ; read: status A
DU_CSRA     equ     DUART+$1        ; write: clock select A
DU_CRA      equ     DUART+$2        ; write: command A
DU_RHRA     equ     DUART+$3        ; read: receive holding A
DU_THRA     equ     DUART+$3        ; write: transmit holding A
DU_ACR      equ     DUART+$4        ; write: auxiliary control
DU_ISR      equ     DUART+$5        ; read: interrupt status
DU_IMR      equ     DUART+$5        ; write: interrupt mask
DU_CTUR     equ     DUART+$6        ; write: counter/timer preload MSB
DU_CTLR     equ     DUART+$7        ; write: counter/timer preload LSB
DU_STARTCT  equ     DUART+$E        ; read: start counter command
DU_OPSET    equ     DUART+$E        ; write: set OP bits (pin goes low)
DU_STOPCT   equ     DUART+$F        ; read: stop counter (timer mode:
                                    ;       just clears ISR bit 3)
DU_OPRESET  equ     DUART+$F        ; write: reset OP bits (pin goes high)

SR_RXRDY    equ     $01
SR_TXRDY    equ     $04
ISR_RXRDYA  equ     $02
ISR_CTR     equ     $08
OP_RTSA     equ     $01             ; OP0 drives RTS for channel A
OP_WDOG     equ     $02             ; OP1 strobes the DS1232 watchdog

XTAL        equ     3686400
TICK_HZ     equ     100
CT_PRELOAD  equ     XTAL/(2*TICK_HZ)  ; timer square wave = 2*preload clocks

; ---- task control blocks ---------------------------------------------
MAXTASK     equ     8
TCBSZ       equ     8
TCB_STATE   equ     0               ; one of TS_xxx
TCB_PAGE    equ     1               ; RAM page in the $8000-$BFFF window
TCB_SP      equ     2               ; saved stack pointer
TCB_WAKE    equ     4               ; ticks left to sleep
TCB_ENT     equ     6               ; entry point (for PS)

TS_FREE     equ     0
TS_READY    equ     1
TS_SLEEP    equ     2
TS_WAITIN   equ     3
TS_WAITVB   equ     4               ; waiting for the next video frame
TS_WAITIO   equ     5               ; waiting for the flash drive

; ---- RAM layout (kernel variables live in the direct page) -----------
curtask     equ     $00             ; running task number
curtcb      equ     $01             ; -> running task's TCB
ticks       equ     $03             ; 16-bit tick counter
subtick     equ     $05             ; 0..TICK_HZ-1
uptime      equ     $06             ; seconds since boot
rxhead      equ     $08             ; input ring buffer write index
rxtail      equ     $09             ; input ring buffer read index
schcnt      equ     $0A             ; scheduler loop counter
ktmp        equ     $0B             ; mktask scratch
rxthrot     equ     $0E             ; non-zero while RTS is dropped
kent        equ     $0C             ; mktask scratch (2)
vdpok       equ     $0F             ; non-zero: video chip present
frames      equ     $10             ; 16-bit video frame counter
vbwoke      equ     $12             ; this IRQ woke a task that should run now
fowner      equ     $13             ; task using the flash drive, 0 = none,
                                    ; $FF = its owner died mid-command
fstate      equ     $14             ; 0 idle, 1 command running, 2 done
vstat       equ     $15             ; video chip STATUS read by this IRQ
tcbs        equ     $20             ; MAXTASK*TCBSZ bytes
rxbuf       equ     $0100           ; console input ring buffer
RXSIZE      equ     64
RX_STOP     equ     RXSIZE-16       ; drop RTS above this many chars
RX_GO       equ     16              ; raise it again below this

; Shell work area
linebuf     equ     $0200
LINEMAX     equ     60
hexv        equ     $0240
hexn        equ     $0242
dcnt        equ     $0243
dflag       equ     $0244
cksum       equ     $0245
lcount      equ     $0246
laddr       equ     $0247
hbtmp       equ     $0249
dumpaddr    equ     $024A
dlines      equ     $024C
mypid       equ     $024D
vblk        equ     $0250           ; SYS_VCOPY/VREAD block (7 bytes)
fname       equ     $0258           ; file name (64 bytes)
fcnt        equ     $0298           ; bytes in fbuf
fpos        equ     $029A           ; read / write index in fbuf
lsave       equ     $029C           ; S to unwind to on a file error
lgetv       equ     $029E           ; S-record loader input routine
svend       equ     $02A0           ; SAVE end address
mbox        equ     $02A3           ; copy of VF_NAME..VF_ATTR (72 bytes)
fbuf        equ     $0C00           ; file data buffer (512 bytes, to $0DFF)
runln       equ     $0300           ; a program's command line, with .PRG (to $0347)
TAB         equ     $09

; Task n uses the 256-byte stack $0400+n*$100 .. $04FF+n*$100
STACKPAGE   equ     $04

; ======================================================================
            org     $E000
; ======================================================================

; ----------------------------------------------------------------------
;  Cold start
; ----------------------------------------------------------------------
reset:      orcc    #$50            ; no interrupts while we set up
            clra                    ; the 74HC670 powers up with random
            sta     MMU_REG         ; contents: map pages 0, 1, 2 to
            inca                    ; $0000, $4000, $8000 before any RAM
            sta     MMU_REG+1       ; access (the stack included)
            inca
            sta     MMU_REG+2
            clrb                    ; ROM bank off ($D803 bit 4)
            stb     MMU_REG+3
            lds     #$0400          ; boot stack, below the task stacks
            clra
            tfr     a,dp
            ldx     #0              ; clear kernel direct page
rz1:        clr     ,x+
            cmpx    #$0100
            blo     rz1

            clr     DU_IMR          ; DUART: no interrupts yet
            lda     #$20            ; reset receiver A
            sta     DU_CRA
            lda     #$30            ; reset transmitter A
            sta     DU_CRA
            lda     #$40            ; reset error status A
            sta     DU_CRA
            lda     #$10            ; point at MR1A
            sta     DU_CRA
            lda     #$13            ; MR1A: no parity, 8 bits, IRQ on RxRDY
            sta     DU_MRA
            lda     #$07            ; MR2A: normal mode, 1 stop bit
            sta     DU_MRA
            lda     #$E0            ; ACR: BRG set 2, timer mode, X1 clock
            sta     DU_ACR
            lda     #$BB            ; CSRA: 9600 baud receive and transmit
            sta     DU_CSRA
            ldd     #CT_PRELOAD     ; 100 Hz tick
            sta     DU_CTUR
            stb     DU_CTLR
            lda     DU_STARTCT      ; start the counter/timer
            lda     #$05            ; CRA: enable receiver and transmitter
            sta     DU_CRA
            lda     #OP_RTSA        ; assert RTS: ready to receive
            sta     DU_OPSET
            lda     #ISR_RXRDYA|ISR_CTR
            sta     DU_IMR

            bsr     vdp_init

            ldx     #banner
            bsr     kputs

            clrb                    ; task 0: idle
            ldx     #idle
            bsr     mktask
            ldb     #1              ; task 1: shell
            ldx     #shell
            bsr     mktask          ; X -> shell's TCB
            ldb     #1
            stb     curtask
            stx     curtcb
            lds     TCB_SP,x
            rti                     ; drop into the shell

; Polled output, used before multitasking starts and by the trap handler
kputs:      lda     ,x+
            beq     kp2
            bsr     kputc
            bra     kputs
kp2:        rts

kputc:
            ifdef   CON_VDC
            tst     vdpok           ; the HDMI screen, if there is one
            beq     kpc0
            sta     VDP+V_TERM
            rts
kpc0:
            endc
            ldb     DU_SRA
            bitb    #SR_TXRDY
            beq     kpc0b
            sta     DU_THRA
            ifndef  CON_SERIAL
            ifndef  CON_VDC
            tst     vdpok           ; and on the HDMI screen
            beq     kpc1
            sta     VDP+V_TERM
            endc
            endc
kpc1:       rts
kpc0b:      bra     kputc

; Look for the video chip.  It may still be starting up after power-on
; (the DS1232 holds reset for >= 250 ms), so keep asking for ~0.2 s; that
; stays well inside the watchdog's 0.5 s minimum.
vdp_init:   ldx     #36000          ; ~22 cycles per try (ROM waits), 3.69 MHz
vi1:        lda     VDP+V_ID
            cmpa    #VDP_IDV
            beq     vi2
            leax    -1,x
            bne     vi1
            rts                     ; not fitted
vi2:        lda     #VCMD_RESET     ; 80x30 text, cleared, cursor home
            sta     VDP+V_CMD
            lda     #VC_DISPLAY|KCTRL
            sta     VDP+V_CTRL
            inc     vdpok
            rts

; ----------------------------------------------------------------------
;  mktask - build a task in slot B starting at X
;  The new stack holds a full RTI frame so the scheduler can start the
;  task exactly like it resumes a preempted one.  Below the frame sits
;  task_exit, so a task that returns with RTS terminates cleanly.
;  Out: X -> TCB.  Clobbers A,B,U.  Interrupts must be masked.
; ----------------------------------------------------------------------
mktask:     stb     ktmp
            stx     kent
            tfr     b,a
            adda    #STACKPAGE+1
            clrb
            tfr     d,u             ; U = top of this task's stack
            ldd     #task_exit
            std     ,--u            ; return address for final RTS
            ldd     kent
            std     ,--u            ; PC
            clra
            clrb
            std     ,--u            ; U
            std     ,--u            ; Y
            std     ,--u            ; X
            sta     ,-u             ; DP = 0
            ldb     ktmp
            std     ,--u            ; A = 0, B = own pid
            lda     #$80            ; CC: E set, interrupts enabled
            sta     ,-u
            lda     #TCBSZ
            mul
            addd    #tcbs
            tfr     d,x
            stu     TCB_SP,x
            ldd     kent
            std     TCB_ENT,x
            clr     TCB_WAKE,x
            clr     TCB_WAKE+1,x
            lda     #DEFPAGE
            sta     TCB_PAGE,x
            lda     #TS_READY
            sta     TCB_STATE,x
            rts

task_exit:  OS      SYS_EXIT

; Map page A at $8000-$BFFF: RAM page 2-31, or ROMPAGE for the ROM bank
; (bit 4 of the $D803 write, the CPLD's PG3).
setwin:     sta     MMU_WIN2
            anda    #ROMPAGE
            lsra
            lsra
            lsra
            sta     MMU_REG+3
            rts

; ----------------------------------------------------------------------
;  Scheduler.  Entered with a complete interrupt frame (E=1) on the
;  current task's stack - either from the IRQ handler or a system call.
;  Saves S, picks the next READY task round-robin (tasks 1..7) and
;  resumes it with RTI.  If nothing is ready, runs the idle task (0).
; ----------------------------------------------------------------------
schedule:   ldx     curtcb
            sts     TCB_SP,x
sc_pick:    ldx     curtcb          ; entry without saving S (trap handler)
            lda     #MAXTASK-1
            sta     schcnt
            ldb     curtask
sc1:        incb
            leax    TCBSZ,x
            cmpb    #MAXTASK
            blo     sc2
            ldb     #1
            ldx     #tcbs+TCBSZ
sc2:        lda     TCB_STATE,x
            cmpa    #TS_READY
            beq     sc3
            dec     schcnt
            bne     sc1
            clrb                    ; nothing ready: idle
            ldx     #tcbs
sc3:        stb     curtask
            stx     curtcb
            lda     TCB_PAGE,x      ; switch in this task's banked page
            bsr     setwin
            lds     TCB_SP,x
            rti

; ----------------------------------------------------------------------
;  IRQ: console receive and the system tick
; ----------------------------------------------------------------------
irq_h:      clra
            tfr     a,dp
            clr     vbwoke
            lda     DU_SRA
            bita    #SR_RXRDY       ; anything in the receive FIFO?
            beq     irq_vdp
irq_rx:     ldb     DU_RHRA
            jsr     rx_put
            lda     DU_SRA          ; drain the whole FIFO (up to 3 chars)
            bita    #SR_RXRDY
            bne     irq_rx
            lda     #TS_WAITIN      ; wake every task waiting for input
            jsr     wake

irq_vdp:    tst     vdpok           ; video chip: vblank, key, file done?
            beq     irq_tmr
            lda     VDP+V_STATUS    ; reading it clears the vblank and
            sta     vstat           ; file done flags
            bpl     iv_key
            ldd     frames
            addd    #1
            std     frames
            ldx     #tcbs           ; wake the SYS_VSYNC waiters, with
iv1:        lda     TCB_STATE,x     ; D = frame count in their frames
            cmpa    #TS_WAITVB
            bne     iv2
            lda     #TS_READY
            sta     TCB_STATE,x
            ldu     TCB_SP,x
            ldd     frames
            std     1,u
            inc     vbwoke
iv2:        leax    TCBSZ,x
            cmpx    #tcbs+MAXTASK*TCBSZ
            blo     iv1

iv_key:     lda     vstat           ; USB keyboard: one key per interrupt,
            bita    #VS_KEY         ; /IRQ stays low while more are waiting
            beq     iv_file
            ldb     VDP+V_CTRL      ; but only while key interrupts are on
            bitb    #VC_KEYIRQ      ; (off: input full, or a serial build)
            beq     iv_file
            ldb     VDP+V_KEY
            beq     iv_file
            bsr     rx_put
            lda     #TS_WAITIN
            jsr     wake

iv_file:    lda     vstat           ; flash drive: file command finished
            bita    #VS_FDONE
            beq     irq_tmr
            lda     fowner
            cmpa    #$FF
            bne     ivf1
            clr     fowner          ; its task died: the drive is free
            clr     fstate
            bra     ivf2
ivf1:       lda     #2
            sta     fstate
ivf2:       lda     #TS_WAITIO      ; the owner collects the result, the
            jsr     wake            ; others check whether it is free
            inc     vbwoke

irq_tmr:    lda     DU_ISR
            bita    #ISR_CTR        ; counter/timer ready?
            beq     irq_end
            lda     DU_STOPCT       ; clears ISR bit 3, timer keeps running
            lda     #OP_WDOG        ; pulse OP1 high then low: the falling
            sta     DU_OPRESET      ; edge restarts the DS1232 watchdog, so
            sta     DU_OPSET        ; it fires only if ticks stop (> 0.5 s)
            ldd     ticks
            addd    #1
            std     ticks
            inc     subtick
            lda     subtick
            cmpa    #TICK_HZ
            blo     it1
            clr     subtick
            ldd     uptime
            addd    #1
            std     uptime
it1:        ldx     #tcbs           ; count down sleeping tasks
it2:        lda     TCB_STATE,x
            cmpa    #TS_SLEEP
            bne     it3
            ldd     TCB_WAKE,x
            subd    #1
            std     TCB_WAKE,x
            bne     it3
            lda     #TS_READY
            sta     TCB_STATE,x
it3:        leax    TCBSZ,x
            cmpx    #tcbs+MAXTASK*TCBSZ
            blo     it2
            jmp     schedule        ; time slice over

irq_end:    tst     vbwoke          ; frame waiters run right away
            lbne    schedule
            tst     curtask         ; idle task running? then switch to
            lbeq    schedule        ; whoever the input just woke up
            rti

rti_stub:   rti

; Put B in the console input buffer (dropped if full).  Clobbers A, X.
rx_put:     lda     rxhead
            inca
            anda    #RXSIZE-1
            cmpa    rxtail
            beq     rp9             ; buffer full - drop the char
            ldx     #rxbuf
            pshs    a
            lda     rxhead
            stb     a,x
            puls    a
            sta     rxhead
            suba    rxtail          ; chars buffered
            anda    #RXSIZE-1
            cmpa    #RX_STOP
            blo     rp9
            lda     #OP_RTSA        ; nearly full: negate RTS, sender waits
            sta     DU_OPRESET
            sta     rxthrot
            tst     vdpok           ; and leave keys in the chip's FIFO
            beq     rp9
            lda     VDP+V_CTRL
            anda    #$FF-VC_KEYIRQ
            sta     VDP+V_CTRL
rp9:        rts

; Make every task in state A ready.  Clobbers B, X.
wake:       ldx     #tcbs
wk1:        cmpa    TCB_STATE,x
            bne     wk2
            ldb     #TS_READY
            stb     TCB_STATE,x
wk2:        leax    TCBSZ,x
            cmpx    #tcbs+MAXTASK*TCBSZ
            blo     wk1
            rts

; Task B is ending: give up the flash drive if it has it.  Clobbers A, B, X.
fdrop:      cmpb    fowner
            bne     fd9
            lda     fstate
            cmpa    #1
            bne     fd1
            lda     #$FF            ; a command is still running: the
            sta     fowner          ; done interrupt frees the drive
            rts
fd1:        clr     fowner
            clr     fstate
            lda     #TS_WAITIO
            bra     wake
fd9:        rts

; ----------------------------------------------------------------------
;  6309 trap ($FFF0): illegal instruction or division by zero.
;  Kill the task that caused it.  Its stack is abandoned, so switch to
;  the boot stack first; if it was the shell, start a fresh one.
; ----------------------------------------------------------------------
trap_h:     clra
            tfr     a,dp
            lds     #$0400
            ldx     #msg_trap
            jsr     kputs
            lda     curtask
            adda    #'0
            jsr     kputc
            ldx     #msg_trap2
            jsr     kputs
            ldb     curtask
            bsr     fdrop
            ldx     curtcb
            clr     TCB_STATE,x
            lda     curtask
            cmpa    #1
            bne     tr1
            ldx     #msg_respawn
            jsr     kputs
            ldb     #1
            ldx     #shell
            jsr     mktask
tr1:        jmp     sc_pick

; ----------------------------------------------------------------------
;  SWI: system call dispatcher
;  Frame on stack: 0 CC, 1 A, 2 B, 3 DP, 4 X, 6 Y, 8 U, 10 PC
; ----------------------------------------------------------------------
swi_h:      clra
            tfr     a,dp
            ldx     10,s            ; fetch function code after SWI
            ldb     ,x+
            stx     10,s
            cmpb    #NSYS
            bhs     sys_fail
            aslb
            ldx     #systab
            jmp     [b,x]

systab:     fdb     sys_exit,sys_putc,sys_getc,sys_yield,sys_sleep
            fdb     sys_spawn,sys_kill,sys_getpid,sys_time,sys_bank
            fdb     sys_vsync,sys_sound,sys_vreg,sys_vcopy,sys_vread
            fdb     sys_fcmd,sys_poll,sys_break
NSYS        equ     (*-systab)/2

sys_fail:   lda     ,s              ; set carry in caller's CC
            ora     #$01
            sta     ,s
            rti
sys_ok:     lda     ,s              ; clear carry in caller's CC
            anda    #$FE
            sta     ,s
            rti

sys_exit:   ldb     curtask
            jsr     fdrop
            ldx     curtcb
            clr     TCB_STATE,x
            jmp     schedule

sys_putc:
            ifdef   CON_VDC
            tst     vdpok           ; the HDMI screen: no waiting
            beq     spc0
            lda     1,s
            sta     VDP+V_TERM
            rti
spc0:
            endc
            lda     DU_SRA
            bita    #SR_TXRDY       ; room in the transmitter?
            beq     sys_retry
            lda     1,s
            sta     DU_THRA
            ifndef  CON_SERIAL
            ifndef  CON_VDC
            tst     vdpok           ; mirror to the HDMI screen
            beq     spc1
            sta     VDP+V_TERM
            endc
            endc
spc1:       rti

; Back the caller's PC up onto the SWI so the call is repeated the next
; time the task runs, then let someone else have the CPU.
sys_retry:  ldx     10,s
            leax    -2,x
            stx     10,s
            jmp     schedule

sys_poll:   lda     ,s              ; like GETC, but C=1 instead of waiting
            anda    #$FE
            sta     ,s
            ldb     rxtail
            cmpb    rxhead
            beq     sys_fail
            bra     getc_1
sys_break:  lda     ,s              ; is a ^C waiting?  C=1 if not
            ora     #$01
            sta     ,s
            ldx     #rxbuf
            ldb     rxtail
brk1:       cmpb    rxhead
            beq     brk9
            lda     b,x
            incb
            andb    #RXSIZE-1
            cmpa    #3
            bne     brk1
            lda     ,s              ; yes: drop the input up to it
            anda    #$FE
            sta     ,s
            bra     getc_1a
brk9:       rti
sys_getc:   ldb     rxtail
            cmpb    rxhead
            beq     getc_blk
getc_1:     ldx     #rxbuf
            lda     b,x
            sta     1,s
            incb
            andb    #RXSIZE-1
getc_1a:    stb     rxtail
            tst     rxthrot
            beq     getc_ok
            lda     rxhead          ; drained enough to resume input?
            suba    rxtail
            anda    #RXSIZE-1
            cmpa    #RX_GO
            bhs     getc_ok
            lda     #OP_RTSA        ; assert RTS again
            sta     DU_OPSET
            clr     rxthrot
            tst     vdpok           ; and take keys again
            beq     getc_ok
            lda     VDP+V_CTRL
            ora     #KCTRL&VC_KEYIRQ   ; (none in a serial build)
            sta     VDP+V_CTRL
getc_ok:    rti
getc_blk:   ldx     curtcb          ; nothing there: block until IRQ
            lda     #TS_WAITIN
            sta     TCB_STATE,x
            bra     sys_retry

sys_yield:  jmp     schedule

sys_sleep:  ldd     1,s
            lbeq    schedule
            ldx     curtcb
            std     TCB_WAKE,x
            lda     #TS_SLEEP
            sta     TCB_STATE,x
            jmp     schedule

sys_spawn:  ldb     #1              ; find a free slot
            ldx     #tcbs+TCBSZ
sp1:        lda     TCB_STATE,x
            beq     sp2
            leax    TCBSZ,x
            incb
            cmpb    #MAXTASK
            blo     sp1
            lbra    sys_fail
sp2:        stb     2,s             ; return pid in B
            ldx     4,s             ; entry point from X
            jsr     mktask
            lbra    sys_ok

sys_kill:   ldb     2,s
            lbeq    sys_fail        ; the idle task is immortal
            cmpb    #MAXTASK
            lbhs    sys_fail
            lda     #TCBSZ
            mul
            addd    #tcbs
            tfr     d,x
            lda     TCB_STATE,x
            lbeq    sys_fail
            pshs    x
            ldb     4,s             ; the pid again
            jsr     fdrop
            puls    x
            clr     TCB_STATE,x
            cmpx    curtcb
            lbeq    schedule        ; killed itself
            lbra    sys_ok

sys_getpid: lda     curtask
            sta     2,s
            rti

sys_time:   ldd     ticks
            std     1,s
            ldd     uptime
            std     4,s
            rti

; B = page 2..31 to map at $8000-$BFFF for this task, ROMPAGE for the
; ROM bank, or $FF to only ask.  Returns A = page before the call.  Pages
; 0 and 1 hold $0000-$7FFF.
sys_bank:   ldx     curtcb
            lda     TCB_PAGE,x
            sta     1,s
            ldb     2,s
            cmpb    #$FF
            lbeq    sys_ok
            cmpb    #ROMPAGE
            beq     sb1
            cmpb    #DEFPAGE
            lblo    sys_fail
            cmpb    #MAXPAGE
            lbhi    sys_fail
sb1:        stb     TCB_PAGE,x
            tfr     b,a
            jsr     setwin
            lbra    sys_ok

; ----------------------------------------------------------------------
;  Video/sound chip calls.  SWI masks interrupts, so each call's register
;  sequence (pointer + data, index + value) can't be split by a task switch.
; ----------------------------------------------------------------------

; Sleep until the next frame interrupt, which stores the frame count in
; the caller's D.
sys_vsync:  tst     vdpok
            lbeq    sys_fail
            lda     ,s
            anda    #$FE            ; carry clear for the caller
            sta     ,s
            ldx     curtcb
            lda     #TS_WAITVB
            sta     TCB_STATE,x
            jmp     schedule

sys_sound:  tst     vdpok
            lbeq    sys_fail
            ldd     1,s             ; A = value, B = register
            stb     VDP+V_SNDIDX
            sta     VDP+V_SNDDAT
            lbra    sys_ok

sys_vreg:   tst     vdpok
            lbeq    sys_fail
            ldx     #VDP
            ldb     2,s
            bmi     vr_rd
            andb    #$0F
            lda     1,s
            cmpb    #V_CTRL         ; the kernel's interrupts stay on
            bne     vr1
            ora     #KCTRL
vr1:        cmpb    #V_CMD          ; file commands go through SYS_FCMD
            bne     vr2
            cmpa    #VCMD_FOPEN
            lbhs    sys_fail
vr2:        sta     b,x
            cmpb    #V_CMD
            lbne    sys_ok
            cmpa    #VCMD_RESET     ; a reset turns them off: back on
            lbne    sys_ok
            lda     #VC_DISPLAY|KCTRL
            sta     V_CTRL,x
            lbra    sys_ok
vr_rd:      andb    #$0F
            cmpb    #V_STATUS       ; reading would eat the vblank flag
            lbeq    sys_fail
            cmpb    #V_KEY          ; keys belong to the console
            lbeq    sys_fail
            lda     b,x
            sta     1,s
            lbra    sys_ok

; Copy VCHUNK bytes at a time, then run the SWI again with the block
; advanced, so interrupts get in between pieces of a long copy.
VCHUNK      equ     32
sys_vcopy:  tst     vdpok
            lbeq    sys_fail
            ldx     4,s             ; parameter block
            lda     ,x
            sta     VDP+V_PTRH
            lda     1,x
            sta     VDP+V_PTRM
            lda     2,x
            sta     VDP+V_PTRL
            lda     #1
            sta     VDP+V_INC
            ldd     5,x             ; bytes left
            lbeq    sys_ok
            cmpd    #VCHUNK
            bls     vc1
            ldb     #VCHUNK
vc1:        pshs    b               ; bytes this time
            ldu     3,x
vc2:        lda     ,u+
            sta     VDP+V_DATA
            decb
            bne     vc2
vc_adv:     stu     3,x
            ldb     ,s              ; VRAM address += n
            clra
            addd    1,x
            std     1,x
            bcc     vc3
            inc     ,x
vc3:        ldd     5,x             ; count -= n
            subb    ,s
            sbca    #0
            std     5,x
            puls    b               ; (leaves the flags alone)
            lbeq    sys_ok
            ldx     10,s            ; more to go: back up onto the SWI
            leax    -2,x
            stx     10,s
            rti

; The same, VRAM to RAM.
sys_vread:  tst     vdpok
            lbeq    sys_fail
            ldx     4,s             ; parameter block
            lda     ,x
            sta     VDP+V_PTRH
            lda     1,x
            sta     VDP+V_PTRM
            lda     2,x
            sta     VDP+V_PTRL
            lda     #1
            sta     VDP+V_INC
            ldd     5,x             ; bytes left
            lbeq    sys_ok
            cmpd    #VCHUNK
            bls     vd1
            ldb     #VCHUNK
vd1:        pshs    b               ; bytes this time
            ldu     3,x
vd2:        lda     VDP+V_DATA
            sta     ,u+
            decb
            bne     vd2
            bra     vc_adv

; File command on the flash drive.  One task at a time has the drive,
; from its first command until FCLOSE, FDELETE or an error.  The task
; sleeps in TS_WAITIO while its command runs (the done interrupt wakes
; it and this call is repeated to collect the result) and while another
; task has the drive.
sys_fcmd:   tst     vdpok
            bne     fc0
            lda     #FR_NOTREADY
            sta     1,s
            lbra    sys_fail
fc0:        lda     1,s
            cmpa    #VCMD_FOPEN     ; only file commands
            blo     fc_bad
            cmpa    #VCMD_FAPPEND
            bhi     fc_bad
            ldb     fowner
            beq     fc_new          ; drive free: take it
            cmpb    curtask
            bne     fc_wait         ; another task has it
            lda     fstate
            beq     fc_issue
            cmpa    #2
            beq     fc_done
fc_wait:    ldx     curtcb
            lda     #TS_WAITIO
            sta     TCB_STATE,x
            jmp     sys_retry
fc_new:     ldb     curtask
            stb     fowner
fc_issue:   lda     1,s
            sta     VDP+V_CMD
            lda     #1
            sta     fstate
            bra     fc_wait
fc_bad:     lda     #19             ; FR_INVALID_PARAMETER
            sta     1,s
            lbra    sys_fail
fc_done:    clr     fstate
            ldx     #VDP
            lda     #VF_BANK        ; read result and count
            sta     V_PTRH,x
            ldd     #VF_RES
            sta     V_PTRM,x
            stb     V_PTRL,x
            lda     #1
            sta     V_INC,x
            ldb     1,s             ; the command
            lda     V_DATA,x
            sta     1,s             ; A = result
            lda     V_DATA,x
            sta     4,s             ; X = count
            lda     V_DATA,x
            sta     5,s
            tst     1,s
            bne     fc_rel
            cmpb    #VCMD_FCLOSE
            beq     fc_rel
            cmpb    #VCMD_FDELETE
            bne     fc_ret
fc_rel:     clr     fowner          ; drive free: wake the tasks waiting
            lda     #TS_WAITIO
            jsr     wake
fc_ret:     lda     1,s
            lbne    sys_fail
            lbra    sys_ok

; ----------------------------------------------------------------------
;  Idle task
; ----------------------------------------------------------------------
idle:       sync
            bra     idle

; ======================================================================
;  User-mode library (runs inside tasks, talks to the kernel via SWI)
; ======================================================================
putc:       OS      SYS_PUTC
            rts

puts:       pshs    a               ; X -> NUL-terminated string
ps1:        lda     ,x+
            beq     ps2
            OS      SYS_PUTC
            bra     ps1
ps2:        puls    a,pc

crlf:       pshs    a
            lda     #CR
            OS      SYS_PUTC
            lda     #LF
            OS      SYS_PUTC
            puls    a,pc

space:      pshs    a
            lda     #$20
            OS      SYS_PUTC
            puls    a,pc

puthex16:   pshs    d               ; D as 4 hex digits
            bsr     puthex8
            lda     1,s
            bsr     puthex8
            puls    d,pc

puthex8:    pshs    a               ; A as 2 hex digits
            lsra
            lsra
            lsra
            lsra
            bsr     putnib
            lda     ,s
            bsr     putnib
            puls    a,pc
putnib:     anda    #$0F
            adda    #'0
            cmpa    #'9
            bls     pn1
            adda    #7
pn1:        OS      SYS_PUTC
            rts

; D as unsigned decimal
putdec:     clr     dflag
            ldy     #pow10
pd1:        clr     dcnt
pd2:        cmpd    ,y
            blo     pd3
            subd    ,y
            inc     dcnt
            bra     pd2
pd3:        pshs    d
            lda     dcnt
            ora     dflag
            bne     pd4             ; non-zero digit, or already printing
            ldx     ,y
            leax    -1,x
            bne     pd5             ; suppress leading zero (not the last)
pd4:        lda     dcnt
            adda    #'0
            OS      SYS_PUTC
            inc     dflag
pd5:        puls    d
            ldx     ,y++
            leax    -1,x
            bne     pd1
            rts
pow10:      fdb     10000,1000,100,10,1

; Read an edited line into linebuf (upper-cased, NUL terminated)
getline:    ldx     #linebuf
            clrb
gl1:        OS      SYS_GETC
            cmpa    #ESC            ; skip ESC [ ... / ESC O x sequences
            beq     gl4             ; (arrow and function keys)
            cmpa    #CR
            beq     gl9
            cmpa    #LF
            beq     gl9
            cmpa    #BS
            beq     gl2
            cmpa    #DEL
            beq     gl2
            cmpa    #$20
            blo     gl1             ; ignore other control chars
            cmpb    #LINEMAX
            bhs     gl1
            cmpa    #'a
            blo     gl3
            cmpa    #'z
            bhi     gl3
            suba    #$20
gl3:        sta     ,x+
            incb
            OS      SYS_PUTC
            bra     gl1
gl2:        tstb
            beq     gl1
            decb
            leax    -1,x
            pshs    x
            ldx     #bsseq
            jsr     puts
            puls    x
            bra     gl1
gl4:        OS      SYS_GETC        ; the [ or O
gl5:        OS      SYS_GETC        ; parameters, up to the final byte
            cmpa    #$40
            blo     gl5
            bra     gl1
gl9:        clr     ,x
            jmp     crlf

skipsp:     lda     ,x
            cmpa    #$20
            bne     sk1
            leax    1,x
            bra     skipsp
sk1:        rts

; A = ASCII hex digit -> A = 0..15, carry set if not a hex digit
hexdig:     suba    #'0
            blo     hd9
            cmpa    #9
            bls     hd1
            suba    #7
            cmpa    #10
            blo     hd9
            cmpa    #15
            bhi     hd9
hd1:        andcc   #$FE
            rts
hd9:        orcc    #$01
            rts

; Parse hex number at X -> D, X advanced.  Carry set if no digits.
gethex:     bsr     skipsp
            clr     hexv
            clr     hexv+1
            clr     hexn
gx1:        lda     ,x
            bsr     hexdig
            bcs     gx3
            leax    1,x
            ldb     #4
gx2:        asl     hexv+1
            rol     hexv
            decb
            bne     gx2
            ora     hexv+1
            sta     hexv+1
            inc     hexn
            bra     gx1
gx3:        ldd     hexv
            tst     hexn
            beq     gx9
            andcc   #$FE
            rts
gx9:        orcc    #$01
            rts

; ======================================================================
;  Shell (task 1)
; ======================================================================
shell:      ldx     #msg_hint
            jsr     puts
            ldd     #$E000
            std     dumpaddr
sh_loop:    ldx     #prompt
            jsr     puts
            jsr     getline
            ldx     #linebuf
            bsr     skipsp
            lda     ,x
            beq     sh_loop
            ldy     #cmdtab
sh1:        ldu     ,y              ; command name
            beq     sh_unk
            pshs    x
sh2:        lda     ,u+
            beq     sh3
            cmpa    ,x+
            beq     sh2
            bra     sh4
sh3:        lda     ,x              ; whole word must match
            beq     sh5
            cmpa    #$20
            beq     sh5
sh4:        puls    x
            leay    4,y
            bra     sh1
sh5:        leas    2,s
            jsr     skipsp          ; X -> arguments
            jsr     [2,y]
            bra     sh_loop
; Anything else is a program on the drive: NAME [args] runs NAME.PRG,
; or NAME.EXT as typed if the word has a dot, and waits for it to end.
sh_unk:     ldu     #runln          ; the word ...
            clrb                    ; (B counts its dots)
su1:        lda     ,x
            beq     su2
            cmpa    #$20
            beq     su2
            cmpa    #'/             ; (a dot in a directory doesn't count)
            bne     su10
            clrb
su10:       cmpa    #'.
            bne     su11
            incb
su11:       sta     ,u+
            leax    1,x
            bra     su1
su2:        tstb
            bne     su4
            ldy     #s_prg          ; ... with .PRG if it has no extension
su3:        lda     ,y+
            sta     ,u+
            bne     su3
            leau    -1,u
su4:        lda     ,x+             ; ... then the rest of the line
            sta     ,u+
            bne     su4
            ldx     #runln
            jsr     setname
            lda     #VCMD_FOPEN     ; no such file: not a command at all
            jsr     fcmd
            bcs     su9
            lda     #VCMD_FCLOSE
            jsr     fcmd
            ldx     #runln
            jsr     cmd_run
            lbra    sh_loop
su9:        ldx     #msg_unk
            jsr     puts
            lbra    sh_loop

cmdtab:     fdb     s_help,cmd_help
            fdb     s_ps,cmd_ps
            fdb     s_d,cmd_dump
            fdb     s_w,cmd_write
            fdb     s_g,cmd_go
            fdb     s_k,cmd_kill
            fdb     s_l,cmd_load
            fdb     s_up,cmd_up
            fdb     s_count,cmd_count
            fdb     s_spin,cmd_spin
            fdb     s_bank,cmd_bank
            fdb     s_cls,cmd_cls
            fdb     s_beep,cmd_beep
            fdb     s_vdp,cmd_vdp
            fdb     s_dir,cmd_dir
            fdb     s_type,cmd_type
            fdb     s_load,cmd_loadf
            fdb     s_save,cmd_save
            fdb     s_del,cmd_del
            fdb     s_basic,cmd_basic
            fdb     0

s_help:     fcn     "HELP"
s_ps:       fcn     "PS"
s_d:        fcn     "D"
s_w:        fcn     "W"
s_g:        fcn     "G"
s_k:        fcn     "K"
s_l:        fcn     "L"
s_up:       fcn     "UP"
s_count:    fcn     "COUNT"
s_spin:     fcn     "SPIN"
s_bank:     fcn     "BANK"
s_cls:      fcn     "CLS"
s_beep:     fcn     "BEEP"
s_vdp:      fcn     "VDP"
s_dir:      fcn     "DIR"
s_type:     fcn     "TYPE"
s_load:     fcn     "LOAD"
s_save:     fcn     "SAVE"
s_del:      fcn     "DEL"
s_prg:      fcn     ".PRG"
s_basic:    fcn     "BASIC"

cmd_err:    ldx     #msg_syntax
            jmp     puts

; HELP: each msg_help line is printed as two spaces, the command padded
; to column 16 (at least one space), then the description.
cmd_help:   ldx     #msg_help
chl1:       tst     ,x
            beq     chl9
            ldb     #2
            lda     #$20
            jsr     putc
            jsr     putc
chl2:       lda     ,x+
            cmpa    #TAB
            beq     chl3
            jsr     putc
            incb
            bra     chl2
chl3:       lda     #$20
chl4:       jsr     putc
            incb
            cmpb    #16
            blo     chl4
            jsr     puts            ; the description; X ends past its NUL
            jsr     crlf
            bra     chl1
chl9:       rts

; CLS - clear the screen (ANSI, so a serial terminal clears too)
cmd_cls:    ldx     #msg_cls
            jmp     puts

; BEEP - 1 kHz for 0.15 s on the video chip's sound generator
cmd_beep:   ldd     #$7D00          ; tone A period 125: 2 MHz/16/125
            OS      SYS_SOUND
            bcs     cmd_novdp
            ldd     #$0001
            OS      SYS_SOUND
            ldd     #$3E07          ; mixer: tone A only
            OS      SYS_SOUND
            ldd     #$0F08          ; volume A = 15
            OS      SYS_SOUND
            ldd     #15
            OS      SYS_SLEEP
            ldd     #$0008          ; volume A = 0
            OS      SYS_SOUND
            rts
cmd_novdp:  ldx     #msg_novdp
            jmp     puts

; VDP - is the video chip there, and are frames arriving?
cmd_vdp:    OS      SYS_VSYNC       ; D = frame count
            bcs     cmd_novdp
            pshs    d
            ldx     #msg_vdp
            jsr     puts
            puls    d
            jsr     putdec
            jmp     crlf

; PS - list tasks
cmd_ps:     ldx     #msg_pshdr
            jsr     puts
            OS      SYS_GETPID
            stb     mypid
            clrb
            ldy     #tcbs
cp1:        lda     TCB_STATE,y
            beq     cp3
            pshs    b
            lda     #$20
            jsr     putc
            tfr     b,a
            adda    #'0
            jsr     putc
            lda     #$20
            cmpb    mypid
            bne     cp2
            lda     #'*
cp2:        jsr     putc
            jsr     space
            ldx     #stnames
            lda     TCB_STATE,y
            lsla
            lsla
            lsla
            leax    a,x
            jsr     puts
            ldd     TCB_SP,y
            jsr     puthex16
            jsr     space
            jsr     space
            ldd     TCB_ENT,y
            jsr     puthex16
            jsr     space
            jsr     space
            jsr     space
            lda     TCB_PAGE,y
            jsr     puthex8
            jsr     crlf
            puls    b
cp3:        leay    TCBSZ,y
            incb
            cmpb    #MAXTASK
            blo     cp1
            rts

; D [addr] - dump 64 bytes
cmd_dump:   jsr     gethex
            bcs     cd0
            std     dumpaddr
cd0:        ldy     dumpaddr
            lda     #4
            sta     dlines
cd1:        tfr     y,d
            jsr     puthex16
            lda     #':
            jsr     putc
            ldb     #16
cd2:        jsr     space
            lda     ,y+
            jsr     puthex8
            decb
            bne     cd2
            ldx     #msg_bar
            jsr     puts
            leay    -16,y
            ldb     #16
cd3:        lda     ,y+
            cmpa    #$20
            blo     cd4
            cmpa    #$7E
            bls     cd5
cd4:        lda     #'.
cd5:        jsr     putc
            decb
            bne     cd3
            lda     #'|
            jsr     putc
            jsr     crlf
            dec     dlines
            bne     cd1
            sty     dumpaddr
            rts

; W addr bb bb ... - write bytes
cmd_write:  jsr     gethex
            lbcs    cmd_err
            tfr     d,y
cw1:        jsr     gethex
            bcs     cw2
            stb     ,y+
            bra     cw1
cw2:        rts

; G addr - start a new task at addr
cmd_go:     jsr     gethex
            lbcs    cmd_err
            tfr     d,x
spawnx:     OS      SYS_SPAWN
            bcs     cg9
            ldx     #msg_start
            jsr     puts
            tfr     b,a
            adda    #'0
            jsr     putc
            jmp     crlf
cg9:        ldx     #msg_full
            jmp     puts

; K pid - kill a task
cmd_kill:   jsr     gethex
            lbcs    cmd_err
            OS      SYS_KILL
            bcc     ck1
            ldx     #msg_nopid
            jmp     puts
ck1:        rts

; UP - uptime
cmd_up:     OS      SYS_TIME        ; D = ticks, X = seconds
            pshs    d,x             ; 0,s = ticks, 2,s = seconds
            ldx     #msg_up1
            jsr     puts
            ldd     2,s
            jsr     putdec
            ldx     #msg_up2
            jsr     puts
            puls    d,x
            jsr     putdec
            ldx     #msg_up3
            jmp     puts

cmd_count:  ldx     #count_task
            bra     spawnx
cmd_spin:   ldx     #spin_task
            bra     spawnx

; BANK [n] - show, or set, the shell's page in the $8000-$BFFF window
cmd_bank:   jsr     gethex
            bcc     cb1
            ldb     #$FF            ; no argument: just report
cb1:        OS      SYS_BANK
            bcc     cb2
            ldx     #msg_badpage
            jmp     puts
cb2:        ldb     #$FF
            OS      SYS_BANK        ; A = current page
            ldx     #msg_page
            jsr     puts
            jsr     puthex8
            jmp     crlf

; L - load Motorola S-records (S1 data, S9 end) from the console
cmd_load:   ldx     #sgetc
            stx     lgetv
            ldx     #msg_load
            jsr     puts
ldgo:       clr     cksum           ; S-record loader, input via lgetv
ld1:        jsr     lgetc
            cmpa    #'S
            bne     ld1
            jsr     lgetc
            cmpa    #'9
            beq     ld8
            cmpa    #'1
            bne     ld1
            clr     cksum
            bsr     gethb           ; byte count
            suba    #3
            sta     lcount
            bsr     gethb
            sta     laddr
            bsr     gethb
            sta     laddr+1
            ldx     laddr
ld2:        tst     lcount
            beq     ld3
            bsr     gethb
            sta     ,x+
            dec     lcount
            bra     ld2
ld3:        bsr     gethb           ; checksum
            lda     cksum
            cmpa    #$FF
            beq     ld4
            lda     #'?
            jsr     putc
            bra     ld1
ld4:        lda     #'.
            jsr     putc
            bra     ld1
ld8:        bsr     gethb           ; S9: count, start address
            bsr     gethb
            sta     laddr
            bsr     gethb
            sta     laddr+1
ld9:        bsr     lgetc           ; discard rest of line
            cmpa    #CR
            beq     ld10
            cmpa    #LF
            bne     ld9
ld10:       ldx     #msg_loaded
ld10a:      jsr     puts
            ldd     laddr
            jsr     puthex16
            jmp     crlf

gethb:      bsr     lgetc           ; two hex chars -> A, added to cksum
            jsr     hexdig
            lsla
            lsla
            lsla
            lsla
            sta     hbtmp
            bsr     lgetc
            jsr     hexdig
            ora     hbtmp
            pshs    a
            adda    cksum
            sta     cksum
            puls    a,pc

lgetc:      jmp     [lgetv]         ; next loader character -> A
sgetc:      OS      SYS_GETC        ; from the console
            rts

; ----------------------------------------------------------------------
;  Flash drive commands (USB drive on the video chip, via SYS_FCMD)
; ----------------------------------------------------------------------

; Copy D bytes between RAM at X and VRAM page VF_BANK offset U.
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

fcmd:       OS      SYS_FCMD        ; A = command -> A = result, X = count
            rts

; Word at X (up to a space) -> fname and VF_NAME.  X moves past it.
setname:    ldu     #fname
sn1:        lda     ,x
            beq     sn2
            cmpa    #$20
            beq     sn2
            sta     ,u+
            leax    1,x
            cmpu    #fname+63
            blo     sn1
sn2:        clr     ,u
            pshs    x
            tfr     u,d
            subd    #fname-1        ; length with the NUL
            ldx     #fname
            ldu     #VF_NAME
            bsr     vput
            puls    x,pc

; Read up to 512 bytes of the open file into fbuf -> X = count (0 at the
; end), carry set and A = result on error.
fread:      ldx     #zero2          ; VF_LEN = 0: a whole buffer
            ldu     #VF_LEN
            ldd     #2
            bsr     vput
            lda     #VCMD_FREAD
            bsr     fcmd
            bcs     fr9
            stx     fcnt
            beq     fr9
            ldx     #fbuf
            ldu     #VF_DATA
            ldd     fcnt
            bsr     vget
            ldx     fcnt
            andcc   #$FE
fr9:        rts
zero2:      fdb     0

; Print the message for file result A.
ferr:       ldx     #msg_fnoprg
            cmpa    #$FE
            beq     fe9
            ldx     #msg_fnodrv
            cmpa    #FR_NOTREADY
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
            ldx     #msg_feof
            cmpa    #$FF
            beq     fe9
            ldx     #msg_ferr
            jsr     puts
            tfr     a,b
            clra
            jsr     putdec
            jmp     crlf
fe9:        jmp     puts

; Abandon a LOAD or SAVE after a file error (A = result): back to the
; caller of cmd_loadf / cmd_save with carry set.
fabort:     lds     lsave
            bsr     ferr
            lda     #VCMD_FCLOSE
            jsr     fcmd
            orcc    #$01
            rts

; D as unsigned decimal, right-aligned in 6 columns
putdec6:    pshs    d
            jsr     space
            ldy     #pow10
pp1:        ldd     ,y
            cmpd    #1
            beq     pp2
            ldd     ,s
            cmpd    ,y
            bhs     pp2
            jsr     space
            leay    2,y
            bra     pp1
pp2:        puls    d
            jmp     putdec

; DIR [path] - list a directory of the flash drive
cmd_dir:    jsr     setname
            lda     #VCMD_DIR
            jsr     fcmd
            bcs     cdr_e
cdr1:       ldx     #mbox           ; entry name, size and attributes
            ldu     #VF_NAME
            ldd     #VF_ATTR+1-VF_NAME
            jsr     vget
            tst     mbox
            beq     cdr9            ; end of the directory
            lda     mbox+VF_ATTR-VF_NAME
            bita    #$10
            beq     cdr2
            ldx     #msg_dirtag
            jsr     puts
            bra     cdr4
cdr2:       ldd     mbox+VF_SIZE-VF_NAME
            bne     cdr3
            ldd     mbox+VF_SIZE-VF_NAME+2
            bsr     putdec6         ; under 64K: bytes
            jsr     space
            jsr     space
            bra     cdr4
cdr3:       cmpa    #4
            bhs     cdr5
            ldx     #2              ; 64K and up: size / 1024 in K
cdr3a:      lsr     mbox+VF_SIZE-VF_NAME
            ror     mbox+VF_SIZE-VF_NAME+1
            ror     mbox+VF_SIZE-VF_NAME+2
            leax    -1,x
            bne     cdr3a
            ldd     mbox+VF_SIZE-VF_NAME+1
            bsr     putdec6
            lda     #'K
            jsr     putc
            jsr     space
            bra     cdr4
cdr5:       ldx     #msg_big
            jsr     puts
cdr4:       ldx     #mbox
            jsr     puts
            jsr     crlf
            lda     #VCMD_DIRNEXT
            jsr     fcmd
            bcc     cdr1
cdr_e:      jsr     ferr
cdr9:       lda     #VCMD_FCLOSE
            jmp     fcmd

; TYPE file - show a text file
cmd_type:   jsr     setname
            tst     fname
            lbeq    cmd_err
            lda     #VCMD_FOPEN
            jsr     fcmd
            bcs     cty_e
cty1:       jsr     fread
            bcs     cty_e
            cmpx    #0
            beq     cty9
            tfr     x,y
            ldx     #fbuf
cty2:       lda     ,x+
            cmpa    #LF             ; LF -> CR LF
            bne     cty3
            lda     #CR
            jsr     putc
            lda     #LF
cty3:       jsr     putc
            leay    -1,y
            bne     cty2
            bra     cty1
cty_e:      jsr     ferr
cty9:       lda     #VCMD_FCLOSE
            jmp     fcmd

; LOAD [file] - load a program file (no name: S-records from the
; console).  Carry set if the file could not be read.  Loads must stay
; clear of fbuf ($0C00-$0DFF).
;
; Program file: a header, then the bytes to load (big-endian numbers):
;   0 "M9", 2 version 1, 3 header length (36), 4 name (12, NUL-padded),
;   16 creator (8), 24 date: year (2), month, day (0 = unknown),
;   28 file size (header included), 30 load address, 32 entry, 34 0 0
PHLEN       equ     36
cmd_loadf:  jsr     setname
            tst     fname
            lbeq    cmd_load
            lda     #VCMD_FOPEN
            jsr     fcmd
            bcc     clf1
            jsr     ferr
            orcc    #$01
            rts
clf1:       ldd     #0
            std     fpos
            std     fcnt
            sts     lsave
            ldx     #linebuf        ; the header (the arguments are done)
            ldb     #PHLEN
clf2:       bsr     fgetc
            sta     ,x+
            decb
            bne     clf2
            ldd     linebuf
            cmpd    #$4D39          ; "M9"
            beq     clf3
            lda     #$FE            ; not a program file
            lbra    fabort
clf3:       ldb     linebuf+3       ; skip a longer header
            subb    #PHLEN
clf4:       beq     clf5
            bsr     fgetc
            decb
            bra     clf4
clf5:       ldd     linebuf+32
            std     laddr
            ldb     linebuf+3       ; bytes = file size - header length
            clra
            pshs    d
            ldd     linebuf+28
            subd    ,s++
            tfr     d,y
            ldx     linebuf+30
clf6:       leay    ,y
            beq     clf7
            bsr     fgetc
            sta     ,x+
            leay    -1,y
            bra     clf6
clf7:       ldx     #msg_loaded+2   ; "Loaded, entry ..." (no dots to end)
            jsr     ld10a
            lda     #VCMD_FCLOSE
            jsr     fcmd
            andcc   #$FE
            rts

; Next character of the open file -> A.  Keeps B, X, Y, U.
fgetc:      pshs    b,x,y,u
            ldd     fpos
            cmpd    fcnt
            blo     fg2
            jsr     fread
            lbcs    fabort
            cmpx    #0
            bne     fg1
            lda     #$FF            ; the file ended early
            lbra    fabort
fg1:        ldd     #0
            std     fpos
fg2:        ldx     #fbuf
            leax    d,x
            addd    #1
            std     fpos
            lda     ,x
            puls    b,x,y,u,pc

; file [args] at X - load a program file, start it as a task at its entry
; and wait for it to end, so the shell doesn't take its keys.  The args go
; to ARGS (see syscalls.inc)
cmd_run:    bsr     setargs
            jsr     cmd_loadf
            bcs     crn9
            ldx     laddr
            beq     crn8
            OS      SYS_SPAWN
            lbcs    cg9
crun:       lda     #TCBSZ
crn0:       mul                     ; wait for task B to end
            addd    #tcbs
            tfr     d,x
crn1:       ldd     #5
            OS      SYS_SLEEP
            tst     TCB_STATE,x
            bne     crn1
crn9:       rts
crn8:       ldx     #msg_noent
            jmp     puts

; The rest of the line after the file name at X -> ARGS, after ARGMARK.
; Keeps X.
setargs:    pshs    x
            jsr     setname         ; X -> after the file name
            jsr     skipsp
            ldu     #ARGS+2
            ldb     #ARGMAX
sa1:        lda     ,x+
            sta     ,u+
            beq     sa2
            decb
            bne     sa1
            clr     ,u
sa2:        ldd     #ARGMARK
            std     ARGS
            puls    x,pc

; BASIC - start the BASIC in the ROM bank and wait for it
cmd_basic:  ldx     #rombas
            OS      SYS_SPAWN
            lbcs    cg9
            bra     crun
; The task: the ROM bank at $8000, and in if a BASIC is there
rombas:     ldb     #ROMPAGE
            OS      SYS_BANK
            ldd     ROMBAS
            cmpd    #$4241          ; "BA"
            lbeq    ROMBAS+2
            ldb     #DEFPAGE
            OS      SYS_BANK
            ldx     #msg_norom
            jsr     puts
            OS      SYS_EXIT

; SAVE file start end [creator] - write memory start..end as a program
; file (see LOAD), entry start, name the file's, date unknown
cmd_save:   jsr     setname
            tst     fname
            lbeq    cmd_err
            jsr     gethex
            lbcs    cmd_err
            std     laddr
            jsr     gethex
            lbcs    cmd_err
            std     svend
            cmpd    laddr
            lblo    cmd_err
            jsr     skipsp          ; X -> the creator, if any
            pshs    x
            lda     #VCMD_FCREATE
            jsr     fcmd
            puls    x
            bcc     csv0
            jmp     ferr
csv0:       ldd     #0
            std     fpos
            sts     lsave
            pshs    x
            ldd     #$4D39          ; "M9", version 1, header length
            bsr     fput16
            ldd     #$0100+PHLEN
            bsr     fput16
            ldx     #fname          ; the name, without its directory
            tfr     x,u
csv1:       lda     ,u+
            beq     csv2
            cmpa    #'/
            bne     csv1
            tfr     u,x
            bra     csv1
csv2:       ldb     #12
            bsr     fputfld
            puls    x               ; the creator, or "MINI09"
            tst     ,x
            bne     csv3
            ldx     #banner+2       ; "MINI09" (cut at the space)
csv3:       ldb     #8
            bsr     fputfld
            ldd     #0              ; date: unknown
            bsr     fput16
            bsr     fput16
            ldd     svend           ; file size = end - start + 1 + header
            subd    laddr
            addd    #PHLEN+1
            bsr     fput16
            ldd     laddr           ; load and entry
            bsr     fput16
            bsr     fput16
            ldd     #0
            bsr     fput16
            ldy     laddr           ; the bytes
csv4:       lda     ,y+
            bsr     fputc
            cmpy    svend
            bls     csv4
            bsr     fflush
            lda     #VCMD_FCLOSE
            jsr     fcmd
            lbcs    ferr
            rts

; D into the file, high byte first.  Keeps D.
fput16:     bsr     fputc
            exg     a,b
            bsr     fputc
            exg     a,b
            rts

; The text at X, up to a NUL or space, in a B-byte field padded with NULs
fputfld:    lda     ,x
            beq     fpf2
            cmpa    #$20
            beq     fpf2
            leax    1,x
fpf1:       bsr     fputc
            decb
            bne     fputfld
            rts
fpf2:       clra
            bra     fpf1

; A into the file buffer, written out every 512 bytes.  Keeps all.
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

; Write the fpos bytes in fbuf to the file.
fflush:     ldd     fpos
            beq     ffl9
            ldx     #fbuf
            ldu     #VF_DATA
            jsr     vput
            ldx     #fpos           ; VF_LEN = fpos (both big-endian)
            ldu     #VF_LEN
            ldd     #2
            jsr     vput
            lda     #VCMD_FWRITE
            jsr     fcmd
            lbcs    fabort
            cmpx    fpos
            beq     ffl1
            lda     #7              ; short write: disk full
            lbra    fabort
ffl1:       ldd     #0
            std     fpos
ffl9:       rts

; DEL file - delete a file (or an empty directory)
cmd_del:    jsr     setname
            tst     fname
            lbeq    cmd_err
            lda     #VCMD_FDELETE
            jsr     fcmd
            lbcs    ferr
            rts


; ======================================================================
;  Demo tasks
; ======================================================================

; Prints five lines one second apart, then returns (-> task_exit).
; Each instance keeps its state on its own stack, so any number can run.
count_task: clra                    ; B = our pid (set up by mktask)
            pshs    d               ; 0,s = counter, 1,s = pid
ct1:        inc     ,s
            ldx     #msg_ct1
            jsr     puts
            lda     1,s
            adda    #'0
            jsr     putc
            ldx     #msg_ct2
            jsr     puts
            lda     ,s
            adda    #'0
            jsr     putc
            jsr     crlf
            ldd     #TICK_HZ
            OS      SYS_SLEEP
            lda     ,s
            cmpa    #5
            blo     ct1
            puls    d,pc

; Never yields - shows that preemption keeps the system responsive.
spin_task:  leax    1,x
            bra     spin_task

; ======================================================================
;  Strings
; ======================================================================
banner:     fcb     CR,LF
            fcc     "MINI09 v1.3 - multitasking OS for the 6809/6309"
            fcb     CR,LF,0
msg_hint:   fcc     "Type HELP for commands."
            fcb     CR,LF,0
prompt:     fcn     "OS09> "
bsseq:      fcb     BS,$20,BS,0
msg_unk:    fcc     "Unknown command"
            fcb     CR,LF,0
msg_syntax: fcc     "Syntax error"
            fcb     CR,LF,0
; HELP lines: command, TAB, description, NUL (cmd_help lays them out)
msg_help:   fcc     "HELP"
            fcb     TAB
            fcn     "this list"
            fcc     "PS"
            fcb     TAB
            fcn     "list tasks"
            fcc     "D [addr]"
            fcb     TAB
            fcn     "dump memory"
            fcc     "W addr bb .."
            fcb     TAB
            fcn     "write bytes"
            fcc     "G addr"
            fcb     TAB
            fcn     "start task at addr"
            fcc     "K pid"
            fcb     TAB
            fcn     "kill task"
            fcc     "L"
            fcb     TAB
            fcn     "load S-records"
            fcc     "UP"
            fcb     TAB
            fcn     "uptime"
            fcc     "COUNT"
            fcb     TAB
            fcn     "demo: counting task"
            fcc     "SPIN"
            fcb     TAB
            fcn     "demo: CPU-bound task"
            fcc     "BANK [n]"
            fcb     TAB
            fcn     "RAM page at $8000-$BFFF (2-1F)"
            fcc     "CLS"
            fcb     TAB
            fcn     "clear the screen"
            fcc     "BEEP"
            fcb     TAB
            fcn     "sound test (video chip)"
            fcc     "VDP"
            fcb     TAB
            fcn     "video chip status"
            fcc     "DIR [path]"
            fcb     TAB
            fcn     "list the USB flash drive"
            fcc     "TYPE file"
            fcb     TAB
            fcn     "show a text file"
            fcc     "LOAD [file]"
            fcb     TAB
            fcn     "load a program (none: S-records)"
            fcc     "SAVE f s e [c]"
            fcb     TAB
            fcn     "save s-e as a program, creator c"
            fcc     "DEL file"
            fcb     TAB
            fcn     "delete a file"
            fcc     "name [args]"
            fcb     TAB
            fcn     "run NAME.PRG from the drive"
            fcc     "EDIT [file]"
            fcb     TAB
            fcn     "text editor (EDIT.PRG)"
            fcc     "BASIC"
            fcb     TAB
            fcn     "BASIC in the ROM bank"
            fcb     0
msg_pshdr:  fcc     "PID  STATE  SP    ENTRY  PAGE"
            fcb     CR,LF,0
stnames:    fcn     "FREE   "
            fcn     "READY  "
            fcn     "SLEEP  "
            fcn     "INPUT  "
            fcn     "VSYNC  "
            fcn     "FILEIO "
msg_bar:    fcn     "  |"
msg_start:  fcn     "Started task "
msg_full:   fcc     "No free task slot"
            fcb     CR,LF,0
msg_nopid:  fcc     "No such task"
            fcb     CR,LF,0
msg_up1:    fcn     "Up "
msg_up2:    fcn     " s ("
msg_up3:    fcc     " ticks)"
            fcb     CR,LF,0
msg_load:   fcc     "Send S-records..."
            fcb     CR,LF,0
msg_loaded: fcb     CR,LF
            fcn     "Loaded, entry "
msg_ct1:    fcn     "[task "
msg_ct2:    fcn     "] count "
msg_page:   fcn     "$8000-$BFFF = page "
msg_badpage: fcc    "Page must be 2-1F"
            fcb     CR,LF,0
msg_cls:    fcb     ESC
            fcc     "[2J"
            fcb     ESC
            fcc     "[H"
            fcb     0
msg_novdp:  fcc     "No video chip"
            fcb     CR,LF,0
msg_vdp:    fcn     "Video chip at $C800, frame "
msg_dirtag: fcn     "  [DIR] "
msg_big:    fcn     "   BIG  "
msg_norom:  fcc     "No BASIC ROM"
            fcb     CR,LF,0
msg_noent:  fcc     "No entry address"
            fcb     CR,LF,0
msg_fnoprg: fcc     "Not a program"
            fcb     CR,LF,0
msg_fnodrv: fcc     "No flash drive"
            fcb     CR,LF,0
msg_fnofile: fcc    "File not found"
            fcb     CR,LF,0
msg_fnopath: fcc    "Path not found"
            fcb     CR,LF,0
msg_fdenied: fcc    "Access denied or disk full"
            fcb     CR,LF,0
msg_fexist: fcc     "Already exists"
            fcb     CR,LF,0
msg_fnofat: fcc     "Not a FAT16/FAT32 drive"
            fcb     CR,LF,0
msg_feof:   fcc     "Unexpected end of file"
            fcb     CR,LF,0
msg_ferr:   fcn     "Drive error "
msg_trap:   fcb     CR,LF
            fcn     "*** trap (illegal instruction or /0) in task "
msg_trap2:  fcc     " - task killed"
            fcb     CR,LF,0
msg_respawn: fcc    "*** restarting shell"
            fcb     CR,LF,0

ROMEND      equ     *

; ======================================================================
;  Vectors
; ======================================================================
            org     $FFF0
            fdb     trap_h          ; 6309 illegal op / div by zero
            fdb     rti_stub        ; SWI3
            fdb     rti_stub        ; SWI2
            fdb     rti_stub        ; FIRQ
            fdb     irq_h           ; IRQ
            fdb     swi_h           ; SWI
            fdb     rti_stub        ; NMI
            fdb     reset           ; RESET
