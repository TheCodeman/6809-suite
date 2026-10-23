; Object test: 6309 instructions with relocations
            section code
            export  ext1
            export  ext2
            export  six
six         ldq     ext1
            stq     ext2
            ldw     #ext1
            ldw     ext1,w
            lda     ext1,w
            oim     #$80,ext1
            aim     #$7f,ext1,x
            tim     #1;<ext1
            band    a,1,2,<ext2
            lde     #ext2&$ff
            muld    ext2
            ldmd    #1
            tfm     x+,y+
            ldq     #$12345678
            rts
            endsection
            section data
ext1        fdb     0,0
ext2        fdb     0,0
            endsection
