; ----------------------------------------------------------------------
;  Pico 6809 video/sound chip (pico6809 firmware) on /EXPCS1
;
;  HDMI 640x480 text and bitmap modes, an AY-3-8910 compatible sound
;  generator and a terminal that MINI09 mirrors its console to.  The
;  kernel owns the chip: user programs use SYS_VSYNC, SYS_SOUND, SYS_VREG,
;  SYS_VCOPY, SYS_VREAD and SYS_FCMD, which keep the VRAM pointer and the
;  sound index safe from task switches.  These register numbers go in B
;  for SYS_VREG.  A USB keyboard on the chip types into the console, and a
;  USB flash drive holds files (see "File commands" below).
; ----------------------------------------------------------------------

VDP         equ     $C800           ; 16 registers, mirrored up to $CFFF

V_DATA      equ     $0              ; VRAM[PTR], then PTR += INC
V_PTRL      equ     $1              ; VRAM pointer, 17 bits
V_PTRM      equ     $2
V_PTRH      equ     $3
V_INC       equ     $4              ; signed step after each DATA access
V_MODE      equ     $5              ; video mode, VM_xxx
V_CTRL      equ     $6              ; VC_xxx, bits 7-4 border colour
V_STATUS    equ     $7              ; read: VS_xxx (the kernel reads it)
V_PALIDX    equ     $8              ; palette index
V_PALDAT    equ     $9              ; palette[IDX] as RGB332, steps IDX
V_BASEL     equ     $A              ; display start / 16
V_BASEH     equ     $B
V_SNDIDX    equ     $C              ; sound register index
V_SNDDAT    equ     $D              ; sound register value
V_KEY       equ     $E              ; read: next USB key, 0 if none (kernel)
V_TERM      equ     $E              ; write: terminal character
V_ID        equ     $F              ; read: VDP_IDV
V_CMD       equ     $F              ; write: VCMD_xxx

VDP_IDV     equ     $56
VC_IRQEN    equ     $01             ; vblank interrupt (kept on by the kernel)
VC_DISPLAY  equ     $02
VC_KEYIRQ   equ     $04             ; key interrupt (kept on by the kernel)
VC_FILEIRQ  equ     $08             ; file command done interrupt (same)
VC_KERNEL   equ     VC_IRQEN|VC_KEYIRQ|VC_FILEIRQ
VS_VBLANK   equ     $80             ; vblank seen; reading STATUS clears it
VS_INVB     equ     $40             ; in vertical blanking now
VS_KEY      equ     $20             ; a key is waiting
VS_FBUSY    equ     $10             ; file command running
VS_DRIVE    equ     $08             ; flash drive mounted
VS_KBD      equ     $04             ; keyboard attached
VS_FDONE    equ     $01             ; file command done; reading clears it

VCMD_RESET  equ     1               ; power-on state, 80x30 text, cleared
VCMD_CLRVRAM equ    2
VCMD_CLRTEXT equ    3               ; clear the text page, cursor home
VCMD_FONT   equ     4               ; reload the built-in font

; File commands (SYS_FCMD).  Paths use / and long names; FAT16/32 drives.
VCMD_FOPEN  equ     $10             ; open VF_NAME for reading, sets VF_SIZE
VCMD_FCREATE equ    $11             ; create / truncate VF_NAME for writing
VCMD_FREAD  equ     $12             ; read up to VF_LEN bytes (0 = 512) to VF_DATA
VCMD_FWRITE equ     $13             ; write VF_LEN bytes from VF_DATA
VCMD_FCLOSE equ     $14             ; close the file and any directory
VCMD_DIR    equ     $15             ; open directory VF_NAME, first entry
VCMD_DIRNEXT equ    $16             ; next entry (VF_NAME empty at the end)
VCMD_FDELETE equ    $17             ; delete VF_NAME
VCMD_FAPPEND equ    $18             ; open VF_NAME for writing at its end

; File mailbox in VRAM page VF_BANK (the high byte of the VRAM address).
; Numbers are big-endian, so LDD/LDX read them directly.
VF_BANK     equ     $01
VF_NAME     equ     $F000           ; 64: path, NUL-terminated / entry name
VF_RES      equ     $F040           ; 1: result, also returned in A
VF_COUNT    equ     $F041           ; 2: bytes read / written (also in X)
VF_SIZE     equ     $F043           ; 4: file size (FOPEN, DIR)
VF_ATTR     equ     $F047           ; 1: DIR entry: $10 directory, $01 read-only
VF_LEN      equ     $F048           ; 2: bytes for FREAD / FWRITE
VF_CAPS     equ     $F04A           ; 1: set to 1 after each command by firmware with FAPPEND
VF_DATA     equ     $F200           ; 512: data buffer

; Results: 0 OK, 3 no drive, 4 no such file, 5 no such path, 7 denied or
; disk full, 8 already exists, 9 no file open, 13 not a FAT drive,
; 19 bad command (FatFs FRESULT codes).
FR_NOTREADY equ     3

VM_TEXT80   equ     0               ; 80x30 text, 2 bytes per cell (char, attr)
VM_BMP320   equ     1               ; 320x240, 1 byte per pixel
VM_TEXT40   equ     2               ; 40x30 text
VM_TEXT80X60 equ    3               ; 80x60 text
VM_BMP256   equ     4               ; 256x192 in a border

VREG_RD     equ     $80             ; SYS_VREG: B = register + VREG_RD reads
