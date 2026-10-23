; Object test: EXTERN / EXTERNAL, and a label on IMPORT
            extern  six
ext2        external
            section init
            export  __start
__start     jsr     six
            ldd     ext2
            ldx     #ext2+2
            bra     *
            endsection
