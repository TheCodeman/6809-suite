; Object test: main module (sections, imports, exports, relocations)
            include "syscalls.inc"
            section init
            export  __start
            import  hello,count,table,s_bss,l_bss,putnum
__start     lds     #stack
            ldx     #s_bss          ; clear bss
            ldd     #l_bss
clr1        clr     ,x+
            subd    #1
            bne     clr1
            lbra    main
            endsection

            section code
main        ldx     #hello
            lbsr    puts
            ldd     #1234
            jsr     putnum
            lda     count
            inca
            sta     count
            ldx     #table
            lda     2,x
            lda     table+3
            lda     <count          ; 8-bit relocation (low byte)
            ldb     #count&$ff
            ldb     #count/256
            ldx     table,pcr
            leax    tlen,pcr
            ldy     [vec,pcr]
            jsr     [vec]
            bsr     sub1
            lbsr    sub2
            lbeq    sub2
            ldd     #local2-main
            ldd     #main+5
            ldd     #*
            lda     table,x
            lda     table,y
            lda     [table,u]
            ldd     #(count+1)*2
            ldd     #-count
            ldd     #~count
            ldd     #count|$8000
            ldd     #count/2
            OS      SYS_EXIT
sub1        rts
local2      equ     *+4
loc3        equ     main+$100
            fdb     loc3,local2
            endsection

            section data
vec         fdb     sub2
tlen        fcb     4,count,table&$ff
            fdb     main,sub1-main,count-1
            endsection

            sect    code
sub2        rts
puts        lda     ,x+
            beq     ps9
            OS      SYS_PUTC
            bra     puts
ps9         rts
            endsect

            section bss,bss
stack0      rmb     100
stack       equ     *
flag        rmb     1
            endsection
