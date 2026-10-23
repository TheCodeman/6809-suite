; Object test: a second module
            include "syscalls.inc"
            section data
hello       fcn     "Hello from the linker"
            export  hello,count
table       fcb     1,2,3,4
            .globl  table
            endsection
            section bss
count       rmb     1
            endsection
putnum      export
            section code
putnum      pshs    d
            ldx     #numbuf
            puls    d,pc
            endsection
            section .bss
numbuf      rmb     8
            endsection
