; ----------------------------------------------------------------------
;  LIBC - the C runtime library for MINI09, one object: LIBC.O.
;  Link it after the program: LINK OUT.PRG CRT0.O PROG.O LIBC.O
; ----------------------------------------------------------------------

            include "syscalls.inc"
            include "vdp.inc"

            section code
            include "arith.asm"
            include "long.asm"
            include "string.asm"
            endsection

            include "stdio.asm"
