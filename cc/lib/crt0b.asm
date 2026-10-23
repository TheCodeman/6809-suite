; CRT0B - C startup for programs with banked code (#pragma bank): CRT0
; with the bank loader and __bcall/__bret.  Link it first instead of CRT0.
BANKED      equ     1
            include "crt0.asm"
