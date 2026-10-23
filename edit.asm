; ======================================================================
;  EDIT.PRG - full-screen text editor for MINI09
;
;     EDIT [file]        (the shell's EDIT [file] does this)
;
;  Drawn with the VT100 subset that both a serial terminal and the video
;  chip's terminal understand (cursor position, erase line, reverse).
;  The shell waits for it, so it gets every key.
;
;  The text lives in 25 RAM pages, TPAGE..TPAGE+24, so a file can be up
;  to 400K.  A position in it is 3 bytes, an offset 0..EBEND; pget and
;  pput map the page that holds one at $8000-$BFFF when they need it.
;  It is a gap buffer: the text before the cursor is at 0..egs-1 and the
;  text after it at ege..EBEND-1.  Long moves (load, find, undo) shift
;  the gap a block at a time through fbuf.
;  Lines end in LF in the buffer; CR is dropped when a file is read and
;  each LF is written back as CR LF.  Tabs are expanded to spaces (stops
;  every 8 columns) when a file is read.
;
;  Keys: arrows, Home, End, PgUp, PgDn, Backspace, Delete (or ^D),
;  Enter (keeps the indent), Tab, ^A/^E line start/end, ^K delete line,
;  ^F find (again: ^F then Enter), ^S save, ^L redraw, ^X quit,
;  ^C cut the line (more ^C in a row add the next lines), ^V paste,
;  ^Z undo, ^Y redo.  Each change is logged in RAM page UPAGE: a run
;  of typing, a deletion with its bytes, a cut block or a paste is one
;  step.  Undoing one logs its reverse in page RPAGE, for redo.
;  The clipboard (page ECPAGE) starts with CBMAGIC and its length, so a
;  cut is still there the next time EDIT runs.
;  Lines wider than the screen scroll sideways in steps of 64 columns.
; ======================================================================

            include "syscalls.inc"
            include "vdp.inc"

TPAGE       equ     $03             ; RAM pages $03-$1B hold the text
NTPAGE      equ     25              ; (25 x 16K = 400K)
ECPAGE      equ     $1E             ; RAM page that holds the clipboard
UPAGE       equ     $1D             ; RAM page that holds the undo log
RPAGE       equ     $1C             ; RAM page that holds the redo log
PWIN        equ     $8000           ; the mapped page
PSIZE       equ     $4000           ; 16K
CBMAGIC     equ     $4342           ; "CB": the clipboard page holds a cut
CBHDR       equ     4               ; magic, length; the bytes follow
URHDR       equ     6               ; undo record header: urpos .. utype
LINEMAX     equ     60              ; typed names
EDROWS      equ     30              ; screen rows: 80x30 HDMI text, status on the last
TROWS       equ     EDROWS-1        ; text rows
ECOLS       equ     80
TAB         equ     $09

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

            org     $1000
start:      lds     #stktop
            ldx     #evars          ; all the variables start at 0
st0:        clr     ,x+
            cmpx    #evend
            blo     st0
            clr     fname
            ldd     ARGS            ; the shell's arguments: the file name
            cmpd    #ARGMARK
            bne     st1
            ldd     #0              ; used up
            std     ARGS
            ldx     #ARGS+2
            jsr     skipsp
            jsr     setname
st1:        ldu     #pebend         ; empty: the gap is all of the pages
            ldy     #ege
            jsr     pcpy
            ldb     #$FF            ; which page we have
            OS      SYS_BANK
            sta     eprev
            sta     ecur
            ldb     #ECPAGE         ; a cut left by an earlier EDIT?
            jsr     ed_map
            ldd     PWIN
            cmpd    #CBMAGIC
            bne     st2
            ldd     PWIN+2
            cmpd    #PSIZE-CBHDR
            bhi     st2
            std     ecblen
st2:
            ldd     #UPAGE*256+RPAGE
            std     upg
            lda     #3
            sta     ered
            lda     #1
            sta     estat           ; 1: draw the whole status line
            ldx     #msg_cls
            jsr     puts
            tst     fname
            beq     ed_go
            jsr     ed_load
            bcc     ed_go
            bra     ed_out          ; the error is on the screen

ed_quit:    ldx     #msg_cls
            jsr     puts
ed_out:     ldb     #ECPAGE         ; the clipboard stays for next time
            jsr     ed_map
            ldd     #CBMAGIC
            std     PWIN
            ldd     ecblen
            std     PWIN+2
            OS      SYS_EXIT

ed_go:      lda     #1              ; log changes from now on
            sta     eulog

; ---- main loop: bring the screen up to date, then do one key ----------
ed_loop:    jsr     ed_col
            tst     ekeep
            bne     el1
            std     ewant
el1:        clr     ekeep
            cmpd    ehoff           ; cursor column on the screen?
            blo     el2
            subd    ehoff
            cmpd    #ECOLS
            blo     el3
el2:        ldd     ecol
            andb    #$C0
            std     ehoff
            lda     #3
            sta     ered
el3:        ldd     eline           ; cursor line on the screen?
            cmpd    etop
            bhs     el4
            std     etop
            bra     el5
el4:        subd    etop
            cmpd    #TROWS
            blo     el6
            ldd     eline
            subd    #TROWS-1
            std     etop
el5:        lda     #3
            sta     ered
el6:        lda     ered
            lbeq    el10
            cmpa    #1
            beq     el9
            cmpa    #2
            beq     el8
            cmpa    #4
            beq     el7
            ldu     #estart         ; 3: back from the cursor line to the top
            ldy     #wpos
            jsr     pcpy
            ldu     #wpos
            ldd     eline
            subd    etop
            pshs    b
el61:       tst     ,s
            beq     el63
            jsr     pdec            ; onto the LF that ends the line above
el62:       jsr     ptst
            beq     el64
            jsr     pdec
            jsr     pget
            cmpa    #LF
            bne     el62
            jsr     pinc            ; back past that LF
el64:       dec     ,s
            bra     el61
el63:       puls    b
            bra     el71
el7:        ldu     #eostart        ; 4: from the line the key was typed on
            ldb     eorow
            bra     el70
el8:        ldu     #estart         ; 2: from the cursor line
            ldd     eline
            subd    etop
el70:       pshs    b
            ldy     #wpos
            jsr     pcpy
            puls    b
el71:       jsr     ed_rows
            bra     el10
el9:        ldu     #estart         ; 1: the cursor line from column erfrom
            ldy     #wpos
            jsr     pcpy
            ldd     erfrom
            std     eskip
            subd    ehoff
            pshs    b
            negb
            addb    #ECOLS
            stb     ecnt
            puls    b
            incb
            pshs    b
            ldd     eline
            subd    etop
            tfr     b,a
            inca
            puls    b
            jsr     ed_goto
            jsr     ed_dline
el10:       clr     ered
            lda     estat           ; status line
            bmi     el12
            beq     el11
            jsr     ed_status
el11:       jsr     ed_pos
            bra     el13
el12:       lda     #1              ; message showing: replace it next time
            sta     estat
el13:       ldd     eline           ; cursor
            subd    etop
            stb     eorow
            tfr     b,a
            inca
            ldb     ecol+1
            subb    ehoff+1
            incb
            jsr     ed_goto
            ldu     #estart
            ldy     #eostart
            jsr     pcpy
            jsr     ed_key
            sta     ekey
            tst     edefer
            beq     el14
            clr     edefer
            ldb     #3
            stb     ered
            stb     estat
el14:       cmpa    #$20            ; anything but typing ends a typing run
            blo     el140
            cmpa    #$7F
            blo     el1401
el140:      jsr     ed_flush
el1401:     cmpa    #3              ; anything but ^C starts a new cut
            beq     el141
            clr     eclast
el141:      cmpa    #$18            ; anything but ^X cancels a pending quit
            beq     el15
            clr     equit
el15:       ldx     #edkeys
el16:       ldb     ,x
            cmpb    #$FF
            beq     el17
            cmpa    ,x
            beq     el18
            leax    3,x
            bra     el16
el18:       jsr     [1,x]
            lbra    ed_loop
el17:       cmpa    #$20            ; printable: insert it
            blo     el19
            cmpa    #$7F
            bhs     el19
            jsr     k_char
el19:       lbra    ed_loop

edkeys:     fcb     K_UP
            fdb     k_up
            fcb     K_DOWN
            fdb     k_down
            fcb     K_LEFT
            fdb     ed_left
            fcb     K_RIGHT
            fdb     ed_right
            fcb     K_HOME
            fdb     ed_home
            fcb     $01             ; ^A
            fdb     ed_home
            fcb     K_END
            fdb     ed_end
            fcb     $05             ; ^E
            fdb     ed_end
            fcb     K_PGUP
            fdb     k_pgup
            fcb     K_PGDN
            fdb     k_pgdn
            fcb     BS
            fdb     k_bs
            fcb     DEL
            fdb     k_bs
            fcb     K_DEL
            fdb     k_del
            fcb     $04             ; ^D
            fdb     k_del
            fcb     CR
            fdb     k_enter
            fcb     TAB
            fdb     k_tab
            fcb     $0B             ; ^K
            fdb     k_kill
            fcb     $06             ; ^F
            fdb     k_find
            fcb     $13             ; ^S
            fdb     k_save
            fcb     $0C             ; ^L
            fdb     k_redraw
            fcb     $18             ; ^X
            fdb     k_quit
            fcb     $03             ; ^C
            fdb     k_cut
            fcb     $16             ; ^V
            fdb     k_paste
            fcb     $1A             ; ^Z
            fdb     k_undo
            fcb     $19             ; ^Y
            fdb     k_redo
            fcb     $FF

; ---- key handlers -----------------------------------------------------
k_up:       inc     ekeep
            jmp     ed_up
k_down:     inc     ekeep
            jmp     ed_down

k_pgup:     bsr     kpg0
kpu1:       jsr     ed_up
            deca
            bne     kpu1
            ldd     eold            ; top moves up as far as the cursor did
            subd    eline
            pshs    d
            ldd     etop
            subd    ,s++
            bcc     kpg9
            ldd     #0
            bra     kpg9
k_pgdn:     bsr     kpg0
kpd1:       jsr     ed_down
            deca
            bne     kpd1
            ldd     eline
            subd    eold
            addd    etop
kpg9:       std     etop
            lda     #3
            sta     ered
            rts
kpg0:       inc     ekeep
            ldd     eline
            std     eold
            lda     #TROWS-1
            rts

k_bs:       ldu     #egs
            jsr     ptst
            beq     kbs9
            lda     #3              ; undo puts the cursor after it
            sta     utmp
            ldy     #udpos          ; the byte before the cursor goes
            jsr     pcpy
            ldu     #udpos
            jsr     pdec
            ldy     #usrc
            jsr     pcpy
            ldd     #1
            jsr     ed_logdel
            ldu     #egs
            jsr     pdec
            jsr     pget
            cmpa    #LF
            bne     kbs1
            ldu     eline
            leau    -1,u
            stu     eline
            lda     #2              ; lines joined
            bra     ked1
kbs1:       ldd     ecol
            subd    #1
            bra     ked2
kbs9:       rts

k_del:      ldu     #ege
            ldy     #pebend
            jsr     pcmp
            beq     kbs9
            ldd     #1
            jsr     ed_logfwd
            ldu     #ege
            jsr     pget
            jsr     pinc
            cmpa    #LF
            bne     kdl1
            lda     #2
ked1:       sta     ered
            lbra    ed_mod
kdl1:       ldd     ecol
ked2:       std     erfrom
            lda     #1
            bra     ked1

k_char:     ldd     ecol
            std     erfrom
            lda     ekey
            jsr     ed_put
            lbcs    k_full
            lda     #1
            bra     ked1

k_tab:      ldd     ecol
            std     erfrom
ktb1:       lda     #$20
            jsr     ed_put
            lbcs    k_full
            ldd     ecol
            addd    #1
            std     ecol
            andb    #7
            bne     ktb1
            lda     #1
            bra     ked1

k_enter:    ldu     #estart         ; B = spaces that start this line
            ldy     #wpos
            jsr     pcpy
            ldu     #wpos
            ldy     #egs
            clrb
ken1:       jsr     pcmp
            beq     ken2
            jsr     pget
            jsr     pinc
            cmpa    #$20
            bne     ken2
            incb
            bra     ken1
ken2:       lda     #LF
ken3:       jsr     ed_put
            bcs     k_full
            lda     #$20
            decb
            bpl     ken3
            lda     #4
            bra     ked1

k_kill:     jsr     ed_home
            bsr     ed_linelen
            beq     kkl9
            pshs    d
            jsr     ed_logfwd
            puls    d
            ldu     #ege
            jsr     padd
            lda     #2
            lbra    ked1
kkl9:       rts

; After ed_home: D = bytes from the cursor to the end of the line, LF
; included (Z=1 if none).
ed_linelen: ldu     #ege
            ldy     #wpos
            jsr     pcpy
            ldu     #wpos
            ldy     #pebend
ell1:       jsr     pcmp
            beq     ell2
            jsr     pget
            jsr     pinc
            cmpa    #LF
            bne     ell1
ell2:       ldy     #ege
            jmp     pdiff

k_full:     ldx     #msg_efull
            jmp     ed_msg

; ^C - cut the cursor's line to the clipboard (RAM page ECPAGE).  Each
; ^C straight after another adds its line to what is already there.
; The bytes go through fbuf, since only one page is mapped at a time.
k_cut:      lda     eclast          ; adding to a cut: one undo step
            sta     umerge
            bne     kct1
            clr     ecblen
            clr     ecblen+1
kct1:       lda     #1
            sta     eclast
            jsr     ed_home
            bsr     ed_linelen      ; the line, LF included, is at ege
            beq     kct9            ; nothing after the cursor
            std     ecn
            addd    ecblen
            cmpd    #PSIZE-CBHDR
            bhi     kct8
            ldd     ecn
            jsr     ed_logfwd
kct4:       jsr     ed_chunk        ; D = bytes this time
            pshs    d
            ldu     #ege            ; gone from the text
            ldy     #fbuf
            jsr     tcopy
            ldb     #ECPAGE
            jsr     ed_map
            ldd     ecblen
            addd    #PWIN+CBHDR
            tfr     d,u
            ldx     #fbuf
            ldd     ,s
            jsr     ed_copy
            puls    d
            addd    ecblen
            std     ecblen
            ldd     ecn
            bne     kct4
            lda     #2
            sta     ered
            jmp     ed_mod
kct8:       ldx     #msg_ecfull
            jmp     ed_msg
kct9:       rts

; ^V - insert the clipboard at the cursor
k_paste:    ldd     ecblen
            beq     kct9
            std     ecn
            ldd     #CBHDR          ; past the clipboard's header
            std     ecoff
            lda     #4              ; redraw from the line it started on
            sta     ered
            lda     #ECPAGE
            sta     epg
; Insert ecn bytes from offset ecoff of page epg at the cursor.
ed_insfrom:
kps1:       bsr     ed_chunk
            pshs    d
            ldb     epg
            jsr     ed_map
            ldd     ecoff
            addd    #PWIN
            tfr     d,x
            ldu     #fbuf
            ldd     ,s
            bsr     ed_copy
            ldd     ecoff
            addd    ,s
            std     ecoff
            puls    y               ; bytes in fbuf
            ldx     #fbuf
kps2:       lda     ,x+
            jsr     ed_put
            lbcs    k_full
            leay    -1,y
            bne     kps2
            ldd     ecn
            bne     kps1
            rts

; Next chunk: D = min(ecn, 512), and ecn -= D.
ed_chunk:   ldd     ecn
            cmpd    #512
            bls     ech1
            ldd     #512
ech1:       pshs    d
            ldd     ecn
            subd    ,s
            std     ecn
            puls    d,pc

; Copy D bytes (D > 0) from X to U; X and U end up past them.
ed_copy:    pshs    y
            tfr     d,y
ecp1:       lda     ,x+
            sta     ,u+
            leay    -1,y
            bne     ecp1
            puls    y,pc

; ^Z - undo the last change.  Its reverse is logged in the redo log.
k_undo:     jsr     ed_flush
            bsr     ed_pop
            bcc     kun1
            ldx     #msg_enoundo
            jmp     ed_msg
kun1:       bsr     ed_swap         ; log into the redo log
            bsr     ed_apply
            bra     ed_swap

; ^Y - redo the last undone change, logged in the undo log again
k_redo:     jsr     ed_flush
            bsr     ed_swap
            bsr     ed_pop
            bsr     ed_swap
            bcc     ed_apply
            ldx     #msg_enoredo
            jmp     ed_msg

; Exchange the undo and redo logs.  Keeps all registers.
ed_swap:    pshs    cc,d,x
            ldd     ulen
            ldx     olen
            std     olen
            stx     ulen
            ldd     upg             ; upg, opg
            exg     a,b
            std     upg
            puls    cc,d,x,pc

; Take the last record off the log: header -> urpos, urlen, utype and
; its bytes at offset ecoff of page epg.  C=1 if the log is empty.
ed_pop:     ldd     ulen
            beq     epo9
            jsr     ed_rdhdr
            ldd     ulen
            subd    #URHDR
            pshs    d
            lda     utype
            deca                    ; Z=1: typed, no bytes
            puls    d               ; (PULS keeps the flags)
            beq     epo1
            subd    urlen           ; deleted: the bytes come before it
epo1:       std     ulen
            std     ecoff
            lda     upg
            sta     epg
            andcc   #$FE
            rts
epo9:       orcc    #$01
            rts

; Do what the popped record says, in reverse: delete typed text, or
; put deleted bytes back.  The change is logged as usual.
ed_apply:   inc     eapply
            clr     umerge
            ldd     urlen
            ldx     utype-1         ; X low byte = type
            pshs    d,x
            jsr     ed_gopos
            jsr     ed_col          ; redraw from this line down if it is
            ldu     #estart         ; on the screen, else everything
            ldy     #eostart
            jsr     pcpy
            lda     #3
            sta     ered
            ldd     eline
            subd    etop
            bcs     eap1
            cmpd    #TROWS
            bhs     eap1
            stb     eorow
            lda     #4
            sta     ered
eap1:       lda     3,s
            cmpa    #1
            bne     eap2
            ldd     ,s              ; typed: delete it again
            jsr     ed_logfwd
            ldd     ,s
            ldu     #ege
            jsr     padd
            bra     eap4
eap2:       ldu     #egs            ; deleted: put the bytes back
            ldy     #eapos
            jsr     pcpy
            ldd     ,s
            std     ecn
            jsr     ed_insfrom
            lda     3,s
            cmpa    #3
            beq     eap4
            ldu     #eapos          ; cursor back to the start
            ldy     #etgt
            jsr     pcpy
            jsr     ed_seek
eap4:       bsr     ed_flush
            leas    4,s
            clr     eapply
            jmp     ed_mod

; Last record's header -> urpos, urlen, utype (ulen is kept)
ed_rdhdr:   ldb     upg
            jsr     ed_map
            ldd     ulen
            addd    #PWIN-URHDR
            tfr     d,x
            ldu     #urpos
            ldd     #URHDR
            jmp     ed_copy

; Cursor to text position urpos
ed_gopos:   ldu     #urpos
            ldy     #etgt
            jsr     pcpy
            jmp     ed_seek

; ed_put is about to insert at the cursor: extend the typing run, or
; start a new one.  Keeps all registers.
ed_logins:  pshs    d,x,y,u
            tst     uopen
            beq     eli2
            ldu     #urpos          ; does the run end at the cursor?
            ldy     #utpos
            jsr     pcpy
            ldu     #utpos
            ldd     urlen
            jsr     padd
            ldy     #egs
            jsr     pcmp
            bne     eli1
            ldd     urlen
            addd    #1
            std     urlen
            puls    d,x,y,u,pc
eli1:       bsr     ed_flush
eli2:       ldu     #egs
            ldy     #urpos
            jsr     pcpy
            ldd     #1
            std     urlen
            lda     #1
            sta     utype
            sta     uopen
            puls    d,x,y,u,pc

; Log the open typing run.  Keeps all registers.
ed_flush:   tst     uopen
            beq     efl9
            clr     uopen
            pshs    d,x,y,u
            ldd     #URHDR
            jsr     ed_uroom
            ldx     #urpos
            ldd     #URHDR
            jsr     ed_tolog
            puls    d,x,y,u
efl9:       rts

; Log D bytes at ege, about to be deleted at the cursor.
ed_logfwd:  pshs    d
            lda     #2
            sta     utmp
            ldu     #egs
            ldy     #udpos
            jsr     pcpy
            ldu     #ege
            ldy     #usrc
            jsr     pcpy
            puls    d
; Log the D bytes at text position usrc, about to be deleted at
; position udpos (type utmp).
ed_logdel:  tst     eulog
            beq     elg9
            bsr     ed_flush
            pshs    d
            addd    #URHDR
            bsr     ed_uroom
            bcs     elg8
            clr     umlen
            clr     umlen+1
            tst     umerge          ; join a deletion at the same place?
            beq     elg2
            ldd     ulen
            cmpd    #URHDR
            blo     elg2
            jsr     ed_rdhdr
            lda     utype
            cmpa    #2
            bne     elg2
            ldu     #urpos
            ldy     #udpos
            jsr     pcmp
            bne     elg2
            ldd     urlen           ; its bytes come first, then these
            std     umlen
            ldd     ulen
            subd    #URHDR
            std     ulen
elg2:       clr     umerge
            ldd     ,s
            inc     usrct           ; from the text
            bsr     ed_tolog
            clr     usrct
            ldd     ,s
            addd    umlen
            std     urlen
            ldu     #udpos
            ldy     #urpos
            jsr     pcpy
            lda     utmp
            sta     utype
            ldx     #urpos
            ldd     #URHDR
            bsr     ed_tolog
elg8:       puls    d
elg9:       rts

; Room for D more bytes in the log: when it is full, the history is
; dropped.  C=1 if D bytes can never fit.
ed_uroom:   cmpd    #PSIZE
            bhi     eur8
            addd    ulen
            cmpd    #PSIZE
            bls     eur9
            clr     ulen
            clr     ulen+1
eur9:       andcc   #$FE
            rts
eur8:       clr     ulen
            clr     ulen+1
            orcc    #$01
            rts

; Append D bytes to the log, through fbuf: from text position usrc
; (which moves past them) when usrct is set, else from X in low RAM.
ed_tolog:   tst     eapply          ; a new change: nothing to redo
            bne     etl0
            clr     olen
            clr     olen+1
etl0:       std     ucnt
            stx     usrcx
etl1:       ldd     ucnt
            beq     etl9
            cmpd    #512
            bls     etl2
            ldd     #512
etl2:       pshs    d
            ldy     #fbuf
            tst     usrct
            beq     etl3
            ldu     #usrc
            jsr     tcopy
            bra     etl4
etl3:       ldx     usrcx
            ldu     #fbuf
            jsr     ed_copy
            stx     usrcx
etl4:       ldb     upg
            jsr     ed_map
            ldd     ulen
            addd    #PWIN
            tfr     d,u
            ldx     #fbuf
            ldd     ,s
            jsr     ed_copy
            ldd     ulen
            addd    ,s
            std     ulen
            ldd     ucnt
            subd    ,s++
            std     ucnt
            bra     etl1
etl9:       rts

; The text has changed: show [modified] the first time.
; Keeps all registers.
ed_mod:     tst     edirty
            bne     emd9
            inc     edirty
            pshs    a
            lda     #1
            sta     estat
            puls    a
emd9:       rts

k_redraw:   ldx     #msg_cls
            jsr     puts
            lda     #3
            sta     ered
            lda     #1
            sta     estat
            rts

k_quit:     tst     edirty
            beq     kqt1
            tst     equit
            bne     kqt1
            inc     equit
            ldx     #msg_equit
            jmp     ed_msg
kqt1:       leas    2,s             ; leave the main loop
            jmp     ed_quit

k_save:     jsr     ed_save
            bcc     ksv9
            inc     edefer          ; the error is over the text
ksv9:       rts

; ^F - find the next match after the cursor.  An empty answer repeats
; the last search.  The text after the gap is searched in place, a
; page at a time for the first character; then the cursor jumps there.
k_find:     ldx     #msg_efind
            jsr     ed_input
            lbcs    kfd9
            beq     kfd2
            ldx     #linebuf
            ldu     #efind
kfd1:       lda     ,x+
            sta     ,u+
            bne     kfd1
kfd2:       tst     efind
            lbeq    kfd9
            ldu     #ege            ; from the character after the cursor's
            ldy     #tpos
            jsr     pcpy
            ldu     #tpos
            ldy     #pebend
            jsr     pcmp
            beq     kfd6
            jsr     pinc
kfd3:       ldu     #tpos           ; tpos = where a match might start
            ldy     #pebend
            jsr     pcmp
            beq     kfd6
            jsr     pmap            ; look along its page for the first
            stx     tend            ; character (the text ends at a page
            lda     efind           ; boundary, so the page is all text)
kfd31:      cmpa    ,x+
            beq     kfd32
            cmpx    #PWIN+PSIZE
            bne     kfd31
            bsr     kfdadv
            bra     kfd3
kfd32:      leax    -1,x
            bsr     kfdadv
            ldy     #tpos2          ; compare the rest from there
            jsr     pcpy
            ldu     #tpos2
            ldx     #efind
kfd4:       ldy     #pebend
            jsr     pcmp
            beq     kfd6            ; the text ends first: no match at all
            jsr     pget
            jsr     pinc
            cmpa    ,x+
            bne     kfd5
            tst     ,x
            bne     kfd4
            ldu     #tpos           ; found: cursor to tpos - ege + egs
            ldy     #etgt
            jsr     pcpy
            ldu     #etgt
            ldy     #ege
            jsr     psubv
            ldy     #egs
            jsr     paddv
            jmp     ed_seek
kfd5:       ldu     #tpos
            jsr     pinc
            bra     kfd3
kfd6:       ldx     #msg_enotfnd
            jmp     ed_msg
kfd9:       rts
kfdadv:     tfr     x,d             ; tpos += X - tend
            subd    tend
            jmp     padd

; ---- text pages ---------------------------------------------------------
; Position P (3 bytes, 0..EBEND) lives in page TPAGE + P/16K at
; $8000 + P%16K.  Only one page is mapped at a time; ecur remembers
; which, so SYS_BANK is only called when a move crosses into another.
; These take U -> the position.

; A = the text byte at [U].  Keeps B, X, Y, U.
pget:       pshs    b,x
            bsr     pmap
            lda     ,x
            puls    b,x,pc

; Store A at [U].  Keeps all registers.
pput:       pshs    d,x
            bsr     pmap
            lda     ,s
            sta     ,x
            puls    d,x,pc

; Map the page that holds [U] -> X = its address in the window.
; Keeps Y, U.
pmap:       ldd     ,u              ; A = position / 64K, B = bits 15-8
            lslb                    ; A = position / 16K
            rola
            lslb
            rola
            adda    #TPAGE
            tfr     a,b
            bsr     ed_map
            ldd     1,u
            anda    #$3F
            ora     #PWIN/256
            tfr     d,x
            rts

; Map page B at $8000-$BFFF, unless it is there already.  Keeps all
; registers.
ed_map:     cmpb    ecur
            beq     emp9
            stb     ecur
            pshs    a
            OS      SYS_BANK
            puls    a
emp9:       rts

; [U] + 1, [U] - 1.  Keep all registers.
pinc:       pshs    d
            ldd     1,u
            addd    #1
            std     1,u
            bcc     pid9
            inc     ,u
pid9:       puls    d,pc
pdec:       pshs    d
            ldd     1,u
            subd    #1
            std     1,u
            bcc     pid9
            dec     ,u
            puls    d,pc

; [U] += D, [U] -= D
padd:       addd    1,u
            std     1,u
            bcc     pad9
            inc     ,u
pad9:       rts
psub:       pshs    d
            ldd     1,u
            subd    ,s++
            std     1,u
            bcc     pad9
            dec     ,u
            rts

; [U] += [Y], [U] -= [Y]
paddv:      ldd     1,u
            addd    1,y
            std     1,u
            lda     ,u
            adca    ,y
            sta     ,u
            rts
psubv:      ldd     1,u
            subd    1,y
            std     1,u
            lda     ,u
            sbca    ,y
            sta     ,u
            rts

; [Y] = [U]
pcpy:       ldd     ,u
            std     ,y
            lda     2,u
            sta     2,y
            rts

; Compare [U] with [Y] (flags as for an unsigned CMP).  Keeps all.
pcmp:       pshs    a
            lda     ,u
            cmpa    ,y
            bne     pcm9
            lda     1,u
            cmpa    1,y
            bne     pcm9
            lda     2,u
            cmpa    2,y
pcm9:       puls    a,pc

; Z=1 if [U] = 0.  Keeps all.
ptst:       pshs    a
            lda     ,u
            ora     1,u
            ora     2,u
            puls    a,pc

; D = [U] - [Y], for a difference under 64K
pdiff:      ldd     1,u
            subd    1,y
            rts

; D = min([U] - [Y], 512), for [U] >= [Y]
pdist:      ldd     1,u
            subd    1,y
            std     ptmp
            lda     ,u
            sbca    ,y
            bne     pds8
            ldd     ptmp
            cmpd    #512
            bls     pds9
pds8:       ldd     #512
pds9:       rts

; Copy D bytes between text position [U] and low RAM at Y: tcopy reads
; the text, tstore writes it.  [U] and Y move past them.
tstore:     clr     tdir
            inc     tdir
            bra     tcp0
tcopy:      clr     tdir
tcp0:       std     tcn
tcp1:       ldd     tcn
            beq     tcp9
            jsr     pmap            ; X -> the first byte
            pshs    x
            ldd     #PWIN+PSIZE     ; as many as this page holds
            subd    ,s++
            cmpd    tcn
            bls     tcp2
            ldd     tcn
tcp2:       pshs    d
            jsr     padd            ; [U] past them
            ldd     tcn
            subd    ,s
            std     tcn
            puls    d
            pshs    u
            leau    d,x
            stu     tcend
            tst     tdir
            bne     tcp4
            lsrb                    ; an odd count: one byte first,
            bcc     tcp3            ; then words
            lda     ,x+
            sta     ,y+
            cmpx    tcend
            beq     tcp5
tcp3:       ldd     ,x++
            std     ,y++
            cmpx    tcend
            bne     tcp3
            bra     tcp5
tcp4:       lsrb
            bcc     tcp41
            lda     ,y+
            sta     ,x+
            cmpx    tcend
            beq     tcp5
tcp41:      ldd     ,y++
            std     ,x++
            cmpx    tcend
            bne     tcp41
tcp5:       puls    u
            bra     tcp1
tcp9:       rts

; Move the cursor to text position etgt, up to 512 bytes at a time.
ed_seek:    ldu     #etgt
            ldy     #egs
            jsr     pcmp
            beq     tcp9
            blo     esk1
            jsr     pdist           ; right
            bsr     ed_mvr
            bra     ed_seek
esk1:       exg     u,y             ; left
            jsr     pdist
            bsr     ed_mvl
            bra     ed_seek

; Move the cursor right by D (1-512) bytes
ed_mvr:     pshs    d
            ldu     #ege
            ldy     #fbuf
            jsr     tcopy
            ldd     ,s
            bsr     ed_lfs
            addd    eline
            std     eline
            puls    d
            ldu     #egs
            ldy     #fbuf
            jmp     tstore

; Move the cursor left by D (1-512) bytes
ed_mvl:     pshs    d
            ldu     #egs
            jsr     psub
            ldy     #tpos
            jsr     pcpy
            ldu     #tpos
            ldy     #fbuf
            ldd     ,s
            jsr     tcopy
            ldd     ,s
            bsr     ed_lfs
            pshs    d
            ldd     eline
            subd    ,s++
            std     eline
            ldd     ,s
            ldu     #ege
            jsr     psub
            ldy     #tpos
            jsr     pcpy
            puls    d
            ldu     #tpos
            ldy     #fbuf
            jmp     tstore

; D = the LFs in the D bytes at fbuf (0 while loading, when eline
; isn't kept)
ed_lfs:     tst     eulog
            beq     elf8
            ldx     #fbuf
            leau    d,x
            stu     tend
            ldu     #0
elf1:       lda     ,x+
            cmpa    #LF
            bne     elf2
            leau    1,u
elf2:       cmpx    tend
            bne     elf1
            tfr     u,d
            rts
elf8:       ldd     #0
            rts

; ---- cursor movement (A = the character passed, C=1 at either end) ----
; These keep X (callers count with it).
ed_left:    pshs    x
            ldu     #egs
            jsr     ptst
            beq     eft7
            jsr     pdec
            jsr     pget
            ldu     #ege
            jsr     pdec
            jsr     pput
            puls    x
            cmpa    #LF
            bne     eft8
            ldu     eline
            leau    -1,u
            stu     eline
eft8:       andcc   #$FE
            rts
eft7:       puls    x
eft9:       orcc    #$01
            rts

ed_right:   pshs    x
            ldu     #ege
            ldy     #pebend
            jsr     pcmp
            beq     eft7
            jsr     pget
            jsr     pinc
            ldu     #egs
            jsr     pput
            jsr     pinc
            puls    x
            cmpa    #LF
            bne     eft8
ert1:       ldu     eline
            leau    1,u
            stu     eline
            bra     eft8

; Insert A at the cursor.  C=1 if the buffer is full.  Keeps A, B, X, Y.
ed_put:     pshs    x,y
            ldu     #egs
            ldy     #ege
            jsr     pcmp
            beq     ept9
            tst     eulog
            beq     ept1
            jsr     ed_logins
ept1:       ldu     #egs
            jsr     pput
            jsr     pinc
            puls    x,y
            lbsr    ed_mod
            cmpa    #LF
            bne     eft8
            bra     ert1
ept9:       puls    x,y
            bra     eft9

ed_home:    pshs    x
ehm1:       ldu     #egs
            jsr     ptst
            beq     ehm8
            jsr     pdec            ; the character before the cursor
            jsr     pget
            jsr     pinc
            cmpa    #LF
            beq     ehm8
            jsr     ed_left
            bra     ehm1
ehm8:       puls    x
ehm9:       rts

ed_end:     pshs    x
een1:       ldu     #ege
            ldy     #pebend
            jsr     pcmp
            beq     ehm8
            jsr     pget
            cmpa    #LF
            beq     ehm8
            jsr     ed_right
            bra     een1

ed_up:      pshs    a
            bsr     ed_home
            jsr     ed_left
            bcs     eup9            ; already on the first line
            bsr     ed_home
            bra     ed_gocol
ed_down:    pshs    a
            bsr     ed_end
            jsr     ed_right
            bcs     eup9            ; already on the last line
; Right along the line to column ewant, or its end.
ed_gocol:   ldx     ewant
egc1:       beq     eup9
            ldu     #ege
            ldy     #pebend
            jsr     pcmp
            beq     eup9
            jsr     pget
            cmpa    #LF
            beq     eup9
            jsr     ed_right
            leax    -1,x
            bra     egc1
eup9:       puls    a,pc

; Cursor column -> D and ecol, start of its line -> estart.
ed_col:     ldu     #egs
            ldy     #estart
            jsr     pcpy
            ldu     #estart
eco1:       jsr     ptst
            beq     eco2
            jsr     pdec
            jsr     pget
            cmpa    #LF
            bne     eco1
            jsr     pinc            ; back past that LF
eco2:       ldu     #egs
            ldy     #estart
            jsr     pdiff
            std     ecol
            rts

; Next character of the text from wpos (skipping the gap) -> A, C=1 at
; the end.
ed_nx:      ldu     #wpos
            ldy     #egs
            jsr     pcmp
            bne     enx1
            ldu     #ege
            ldy     #wpos
            jsr     pcpy
            ldu     #wpos
enx1:       ldy     #pebend
            jsr     pcmp
            lbeq    eft9
            jsr     pget
            jsr     pinc
            andcc   #$FE
            rts

; ---- drawing ---------------------------------------------------------
; Lines from wpos at screen rows B..TROWS-1.
ed_rows:    pshs    b
            tfr     b,a
            inca
            ldb     #1
            bsr     ed_goto
            ldd     ehoff
            std     eskip
            lda     #ECOLS
            sta     ecnt
            bsr     ed_dline
            puls    b
            incb
            cmpb    #TROWS
            blo     ed_rows
            rts

; One line from wpos: skip eskip columns, show up to ecnt, clear the
; rest.  wpos ends up at the next line.
ed_dline:   ldd     eskip
            beq     edl2
            bsr     ed_nx
            bcs     edl5
            cmpa    #LF
            beq     edl5
            ldd     eskip
            subd    #1
            std     eskip
            bra     ed_dline
edl2:       bsr     ed_nx
            bcs     edl5
            cmpa    #LF
            beq     edl5
            cmpa    #$20            ; control characters show as '.'
            blo     edl3
            cmpa    #DEL
            blo     edl4
edl3:       lda     #'.
edl4:       jsr     putc
            dec     ecnt
            bne     edl2
edl6:       bsr     ed_nx           ; screen full: skip the rest
            bcs     edl9
            cmpa    #LF
            bne     edl6
edl9:       rts
edl5:       ldx     #msg_eeol
            jmp     puts

; Cursor to row A, column B (both from 1).  Keeps all registers.
ed_goto:    pshs    d,x,y
            ldx     #msg_ecsi
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

; Status line: name, [modified] and the keys
ed_status:  clr     estat
            lda     #EDROWS
            ldb     #1
            bsr     ed_goto
            ldx     #msg_erev
            jsr     puts
            ldx     #fname
            tst     ,x
            bne     est1
            ldx     #msg_enoname
est1:       jsr     puts
            tst     edirty
            beq     est2
            ldx     #msg_emod
            jsr     puts
est2:       ldx     #msg_ekeys
            jsr     puts
            ldx     #msg_enorm
            jmp     puts

; Line and column at the right of the status line
ed_pos:     lda     #EDROWS
            ldb     #ECOLS-17
            bsr     ed_goto
            ldx     #msg_erev
            jsr     puts
            ldx     #msg_eln
            jsr     puts
            ldd     eline
            addd    #1
            jsr     putdec
            ldx     #msg_ecl
            jsr     puts
            ldd     ecol
            addd    #1
            jsr     putdec
            ldx     #msg_enorm
            jmp     puts

; Message X on the status line until the next key
ed_msg:     lda     #EDROWS
            ldb     #1
            jsr     ed_goto
            pshs    x
            ldx     #msg_erev
            jsr     puts
            puls    x
            jsr     puts
            ldx     #msg_enorm
            jsr     puts
            lda     #$80
            sta     estat
            rts

; Ask for a line on the status line (prompt X) -> linebuf, B = length
; (Z=1 if empty).  C=1 if cancelled with ^C.
ed_input:   bsr     ed_msg
            lda     #1
            sta     estat
            ldx     #linebuf
            clrb
ein1:       OS      SYS_GETC
            cmpa    #CR
            beq     ein5
            cmpa    #3
            beq     ein6
            cmpa    #ESC
            beq     ein4
            cmpa    #BS
            beq     ein3
            cmpa    #DEL
            beq     ein3
            cmpa    #$20
            blo     ein1
            cmpb    #EFINDMAX
            bhs     ein1
            sta     ,x+
            incb
            jsr     putc
            bra     ein1
ein3:       tstb
            beq     ein1
            decb
            leax    -1,x
            pshs    x
            ldx     #bsseq
            jsr     puts
            puls    x
            bra     ein1
ein4:       OS      SYS_GETC        ; skip arrow keys and the like
ein41:      OS      SYS_GETC
            cmpa    #$40
            blo     ein41
            bra     ein1
ein5:       clr     ,x
            tstb
            andcc   #$FE
            rts
ein6:       orcc    #$01
            rts

; ---- keyboard ----------------------------------------------------------
; Next key -> A: a character, or K_xxx for a VT100 key sequence, or 0.
ed_key:     OS      SYS_GETC
            cmpa    #ESC
            beq     eky1
            cmpa    #$80
            blo     eky9
eky0:       clra
eky9:       rts
eky1:       OS      SYS_GETC
            cmpa    #'[
            beq     eky2
            cmpa    #'O
            bne     eky0
eky2:       clr     ekp
eky3:       OS      SYS_GETC        ; parameters, up to the final byte
            cmpa    #'0
            blo     eky4
            cmpa    #'9
            bhi     eky4
            suba    #'0
            pshs    a
            lda     ekp
            ldb     #10
            mul
            addb    ,s+
            stb     ekp
            bra     eky3
eky4:       cmpa    #$40
            blo     eky3
            cmpa    #'~             ; ESC [ n ~: look up n
            bne     eky5
            lda     ekp
            adda    #'0
eky5:       ldx     #esckeys
eky6:       tst     ,x
            beq     eky0
            cmpa    ,x++
            bne     eky6
            lda     -1,x
            rts

esckeys:    fcb     'A,K_UP,'B,K_DOWN,'C,K_RIGHT,'D,K_LEFT
            fcb     'H,K_HOME,'F,K_END,'1,K_HOME,'7,K_HOME
            fcb     '4,K_END,'8,K_END,'3,K_DEL,'5,K_PGUP,'6,K_PGDN,0

; ---- files ---------------------------------------------------------------
; Read file fname into the buffer, cursor at the top.  A missing file
; starts empty.  C=1 (message shown) if it can't be read or is too big.
; Each block read goes through obuf (CR dropped, tabs expanded) and is
; added before the gap; then the gap moves to the top in one go.
ed_load:    lda     #VCMD_FOPEN
            jsr     fcmd
            bcc     eld1
            cmpa    #4
            bne     eld8
            ldx     #msg_enew
            jsr     ed_msg
            andcc   #$FE
            rts
eld1:       clr     ecol+1          ; column, for the tabs (only mod 8)
            ldu     #obuf
eld2:       stu     lptr
            jsr     fread
            bcs     eld8
            ldu     lptr
            cmpx    #0
            beq     eld6
            ldy     #fbuf
eld3:       cmpu    #obuf+512-8     ; room for a tab's spaces?
            blo     eld30
            bsr     eldput
            bcs     eld7
eld30:      lda     ,y+
            cmpa    #CR
            beq     eld5
            cmpa    #TAB
            bne     eld4
eld31:      lda     #$20
            sta     ,u+
            inc     ecol+1
            ldb     ecol+1
            andb    #7
            bne     eld31
            bra     eld5
eld4:       sta     ,u+
            inc     ecol+1
            cmpa    #LF
            bne     eld5
            clr     ecol+1
eld5:       leax    -1,x
            bne     eld3
            bra     eld2
eld6:       bsr     eldput
            bcs     eld7
            lda     #VCMD_FCLOSE
            jsr     fcmd
            clr     edirty
            clr     etgt            ; cursor back to the top
            clr     etgt+1
            clr     etgt+2
            jsr     ed_seek
            andcc   #$FE
            rts
eld7:       ldx     #msg_ebig
            jsr     puts
            bra     eld9
eld8:       jsr     ferr
eld9:       lda     #VCMD_FCLOSE
            jsr     fcmd
            orcc    #$01
            rts

; Add the bytes obuf..U-1 at the cursor; U -> obuf again.  Keeps X, Y.
; C=1 if they don't fit.
eldput:     pshs    x,y
            tfr     u,d
            subd    #obuf
            beq     elp8
            pshs    d
            ldu     #ege            ; room, up to 512
            ldy     #egs
            jsr     pdist
            cmpd    ,s
            puls    d
            bcs     elp9
            ldu     #egs
            ldy     #obuf
            jsr     tstore
elp8:       ldu     #obuf
            andcc   #$FE
elp9:       puls    x,y,pc

; Write the buffer to fname (asking for a name if there is none).
; C=1 after an error, whose message is on text row TROWS.
ed_save:    ldx     #fname
            tst     ,x
            bne     esv1
            ldx     #msg_esaveas
            jsr     ed_input
            bcs     esv9
            beq     esv9
            ldx     #linebuf
esv1:       jsr     setname         ; (fname onto itself is fine)
            lda     #1
            sta     estat
            lda     #TROWS          ; any error message goes here
            ldb     #1
            jsr     ed_goto
            lda     #VCMD_FCREATE
            jsr     fcmd
            bcc     esv2
            jsr     ferr
            orcc    #$01
            rts
esv2:       ldx     #fbuf
            stx     fptr
            sts     lsave           ; fabort returns from here, C=1
            clr     tpos            ; the text before the gap
            clr     tpos+1
            clr     tpos+2
            ldy     #egs
            bsr     esvspan
            ldu     #ege            ; and after it
            ldy     #tpos
            jsr     pcpy
            ldy     #pebend
            bsr     esvspan
            jsr     fflush
            lda     #VCMD_FCLOSE
            jsr     fcmd
            bcc     esv6
            jsr     ferr
            orcc    #$01
            rts
esv6:       clr     edirty
            ldx     #msg_esaved
            jsr     ed_msg
esv9:       andcc   #$FE
            rts

; Write the text from tpos up to position [Y], through obuf
esvspan:    pshs    y
esp1:       ldu     #tpos
            ldy     ,s
            jsr     pcmp
            beq     esp9
            exg     u,y
            jsr     pdist           ; up to 512 bytes from tpos
            exg     u,y
            pshs    d
            ldy     #obuf
            jsr     tcopy
            puls    d
            ldx     #obuf
            leau    d,x
            stu     tend
esp2:       lda     ,x+
            cmpa    #LF
            bne     esp3
            lda     #CR
            jsr     fputc
            lda     #LF
esp3:       jsr     fputc
            cmpx    tend
            bne     esp2
            bra     esp1
esp9:       puls    y,pc

pebend:     fcb     NTPAGE/4        ; EBEND: the end of the text pages
            fdb     (NTPAGE&3)*PSIZE

msg_ecsi:   fcb     ESC
            fcn     "["
msg_eeol:   fcb     ESC
            fcn     "[K"
msg_erev:   fcb     ESC
            fcc     "[7m"
            fcn     " "
msg_enorm:  fcc     " "
            fcb     ESC
            fcc     "[0m"
            fcb     ESC
            fcn     "[K"
msg_enoname: fcn    "(no name)"
msg_emod:   fcn     " [modified]"
msg_ekeys:  fcn     "  ^S save ^X exit ^F find ^C cut ^V paste"
msg_eln:    fcn     "Ln "
msg_ecl:    fcn     " Col "
msg_enew:   fcn     "New file"
msg_esaved: fcn     "Saved"
msg_efull:  fcn     "Buffer full (400K)"
msg_ecfull: fcn     "Clipboard full (16K)"
msg_enoundo: fcn    "Nothing to undo"
msg_enoredo: fcn    "Nothing to redo"
msg_enotfnd: fcn    "Not found"
msg_equit:  fcn     "Unsaved changes: ^X again to quit, ^S to save"
msg_efind:  fcn     "Find:"
msg_esaveas: fcn    "Save as:"
msg_ebig:   fcc     "File too big for EDIT (400K)"
            fcb     CR,LF,0

; ======================================================================
;  Helpers.  The shell has the same routines in ROM, but a program can't
;  call into it, so EDIT carries its own copies.
; ======================================================================

skipsp:     lda     ,x
            cmpa    #$20
            bne     sk9
            leax    1,x
            bra     skipsp
sk9:        rts

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

; A into the file buffer, written out every 512 bytes.  Keeps all.
fputc:      pshs    x
            ldx     fptr
            sta     ,x+
            stx     fptr
            cmpx    #fbuf+512
            puls    x
            bne     fpc9
            pshs    d,x,y,u
            bsr     fflush
            puls    d,x,y,u
fpc9:       rts

; Write the bytes fbuf..fptr-1 to the file.
fflush:     ldd     fptr
            subd    #fbuf
            beq     ffl9
            std     fpos
            ldx     #fbuf
            ldu     #VF_DATA
            bsr     vput
            ldx     #fpos           ; VF_LEN = fpos (both big-endian)
            ldu     #VF_LEN
            ldd     #2
            jsr     vput
            lda     #VCMD_FWRITE
            bsr     fcmd
            bcs     fabort
            cmpx    fpos
            beq     ffl1
            lda     #7              ; short write: disk full
            bra     fabort
ffl1:       ldx     #fbuf
            stx     fptr
ffl9:       rts

; Abandon a save after a file error (A = result): back to the caller of
; ed_save with carry set.
fabort:     lds     lsave
            bsr     ferr
            lda     #VCMD_FCLOSE
            jsr     fcmd
            orcc    #$01
            rts

; Print the message for file result A.
ferr:       ldx     #msg_fnodrv
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
            bsr     puts
            tfr     a,b
            clra
            bsr     putdec
            bra     crlf
fe9:        bra     puts

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
            fcc     "[2J"
            fcb     ESC
            fcn     "[H"
bsseq:      fcb     BS,$20,BS,0
msg_fnodrv: fcc     "No flash drive"
            fcb     CR,LF,0
msg_fnofile: fcc    "File not found"
            fcb     CR,LF,0
msg_fnopath: fcc    "Path not found"
            fcb     CR,LF,0
msg_fdenied: fcc    "Access denied or disk full"
            fcb     CR,LF,0
msg_fnofat: fcc     "Not a FAT16/FAT32 drive"
            fcb     CR,LF,0
msg_ferr:   fcn     "Drive error "

; ======================================================================
;  RAM (not part of the program file)
; ======================================================================
vblk        rmb     7               ; SYS_VCOPY / SYS_VREAD block
fpos        rmb     2               ; bytes in fbuf to write
fptr        rmb     2               ; -> next free byte in fbuf
fcnt        rmb     2               ; bytes read into fbuf
lsave       rmb     2               ; S to unwind to on a save error
lptr        rmb     2               ; ed_load: -> next free byte in obuf
fname       rmb     64              ; the file's name
linebuf     rmb     64              ; ^F / Save-as answer

; Editor variables, all 0 at the start.  Text positions are 3 bytes.
evars       equ     *
egs         rmb     3               ; gap start = cursor
ege         rmb     3               ; gap end = first character after it
estart      rmb     3               ; start of the cursor's line
eostart     rmb     3               ; estart before the last key
wpos        rmb     3               ; ed_nx: the next character to show
tpos        rmb     3               ; find, save, ed_mvl
tpos2       rmb     3               ; find: compares from here
etgt        rmb     3               ; ed_seek: where the cursor goes
eapos       rmb     3               ; ed_apply: where the bytes went back
udpos       rmb     3               ; ed_logdel: where the bytes go
usrc        rmb     3               ; ed_tolog: the bytes in the text
utpos       rmb     3               ; ed_logins: end of the typing run
eline       rmb     2               ; cursor line (0 = first)
etop        rmb     2               ; line at the top of the screen
ehoff       rmb     2               ; first column shown
ecol        rmb     2               ; cursor column
ewant       rmb     2               ; column that up/down aim for
erfrom      rmb     2               ; ered 1: redraw the line from here
eskip       rmb     2               ; ed_dline: columns to skip
eorow       rmb     1               ; screen row of the eostart line
eold        rmb     2               ; eline before PgUp / PgDn
ered        rmb     1               ; redraw: 0 none, 1 rest of line,
                                    ; 2 from the cursor line down,
                                    ; 3 everything, 4 from the old line down
estat       rmb     1               ; status: 1 redraw, $80 message showing
edirty      rmb     1               ; text changed since load / save
equit       rmb     1               ; ^X pressed once with unsaved changes
ekeep       rmb     1               ; last key was up/down: keep ewant
edefer      rmb     1               ; redraw everything after the next key
ekey        rmb     1
ekp         rmb     1               ; escape sequence parameter
ecnt        rmb     1               ; ed_dline: columns left
eprev       rmb     1               ; shell's page before EDIT
eclast      rmb     1               ; last key was ^C: the next one appends
ecn         rmb     2               ; cut / paste: bytes left
ecoff       rmb     2               ; paste: offset in the clipboard
ulen        rmb     2               ; bytes in the undo log
uopen       rmb     1               ; a run of typing is not logged yet
eulog       rmb     1               ; 0 while loading
epg         rmb     1               ; ed_insfrom: page to insert from
utmp        rmb     1               ; ed_logdel: record type
umerge      rmb     1               ; ed_logdel: join the last record
EFINDMAX    equ     40
efind       rmb     EFINDMAX+1      ; search string
ecblen      rmb     2               ; bytes in the clipboard (also kept in
                                    ; its page, for the next EDIT)
; Undo record: the deleted bytes (types 2 and 3), then this header
urpos       rmb     3               ; position in the text
urlen       rmb     2               ; byte count
utype       rmb     1               ; 1 typed, 2 deleted (cursor back to
                                    ; the start), 3 deleted (cursor after)
usrcx       rmb     2               ; ed_tolog: source in low RAM
ucnt        rmb     2               ; ed_tolog: bytes left
umlen       rmb     2               ; ed_logdel: bytes already in it
olen        rmb     2               ; bytes in the other log
upg         rmb     1               ; page of the log being written
opg         rmb     1               ; page of the other log (after upg)
eapply      rmb     1               ; non-zero during undo / redo
usrct       rmb     1               ; ed_tolog: the source is usrc
ecur        rmb     1               ; page mapped at $8000-$BFFF now
tdir        rmb     1               ; 0 tcopy, 1 tstore
tcn         rmb     2               ; tcopy: bytes left
tcend       rmb     2               ; tcopy: end of this run
tend        rmb     2               ; end of a run in low RAM
ptmp        rmb     2               ; pdist
evend       equ     *

fbuf        rmb     512             ; file data; also the copy buffer
obuf        rmb     512             ; load / save: the text side
            rmb     256             ; stack
stktop      equ     *

            end     start
