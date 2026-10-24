; ======================================================================
;  MC.PRG - a two-panel file manager for MINI09, after Midnight Commander
;
;     MC [folder]        (the shell runs MC.PRG when you type MC)
;
;  Two panels side by side on the 80x30 screen, each listing a folder of
;  the flash drive: folders first, then files, sorted by name ignoring
;  case.  Drawn with the same VT100 subset as EDIT (cursor position,
;  erase line, reverse), so it works on the HDMI screen and a serial
;  terminal with 30 rows.
;
;  Keys: Up, Down, PgUp, PgDn, Home, End move; Tab switches panels;
;  Enter opens a folder (.. goes up); Insert or ^T marks; F5 copies and
;  F6 moves the marked entries (or the one under the cursor) to the other
;  panel's folder; F8 deletes them; ^R reads the panel's folder again;
;  ^L redraws; F1 help; F10 or ^X quits.  ESC then a digit is the same
;  as that function key (ESC 0 = F10), for keyboards without them.
;
;  Each panel's list lives in its own RAM page, mapped at $8000-$BFFF
;  while it is read or drawn: an index of 2-byte pointers at $8000, one
;  per entry in sorted order, then the entries themselves from $8400.
;  An entry is the attribute byte, the size (4 bytes, big-endian) and
;  the name, NUL-terminated.  The index is kept sorted as the folder is
;  read: a binary search finds each new entry's place.
;
;  Screen: row 1 the panels' top borders with their folders, rows 2-27
;  the entries, row 28 the bottom borders with the entry counts, row 29
;  the selected entry in full (or a message), row 30 the function keys.
;  Only what changes is redrawn: the two rows a cursor move touches, or
;  a panel's rows after a scroll, since a serial console runs at 9600
;  baud.
; ======================================================================

            include "syscalls.inc"
            include "vdp.inc"

PAGEL       equ     $03             ; RAM page for the left panel's list
PAGER       equ     $04             ; and for the right one's
BUFPG       equ     $05             ; copy buffer: pages $05-$1F
BUFBLK      equ     27*32           ; its 512-byte blocks (432K)
PWIN        equ     $8000           ; the mapped page
PIDX        equ     PWIN            ; index: 2 bytes per entry
MAXENT      equ     512
PREC        equ     PWIN+MAXENT*2   ; the entries
PEND        equ     PWIN+$4000

R_ATTR      equ     0               ; an entry: attribute ($10 = folder,
                                    ; M_MARK = marked)
M_MARK      equ     $80
R_SIZE      equ     1               ; size, 4 bytes
R_NAME      equ     5               ; name, NUL-terminated

; A panel: its folder, page and position
P_PATH      equ     0               ; 64: folder, "" = root, no leading /
P_PAGE      equ     64              ; RAM page for its list
P_X         equ     65              ; screen column of its left border
P_CNT       equ     66              ; 2: entries
P_TOP       equ     68              ; 2: entry on the first row
P_CUR       equ     70              ; 2: the selected entry
P_OLD       equ     72              ; 2: the selected entry when last drawn
P_FREE      equ     74              ; 2: where the next entry goes
P_RED       equ     76              ; redraw: RD_xxx bits
P_FULL      equ     77              ; non-zero: the folder didn't all fit
P_NMARK     equ     78              ; 2: marked entries
PSZ         equ     80
PATHMAX     equ     63

RD_CUR      equ     1               ; the old and new cursor rows
RD_ROWS     equ     2               ; every row
RD_FRAME    equ     4               ; top and bottom borders

ROWS        equ     30              ; screen rows
PROWS       equ     26              ; entry rows in a panel, from row 2
PW          equ     40              ; panel width, borders included
NAMEW       equ     28              ; name column
SIZEW       equ     9               ; size column
TAB         equ     $09

; Our file results, past the drive's (ferrtxt)
ER_LONG     equ     $F0             ; a path over PATHMAX
ER_NOTEMPTY equ     $F1             ; delete: a folder with things in it
ER_FIRMWARE equ     $F2             ; a file over 432K needs FAPPEND
ER_CANCEL   equ     $F3             ; ESC or ^C during a copy

; Key codes for VT100 sequences
K_UP        equ     $80
K_DOWN      equ     $81
K_RIGHT     equ     $82
K_LEFT      equ     $83
K_HOME      equ     $84
K_END       equ     $85
K_PGUP      equ     $86
K_PGDN      equ     $87
K_DEL       equ     $88
K_INS       equ     $89
K_F1        equ     $91             ; K_F1 .. K_F1+9 = F1 .. F10
K_F10       equ     K_F1+9

            org     $1000
start:      lds     #stktop
            ldx     #mvars          ; all the variables start at 0
st0:        clr     ,x+
            cmpx    #mvend
            blo     st0
            ldb     #$FF            ; which page we have
            OS      SYS_BANK
            sta     mcur
            lda     #PAGEL
            sta     pl+P_PAGE
            lda     #1
            sta     pl+P_X
            lda     #PAGER
            sta     pr+P_PAGE
            lda     #PW+1
            sta     pr+P_X
            ldd     ARGS            ; MC folder: the left panel starts there
            cmpd    #ARGMARK
            bne     st2
            ldd     #0              ; used up
            std     ARGS
            ldx     #ARGS+2
            jsr     skipsp
            lda     ,x
            cmpa    #'/
            bne     st1
            leax    1,x
st1:        ldu     #pl+P_PATH
            ldb     #PATHMAX
            jsr     cpyword
            ldx     #pl+P_PATH      ; drop a trailing /
            jsr     strend
            cmpx    #pl+P_PATH
            beq     st2
            lda     ,-x
            cmpa    #'/
            bne     st2
            clr     ,x
st2:        ldu     #pl
            stu     act
            jsr     readdir
            bcc     st3
            clr     pl+P_PATH       ; no such folder: the root instead
            jsr     readdir
st3:        ldu     #pr
            jsr     readdir
            lda     #1
            sta     rdall

; ---- main loop: bring the screen up to date, then do one key ----------
mloop:      jsr     redraw
            jsr     getkey
            ldx     msgp            ; a message stays until the next key
            beq     ml1
            ldx     #0
            stx     msgp
            inc     rdinfo
ml1:        ldx     #mkeys
ml2:        ldb     ,x
            cmpb    #$FF
            beq     ml4
            cmpa    ,x
            beq     ml3
            leax    3,x
            bra     ml2
ml3:        ldu     act
            jsr     [1,x]
            bra     mloop
ml4:        cmpa    #K_F1           ; a function key we don't have yet
            blo     mloop
            cmpa    #K_F10
            bhi     mloop
            ldx     #msg_notyet
            jsr     setmsg
            bra     mloop

mkeys:      fcb     K_UP
            fdb     k_up
            fcb     K_DOWN
            fdb     k_down
            fcb     K_PGUP
            fdb     k_pgup
            fcb     K_PGDN
            fdb     k_pgdn
            fcb     K_HOME
            fdb     k_home
            fcb     K_END
            fdb     k_end
            fcb     TAB
            fdb     k_tab
            fcb     CR
            fdb     k_enter
            fcb     $12             ; ^R
            fdb     k_reread
            fcb     $0C             ; ^L
            fdb     k_redraw
            fcb     K_F1
            fdb     k_help
            fcb     K_INS
            fdb     k_mark
            fcb     $14             ; ^T
            fdb     k_mark
            fcb     K_F1+4          ; F5
            fdb     k_copy
            fcb     K_F1+5          ; F6
            fdb     k_move
            fcb     K_F1+7          ; F8
            fdb     k_delete
            fcb     K_F10
            fdb     k_quit
            fcb     $18             ; ^X
            fdb     k_quit
            fcb     $FF

; ---- key handlers: U = the active panel --------------------------------
k_up:       ldd     P_CUR,u
            beq     kmv9
            subd    #1
            bra     kmove
k_down:     ldd     P_CUR,u
            addd    #1
            cmpd    P_CNT,u
            bhs     kmv9
            bra     kmove
k_pgup:     ldd     P_CUR,u
            subd    #PROWS-1
            bcc     kmove
            ldd     #0
            bra     kmove
k_pgdn:     ldd     P_CNT,u
            beq     kmv9
            ldd     P_CUR,u
            addd    #PROWS-1
            cmpd    P_CNT,u
            blo     kmove
k_end:      ldd     P_CNT,u
            beq     kmv9
            subd    #1
            bra     kmove
k_home:     ldd     #0
; Move the cursor to entry D, scrolling if it leaves the panel
kmove:      std     P_CUR,u
            lda     P_RED,u
            ora     #RD_CUR
            sta     P_RED,u
            inc     rdinfo
            jsr     settop
kmv9:       rts

k_tab:      lda     P_RED,u         ; the cursor bar and the top border
            ora     #RD_CUR+RD_FRAME
            sta     P_RED,u
            jsr     other
            stx     act
            lda     P_RED,x
            ora     #RD_CUR+RD_FRAME
            sta     P_RED,x
            inc     rdinfo
            rts

k_redraw:   lda     #1
            sta     rdall
            rts

k_help:     ldx     #msg_help
            jmp     setmsg

k_quit:     ldx     #msg_cls
            jsr     puts
            OS      SYS_EXIT

; ^R: read the folder again, keeping the cursor on the same name
k_reread:   clr     keepnm
            ldd     P_CNT,u
            beq     krr1
            ldd     P_CUR,u
            jsr     entry           ; X -> the entry
            leax    R_NAME,x
            pshs    u
            ldu     #keepnm
            ldb     #PATHMAX
            jsr     cpyword0
            puls    u
krr1:       ldd     P_CUR,u         ; if it's gone, about where it was
            std     fnfall
            jsr     readdir
            bcs     krr9
            ldx     #keepnm
            jsr     findname
krr9:       rts

; Enter: open the folder under the cursor
k_enter:    ldd     P_CNT,u
            lbeq    ken9
            ldd     P_CUR,u
            jsr     entry
            lda     R_ATTR,x
            bita    #$10
            beq     ken8            ; a file: nothing to do yet
            leax    R_NAME,x
            ldd     ,x
            cmpd    #$2E2E          ; ".."
            bne     ken2
            tst     2,x
            beq     k_parent
ken2:       pshs    x               ; the folder's name
            leax    P_PATH,u        ; to come back to if it can't be read
            ldu     #oldpath
            ldb     #PATHMAX
            jsr     cpyword0
            ldu     act
            leax    P_PATH,u
            jsr     strlen          ; B = the folder's length
            pshs    b
            ldx     1,s
            jsr     strlen
            addb    ,s+
            tst     P_PATH,u        ; the / between them
            beq     ken3
            incb
ken3:       cmpb    #PATHMAX
            bls     ken4
            puls    x
            ldx     #msg_long
            jmp     setmsg
ken4:       leax    P_PATH,u
            jsr     strend
            tst     P_PATH,u
            beq     ken5
            lda     #'/
            sta     ,x+
ken5:       tfr     x,u
            puls    x
            ldb     #PATHMAX
            jsr     cpyword0
            ldu     act
            jsr     readdir
            bcc     ken9
            ldx     #oldpath        ; back to where we were
            leau    P_PATH,u
            ldb     #PATHMAX
            jsr     cpyword0
            ldu     act
            ldx     msgp            ; keep readdir's message
            pshs    x
            jsr     readdir
            puls    x
            stx     msgp
ken9:       rts
ken8:       ldx     #msg_nofile
            jmp     setmsg

; .. : up to the parent folder, with the cursor on the one we left
k_parent:   leax    P_PATH,u
            jsr     strend          ; X -> the NUL
kp1:        cmpx    act             ; back to the last / or the start
                                    ; (P_PATH is 0: the panel's address)
            beq     kp2
            lda     ,-x
            cmpa    #'/
            bne     kp1
            leax    1,x
kp2:        pshs    x
            ldu     #keepnm
            ldb     #PATHMAX
            jsr     cpyword0
            puls    x
            ldu     act
            cmpx    act
            beq     kp3
            leax    -1,x            ; the / goes too
kp3:        clr     ,x
            jsr     readdir
            bcs     kp9
            ldd     #0
            std     fnfall
            ldx     #keepnm
            jsr     findname
kp9:        rts

; The other panel than U -> X
other:      ldx     #pr
            cmpu    #pl
            beq     ot9
            ldx     #pl
ot9:        rts

; Message X on row 29 until the next key
setmsg:     stx     msgp
            inc     rdinfo
            rts

; Put the cursor on the entry named X (ignoring case), or if it's gone on
; entry fnfall (or the last)
findname:   ldd     #0
fn1:        cmpd    P_CNT,u
            bhs     fn8
            pshs    d,x
            jsr     entry
            leay    R_NAME,x
            ldx     2,s
            jsr     namecmp
            puls    d,x
            beq     fn9
            addd    #1
            bra     fn1
fn8:        ldd     P_CNT,u
            beq     fn9
            subd    #1
            cmpd    fnfall
            bls     fn9
            ldd     fnfall
fn9:        std     P_CUR,u
            std     P_OLD,u
            ldd     P_CUR,u
            subd    #PROWS/2        ; in the middle of the panel
            bcc     fn10
            ldd     #0
fn10:       std     P_TOP,u
            ; fall into settop to keep the last rows full

; Keep the cursor on the panel's rows, scrolling if it isn't
settop:     ldd     P_CUR,u
            cmpd    P_TOP,u
            bhs     stp1
            std     P_TOP,u         ; above the top
            bra     stp8
stp1:       subd    P_TOP,u
            cmpd    #PROWS
            blo     stp9
            ldd     P_CUR,u         ; below the bottom
            subd    #PROWS-1
            std     P_TOP,u
stp8:       lda     P_RED,u
            ora     #RD_ROWS
            sta     P_RED,u
stp9:       rts

; ---- marking ------------------------------------------------------------
; Insert or ^T: mark or unmark the entry under the cursor, then move down
k_mark:     ldd     P_CNT,u
            beq     kmk9
            ldb     P_PAGE,u
            jsr     pmap
            ldd     P_CUR,u
            jsr     entry
            jsr     isup            ; .. can't be marked
            beq     kmk1
            lda     R_ATTR,x
            eora    #M_MARK
            sta     R_ATTR,x
            pshs    a
            ldd     P_NMARK,u
            addd    #1
            tst     ,s+
            bmi     kmk0
            subd    #2
kmk0:       std     P_NMARK,u
kmk1:       lda     P_RED,u         ; its row, even at the last entry
            ora     #RD_CUR
            sta     P_RED,u
            inc     rdinfo
            jmp     k_down
kmk9:       rts

; Is entry X ..?  Z=1 if it is.
isup:       lda     R_NAME,x
            cmpa    #'.
            bne     iu9
            lda     R_NAME+1,x
            cmpa    #'.
            bne     iu9
            tst     R_NAME+2,x
iu9:        rts

; ---- copy, move, delete -------------------------------------------------
; They work on the selection of panel opan: the marked entries, or the
; one under the cursor if none is marked.  An error stops the operation
; with a message (operr); either way both panels are read again after.

; F8: delete the selection.  A folder must be empty (the drive's delete
; won't remove one that isn't).
k_delete:   sts     opsp
            stu     opan
            ldx     #msg_vdel
            jsr     opstart
            bcs     kd9
            ldu     mbend
            ldx     #msg_yn
            jsr     app
            jsr     askkey
            cmpa    #'Y
            bne     kd9
            ldd     #0
            std     sidx
kd1:        ldu     opan
            jsr     selnext
            bcs     kd8
            ldx     opan            ; (P_PATH is 0)
            ldy     #curnm
            ldu     #pbuf
            jsr     mkpath
            lbcs    toolong
            ldx     #pbuf
            jsr     setvname
            lda     #VCMD_FDELETE
            jsr     fcmd
            lbcs    operr
            bra     kd1
kd8:        jmp     opdone
kd9:        rts

; F5: copy the selection to the other panel's folder.  F6: move it there
; (copy, then delete the original).  Files only: the drive has no command
; to make a folder, so folders are skipped and counted.
k_copy:     clr     opmove
            bra     kc0
k_move:     lda     #1
            sta     opmove
kc0:        sts     opsp
            stu     opan
            jsr     other
            stx     dpan
            ldx     opan            ; the same folder?
            ldy     dpan
            jsr     namecmp
            bne     kc1
            ldx     #msg_same
            jmp     setmsg
kc1:        ldx     #msg_vcopy
            tst     opmove
            beq     kc2
            ldx     #msg_vmove
kc2:        jsr     opstart
            lbcs    kc9
            ldu     mbend
            ldx     #msg_to
            jsr     app
            ldx     dpan
            jsr     app
            ldx     #msg_yn
            jsr     app
            jsr     askkey
            cmpa    #'Y
            lbne    kc9
            clr     ovall
            clr     nskip
            ldd     #0
            std     sidx
kc3:        ldu     opan
            jsr     selnext
            bcs     kc8
            tst     curat
            beq     kc4
            inc     nskip           ; a folder
            bra     kc3
kc4:        ldx     opan
            ldy     #curnm
            ldu     #pbuf
            jsr     mkpath
            bcs     toolong
            ldx     dpan
            ldy     #curnm
            ldu     #pbuf2
            jsr     mkpath
            bcs     toolong
            jsr     copyfile        ; C=1: not copied (not overwritten)
            bcs     kc3
            tst     opmove
            beq     kc3
            ldx     #pbuf           ; moved: the original goes
            jsr     setvname
            lda     #VCMD_FDELETE
            jsr     fcmd
            lbcs    operr
            bra     kc3
kc8:        tst     nskip
            beq     kc81
            ldx     #msg_skipdir
            jsr     setmsg
kc81:       jmp     opdone
kc9:        rts
toolong:    lda     #ER_LONG
            ; fall into operr

; A file operation failed with result A on curnm: back to the main loop
; with " name: what went wrong" on row 29, after reading both panels again.
operr:      lds     opsp
            pshs    a
            lda     #VCMD_FCLOSE    ; whatever is open
            jsr     fcmd
            puls    a
            tst     created         ; a copy that stopped: delete the part
            beq     oe0
            pshs    a
            ldx     #pbuf2
            jsr     setvname
            lda     #VCMD_FDELETE
            jsr     fcmd
            clr     created
            puls    a
            bra     oe1
oe0:        ldb     curat           ; a folder that won't go is not empty
            beq     oe1
            cmpa    #7
            bne     oe1
            lda     #ER_NOTEMPTY
oe1:        jsr     ferrtxt
            pshs    x
            ldu     #msgbuf
            lda     #$20
            sta     ,u+
            ldx     #curnm
            jsr     app
            lda     #':
            sta     ,u+
            puls    x
            jsr     app
            ldx     #msgbuf
            jsr     setmsg
            ; fall into opdone

; Read both panels again, the cursors staying on the same names
opdone:     ldu     #pl
            jsr     k_reread
            ldu     #pr
            jmp     k_reread

; Start an operation on the selection of panel opan: msgbuf <- " " X and
; the one name or "n entries", mbend -> its end.  C=1 (with a message) if
; nothing is selected.
opstart:    pshs    x
            ldu     opan
            jsr     selcount
            std     nsel
            puls    x
            bne     ops1
            ldx     #msg_nosel
            jsr     setmsg
            orcc    #$01
            rts
ops1:       ldu     #msgbuf
            lda     #$20
            sta     ,u+
            jsr     app
            ldd     nsel
            cmpd    #1
            bne     ops2
            pshs    u
            ldd     #0
            std     sidx
            ldu     opan
            jsr     selnext         ; its name
            puls    u
            ldx     #curnm
            jsr     app
            bra     ops3
ops2:       jsr     utoa16
            leau    -1,u
            ldx     #msg_nents
            jsr     app
ops3:       stu     mbend
            andcc   #$FE
            rts

; How many entries of panel U are selected -> D (Z=1 if none)
selcount:   ldd     P_NMARK,u
            bne     sc9
            ldd     P_CNT,u
            beq     sc9
            ldb     P_PAGE,u
            jsr     pmap
            ldd     P_CUR,u
            jsr     entry
            jsr     isup
            beq     sc8
            ldd     #1
            rts
sc8:        ldd     #0
sc9:        rts

; The next selected entry of panel U from entry sidx on: its name to
; curnm, $10 in curat if it is a folder; sidx moves past it.  C=1 when
; there are no more.
selnext:    ldb     P_PAGE,u
            jsr     pmap
sn1:        ldd     sidx
            cmpd    P_CNT,u
            bhs     sn8
            addd    #1
            std     sidx
            subd    #1
            ldy     P_NMARK,u
            bne     sn2
            cmpd    P_CUR,u         ; no marks: the cursor's entry
            bne     sn1
            jsr     entry
            jsr     isup
            beq     sn8
            bra     sn3
sn2:        jsr     entry           ; marks: each marked one
            lda     R_ATTR,x
            bpl     sn1
sn3:        lda     R_ATTR,x
            anda    #$10
            sta     curat
            leax    R_NAME,x
            pshs    u
            ldu     #curnm
            ldb     #PATHMAX
            jsr     cpyword0
            puls    u
            andcc   #$FE
            rts
sn8:        orcc    #$01
            rts

; Copy file pbuf to pbuf2 (curnm is its name).  If pbuf2 is there already
; it asks first; C=1 if the answer was no.  The file goes through RAM
; pages BUFPG on, BUFBLK blocks of 512 at a time: the drive has one file
; open at a time and can't seek, so a file bigger than that is read again
; from the start for each round, skipping what is done, and the rounds
; after the first are appended (FAPPEND).
copyfile:   tst     ovall
            bne     cf1
            ldx     #pbuf2          ; there already?
            jsr     setvname
            lda     #VCMD_FOPEN
            jsr     fcmd
            pshs    cc
            lda     #VCMD_FCLOSE
            jsr     fcmd
            puls    cc
            bcs     cf1             ; no
            ldu     #msgbuf
            ldx     #msg_over
            jsr     app
            ldx     #curnm
            jsr     app
            ldx     #msg_yna
            jsr     app
            jsr     askkey
            cmpa    #'A
            bne     cf0
            sta     ovall           ; all: don't ask again
            bra     cf1
cf0:        cmpa    #'Y
            beq     cf1
            orcc    #$01
            rts
cf1:        clr     created
            ldu     #msgbuf         ; " Copying name" while it works
            ldx     #msg_copying
            jsr     app
            ldx     #curnm
            jsr     app
            ldx     #msgbuf
            jsr     showrow
            clr     rounds
cf2:        ldx     #pbuf           ; read a bufferful
            jsr     setvname
            lda     #VCMD_FOPEN
            jsr     fcmd
            lbcs    operr
            ldx     #zero2          ; VF_LEN = 0: whole blocks
            ldu     #VF_LEN
            ldd     #2
            jsr     vput
            lda     rounds          ; skip what earlier rounds copied
            sta     cnt8
cf3:        tst     cnt8
            beq     cf5
            ldd     #BUFBLK
            std     nblk
cf4:        jsr     chkabort
            lda     #VCMD_FREAD
            jsr     fcmd
            lbcs    operr
            ldd     nblk
            subd    #1
            std     nblk
            bne     cf4
            dec     cnt8
            bra     cf3
cf5:        ldd     #0
            std     nblk
            clr     ceof
cf6:        jsr     chkabort
            lda     #VCMD_FREAD
            jsr     fcmd
            lbcs    operr
            stx     lastn
            beq     cf7e            ; the end: nothing in this block
            ldd     nblk
            jsr     blkaddr
            ldu     #VF_DATA
            ldd     lastn
            std     lastlen
            jsr     vget
            ldd     nblk
            addd    #1
            std     nblk
            ldd     lastn
            cmpd    #512
            blo     cf7e            ; a short block ends it
            ldd     nblk
            cmpd    #BUFBLK
            blo     cf6
            bra     cf7             ; the buffer is full, more to come
cf7e:       inc     ceof
cf7:        lda     #VCMD_FCLOSE
            jsr     fcmd
            ldx     #pbuf2          ; write it: a new file, or appended
            jsr     setvname
            lda     #VCMD_FCREATE
            tst     rounds
            beq     cf8
            jsr     hasappend
            lbcs    operr
            lda     #VCMD_FAPPEND
cf8:        jsr     fcmd
            lbcs    operr
            lda     #1
            sta     created         ; a cancel deletes what's written
            ldd     #0
            std     wblk
cf9:        ldd     wblk
            cmpd    nblk
            bhs     cf11
            addd    #1              ; the last block may be short
            cmpd    nblk
            beq     cf91
            ldd     #512
            bra     cf10
cf91:       ldd     lastlen
cf10:       std     wlen
            jsr     chkabort
            ldd     wblk
            jsr     blkaddr
            ldu     #VF_DATA
            ldd     wlen
            jsr     vput
            ldx     #wlen           ; VF_LEN (both big-endian)
            ldu     #VF_LEN
            ldd     #2
            jsr     vput
            lda     #VCMD_FWRITE
            jsr     fcmd
            lbcs    operr
            cmpx    wlen
            beq     cf105
            lda     #7              ; a short write: the disk is full
            lbra    operr
cf105:      ldd     wblk
            addd    #1
            std     wblk
            bra     cf9
cf11:       lda     #VCMD_FCLOSE
            jsr     fcmd
            lbcs    operr
            tst     ceof
            bne     cf12
            inc     rounds
            lbra    cf2
cf12:       clr     created
            andcc   #$FE
            rts

; ESC or ^C typed?  Then stop the copy.  Other keys are dropped.
chkabort:   OS      SYS_POLL
            bcs     ca9
            cmpa    #ESC
            beq     ca8
            cmpa    #3
            bne     chkabort
ca8:        lda     #ER_CANCEL
            jmp     operr
ca9:        rts

; Block D of the copy buffer: its page mapped, X -> it in the window
blkaddr:    pshs    d
            lsra                    ; / 32 blocks a page
            rorb
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            lsra
            rorb
            addb    #BUFPG
            jsr     pmap
            puls    d
            andb    #31             ; * 512
            lslb
            tfr     b,a
            clrb
            addd    #PWIN
            tfr     d,x
            rts

; Does the firmware have FAPPEND?  C=1 and A = ER_FIRMWARE if not.  It sets
; bit 0 of VF_CAPS after each command if it has (README, "Files").
hasappend:  lda     caps            ; 0 not asked yet, 1 yes, 2 no
            bne     ha1
            ldx     #zero2
            ldu     #VF_CAPS
            ldd     #1
            jsr     vput
            lda     #VCMD_FCLOSE
            jsr     fcmd
            ldx     #capsb
            ldu     #VF_CAPS
            ldd     #1
            jsr     vget
            lda     #2
            ldb     capsb
            andb    #1
            beq     ha0
            lda     #1
ha0:        sta     caps
ha1:        cmpa    #1
            bne     ha8
            andcc   #$FE
            rts
ha8:        lda     #ER_FIRMWARE
            orcc    #$01
            rts

; Path X / name Y -> U ("name" alone at the root).  C=1 if it would be
; longer than PATHMAX.
mkpath:     pshs    x,y
            jsr     strlen          ; the folder's length
            tstb
            beq     mp1
            incb                    ; and the /
mp1:        pshs    b
            tfr     y,x
            jsr     strlen
            addb    ,s+
            bcs     mp9
            cmpb    #PATHMAX
            bhi     mp9
            puls    x,y
            tst     ,x
            beq     mp2
            jsr     app
            lda     #'/
            sta     ,u+
mp2:        tfr     y,x
            jsr     app
            andcc   #$FE
            rts
mp9:        puls    x,y
            orcc    #$01
            rts

; The string X to the mailbox's VF_NAME
setvname:   jsr     strlen
            incb
            clra
            ldu     #VF_NAME
            jmp     vput

; Append string X at U: U -> its NUL
app:        lda     ,x+
            sta     ,u+
            bne     app
            leau    -1,u
            rts

; msgbuf on row 29 in reverse, then wait for a key -> A, in capitals
askkey:     ldx     #msgbuf
            bsr     showrow
            jsr     getkey
            jmp     upper

; String X on row 29, in reverse, at most 78 characters
showrow:    pshs    x
            lda     #ROWS-1
            ldb     #1
            jsr     goto
            ldx     #msg_eeol
            jsr     puts
            ldx     #msg_rev
            jsr     puts
            puls    x
            jsr     putsl
            ldx     #msg_norm
            jsr     puts
            inc     rdinfo
            rts

; String X, at most 78 characters of it
putsl:      ldb     #78
psl1:       lda     ,x+
            beq     psl9
            jsr     putc
            decb
            bne     psl1
psl9:       rts

; ---- reading a folder ---------------------------------------------------
; Read panel U's folder into its page, sorted.  C=1 with a message set if
; it can't be read: the panel is then empty (just .. outside the root).
readdir:    ldb     P_PAGE,u
            jsr     pmap
            ldd     #0
            std     P_CNT,u
            std     P_TOP,u
            std     P_CUR,u
            std     P_OLD,u
            std     P_NMARK,u
            clr     P_FULL,u
            lda     #RD_ROWS+RD_FRAME
            ora     P_RED,u
            sta     P_RED,u
            inc     rdinfo
            ldx     #PREC
            stx     P_FREE,u
            tst     P_PATH,u        ; outside the root, .. comes first
            beq     rd1
            ldd     #$1000          ; a folder, size 0
            std     ,x
            clr     2,x
            ldd     #$0000
            std     3,x
            ldd     #$2E2E
            std     R_NAME,x
            clr     R_NAME+2,x
            stx     PIDX
            leax    R_NAME+3,x
            stx     P_FREE,u
            ldd     #1
            std     P_CNT,u
rd1:        leax    P_PATH,u        ; the folder's name to the mailbox
            jsr     strlen
            incb
            clra
            pshs    u
            ldu     #VF_NAME
            jsr     vput
            puls    u
            lda     #VCMD_DIR
            jsr     fcmd
            bcs     rd_err
rd2:        pshs    u
            ldx     #mbox           ; the entry's name, size and attribute
            ldu     #VF_NAME
            ldd     #VF_ATTR+1-VF_NAME
            jsr     vget
            puls    u
            ldx     #mbox
            lda     ,x
            beq     rd9             ; the end of the folder
            cmpa    #'.             ; . and .. are ours to add
            bne     rd3
            lda     1,x
            beq     rd8
            cmpa    #'.
            bne     rd3
            tst     2,x
            beq     rd8
rd3:        jsr     strlen          ; room for it?
            clra
            addd    #R_NAME+1
            addd    P_FREE,u
            bcs     rd7
            cmpd    #PEND
            bhi     rd7
            ldd     P_CNT,u
            cmpd    #MAXENT
            bhs     rd7
            ldy     P_FREE,u        ; store it
            lda     mbox+VF_ATTR-VF_NAME
            anda    #$10
            sta     R_ATTR,y
            ldd     mbox+VF_SIZE-VF_NAME
            std     R_SIZE,y
            ldd     mbox+VF_SIZE-VF_NAME+2
            std     R_SIZE+2,y
            pshs    u
            leau    R_NAME,y
            ldx     #mbox
            ldb     #PATHMAX
            jsr     cpyword0        ; U -> after the NUL
            tfr     u,d
            puls    u
            std     P_FREE,u
            jsr     insert          ; Y = the entry
            bra     rd8
rd7:        inc     P_FULL,u        ; no room: count it, skip it
rd8:        lda     #VCMD_DIRNEXT
            jsr     fcmd
            bcc     rd2
rd_err:     pshs    a
            lda     #VCMD_FCLOSE
            jsr     fcmd
            puls    a
            jsr     ferrmsg
            orcc    #$01
            rts
rd9:        lda     #VCMD_FCLOSE
            jsr     fcmd
            tst     P_FULL,u
            beq     rd10
            ldx     #msg_full
            jsr     setmsg
rd10:       andcc   #$FE
            rts

; Put entry Y into panel U's sorted index (a binary search for its place,
; after .. if that is there), one more entry.
insert:     ldd     #0
            tst     P_PATH,u
            beq     in1
            ldd     #1
in1:        std     lo
            ldd     P_CNT,u
            std     hi
in2:        ldd     lo              ; lo < hi: look at the middle
            cmpd    hi
            bhs     in5
            addd    hi
            lsra
            rorb
            std     mid
            jsr     entry           ; X -> the middle entry
            exg     x,y
            jsr     entcmp          ; new (X) before middle (Y)?
            exg     x,y
            bcs     in3
            ldd     mid             ; no: after it
            addd    #1
            std     lo
            bra     in2
in3:        ldd     mid
            std     hi
            bra     in2
in5:        ldd     P_CNT,u         ; move the index from lo up by one
            lslb
            rola
            addd    #PIDX
            tfr     d,x
            ldd     lo
            lslb
            rola
            addd    #PIDX
            pshs    d
in6:        cmpx    ,s
            bls     in7
            ldd     -2,x
            std     ,x
            leax    -2,x
            bra     in6
in7:        leas    2,s
            sty     ,x
            ldd     P_CNT,u
            addd    #1
            std     P_CNT,u
            rts

; Entry D of panel U -> X (its page must be mapped)
entry:      lslb
            rola
            addd    #PIDX
            tfr     d,x
            ldx     ,x
            rts

; Does entry X sort before entry Y?  C=1 if it does.  Folders come first,
; then by name, ignoring case.
entcmp:     lda     R_ATTR,x
            eora    R_ATTR,y
            bita    #$10
            beq     ec1
            lda     R_ATTR,x        ; one is a folder: is it X?
            bita    #$10
            beq     ec8
ec7:        orcc    #$01
            rts
ec1:        pshs    x,y
            leax    R_NAME,x
            leay    R_NAME,y
            bsr     namecmp
            puls    x,y,pc
ec8:        andcc   #$FE
            rts

; Compare names X and Y ignoring case: Z=1 if the same, C=1 if X comes
; first.  Keeps X, Y.
namecmp:    pshs    x,y
nc1:        lda     ,x+
            bsr     upper
            pshs    a
            lda     ,y+
            bsr     upper
            cmpa    ,s+             ; Y's against X's
            bne     nc2
            tsta
            bne     nc1
            puls    x,y,pc          ; Z=1, C=0
nc2:        bhi     nc3             ; Y's is bigger: X first
            andcc   #$FA            ; C=0, Z=0
            puls    x,y,pc
nc3:        andcc   #$FB            ; Z=0
            orcc    #$01
            puls    x,y,pc

upper:      cmpa    #'a
            blo     up9
            cmpa    #'z
            bhi     up9
            suba    #$20
up9:        rts

; Map page B at $8000-$BFFF, unless it is there already.  Keeps all.
pmap:       cmpb    mcur
            beq     pm9
            stb     mcur
            pshs    a
            OS      SYS_BANK
            puls    a
pm9:        rts

; ---- drawing --------------------------------------------------------------
redraw:     tst     rdall
            beq     rw1
            clr     rdall
            ldx     #msg_cls
            jsr     puts
            lda     #RD_ROWS+RD_FRAME
            sta     pl+P_RED
            sta     pr+P_RED
            jsr     dfkeys
            inc     rdinfo
rw1:        ldu     #pl
            bsr     dpanel
            ldu     #pr
            bsr     dpanel
            tst     rdinfo
            beq     rw2
            clr     rdinfo
            jsr     dinfo
rw2:        lda     #ROWS-1         ; park the cursor on the message row
            ldb     #1
            jmp     goto

; Panel U: what P_RED asks for
dpanel:     lda     P_RED,u
            beq     dp9
            ldb     P_PAGE,u
            jsr     pmap
            bita    #RD_FRAME
            beq     dp1
            jsr     dtop
            jsr     dbottom
            lda     P_RED,u
dp1:        bita    #RD_ROWS
            beq     dp3
            clrb                    ; every row
dp2:        pshs    b
            jsr     drow
            puls    b
            incb
            cmpb    #PROWS
            blo     dp2
            bra     dp8
dp3:        ldd     P_OLD,u         ; the old cursor row, then the new
            bsr     drowe
            ldd     P_CUR,u
            bsr     drowe
dp8:        ldd     P_CUR,u
            std     P_OLD,u
            clr     P_RED,u
dp9:        rts

; Draw the row of entry D, if it is on the panel
drowe:      subd    P_TOP,u
            bcs     dre9
            cmpd    #PROWS
            bhs     dre9
            jmp     drow
dre9:       rts

; Row B (0 = the first) of panel U: | name | size |, the cursor's in reverse
drow:       pshs    b
            lda     ,s
            adda    #2
            ldb     P_X,u
            jsr     goto
            lda     #'|
            jsr     putc
            clra
            ldb     ,s
            addd    P_TOP,u
            std     rowent
            cmpd    P_CNT,u
            lbhs    dr8             ; past the last entry: blank
            cmpd    P_CUR,u
            bne     dr1
            cmpu    act
            bne     dr1
            ldx     #msg_rev
            jsr     puts
dr1:        ldd     rowent
            jsr     entry
            stx     rowp
            clr     ncol            ; the name: *marked, /folder or file
            lda     R_ATTR,x
            bpl     dr11
            lda     #'*
            jsr     putcc
dr11:       lda     R_ATTR,x
            bita    #$10
            beq     dr2
            lda     #'/
            jsr     putcc
dr2:        ldx     rowp
            leax    R_NAME,x
            jsr     strlen
            addb    ncol
            cmpb    #NAMEW
            bls     dr4
            ldb     #NAMEW-1        ; too long: cut, with a ~ at the end
            subb    ncol
dr3:        lda     ,x+
            jsr     putcc
            decb
            bne     dr3
            lda     #'~
            jsr     putcc
            bra     dr5
dr4:        jsr     putsc
dr5:        ldb     #NAMEW
            jsr     padto
            lda     #'|
            jsr     putc
            pshs    u
            ldx     rowp            ; the size, or what the folder is
            ldu     #nbuf
            lda     R_ATTR,x
            bita    #$10
            beq     dr6
            ldy     #msg_updir
            lda     R_NAME,x
            cmpa    #'.
            bne     dr51
            lda     R_NAME+1,x
            cmpa    #'.
            bne     dr51
            tst     R_NAME+2,x
            beq     dr52
dr51:       ldy     #msg_dir
dr52:       lda     ,y+
            sta     ,u+
            bne     dr52
            bra     dr7
dr6:        leax    R_SIZE,x
            jsr     fmtsize
dr7:        puls    u
            ldx     #nbuf
            jsr     strlen
            negb
            addb    #SIZEW
            clr     ncol
            jsr     spaces
            ldx     #nbuf
            jsr     puts
            ldx     #msg_norm
            jsr     puts
            bra     dr9
dr8:        clr     ncol            ; an empty row
            ldb     #NAMEW
            jsr     padto
            lda     #'|
            jsr     putc
            ldb     #SIZEW
            jsr     spaces
dr9:        lda     #'|
            jsr     putc
            puls    b,pc

; Top border of panel U, with its folder (in reverse if it is active)
dtop:       lda     #1
            ldb     P_X,u
            jsr     goto
            ldx     #msg_tl         ; "+-"
            jsr     puts
            cmpu    act
            bne     dt1
            ldx     #msg_rev
            jsr     puts
dt1:        lda     #$20
            jsr     putc
            clr     ncol
            lda     #'/
            jsr     putcc
            leax    P_PATH,u        ; at most 32 characters of the folder
            jsr     strlen
            cmpb    #31
            bls     dt2
            subb    #28             ; longer: ... and its last 28
            pshs    b
            ldx     #msg_dots
            jsr     putsc
            leax    P_PATH,u
            puls    b
            abx
dt2:        jsr     putsc
            lda     #$20
            jsr     putc
            ldx     #msg_norm
            jsr     puts
            ldb     ncol            ; dashes to the corner
            negb
            addb    #PW-5
dt3:        lda     #'-
            jsr     putc
            decb
            bne     dt3
            lda     #'+
            jmp     putc

; Bottom border of panel U, with how many entries
dbottom:    lda     #PROWS+2
            ldb     P_X,u
            jsr     goto
            ldx     #msg_tl
            jsr     puts
            lda     #$20
            jsr     putc
            ldd     P_CNT,u
            tst     P_PATH,u        ; .. isn't an entry of the folder
            beq     db1
            subd    #1
db1:        pshs    u
            ldu     #nbuf
            jsr     utoa16
            puls    u
            ldx     #nbuf
            clr     ncol
            jsr     putsc
            ldx     #msg_ents
            jsr     putsc
            ldb     ncol
            negb
            addb    #PW-4
db2:        lda     #'-
            jsr     putc
            decb
            bne     db2
            lda     #'+
            jmp     putc

; Row 29: the message, or the active panel's entry in full with its size
dinfo:      lda     #ROWS-1
            ldb     #1
            jsr     goto
            ldx     #msg_eeol
            jsr     puts
            ldx     msgp
            beq     di1
            jmp     putsl
di1:        ldu     act
            ldd     P_CNT,u
            beq     di9
            ldd     P_NMARK,u       ; " n marked |" first if there are marks
            beq     di11
            pshs    u
            ldu     #nbuf
            jsr     utoa16
            puls    u
            lda     #$20
            jsr     putc
            ldx     #nbuf
            jsr     puts
            ldx     #msg_marked
            jsr     puts
di11:       ldb     P_PAGE,u
            jsr     pmap
            ldd     P_CUR,u
            jsr     entry
            stx     rowp
            lda     #$20
            jsr     putc
            leax    R_NAME,x
            ldb     #46             ; leave room for the marks and size
di2:        lda     ,x+
            beq     di3
            jsr     putc
            decb
            bne     di2
di3:        ldx     rowp
            lda     R_ATTR,x
            bita    #$10
            bne     di9
            ldx     #msg_sp2
            jsr     puts
            ldx     rowp
            leax    R_SIZE,x
            ldu     #nbuf
            jsr     utoa32
            ldx     #nbuf
            jsr     puts
            ldx     #msg_bytes
            jmp     puts
di9:        rts

; Row 30: the function keys
dfkeys:     lda     #ROWS
            ldb     #1
            jsr     goto
            ldx     #msg_fkeys
            jmp     puts

; ---- text helpers -----------------------------------------------------------
; putcc / putsc print and count columns in ncol; padto B prints spaces
; until ncol reaches B; spaces prints B spaces.
putcc:      inc     ncol
            jmp     putc
putsc:      pshs    a
psc1:       lda     ,x+
            beq     psc2
            bsr     putcc
            bra     psc1
psc2:       puls    a,pc
padto:      subb    ncol
            bls     sps9
spaces:     tstb
            beq     sps9
sps1:       lda     #$20
            bsr     putcc
            decb
            bne     sps1
sps9:       rts

; Size at X (4 bytes) -> text at U: bytes, or K over 999,999,999
fmtsize:    ldd     ,x
            cmpd    #$3B9A
            blo     fs1
            bhi     fs2
            ldd     2,x
            cmpd    #$C9FF
            bls     fs1
fs2:        ldd     ,x              ; / 1024: shift right 10
            std     n32
            ldd     2,x
            std     n32+2
            ldb     #10
fs3:        lsr     n32
            ror     n32+1
            ror     n32+2
            ror     n32+3
            decb
            bne     fs3
            ldx     #n32
            bsr     utoa32
            lda     #'K
            sta     -1,u
            clr     ,u+
            rts
fs1:        bra     utoa32

; D -> unsigned decimal text at U, NUL-terminated.  U -> after the NUL.
utoa16:     std     n32+2
            ldd     #0
            std     n32
            ldx     #n32
; [X] (4 bytes) -> unsigned decimal text at U, NUL-terminated.  U -> after
; the NUL.  Divides by 10 a bit at a time; the digits come out last first.
utoa32:     ldd     ,x
            std     n32
            ldd     2,x
            std     n32+2
            clr     ,-s             ; end marker
ua1:        clra                    ; remainder
            ldb     #32
ua2:        lsl     n32+3
            rol     n32+2
            rol     n32+1
            rol     n32
            rola
            cmpa    #10
            blo     ua3
            suba    #10
            inc     n32+3
ua3:        decb
            bne     ua2
            adda    #'0
            pshs    a
            ldd     n32
            bne     ua1
            ldd     n32+2
            bne     ua1
ua4:        puls    a
            sta     ,u+
            bne     ua4
            rts

; Copy the NUL-terminated string X to U, at most B characters, stopping at
; a space too (cpyword) or only at the NUL (cpyword0).  U -> after the NUL.
cpyword:    lda     ,x
            beq     cw9
            cmpa    #$20
            beq     cw9
            sta     ,u+
            leax    1,x
            decb
            bne     cpyword
cw9:        clr     ,u+
            rts
cpyword0:   lda     ,x+
            beq     cw9
            sta     ,u+
            decb
            bne     cpyword0
            bra     cw9

; Length of the string X -> B (at most 255).  Keeps X.
strlen:     pshs    x
            clrb
sl1:        tst     ,x+
            beq     sl9
            incb
            bne     sl1
sl9:        puls    x,pc

; X -> the NUL at the end of the string X
strend:     tst     ,x+
            bne     strend
            leax    -1,x
            rts

skipsp:     lda     ,x
            cmpa    #$20
            bne     sk9
            leax    1,x
            bra     skipsp
sk9:        rts

; Cursor to row A, column B.  Keeps all.
goto:       pshs    d,x,y
            ldx     #msg_csi
            jsr     puts
            ldb     ,s
            clra
            jsr     putdec
            lda     #';
            jsr     putc
            ldb     1,s
            clra
            jsr     putdec
            lda     #'H
            jsr     putc
            puls    d,x,y,pc

; ---- keyboard ----------------------------------------------------------
; Next key -> A: a character, or K_xxx for a VT100 key sequence, or 0.
; ESC then a digit is a function key (ESC 0 = F10).
getkey:     OS      SYS_GETC
            cmpa    #ESC
            beq     gk1
            cmpa    #$80
            blo     gk9
gk0:        clra
gk9:        rts
gk1:        OS      SYS_GETC
            cmpa    #'[
            beq     gk2
            cmpa    #'O
            beq     gk2
            cmpa    #'0             ; ESC digit
            blo     gk0
            cmpa    #'9
            bhi     gk0
            suba    #'1
            bcc     gk11
            lda     #9              ; ESC 0: F10
gk11:       adda    #K_F1
            rts
gk2:        clr     kpar
gk3:        OS      SYS_GETC        ; parameters, up to the final byte
            cmpa    #'0
            blo     gk4
            cmpa    #'9
            bhi     gk4
            suba    #'0
            pshs    a
            lda     kpar
            ldb     #10
            mul
            addb    ,s+
            stb     kpar
            bra     gk3
gk4:        cmpa    #$40
            blo     gk3
            cmpa    #'~             ; ESC [ n ~: look up n
            bne     gk5
            ldx     #tildekeys
            lda     kpar
            bra     gk6
gk5:        ldx     #esckeys
gk6:        tst     ,x
            beq     gk0
            cmpa    ,x++
            bne     gk6
            lda     -1,x
            rts

; ESC [ or ESC O, then the final byte
esckeys:    fcb     'A,K_UP,'B,K_DOWN,'C,K_RIGHT,'D,K_LEFT
            fcb     'H,K_HOME,'F,K_END
            fcb     'P,K_F1,'Q,K_F1+1,'R,K_F1+2,'S,K_F1+3,0
; ESC [ n ~
tildekeys:  fcb     1,K_HOME,7,K_HOME,4,K_END,8,K_END
            fcb     2,K_INS,3,K_DEL,5,K_PGUP,6,K_PGDN
            fcb     11,K_F1,12,K_F1+1,13,K_F1+2,14,K_F1+3
            fcb     15,K_F1+4,17,K_F1+5,18,K_F1+6,19,K_F1+7
            fcb     20,K_F1+8,21,K_F1+9,0

; ---- files ----------------------------------------------------------------
; The message for file result A -> msgp
ferrmsg:    bsr     ferrtxt
            jmp     setmsg

; The text for file result A -> X
ferrtxt:    ldx     #msg_long
            cmpa    #ER_LONG
            beq     fe9
            ldx     #msg_notempty
            cmpa    #ER_NOTEMPTY
            beq     fe9
            ldx     #msg_firmware
            cmpa    #ER_FIRMWARE
            beq     fe9
            ldx     #msg_cancel
            cmpa    #ER_CANCEL
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
            ldx     #msg_fnofat
            cmpa    #13
            beq     fe9
            ldx     #msg_ferr
fe9:        rts

; VRAM mailbox: vput copies D bytes from X to VRAM U, vget from VRAM U to X
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

putc:       OS      SYS_PUTC
            rts

puts:       pshs    a               ; X -> NUL-terminated string
ps1:        lda     ,x+
            beq     ps2
            OS      SYS_PUTC
            bra     ps1
ps2:        puls    a,pc

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

msg_cls:    fcb     ESC
            fcc     "[0m"
            fcb     ESC
            fcc     "[2J"
            fcb     ESC
            fcn     "[H"
msg_csi:    fcb     ESC
            fcn     "["
msg_eeol:   fcb     ESC
            fcn     "[K"
msg_rev:    fcb     ESC
            fcn     "[7m"
msg_norm:   fcb     ESC
            fcn     "[0m"
msg_tl:     fcn     "+-"
msg_dots:   fcn     "..."
msg_ents:   fcn     " entries "
msg_sp2:    fcn     "  "
msg_bytes:  fcn     " bytes"
msg_dir:    fcn     "<DIR>"
msg_updir:  fcn     "<UP>"
; Row 30: 79 columns, so the screen never scrolls
msg_fkeys:  fcc     "1"
            fcb     ESC
            fcc     "[7mHelp   "
            fcb     ESC
            fcc     "[0m2"
            fcb     ESC
            fcc     "[7m       "
            fcb     ESC
            fcc     "[0m3"
            fcb     ESC
            fcc     "[7mView   "
            fcb     ESC
            fcc     "[0m4"
            fcb     ESC
            fcc     "[7mEdit   "
            fcb     ESC
            fcc     "[0m5"
            fcb     ESC
            fcc     "[7mCopy   "
            fcb     ESC
            fcc     "[0m6"
            fcb     ESC
            fcc     "[7mRenMov "
            fcb     ESC
            fcc     "[0m7"
            fcb     ESC
            fcc     "[7mMkdir  "
            fcb     ESC
            fcc     "[0m8"
            fcb     ESC
            fcc     "[7mDelete "
            fcb     ESC
            fcc     "[0m9"
            fcb     ESC
            fcc     "[7m       "
            fcb     ESC
            fcc     "[0m10"
            fcb     ESC
            fcc     "[7mQuit "
            fcb     ESC
            fcn     "[0m"
msg_help:   fcn     " Ins mark  F5 copy  F6 move  F8 delete  Tab panel  Enter open  ^R reread"
msg_notyet: fcn     " Not in this version of MC yet"
msg_nofile: fcn     " Enter opens folders; files come in a later version"
msg_long:   fcn     " Name too long (63 characters at most with its folder)"
msg_full:   fcn     " Folder too big: some entries are not shown"
msg_fnodrv: fcn     " No flash drive"
msg_fnofile: fcn    " File not found"
msg_fnopath: fcn    " Folder not found"
msg_fdenied: fcn    " Access denied or disk full"
msg_fnofat: fcn     " Not a FAT16/FAT32 drive"
msg_ferr:   fcn     " Drive error"
msg_notempty: fcn   " Folder not empty"
msg_firmware: fcn   " Over 432K: needs pico6809 firmware with FAPPEND"
msg_cancel: fcn     " Cancelled"
msg_marked: fcn     " marked |"
msg_vdel:   fcn     "Delete "
msg_vcopy:  fcn     "Copy "
msg_vmove:  fcn     "Move "
msg_nents:  fcn     " entries"
msg_to:     fcn     " to /"
msg_yn:     fcn     "? (Y/N)"
msg_over:   fcn     " Overwrite "
msg_yna:    fcn     "? (Y/N, A = all)"
msg_copying: fcn    " ESC cancels. Copying "
msg_same:   fcn     " Both panels show the same folder"
msg_nosel:  fcn     " Nothing selected"
msg_skipdir: fcn    " Folders skipped: the drive can't make folders yet"
zero2:      fdb     0

; ======================================================================
;  RAM (not part of the program file)
; ======================================================================
vblk        rmb     7               ; SYS_VCOPY / SYS_VREAD block
mbox        rmb     72              ; a copy of VF_NAME..VF_ATTR
keepnm      rmb     64              ; the name to put the cursor back on
oldpath     rmb     64              ; a panel's folder before Enter
nbuf        rmb     16              ; a number as text
curnm       rmb     64              ; the entry being worked on
pbuf        rmb     64              ; its path
pbuf2       rmb     64              ; the path it is copied to
msgbuf      rmb     160             ; a prompt or message being built

; Variables, all 0 at the start
mvars       equ     *
pl          rmb     PSZ             ; the left panel
pr          rmb     PSZ             ; the right panel
act         rmb     2               ; -> the active panel
msgp        rmb     2               ; -> the message on row 29, or 0
rdall       rmb     1               ; redraw the whole screen
rdinfo      rmb     1               ; redraw row 29
mcur        rmb     1               ; page mapped at $8000-$BFFF now
kpar        rmb     1               ; escape sequence parameter
ncol        rmb     1               ; columns printed by putcc
lo          rmb     2               ; insert: binary search
hi          rmb     2
mid         rmb     2
rowent      rmb     2               ; drow: the entry
rowp        rmb     2               ; drow, dinfo: -> the entry
n32         rmb     4               ; utoa32's number
opan        rmb     2               ; copy, move, delete: the panel
dpan        rmb     2               ; the other panel
opsp        rmb     2               ; S to go back to on an error
sidx        rmb     2               ; selnext: the next entry to look at
nsel        rmb     2               ; entries selected
mbend       rmb     2               ; -> the end of msgbuf
opmove      rmb     1               ; non-zero: move, not copy
ovall       rmb     1               ; overwrite without asking
nskip       rmb     1               ; folders skipped
curat       rmb     1               ; $10 if curnm is a folder
rounds      rmb     1               ; bufferfuls of the file done
cnt8        rmb     1
ceof        rmb     1               ; the file's end is in the buffer
caps        rmb     1               ; FAPPEND: 0 not asked, 1 yes, 2 no
capsb       rmb     1
nblk        rmb     2               ; blocks in the buffer
wblk        rmb     2               ; the block being written
wlen        rmb     2               ; its length
lastn       rmb     2               ; bytes the last read gave
lastlen     rmb     2               ; length of the buffer's last block
created     rmb     1               ; the copy's file has been made
fnfall      rmb     2               ; findname: where to go if it's gone
mvend       equ     *

            rmb     256             ; stack
stktop      equ     *

            end     start
