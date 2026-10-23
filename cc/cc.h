/*
 * cc.h - what the four passes of CC share.  See cc.md.
 *
 *     CPP    FILE.C -> FILE.I    the preprocessor: plain C, with #line
 *     PARSE  FILE.I -> FILE.A    the syntax, as a tree file, and FILE.N,
 *                                the names
 *     SEMA   FILE.A -> FILE.T    symbols and types: assembler, with each
 *                                expression left as a tree
 *     GEN    FILE.T -> FILE.ASM  code for the trees, names filled in
 *
 * Each pass is one C file that includes this and common.c.  The passes
 * are written in the subset of C that CC compiles, and the PC builds
 * (gcc) and the MINI09 builds must write the same bytes, so nothing may
 * depend on the host's sizes: a value that stands for a number on the
 * 6809 is cut to 8, 16 or 32 bits (truncv, tr32) before it is used or
 * written.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef __MINI09__
#include <mini09.h>
#endif

/* ---- limits ------------------------------------------------------ */

#define NAMESZ   7000           /* identifier characters */
#define MAXNAME  800            /* identifiers */
#define NHASH    256
#define MAXGSYM  352            /* global symbols */
#define MAXLSYM  96             /* local symbols in scope */
#define MAXTYPE  512
#define MAXMEMB  192            /* struct members */
#define MAXPARM  256            /* parameters of all function types */
#define MAXFP    16             /* parameters of one function */
#define MAXMAC   384            /* macros */
#define MACSZ    5000           /* macro bodies */
#define EXPSZ    2000           /* macro expansions in use */
#define ARGSZ    600            /* the arguments of one macro call */
#define MAXSRC   16             /* nested files and macro expansions */
#define MAXNODE  128            /* expression tree nodes */
#define MAXCASE  128
#define MAXIF    16
#define MAXGOTO  32             /* goto labels in one function */
#define MAXLOOP  24
#define MAXSTK   48             /* SEMA's operand stack */
#define MAXSCOPE 128            /* PARSE: names hidden in inner blocks */
#define STRSZ    512            /* a string literal, an identifier */
#define PATHSZ   128            /* a file's path */

/* ---- tokens ------------------------------------------------------ */

#define T_EOF    0
#define T_EOL    1              /* the end of a #if line */
#define T_IDENT  128
#define T_NUM    129
#define T_STR    130
#define T_EQ     131            /* == */
#define T_NE     132
#define T_LE     133
#define T_GE     134
#define T_LAND   135            /* && */
#define T_LOR    136
#define T_SHL    137
#define T_SHR    138
#define T_INC    139
#define T_DEC    140
#define T_ARROW  141
#define T_ELLIP  142
#define T_ASGN   143            /* op= ; tokop is the operator */

/* Keywords are the first names entered, so a keyword's token is
   K_BASE + its name number. */
#define K_BASE     160
#define K_AUTO     160
#define K_BREAK    161
#define K_CASE     162
#define K_CHAR     163
#define K_CONST    164
#define K_CONTINUE 165
#define K_DEFAULT  166
#define K_DO       167
#define K_ELSE     168
#define K_ENUM     169
#define K_EXTERN   170
#define K_FOR      171
#define K_GOTO     172
#define K_IF       173
#define K_INT      174
#define K_LONG     175
#define K_REGISTER 176
#define K_RETURN   177
#define K_SHORT    178
#define K_SIGNED   179
#define K_SIZEOF   180
#define K_STATIC   181
#define K_STRUCT   182
#define K_SWITCH   183
#define K_TYPEDEF  184
#define K_UNION    185
#define K_UNSIGNED 186
#define K_VOID     187
#define K_VOLATILE 188
#define K_WHILE    189
#define NKW        30
#define ID_DEFINED 30           /* the names after the keywords */
#define ID_LINE    31
#define ID_FILE    32

char *kwords[] = {
    "auto", "break", "case", "char", "const", "continue", "default", "do",
    "else", "enum", "extern", "for", "goto", "if", "int", "long",
    "register", "return", "short", "signed", "sizeof", "static", "struct",
    "switch", "typedef", "union", "unsigned", "void", "volatile", "while",
    "defined", "__LINE__", "__FILE__", 0
};

/* ---- types ------------------------------------------------------- */

#define TY_VOID   1
#define TY_CHAR   2
#define TY_UCHAR  3
#define TY_INT    4
#define TY_UINT   5
#define TY_LONG   6
#define TY_ULONG  7
#define TY_PTR    8
#define TY_ARRAY  9
#define TY_STRUCT 10
#define TY_UNION  11
#define TY_FUNC   12
#define TY_HOLE   13            /* stands in while a declarator is read */

/* the basic types are at the index of their kind */
#define TV   1
#define TC   2
#define TUC  3
#define TI   4
#define TUI  5
#define TL   6
#define TUL  7

#define FN_VARARG  256          /* in ty_x of a function: ... */
#define FN_NOPROTO 512          /* f(): any arguments */

/* ---- symbols ----------------------------------------------------- */

#define SC_EXTERN  1
#define SC_GLOBAL  2
#define SC_STATIC  3
#define SC_TYPEDEF 4
#define SC_ENUM    5
#define SC_AUTO    6
#define SC_LSTATIC 7            /* a static local: ls_val is its label */

#define F_DEF  1
#define F_USED 2

/* ---- expression trees (SEMA builds them, GEN reads them) --------- */

#define N_NUM     1
#define N_LVAR    2             /* local: nd_val = offset from U */
#define N_GVAR    3             /* global: nd_sym = its name */
#define N_SVAR    4             /* static local: nd_sym = label */
#define N_STR     5             /* string: nd_sym = label */
#define N_ADDR    6
#define N_DEREF   7
#define N_CAST    8
#define N_NEG     9
#define N_COM     10
#define N_NOT     11
#define N_ADD     12
#define N_SUB     13
#define N_MUL     14
#define N_DIV     15
#define N_MOD     16
#define N_AND     17
#define N_OR      18
#define N_XOR     19
#define N_SHL     20
#define N_SHR     21
#define N_EQ      22
#define N_NE      23
#define N_LT      24
#define N_GT      25
#define N_LE      26
#define N_GE      27
#define N_LAND    28
#define N_LOR     29
#define N_ASSIGN  30
#define N_ASGOP   31            /* nd_val = the operator (N_ADD ...) */
#define N_PREINC  32            /* nd_val = the step, negative for -- */
#define N_POSTINC 33
#define N_COND    34            /* l = condition, r = N_COLON */
#define N_COLON   35
#define N_COMMA   36
#define N_CALL    37            /* l = function, r = N_ARG list */
#define N_ARG     38
#define N_SCOPY   39            /* struct l = struct r; no value */

/*
 * ---- the tree file (PARSE writes it, SEMA reads it) --------------
 *
 * Bytes: a tag, then its numbers (wnum: 0-239 in one byte, else $F0 and
 * 2 bytes, or $F1 and 4, big-endian).  X_LINE and X_FILE can come before
 * any tag; the reader takes them in passing.
 *
 * An expression is postfix, ended by A_END: A_NUM type value, A_STR len
 * bytes, A_IDENT name, then operators that take their operands from a
 * stack.  Declarations and statements are prefix, in the order the
 * source has them.
 */
#define X_LINE    1             /* line */
#define X_FILE    2             /* name of the file */
#define A_END     3             /* the end of an expression */
#define A_NONE    4             /* no expression here */
#define A_NUM     5             /* type value */
#define A_STR     6             /* length bytes */
#define A_IDENT   7             /* name */
#define A_BIN     8             /* op (N_ADD ... N_LOR): l r */
#define A_COND    9             /* c a b */
#define A_ASSIGN  10            /* l r */
#define A_ASGOP   11            /* op: l r */
#define A_COMMA   12            /* l r */
#define A_INDEX   13            /* a i */
#define A_CALL    14            /* nargs: f args */
#define A_MEMBER  15            /* arrow name: n */
#define A_INC     16            /* step post: n */
#define A_ADDR    17            /* n */
#define A_DEREF   18
#define A_UNARY   19            /* '-' '+' '~': n */
#define A_NOT     20
#define A_SIZEOFE 21            /* n */
#define A_SIZEOFT 22            /* then a type name */
#define A_CASTT   23            /* a type name, kept for the A_CAST after */
#define A_CAST    24            /* n */

/* a type name: a declspec and a declarator without a name */
#define DS        30            /* then B_STRUCT, B_ENUM or B_TYPEDEF, then B_BASIC */
#define B_BASIC   31            /* storage class (K_...) or 0, basic kind or 0 */
#define B_TYPEDEF 32            /* name */
#define B_STRUCT  33            /* union tag hasbody [M_DECL ... M_END] */
#define B_ENUM    34            /* hasbody [E_ITEM ... E_END] */
#define M_DECL    35            /* a declspec, then M_ITEM declarators, M_DONE */
#define M_ITEM    36
#define M_DONE    37
#define M_END     38
#define E_ITEM    39            /* name hasvalue [expression] */
#define E_END     40
#define D_PTR     41            /* then the rest of the declarator */
#define D_NEST    42            /* ( declarator ) suffixes */
#define D_NAME    43            /* name suffixes */
#define D_ANON    44            /* suffixes */
#define S_ARRAY   45            /* expression or A_NONE, then suffixes */
#define S_FUNC    46            /* P_PARAM ... P_END flags */
#define S_SEND    47            /* the end of the suffixes */
#define P_PARAM   48            /* a declspec and a declarator */
#define P_END     49            /* flags (FN_VARARG, FN_NOPROTO) */

/* declarations: DECL, a declspec, then I_DECL items and I_END */
#define DECL      50
#define I_DECL    51            /* a declarator, then I_INIT, I_FUNC or I_NONE */
#define I_INIT    52            /* an initializer */
#define I_FUNC    53            /* then the body: a block */
#define I_NONE    54
#define I_END     55
#define V_LIST    56            /* initializers ... V_LEND */
#define V_LEND    57
#define V_EXPR    58            /* an expression */
#define V_STRING  59            /* length bytes: a string on its own */

/* statements */
#define S_BLOCK   60            /* declarations and statements, S_BEND */
#define S_BEND    61
#define S_EMPTY   62
#define S_EXPR    63
#define S_IF      64            /* expression statement, S_ELSE statement or S_NOELSE */
#define S_ELSE    65
#define S_NOELSE  66
#define S_WHILE   67
#define S_DO      68            /* statement expression */
#define S_FOR     69            /* 3 expressions (or A_NONE), statement */
#define S_SWITCH  70
#define S_CASE    71            /* expression statement */
#define S_DEFAULT 72
#define S_BREAK   73
#define S_CONT    74
#define S_RETURN  75            /* expression or A_NONE */
#define S_GOTO    76            /* name */
#define S_LABEL   77            /* name statement */
#define X_EOF     78            /* the end of the file */
#define X_BANK    79            /* #pragma bank: like X_LINE, before a tag */
