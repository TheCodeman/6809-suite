/*
 * CC - a C compiler for MINI09.  See cc.md.
 *
 *     cc09 [-I dir] file.c [out.asm]           on the PC
 *     CC FILE.C [OUT.ASM] [-I DIR]     on MINI09
 *
 * One pass.  The parser builds a tree for each expression and the code
 * generator turns it into 6809 assembler for ASM (or lwasm) at once;
 * statements are emitted as they are read.
 *
 * cc.c is written in the subset of C that it compiles.  The PC build
 * (gcc) and the MINI09 build must write the same bytes, so nothing here
 * may depend on the host's sizes: a value that stands for a number on
 * the 6809 is always cut to 8, 16 or 32 bits (trunc), and only those
 * cut values are printed.
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
#define MAXGSYM  480            /* global symbols */
#define MAXLSYM  96             /* local symbols in scope */
#define MAXTYPE  640
#define MAXMEMB  320            /* struct members */
#define MAXPARM  320            /* parameters of all function types */
#define MAXFP    16             /* parameters of one function */
#define MAXMAC   256            /* macros */
#define MACSZ    5000           /* macro bodies */
#define EXPSZ    2000           /* macro expansions in use */
#define ARGSZ    600            /* the arguments of one macro call */
#define MAXSRC   16             /* nested files and macro expansions */
#define MAXNODE  300            /* expression tree nodes */
#define MAXCASE  160
#define MAXIF    16
#define MAXGOTO  32             /* goto labels in one function */
#define MAXLOOP  24
#define STRSZ    512            /* a string literal, an identifier */
#define PATHSZ   128            /* an #include file's path */

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

/* ---- tree nodes -------------------------------------------------- */

#define N_NUM     1
#define N_LVAR    2             /* local: nd_val = offset from U */
#define N_GVAR    3             /* global: nd_sym = symbol */
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

/* operand modes for the code generator */
#define M_IMM  1                /* #v */
#define M_ISYM 2                /* #sym+v */
#define M_LOC  3                /* v,u */
#define M_GLB  4                /* sym+v */
#define M_IX   5                /* v,x */
#define M_IY   6                /* v,y */
#define M_ABS  7                /* v */
#define M_STK  8                /* ,s++ (or ,s+ for a byte) */

/* runtime helpers, imported when used */
#define H_MUL   0
#define H_DIVS  1
#define H_DIVU  2
#define H_MODS  3
#define H_MODU  4
#define H_SHL   5
#define H_SHRS  6
#define H_SHRU  7
#define H_LADD  8
#define H_LSUB  9
#define H_LMUL  10
#define H_LDIVS 11
#define H_LDIVU 12
#define H_LMODS 13
#define H_LMODU 14
#define H_LAND  15
#define H_LOR   16
#define H_LXOR  17
#define H_LSHL  18
#define H_LSHRS 19
#define H_LSHRU 20
#define H_LCMP  21
#define H_LCMPU 22
#define H_LNEG  23
#define H_SEXT  24
#define NHELP   25

char *helpers[] = {
    "__mul", "__divs", "__divu", "__mods", "__modu", "__shl", "__shrs",
    "__shru", "__ladd", "__lsub", "__lmul", "__ldivs", "__ldivu", "__lmods",
    "__lmodu", "__land", "__lor", "__lxor", "__lshl", "__lshrs", "__lshru",
    "__lcmp", "__lcmpu", "__lneg", "__sext", 0
};
char hused[NHELP];

/* ---- state ------------------------------------------------------- */

FILE *out;
char *outname;
char *incdir;
int errors;

/* names */
#ifdef __MINI09__
char *names;
char *mactext;
#else
char namebuf[NAMESZ];
char macbuf[MACSZ];
char *names;
char *mactext;
#endif
int nnamech, nnames;
int nm_off[MAXNAME], nm_next[MAXNAME], nm_head[NHASH];
int nm_gsym[MAXNAME], nm_lsym[MAXNAME], nm_mac[MAXNAME], nm_tag[MAXNAME];

/* input */
FILE *src_f[MAXSRC];
char *src_p[MAXSRC];
int src_line[MAXSRC], src_name[MAXSRC], src_mac[MAXSRC], src_mark[MAXSRC];
int src_pb[MAXSRC];
int nsrc;
char expbuf[EXPSZ];
int expend;
char argbuf[ARGSZ];

/* macros */
int mac_off[MAXMAC], mac_np[MAXMAC];
char mac_busy[MAXMAC];
int nmac, macend;

/* conditionals */
char iftaken[MAXIF];
int ifdepth;

/* lexer */
int ch, tok, toktype, tokname, tokop, tokline, bol, pp_line, pp_if;
long tokval;
char strbuf[STRSZ];
int strn;
char strtmp[STRSZ];

/* types */
int ty_kind[MAXTYPE], ty_base[MAXTYPE], ty_size[MAXTYPE], ty_n[MAXTYPE];
int ty_x[MAXTYPE], ty_ptr[MAXTYPE];
int ntypes;
int mb_name[MAXMEMB], mb_type[MAXMEMB], mb_off[MAXMEMB], mb_next[MAXMEMB];
int nmemb;
int pm_type[MAXPARM], pm_name[MAXPARM];
int nparm;
int holes[8];
int nhole;

/* symbols */
int gs_name[MAXGSYM], gs_type[MAXGSYM], gs_sc[MAXGSYM], gs_fl[MAXGSYM];
int gs_val[MAXGSYM];
int ngsym;
int ls_name[MAXLSYM], ls_type[MAXLSYM], ls_sc[MAXLSYM], ls_val[MAXLSYM];
int ls_prev[MAXLSYM];
int nlsym;

/* tree */
int nd_op[MAXNODE], nd_type[MAXNODE], nd_l[MAXNODE], nd_r[MAXNODE];
int nd_sym[MAXNODE];
long nd_val[MAXNODE];
int nnode;

/* code */
int nlabel, cursect, retlabel, rettype, curoff, maxoff, infunc, nfuncs;
int brk[MAXLOOP], cont[MAXLOOP];
int nbrk, ncont;
int case_lab[MAXCASE];
int case_val[MAXCASE];
int ncase, sw_first, sw_def, insw;
int gl_name[MAXGOTO], gl_lab[MAXGOTO];
char gl_def[MAXGOTO];
int ngoto;
int om, oms;
long omv;
int s_om, s_oms;
long s_omv;
int dbn;
int dbuf[16];

/* ---- prototypes -------------------------------------------------- */

void next(void);
int expr(void);
int assign(void);
int cond(void);
int unary(void);
int declspec(int *psc);
int declarator(int t, int *pname);
long constexpr(void);
void statement(void);
void compound(void);
void gen(int n);
void gen_cond(int n, int lab, int jt);
void gen_addr(int n);
int init_data(int t);
void error(char *msg);

/* ---- small things ------------------------------------------------ */

void putstr(char *s)
{
    while (*s)
        putchar(*s++);
}

void putnum(long v)
{
    char b[12];
    int i;
    if (v < 0) {
        putchar('-');
        v = -v;
    }
    i = 0;
    do {
        b[i++] = '0' + v % 10;
        v = v / 10;
    } while (v);
    while (i)
        putchar(b[--i]);
}

int curline(void)
{
    int i;
    for (i = nsrc - 1; i > 0; i--)
        if (src_f[i])
            break;
    return src_line[i];
}

char *curfile(void)
{
    int i;
    for (i = nsrc - 1; i > 0; i--)
        if (src_f[i])
            break;
    return names + nm_off[src_name[i]];
}

void error2(char *msg, char *arg)
{
    putstr(curfile());
    putchar(':');
    putnum(tokline);
    putstr(": ");
    putstr(msg);
    if (arg) {
        putstr(arg);
    }
    putchar('\n');
    if (++errors >= 20) {
        putstr("Too many errors\n");
        if (out) {
            fclose(out);
            remove(outname);
        }
        exit(1);
    }
}

void error(char *msg)
{
    error2(msg, 0);
}

void fatal(char *msg)
{
    errors = 19;
    error(msg);
}

int isid1(int c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

int isdig(int c)
{
    return c >= '0' && c <= '9';
}

int isid(int c)
{
    return isid1(c) || isdig(c);
}

/* v cut to 32 bits, as the 6809 has it (a no-op there) */
long tr32(long v)
{
    v = v & 0xFFFFFFFF;
    if (v & 0x80000000)
        v = v - 0xFFFFFFFF - 1;
    return v;
}

/* ---- names ------------------------------------------------------- */

int lookup(char *s)
{
    int h, i, n;
    char *p;
    h = 0;
    for (p = s; *p; p++)
        h = (h * 3 + *p) & (NHASH - 1);
    for (i = nm_head[h]; i >= 0; i = nm_next[i])
        if (strcmp(names + nm_off[i], s) == 0)
            return i;
    n = strlen(s) + 1;
    if (nnames >= MAXNAME || nnamech + n > NAMESZ)
        fatal("Too many names");
    strcpy(names + nnamech, s);
    nm_off[nnames] = nnamech;
    nnamech = nnamech + n;
    nm_next[nnames] = nm_head[h];
    nm_head[h] = nnames;
    nm_gsym[nnames] = -1;
    nm_lsym[nnames] = -1;
    nm_mac[nnames] = -1;
    nm_tag[nnames] = 0;
    return nnames++;
}

char *name(int id)
{
    return names + nm_off[id];
}

/* ---- input ------------------------------------------------------- */

int rawc(void)
{
    int c, t;
    for (;;) {
        t = nsrc - 1;
        if (src_pb[t] != -2) {
            c = src_pb[t];
            src_pb[t] = -2;
            return c;
        }
        if (src_f[t]) {
            c = fgetc(src_f[t]);
            if (c == '\r')
                continue;
            if (c == '\n')
                src_line[t]++;
            if (c != EOF)
                return c;
            if (t == 0)
                return EOF;
            fclose(src_f[t]);
            nsrc--;
            return '\n';
        }
        c = *src_p[t];
        if (c) {
            src_p[t]++;
            if (c == 2) {           /* an argument starts: the macro may */
                mac_busy[src_mac[t]] = 0;   /* be used in it */
                continue;
            }
            if (c == 3) {
                mac_busy[src_mac[t]] = 1;
                continue;
            }
            return c;
        }
        mac_busy[src_mac[t]] = 0;
        expend = src_mark[t];
        nsrc--;
        return ' ';
    }
}

void nextch(void)
{
    ch = rawc();
}

void unch(int c)
{
    src_pb[nsrc - 1] = c;
}

int pushfile(char *path)
{
    FILE *f;
    if (nsrc >= MAXSRC) {
        error("Includes nested too deep");
        return 0;
    }
    f = fopen(path, "r");
    if (!f)
        return 0;
    src_f[nsrc] = f;
    src_line[nsrc] = 1;
    src_name[nsrc] = lookup(path);
    src_pb[nsrc] = -2;
    nsrc++;
    return 1;
}

void skipsp(void)
{
    while (ch == ' ' || ch == '\t')
        nextch();
}

void readident(void)
{
    int n;
    n = 0;
    while (isid(ch)) {
        if (n < STRSZ - 1)
            strbuf[n++] = ch;
        nextch();
    }
    strbuf[n] = 0;
}

void skipline(void)
{
    while (ch != '\n' && ch != EOF)
        nextch();
}

/* ---- the preprocessor -------------------------------------------- */

int macstore(int c)
{
    if (macend >= MACSZ)
        fatal("Macros too big");
    mactext[macend++] = c;
    return c;
}

/* #define nm body, before the source is read */
void predef(char *nm, char *body)
{
    int id, m;
    id = lookup(nm);
    m = nmac++;
    nm_mac[id] = m;
    mac_off[m] = macend;
    mac_np[m] = -1;
    mac_busy[m] = 0;
    while (*body)
        macstore(*body++);
    macstore(0);
}

/* copy a quoted literal starting at ch, by put (0: mactext, 1: argbuf) */
int argn;

void putq(int c, int where)
{
    if (where == 0)
        macstore(c);
    else {
        if (argn >= ARGSZ - 1)
            fatal("Macro arguments too long");
        argbuf[argn++] = c;
    }
}

void copyquote(int where)
{
    int q;
    q = ch;
    putq(ch, where);
    nextch();
    while (ch != q && ch != '\n' && ch != EOF) {
        if (ch == '\\') {
            putq(ch, where);
            nextch();
        }
        putq(ch, where);
        nextch();
    }
    if (ch == q) {
        putq(ch, where);
        nextch();
    }
}

void do_define(void)
{
    int id, m, np, i, k, c;
    int pid[MAXFP];
    skipsp();
    if (!isid1(ch)) {
        error("Macro name expected");
        return;
    }
    readident();
    id = lookup(strbuf);
    np = -1;
    if (ch == '(') {
        np = 0;
        nextch();
        for (;;) {
            skipsp();
            if (ch == ')' || ch == '\n' || ch == EOF)
                break;
            readident();
            if (np < MAXFP)
                pid[np++] = lookup(strbuf);
            skipsp();
            if (ch == ',')
                nextch();
            else if (ch != ')') {
                error("Bad macro parameters");
                return;
            }
        }
        if (ch == ')')
            nextch();
    }
    skipsp();
    m = nm_mac[id];
    if (m < 0) {
        if (nmac >= MAXMAC)
            fatal("Too many macros");
        m = nmac++;
        nm_mac[id] = m;
    }
    mac_off[m] = macend;
    mac_np[m] = np;
    mac_busy[m] = 0;
    while (ch != '\n' && ch != EOF) {
        if (isid1(ch)) {
            readident();
            k = -1;
            for (i = 0; i < np; i++)
                if (strcmp(strbuf, name(pid[i])) == 0)
                    k = i;
            if (k >= 0) {
                macstore(1);
                macstore(k + 1);
            } else
                for (i = 0; strbuf[i]; i++)
                    macstore(strbuf[i]);
        } else if (ch == '"' || ch == '\'')
            copyquote(0);
        else if (ch == '/') {
            c = rawc();
            if (c == '*') {
                nextch();
                for (;;) {
                    if (ch == EOF)
                        break;
                    if (ch == '*') {
                        nextch();
                        if (ch == '/') {
                            nextch();
                            break;
                        }
                    } else
                        nextch();
                }
                macstore(' ');
            } else if (c == '/')
                skipline();
            else {
                unch(c);
                macstore('/');
                nextch();
            }
        } else {
            macstore(ch);
            nextch();
        }
    }
    while (macend > mac_off[m] && (mactext[macend - 1] == ' ' || mactext[macend - 1] == '\t'))
        macend--;
    macstore(0);
}

/* The macro m was named and ch is the character after the name.  Push
   its expansion and return 1; 0 if it is function-like and no ( follows. */
int expand(int m)
{
    int np, na, depth, i, k, start, nl;
    int argat[MAXFP];
    char *p;
    np = mac_np[m];
    na = 0;
    if (np >= 0) {
        nl = 0;
        while (ch == ' ' || ch == '\t' || ch == '\n') {
            if (ch == '\n')
                nl = 1;
            nextch();
        }
        if (ch != '(') {
            if (nl)
                bol = 1;
            return 0;
        }
        nextch();
        argn = 0;
        depth = 0;
        argat[0] = 0;
        for (;;) {
            if (ch == EOF) {
                error("Macro call not ended");
                return 0;
            }
            if (ch == '(')
                depth++;
            else if (ch == ')') {
                if (depth == 0)
                    break;
                depth--;
            } else if (ch == ',' && depth == 0) {
                putq(0, 1);
                if (na < MAXFP - 1)
                    na++;
                argat[na] = argn;
                nextch();
                continue;
            } else if (ch == '"' || ch == '\'') {
                copyquote(1);
                continue;
            } else if (ch == '\n')
                ch = ' ';
            putq(ch, 1);
            nextch();
        }
        putq(0, 1);
        na++;
        nextch();
        if (np == 0 && na == 1) {
            for (p = argbuf; *p == ' ' || *p == '\t'; p++)
                ;
            if (*p == 0)
                na = 0;
        }
        if (na != np) {
            error("Wrong number of macro arguments");
            return 0;
        }
    }
    if (nsrc >= MAXSRC) {
        error("Macros nested too deep");
        return 0;
    }
    start = expend;
    for (p = mactext + mac_off[m]; *p; p++) {
        if (*p == 1) {
            p++;
            k = *p - 1;
            if (expend >= EXPSZ - 4)
                fatal("Macro expansion too long");
            expbuf[expend++] = 2;
            for (i = argat[k]; argbuf[i]; i++) {
                if (expend >= EXPSZ - 3)
                    fatal("Macro expansion too long");
                expbuf[expend++] = argbuf[i];
            }
            expbuf[expend++] = 3;
        } else {
            if (expend >= EXPSZ - 2)
                fatal("Macro expansion too long");
            expbuf[expend++] = *p;
        }
    }
    expbuf[expend++] = 0;
    /* ch goes back to the source it came from; if that one still has a
       character back, ch is the space that ended an expansion inside
       it, and can go */
    if (src_pb[nsrc - 1] == -2)
        src_pb[nsrc - 1] = ch;
    src_f[nsrc] = 0;
    src_p[nsrc] = expbuf + start;
    src_mac[nsrc] = m;
    src_mark[nsrc] = start;
    src_pb[nsrc] = -2;
    src_line[nsrc] = 0;
    nsrc++;
    mac_busy[m] = 1;
    nextch();
    return 1;
}

int pp_eval(void)
{
    long v;
    pp_line = 1;
    pp_if = 1;
    next();
    v = constexpr();
    if (tok != T_EOL)
        error("Bad #if");
    pp_line = 0;
    pp_if = 0;
    return v != 0;
}

/* Skip lines up to the #else, #elif or #endif that ends this part. */
void skip_block(void)
{
    int depth;
    depth = 0;
    for (;;) {
        skipline();
        if (ch == EOF) {
            error("Missing #endif");
            return;
        }
        nextch();
        skipsp();
        if (ch != '#')
            continue;
        nextch();
        skipsp();
        if (!isid1(ch))
            continue;
        readident();
        if (strcmp(strbuf, "if") == 0 || strcmp(strbuf, "ifdef") == 0 ||
            strcmp(strbuf, "ifndef") == 0)
            depth++;
        else if (strcmp(strbuf, "endif") == 0) {
            if (depth == 0) {
                ifdepth--;
                return;
            }
            depth--;
        } else if (depth == 0 && strcmp(strbuf, "else") == 0) {
            if (!iftaken[ifdepth - 1]) {
                iftaken[ifdepth - 1] = 1;
                return;
            }
        } else if (depth == 0 && strcmp(strbuf, "elif") == 0) {
            if (!iftaken[ifdepth - 1] && pp_eval()) {
                iftaken[ifdepth - 1] = 1;
                return;
            }
        }
    }
}

void push_if(int v)
{
    if (ifdepth >= MAXIF)
        fatal("#if nested too deep");
    iftaken[ifdepth++] = v;
    if (!v)
        skip_block();
}

void do_include(void)
{
    int q, n, i;
    char path[PATHSZ];
    skipsp();
    if (ch != '"' && ch != '<') {
        error("Bad #include");
        return;
    }
    q = ch == '<' ? '>' : '"';
    nextch();
    n = 0;
    while (ch != q && ch != '\n' && ch != EOF) {
        if (n < PATHSZ - 1)
            strbuf[n++] = ch;
        nextch();
    }
    strbuf[n] = 0;
    skipline();
    if (q == '"') {
        /* beside the file that includes it */
        strcpy(path, curfile());
        for (i = strlen(path); i > 0 && path[i - 1] != '/'; i--)
            ;
        path[i] = 0;
        if (i + n < PATHSZ - 1) {
            strcat(path, strbuf);
            if (pushfile(path))
                return;
        }
    }
    i = strlen(incdir);
    if (i + n < PATHSZ - 2) {
        strcpy(path, incdir);
        if (i > 0 && path[i - 1] != '/') {
            path[i] = '/';
            path[i + 1] = 0;
        }
        strcat(path, strbuf);
        if (pushfile(path))
            return;
    }
    error2("Can't open ", strbuf);
}

void directive(void)
{
    int id;
    skipsp();
    if (!isid1(ch)) {
        skipline();
        return;
    }
    readident();
    if (strcmp(strbuf, "define") == 0)
        do_define();
    else if (strcmp(strbuf, "undef") == 0) {
        skipsp();
        readident();
        id = lookup(strbuf);
        nm_mac[id] = -1;
    } else if (strcmp(strbuf, "include") == 0) {
        do_include();
        return;
    } else if (strcmp(strbuf, "ifdef") == 0 || strcmp(strbuf, "ifndef") == 0) {
        id = strbuf[2] == 'n';
        skipsp();
        readident();
        push_if((nm_mac[lookup(strbuf)] >= 0) != id);
    } else if (strcmp(strbuf, "if") == 0)
        push_if(pp_eval());
    else if (strcmp(strbuf, "elif") == 0 || strcmp(strbuf, "else") == 0) {
        if (ifdepth == 0)
            error("#else without #if");
        else
            skip_block();
    } else if (strcmp(strbuf, "endif") == 0) {
        if (ifdepth == 0)
            error("#endif without #if");
        else
            ifdepth--;
    } else if (strcmp(strbuf, "error") == 0)
        error("#error");
    skipline();
}

/* ---- the lexer --------------------------------------------------- */

int escape(void)
{
    int v, n;
    nextch();
    v = ch;
    nextch();
    if (v == 'n')
        return 10;
    if (v == 't')
        return 9;
    if (v == 'r')
        return 13;
    if (v == 'a')
        return 7;
    if (v == 'b')
        return 8;
    if (v == 'f')
        return 12;
    if (v == 'v')
        return 11;
    if (v == 'x') {
        v = 0;
        for (;;) {
            if (isdig(ch))
                v = v * 16 + ch - '0';
            else if (ch >= 'a' && ch <= 'f')
                v = v * 16 + ch - 'a' + 10;
            else if (ch >= 'A' && ch <= 'F')
                v = v * 16 + ch - 'A' + 10;
            else
                break;
            nextch();
        }
        return v & 255;
    }
    if (v >= '0' && v <= '7') {
        v = v - '0';
        for (n = 1; n < 3 && ch >= '0' && ch <= '7'; n++) {
            v = v * 8 + ch - '0';
            nextch();
        }
        return v & 255;
    }
    return v;
}

void number(void)
{
    long v;
    int base, d, uns, lng;
    v = 0;
    base = 10;
    if (ch == '0') {
        nextch();
        base = 8;
        if (ch == 'x' || ch == 'X') {
            base = 16;
            nextch();
        }
    }
    for (;;) {
        if (isdig(ch))
            d = ch - '0';
        else if (ch >= 'a' && ch <= 'f')
            d = ch - 'a' + 10;
        else if (ch >= 'A' && ch <= 'F')
            d = ch - 'A' + 10;
        else
            break;
        if (d >= base)
            break;
        v = tr32(v * base + d);
        nextch();
    }
    uns = 0;
    lng = 0;
    for (;;) {
        if (ch == 'u' || ch == 'U')
            uns = 1;
        else if (ch == 'l' || ch == 'L')
            lng = 1;
        else
            break;
        nextch();
    }
    tok = T_NUM;
    tokval = v;
    if (!lng && !uns && (unsigned long)v <= 32767)
        toktype = TI;
    else if (!lng && (uns || base != 10) && (unsigned long)v <= 65535)
        toktype = TUI;
    else if (!uns && (unsigned long)v <= 0x7FFFFFFF)
        toktype = TL;
    else
        toktype = TUL;
}

void next(void)
{
    int c, id, m, paren;
    for (;;) {
        for (;;) {
            if (ch == '\n') {
                if (pp_line) {
                    tok = T_EOL;
                    return;
                }
                bol = 1;
                nextch();
            } else if (ch == ' ' || ch == '\t' || ch == 12 || ch == 11)
                nextch();
            else if (ch == '/') {
                c = rawc();
                if (c == '*') {
                    nextch();
                    for (;;) {
                        if (ch == EOF) {
                            error("Comment not ended");
                            break;
                        }
                        if (ch == '*') {
                            nextch();
                            if (ch == '/') {
                                nextch();
                                break;
                            }
                        } else
                            nextch();
                    }
                } else if (c == '/')
                    skipline();
                else {
                    unch(c);
                    break;
                }
            } else
                break;
        }
        tokline = curline();
        if (ch == '#' && bol && src_f[nsrc - 1]) {
            nextch();
            directive();
            continue;
        }
        bol = 0;
        if (isid1(ch)) {
            readident();
            id = lookup(strbuf);
            if (id < NKW) {
                tok = K_BASE + id;
                return;
            }
            if (pp_if && id == ID_DEFINED) {
                skipsp();
                paren = ch == '(';
                if (paren) {
                    nextch();
                    skipsp();
                }
                readident();
                tokval = nm_mac[lookup(strbuf)] >= 0;
                if (paren) {
                    skipsp();
                    if (ch == ')')
                        nextch();
                }
                tok = T_NUM;
                toktype = TI;
                return;
            }
            m = nm_mac[id];
            if (m >= 0 && !mac_busy[m] && expand(m))
                continue;
            if (id == ID_LINE) {
                tok = T_NUM;
                tokval = tokline;
                toktype = TI;
                return;
            }
            if (id == ID_FILE) {
                strcpy(strbuf, curfile());
                strn = strlen(strbuf);
                tok = T_STR;
                return;
            }
            if (pp_if) {
                tok = T_NUM;
                tokval = 0;
                toktype = TI;
                return;
            }
            tok = T_IDENT;
            tokname = id;
            return;
        }
        if (isdig(ch)) {
            number();
            return;
        }
        if (ch == '\'') {
            nextch();
            if (ch == '\\')
                c = escape();
            else {
                c = ch;
                nextch();
            }
            if (ch != '\'')
                error("Bad character constant");
            else
                nextch();
            if (c > 127)
                c = c - 256;
            tok = T_NUM;
            tokval = c;
            toktype = TI;
            return;
        }
        if (ch == '"') {
            nextch();
            strn = 0;
            while (ch != '"') {
                if (ch == '\n' || ch == EOF) {
                    error("String not ended");
                    break;
                }
                if (ch == '\\')
                    c = escape();
                else {
                    c = ch;
                    nextch();
                }
                if (strn < STRSZ - 1)
                    strbuf[strn++] = c;
            }
            nextch();
            strbuf[strn] = 0;
            tok = T_STR;
            return;
        }
        c = ch;
        if (c == EOF) {
            tok = T_EOF;
            return;
        }
        nextch();
        tok = c;
        if (c == '=') {
            if (ch == '=') {
                nextch();
                tok = T_EQ;
            }
        } else if (c == '!') {
            if (ch == '=') {
                nextch();
                tok = T_NE;
            }
        } else if (c == '<' || c == '>') {
            if (ch == '=') {
                nextch();
                tok = c == '<' ? T_LE : T_GE;
            } else if (ch == c) {
                nextch();
                tok = c == '<' ? T_SHL : T_SHR;
                if (ch == '=') {
                    nextch();
                    tokop = tok;
                    tok = T_ASGN;
                }
            }
        } else if (c == '&' || c == '|') {
            if (ch == c) {
                nextch();
                tok = c == '&' ? T_LAND : T_LOR;
            } else if (ch == '=') {
                nextch();
                tokop = c;
                tok = T_ASGN;
            }
        } else if (c == '+' || c == '-') {
            if (ch == c) {
                nextch();
                tok = c == '+' ? T_INC : T_DEC;
            } else if (ch == '=') {
                nextch();
                tokop = c;
                tok = T_ASGN;
            } else if (c == '-' && ch == '>') {
                nextch();
                tok = T_ARROW;
            }
        } else if (c == '*' || c == '/' || c == '%' || c == '^') {
            if (ch == '=') {
                nextch();
                tokop = c;
                tok = T_ASGN;
            }
        } else if (c == '.') {
            if (ch == '.') {
                nextch();
                if (ch == '.')
                    nextch();
                tok = T_ELLIP;
            }
        }
        return;
    }
}

void expect(int t)
{
    char m[16];
    if (tok == t) {
        next();
        return;
    }
    strcpy(m, "Expected  ");
    m[9] = t;
    if (t == T_IDENT)
        strcpy(m, "Expected a name");
    error(m);
    if (t == ';') {
        while (tok != ';' && tok != '}' && tok != T_EOF)
            next();
        if (tok == ';')
            next();
    }
}

/* ---- types ------------------------------------------------------- */

int newtype(int k, int base, int size, int n, int x)
{
    if (ntypes >= MAXTYPE)
        fatal("Too many types");
    ty_kind[ntypes] = k;
    ty_base[ntypes] = base;
    ty_size[ntypes] = size;
    ty_n[ntypes] = n;
    ty_x[ntypes] = x;
    ty_ptr[ntypes] = 0;
    return ntypes++;
}

int ptr_to(int t)
{
    if (!ty_ptr[t])
        ty_ptr[t] = newtype(TY_PTR, t, 2, 0, 0);
    return ty_ptr[t];
}

int tsize(int t)
{
    return ty_size[t];
}

int array_of(int t, int n)
{
    int i, s;
    for (i = TUL + 1; i < ntypes; i++)
        if (ty_kind[i] == TY_ARRAY && ty_base[i] == t && ty_n[i] == n)
            return i;
    s = -1;
    if (tsize(t) < 0)
        error("Array of an incomplete type");
    else if (n >= 0)
        s = n * tsize(t);
    return newtype(TY_ARRAY, t, s, n, 0);
}

int isint(int t)
{
    return ty_kind[t] >= TY_CHAR && ty_kind[t] <= TY_ULONG;
}

int ischar(int t)
{
    return ty_kind[t] == TY_CHAR || ty_kind[t] == TY_UCHAR;
}

int islong(int t)
{
    return ty_kind[t] == TY_LONG || ty_kind[t] == TY_ULONG;
}

int isptr(int t)
{
    return ty_kind[t] == TY_PTR;
}

int isuns(int t)
{
    int k;
    k = ty_kind[t];
    return k == TY_UCHAR || k == TY_UINT || k == TY_ULONG || k == TY_PTR;
}

int isscalar(int t)
{
    return isint(t) || isptr(t);
}

int isstruct(int t)
{
    return ty_kind[t] == TY_STRUCT || ty_kind[t] == TY_UNION;
}

int promote(int t)
{
    if (ischar(t))
        return TI;
    return t;
}

int usual(int a, int b)
{
    if (ty_kind[a] == TY_ULONG || ty_kind[b] == TY_ULONG)
        return TUL;
    if (islong(a) || islong(b))
        return TL;
    if (ty_kind[a] == TY_UINT || ty_kind[b] == TY_UINT)
        return TUI;
    return TI;
}

/* v cut to what type t holds */
long truncv(long v, int t)
{
    int k;
    k = ty_kind[t];
    if (k == TY_CHAR) {
        v = v & 255;
        if (v > 127)
            v = v - 256;
    } else if (k == TY_UCHAR)
        v = v & 255;
    else if (k == TY_INT) {
        v = v & 0xFFFF;
        if (v > 32767)
            v = v - 65536;
    } else if (k == TY_LONG || k == TY_ULONG)
        v = tr32(v);
    else
        v = v & 0xFFFF;
    return v;
}

/* ---- symbols ----------------------------------------------------- */

int addglobal(int id, int t, int sc)
{
    int g;
    g = nm_gsym[id];
    if (g >= 0) {
        if (sc == SC_TYPEDEF && gs_sc[g] == SC_TYPEDEF && gs_type[g] == t)
            return g;           /* the same typedef again */
        if (gs_sc[g] == SC_TYPEDEF || gs_sc[g] == SC_ENUM || sc == SC_TYPEDEF || sc == SC_ENUM)
            error2("Redeclared: ", name(id));
        if (ty_kind[t] == TY_ARRAY && ty_size[gs_type[g]] < 0)
            gs_type[g] = t;
        if (ty_kind[t] == TY_FUNC && (ty_x[gs_type[g]] & FN_NOPROTO))
            gs_type[g] = t;
        if (sc == SC_STATIC || gs_sc[g] == SC_EXTERN)
            gs_sc[g] = sc;
        return g;
    }
    if (ngsym >= MAXGSYM)
        fatal("Too many globals");
    g = ngsym++;
    gs_name[g] = id;
    gs_type[g] = t;
    gs_sc[g] = sc;
    gs_fl[g] = 0;
    gs_val[g] = 0;
    nm_gsym[id] = g;
    return g;
}

int addlocal(int id, int t, int sc, int val)
{
    int l;
    if (nlsym >= MAXLSYM)
        fatal("Too many locals");
    l = nlsym++;
    ls_name[l] = id;
    ls_type[l] = t;
    ls_sc[l] = sc;
    ls_val[l] = val;
    ls_prev[l] = nm_lsym[id];
    nm_lsym[id] = l;
    return l;
}

void popscope(int mark)
{
    while (nlsym > mark) {
        nlsym--;
        nm_lsym[ls_name[nlsym]] = ls_prev[nlsym];
    }
}

int istypedef(int id)
{
    int l;
    l = nm_lsym[id];
    if (l >= 0)
        return ls_sc[l] == SC_TYPEDEF;
    l = nm_gsym[id];
    return l >= 0 && gs_sc[l] == SC_TYPEDEF;
}

int typedeftype(int id)
{
    int l;
    l = nm_lsym[id];
    if (l >= 0)
        return ls_type[l];
    return gs_type[nm_gsym[id]];
}

int istypestart(void)
{
    if (tok == T_IDENT)
        return istypedef(tokname);
    return tok == K_CHAR || tok == K_INT || tok == K_LONG || tok == K_SHORT ||
        tok == K_UNSIGNED || tok == K_SIGNED || tok == K_VOID || tok == K_STRUCT ||
        tok == K_UNION || tok == K_ENUM || tok == K_CONST || tok == K_VOLATILE;
}

int isdeclstart(void)
{
    return istypestart() || tok == K_TYPEDEF || tok == K_EXTERN || tok == K_STATIC ||
        tok == K_AUTO || tok == K_REGISTER;
}

/* ---- output ------------------------------------------------------ */

void ot(char *s)
{
    fputs(s, out);
}

void oc(int c)
{
    fputc(c, out);
}

void onum(long v)
{
    char b[12];
    int i;
    if (v < 0) {
        oc('-');
        v = -v;
    }
    i = 0;
    do {
        b[i++] = '0' + v % 10;
        v = v / 10;
    } while (v);
    while (i)
        oc(b[--i]);
}

void olab(int l)
{
    oc('L');
    onum(l);
}

int newlabel(void)
{
    return ++nlabel;
}

void label(int l)
{
    olab(l);
    oc('\n');
}

void op0(char *s)
{
    oc(' ');
    ot(s);
    oc('\n');
}

void op1(char *s, char *a)
{
    oc(' ');
    ot(s);
    oc(' ');
    ot(a);
    oc('\n');
}

void opl(char *s, int l)
{
    oc(' ');
    ot(s);
    oc(' ');
    olab(l);
    oc('\n');
}

void opi(char *s, long v)
{
    oc(' ');
    ot(s);
    ot(" #");
    onum(v);
    oc('\n');
}

void jmp(int l)
{
    opl("lbra", l);
}

void call(int h)
{
    hused[h] = 1;
    op1("jsr", helpers[h]);
}

void db_flush(void);

/* 1 code, 2 data, 3 bss, 4 strings (literals, kept apart so that one in
   an initializer doesn't land inside the object) */
void section(int s)
{
    if (s == cursect)
        return;
    db_flush();
    if (cursect)
        op0("endsection");
    if (s == 1)
        op1("section", "code");
    else if (s == 2)
        op1("section", "data");
    else if (s == 3)
        op1("section", "bss");
    else if (s == 4)
        op1("section", "strings");
    cursect = s;
}

void osym(int s)
{
    if (s >= 0) {
        oc('_');
        ot(name(gs_name[s]));
        gs_fl[s] = gs_fl[s] | F_USED;
    } else
        olab(-s);
}

void ooff(long v)
{
    if (v > 0)
        oc('+');
    if (v)
        onum(v);
}

/* the operand in om, omv, oms, plus extra */
void oper(int extra)
{
    long v;
    v = omv + extra;
    if (om == M_IMM) {
        oc('#');
        onum(v & 0xFFFF);
    } else if (om == M_ISYM) {
        oc('#');
        osym(oms);
        ooff(v);
    } else if (om == M_LOC) {
        onum(v);
        ot(",u");
    } else if (om == M_GLB) {
        osym(oms);
        ooff(v);
    } else if (om == M_ABS)
        onum(v & 0xFFFF);
    else if (om == M_IX) {
        if (v)
            onum(v);
        ot(",x");
    } else if (om == M_IY) {
        if (v)
            onum(v);
        ot(",y");
    } else
        ot(",s++");
}

void opm(char *s, int extra)
{
    oc(' ');
    ot(s);
    oc(' ');
    oper(extra);
    oc('\n');
}

/* a byte of the operand: hi (0) or lo (1) */
void opb(char *s, int lo)
{
    oc(' ');
    ot(s);
    oc(' ');
    if (om == M_IMM) {
        oc('#');
        if (lo)
            onum(omv & 255);
        else
            onum((omv >> 8) & 255);
    } else if (om == M_STK)
        ot(",s+");
    else
        oper(lo);
    oc('\n');
}

void save_om(void)
{
    s_om = om;
    s_omv = omv;
    s_oms = oms;
}

void restore_om(void)
{
    om = s_om;
    omv = s_omv;
    oms = s_oms;
}

/* data: bytes collected into fcb lines */
void db_flush(void)
{
    int i;
    if (!dbn)
        return;
    ot(" fcb ");
    for (i = 0; i < dbn; i++) {
        if (i)
            oc(',');
        onum(dbuf[i]);
    }
    oc('\n');
    dbn = 0;
}

void db(int b)
{
    dbuf[dbn++] = b & 255;
    if (dbn == 16)
        db_flush();
}

void dzero(int n)
{
    while (n-- > 0)
        db(0);
}

/* a string's bytes, n of them, then zeros up to size */
void dstring(char *s, int n, int size)
{
    int i;
    for (i = 0; i < n && i < size; i++)
        db(s[i]);
    dzero(size - i);
}

/* ---- tree -------------------------------------------------------- */

int node(int op, int t, int l, int r)
{
    if (nnode >= MAXNODE)
        fatal("Expression too complex");
    nd_op[nnode] = op;
    nd_type[nnode] = t;
    nd_l[nnode] = l;
    nd_r[nnode] = r;
    nd_val[nnode] = 0;
    nd_sym[nnode] = 0;
    return nnode++;
}

int mknum(long v, int t)
{
    int n;
    n = node(N_NUM, t, 0, 0);
    nd_val[n] = truncv(v, t);
    return n;
}

int log2of(long v)
{
    int k;
    for (k = 0; k < 16; k++)
        if (v == (1L << k))
            return k;
    return -1;
}

int fold(int n)
{
    int op, l, r, u, t;
    long a, b, v;
    unsigned long ua, ub;
    op = nd_op[n];
    l = nd_l[n];
    r = nd_r[n];
    t = nd_type[n];
    if (op == N_NEG || op == N_COM || op == N_NOT) {
        if (nd_op[l] != N_NUM)
            return n;
        a = nd_val[l];
        if (op == N_NEG)
            v = -a;
        else if (op == N_COM)
            v = ~a;
        else
            v = !a;
        return mknum(v, t);
    }
    if (op < N_ADD || op > N_LOR || nd_op[l] != N_NUM || nd_op[r] != N_NUM)
        return n;
    a = nd_val[l];
    b = nd_val[r];
    u = isuns(nd_type[l]);
    ua = (unsigned long)a & 0xFFFFFFFF;
    ub = (unsigned long)b & 0xFFFFFFFF;
    if ((op == N_DIV || op == N_MOD) && b == 0) {
        error("Division by zero");
        return mknum(0, t);
    }
    if (op == N_ADD)
        v = a + b;
    else if (op == N_SUB)
        v = a - b;
    else if (op == N_MUL)
        v = tr32(a) * tr32(b);
    else if (op == N_DIV)
        v = u ? (long)(ua / ub) : a / b;
    else if (op == N_MOD)
        v = u ? (long)(ua % ub) : a % b;
    else if (op == N_AND)
        v = a & b;
    else if (op == N_OR)
        v = a | b;
    else if (op == N_XOR)
        v = a ^ b;
    else if (op == N_SHL)
        v = b > 31 ? 0 : tr32(a) << b;
    else if (op == N_SHR) {
        if (b > 31)
            b = 31;
        v = u ? (long)(ua >> b) : a >> b;
    } else if (op == N_EQ)
        v = a == b;
    else if (op == N_NE)
        v = a != b;
    else if (op == N_LT)
        v = u ? ua < ub : a < b;
    else if (op == N_GT)
        v = u ? ua > ub : a > b;
    else if (op == N_LE)
        v = u ? ua <= ub : a <= b;
    else if (op == N_GE)
        v = u ? ua >= ub : a >= b;
    else if (op == N_LAND)
        v = a && b;
    else
        v = a || b;
    return mknum(tr32(v), t);
}

/* n as type t */
int conv(int n, int t)
{
    int f;
    f = nd_type[n];
    if (f == t)
        return n;
    if (ty_kind[t] == TY_VOID)
        return node(N_CAST, t, n, 0);
    if (!isscalar(f) || !isscalar(t)) {
        error("Bad conversion");
        return n;
    }
    if (nd_op[n] == N_NUM) {
        nd_val[n] = truncv(nd_val[n], t);
        nd_type[n] = t;
        return n;
    }
    if (tsize(f) == tsize(t) && !ischar(t)) {
        nd_type[n] = t;
        return n;
    }
    return node(N_CAST, t, n, 0);
}

int islvalue(int n)
{
    int op;
    op = nd_op[n];
    return op == N_LVAR || op == N_GVAR || op == N_SVAR || op == N_DEREF || op == N_STR;
}

/* &n */
int addr_of(int n)
{
    int p, t;
    t = ptr_to(nd_type[n]);
    if (nd_op[n] == N_DEREF) {
        p = nd_l[n];
        if (nd_type[p] == t)
            return p;
        return node(N_CAST, t, p, 0);
    }
    if (!islvalue(n)) {
        error("Not an lvalue");
        return n;
    }
    return node(N_ADDR, t, n, 0);
}

/* arrays and functions become pointers */
int rvalue(int n)
{
    int k;
    k = ty_kind[nd_type[n]];
    if (k == TY_ARRAY) {
        n = addr_of(n);
        nd_type[n] = ptr_to(ty_base[ty_base[nd_type[n]]]);
        return n;
    }
    if (k == TY_FUNC)
        return addr_of(n);
    return n;
}

int mkderef(int p)
{
    int t;
    p = rvalue(p);
    if (!isptr(nd_type[p])) {
        error("Not a pointer");
        return p;
    }
    t = ty_base[nd_type[p]];
    if (ty_kind[t] == TY_FUNC)
        return p;
    if (ty_kind[t] == TY_VOID)
        error("Can't use a void *");
    return node(N_DEREF, t, p, 0);
}

int scale(int i, int pt)
{
    int s;
    s = tsize(ty_base[pt]);
    i = conv(i, TI);
    if (s <= 1)
        return i;
    return fold(node(N_MUL, TI, i, mknum(s, TI)));
}

int mkbin(int op, int a, int b)
{
    int ta, tb, t, n, s;
    a = rvalue(a);
    b = rvalue(b);
    ta = nd_type[a];
    tb = nd_type[b];
    if (op == N_LAND || op == N_LOR) {
        if (!isscalar(ta) || !isscalar(tb))
            error("Bad operands");
        return fold(node(op, TI, a, b));
    }
    if (op == N_ADD || op == N_SUB) {
        if (isptr(ta) && isint(tb))
            return fold(node(op, ta, a, scale(b, ta)));
        if (op == N_ADD && isint(ta) && isptr(tb))
            return fold(node(op, tb, b, scale(a, tb)));
        if (op == N_SUB && isptr(ta) && isptr(tb)) {
            s = tsize(ty_base[ta]);
            nd_type[a] = TI;
            nd_type[b] = TI;
            n = fold(node(N_SUB, TI, a, b));
            if (s > 1)
                n = fold(node(N_DIV, TI, n, mknum(s, TI)));
            return n;
        }
    }
    if (op >= N_EQ && op <= N_GE) {
        if (isptr(ta) || isptr(tb)) {
            if (!isscalar(ta) || !isscalar(tb))
                error("Bad operands");
            a = conv(a, TUI);
            b = conv(b, TUI);
        } else if (!isint(ta) || !isint(tb))
            error("Bad operands");
        else {
            t = usual(ta, tb);
            a = conv(a, t);
            b = conv(b, t);
        }
        return fold(node(op, TI, a, b));
    }
    if (!isint(ta) || !isint(tb)) {
        error("Bad operands");
        return a;
    }
    if (op == N_SHL || op == N_SHR) {
        t = promote(ta);
        return fold(node(op, t, conv(a, t), conv(b, TI)));
    }
    t = usual(ta, tb);
    return fold(node(op, t, conv(a, t), conv(b, t)));
}

int mkassign(int l, int r)
{
    int t;
    t = nd_type[l];
    if (!islvalue(l) || ty_kind[t] == TY_ARRAY || ty_kind[t] == TY_FUNC) {
        error("Can't assign to this");
        return l;
    }
    if (!isscalar(t)) {
        if (!islvalue(r) || nd_type[r] != t) {
            error("Can't copy this struct");
            return l;
        }
        return node(N_SCOPY, t, l, r);
    }
    return node(N_ASSIGN, t, l, conv(rvalue(r), t));
}

int tokbinop(int t)
{
    if (t == '+')
        return N_ADD;
    if (t == '-')
        return N_SUB;
    if (t == '*')
        return N_MUL;
    if (t == '/')
        return N_DIV;
    if (t == '%')
        return N_MOD;
    if (t == '&')
        return N_AND;
    if (t == '|')
        return N_OR;
    if (t == '^')
        return N_XOR;
    if (t == T_SHL)
        return N_SHL;
    if (t == T_SHR)
        return N_SHR;
    if (t == T_EQ)
        return N_EQ;
    if (t == T_NE)
        return N_NE;
    if (t == '<')
        return N_LT;
    if (t == '>')
        return N_GT;
    if (t == T_LE)
        return N_LE;
    if (t == T_GE)
        return N_GE;
    if (t == T_LAND)
        return N_LAND;
    if (t == T_LOR)
        return N_LOR;
    return 0;
}

int mkasgop(int op, int l, int r)
{
    int t, n;
    t = nd_type[l];
    if (!islvalue(l) || !isscalar(t)) {
        error("Can't assign to this");
        return l;
    }
    r = rvalue(r);
    if (isptr(t)) {
        if (op != N_ADD && op != N_SUB)
            error("Bad operands");
        r = scale(r, t);
    } else if (op == N_SHL || op == N_SHR)
        r = conv(r, TI);
    else
        r = conv(r, promote(t));
    n = node(N_ASGOP, t, l, r);
    nd_val[n] = op;
    return n;
}

int mkinc(int n, int step, int post)
{
    int t, r;
    t = nd_type[n];
    if (!islvalue(n) || !isscalar(t)) {
        error("Can't change this");
        return n;
    }
    if (isptr(t))
        step = step * tsize(ty_base[t]);
    r = node(post ? N_POSTINC : N_PREINC, t, n, 0);
    nd_val[r] = step;
    return r;
}

int mkmember(int n, int arrow)
{
    int st, m, p, id, mt;
    if (tok != T_IDENT) {
        error("Member name expected");
        return n;
    }
    id = tokname;
    next();
    if (arrow) {
        n = rvalue(n);
        if (!isptr(nd_type[n]) || !isstruct(ty_base[nd_type[n]])) {
            error("Not a struct pointer");
            return n;
        }
        st = ty_base[nd_type[n]];
        p = n;
    } else {
        st = nd_type[n];
        if (!isstruct(st)) {
            error("Not a struct");
            return n;
        }
        p = addr_of(n);
    }
    for (m = ty_n[st]; m >= 0; m = mb_next[m])
        if (mb_name[m] == id)
            break;
    if (m < 0) {
        error2("No such member: ", name(id));
        return n;
    }
    mt = mb_type[m];
    if (mb_off[m])
        p = node(N_ADD, ptr_to(mt), p, mknum(mb_off[m], TI));
    else
        p = node(N_CAST, ptr_to(mt), p, 0);
    return node(N_DEREF, mt, p, 0);
}

int mkcall(int f)
{
    int ft, np, i, a, head, tail, fl, t;
    f = rvalue(f);
    if (!isptr(nd_type[f]) || ty_kind[ty_base[nd_type[f]]] != TY_FUNC) {
        error("Not a function");
        ft = 0;
    } else
        ft = ty_base[nd_type[f]];
    np = ft ? ty_x[ft] & 255 : 0;
    fl = ft ? ty_x[ft] & (FN_VARARG | FN_NOPROTO) : FN_NOPROTO;
    head = 0;
    tail = 0;
    i = 0;
    while (tok != ')' && tok != T_EOF) {
        a = rvalue(assign());
        t = nd_type[a];
        if (i < np)
            a = conv(a, pm_type[ty_n[ft] + i]);
        else if (!fl)
            error("Too many arguments");
        else if (isscalar(t))
            a = conv(a, promote(t));
        if (!isscalar(nd_type[a]))
            error("Bad argument");
        a = node(N_ARG, nd_type[a], a, 0);
        if (tail)
            nd_r[tail] = a;
        else
            head = a;
        tail = a;
        i++;
        if (tok != ',')
            break;
        next();
    }
    expect(')');
    if (i < np)
        error("Too few arguments");
    return node(N_CALL, ft ? ty_base[ft] : TI, f, head);
}

/* ---- expressions ------------------------------------------------- */

int primary(void)
{
    int n, id, l, g, t, len;
    if (tok == T_NUM) {
        n = mknum(tokval, toktype);
        next();
        return n;
    }
    if (tok == T_STR) {
        len = 0;
        while (tok == T_STR) {
            if (len + strn > STRSZ - 1)
                error("String too long");
            else {
                memcpy(strtmp + len, strbuf, strn);
                len = len + strn;
            }
            next();
        }
        l = newlabel();
        t = cursect;
        section(4);
        label(l);
        dstring(strtmp, len, len + 1);
        db_flush();
        section(t);
        n = node(N_STR, array_of(TC, len + 1), 0, 0);
        nd_sym[n] = l;
        return n;
    }
    if (tok == T_IDENT) {
        id = tokname;
        next();
        l = nm_lsym[id];
        if (l >= 0) {
            if (ls_sc[l] == SC_AUTO) {
                n = node(N_LVAR, ls_type[l], 0, 0);
                nd_val[n] = ls_val[l];
                return n;
            }
            if (ls_sc[l] == SC_LSTATIC) {
                n = node(N_SVAR, ls_type[l], 0, 0);
                nd_sym[n] = ls_val[l];
                return n;
            }
            if (ls_sc[l] == SC_ENUM)
                return mknum(ls_val[l], TI);
        } else {
            g = nm_gsym[id];
            if (g >= 0 && gs_sc[g] == SC_ENUM)
                return mknum(gs_val[g], TI);
            if (g >= 0 && gs_sc[g] != SC_TYPEDEF) {
                n = node(N_GVAR, gs_type[g], 0, 0);
                nd_sym[n] = g;
                return n;
            }
        }
        error2("Undeclared: ", name(id));
        return mknum(0, TI);
    }
    if (tok == '(') {
        next();
        n = expr();
        expect(')');
        return n;
    }
    error("Expression expected");
    if (tok != ';' && tok != '}' && tok != ')' && tok != T_EOF)
        next();
    return mknum(0, TI);
}

int postfix(int n)
{
    int i;
    for (;;) {
        if (tok == '[') {
            next();
            i = expr();
            expect(']');
            n = mkderef(mkbin(N_ADD, n, i));
        } else if (tok == '(') {
            next();
            n = mkcall(n);
        } else if (tok == '.') {
            next();
            n = mkmember(n, 0);
        } else if (tok == T_ARROW) {
            next();
            n = mkmember(n, 1);
        } else if (tok == T_INC || tok == T_DEC) {
            n = mkinc(n, tok == T_INC ? 1 : -1, 1);
            next();
        } else
            return n;
    }
}

int typename(void)
{
    int t, sc, id;
    t = declspec(&sc);
    t = declarator(t, &id);
    if (id >= 0)
        error("Unexpected name");
    return t;
}

int unary(void)
{
    int n, t;
    if (tok == T_INC || tok == T_DEC) {
        t = tok == T_INC ? 1 : -1;
        next();
        return mkinc(unary(), t, 0);
    }
    if (tok == '&') {
        next();
        n = unary();
        if (ty_kind[nd_type[n]] == TY_FUNC || nd_op[n] == N_STR)
            return rvalue(n);
        return addr_of(n);
    }
    if (tok == '*') {
        next();
        return mkderef(unary());
    }
    if (tok == '-' || tok == '+' || tok == '~') {
        t = tok;
        next();
        n = rvalue(unary());
        if (!isint(nd_type[n])) {
            error("Bad operand");
            return n;
        }
        n = conv(n, promote(nd_type[n]));
        if (t == '+')
            return n;
        return fold(node(t == '-' ? N_NEG : N_COM, nd_type[n], n, 0));
    }
    if (tok == '!') {
        next();
        n = rvalue(unary());
        if (!isscalar(nd_type[n]))
            error("Bad operand");
        return fold(node(N_NOT, TI, n, 0));
    }
    if (tok == K_SIZEOF) {
        next();
        if (tok == '(') {
            next();
            if (istypestart()) {
                t = typename();
                expect(')');
            } else {
                n = postfix(expr());
                expect(')');
                t = nd_type[n];
            }
        } else
            t = nd_type[unary()];
        if (tsize(t) < 0)
            error("Size unknown");
        return mknum(tsize(t), TUI);
    }
    if (tok == '(') {
        next();
        if (istypestart()) {
            t = typename();
            expect(')');
            n = rvalue(unary());
            return conv(n, t);
        }
        n = expr();
        expect(')');
        return postfix(n);
    }
    return postfix(primary());
}

int binprec(int t)
{
    if (t == T_LOR)
        return 1;
    if (t == T_LAND)
        return 2;
    if (t == '|')
        return 3;
    if (t == '^')
        return 4;
    if (t == '&')
        return 5;
    if (t == T_EQ || t == T_NE)
        return 6;
    if (t == '<' || t == '>' || t == T_LE || t == T_GE)
        return 7;
    if (t == T_SHL || t == T_SHR)
        return 8;
    if (t == '+' || t == '-')
        return 9;
    if (t == '*' || t == '/' || t == '%')
        return 10;
    return 0;
}

int binary(int minp)
{
    int l, r, t, p;
    l = unary();
    for (;;) {
        t = tok;
        p = binprec(t);
        if (p == 0 || p < minp)
            return l;
        next();
        r = binary(p + 1);
        l = mkbin(tokbinop(t), l, r);
    }
}

int cond(void)
{
    int c, a, b, ta, tb, t;
    c = binary(1);
    if (tok != '?')
        return c;
    next();
    c = rvalue(c);
    a = rvalue(expr());
    expect(':');
    b = rvalue(cond());
    ta = nd_type[a];
    tb = nd_type[b];
    if (isint(ta) && isint(tb))
        t = usual(ta, tb);
    else if (isptr(ta))
        t = ta;
    else if (isptr(tb))
        t = tb;
    else
        t = ta;
    if (ty_kind[t] != TY_VOID) {
        a = conv(a, t);
        b = conv(b, t);
    }
    if (nd_op[c] == N_NUM)
        return nd_val[c] ? a : b;
    return node(N_COND, t, c, node(N_COLON, t, a, b));
}

int assign(void)
{
    int l, op;
    l = cond();
    if (tok == '=') {
        next();
        return mkassign(l, assign());
    }
    if (tok == T_ASGN) {
        op = tokbinop(tokop);
        next();
        return mkasgop(op, l, assign());
    }
    return l;
}

int expr(void)
{
    int l, r;
    l = assign();
    while (tok == ',') {
        next();
        r = rvalue(assign());
        l = node(N_COMMA, nd_type[r], l, r);
    }
    return l;
}

long constexpr(void)
{
    int n;
    n = cond();
    if (nd_op[n] != N_NUM) {
        error("Constant expected");
        return 0;
    }
    return nd_val[n];
}

/* ---- declarations ------------------------------------------------ */

int structspec(void)
{
    int isun, tag, t, off, size, b, mt, id, last, m, sc;
    isun = tok == K_UNION;
    next();
    tag = -1;
    t = 0;
    if (tok == T_IDENT) {
        tag = tokname;
        t = nm_tag[tag];
        next();
    }
    if (tok != '{') {
        if (tag < 0)
            error("Struct name expected");
        else if (!t) {
            t = newtype(isun ? TY_UNION : TY_STRUCT, 0, -1, -1, tag);
            nm_tag[tag] = t;
        }
        return t;
    }
    next();
    if (!t || ty_size[t] >= 0) {
        t = newtype(isun ? TY_UNION : TY_STRUCT, 0, -1, -1, tag);
        if (tag >= 0)
            nm_tag[tag] = t;
    }
    off = 0;
    size = 0;
    last = -1;
    while (tok != '}' && tok != T_EOF) {
        b = declspec(&sc);
        for (;;) {
            mt = declarator(b, &id);
            if (tsize(mt) < 0 || ty_kind[mt] == TY_FUNC)
                error("Bad member");
            if (nmemb >= MAXMEMB)
                fatal("Too many members");
            m = nmemb++;
            mb_name[m] = id;
            mb_type[m] = mt;
            mb_off[m] = isun ? 0 : off;
            mb_next[m] = -1;
            if (last >= 0)
                mb_next[last] = m;
            else
                ty_n[t] = m;
            last = m;
            if (isun) {
                if (tsize(mt) > size)
                    size = tsize(mt);
            } else
                off = off + tsize(mt);
            if (tok != ',')
                break;
            next();
        }
        expect(';');
    }
    expect('}');
    ty_size[t] = isun ? size : off;
    return t;
}

int enumspec(void)
{
    int id;
    long v;
    next();
    if (tok == T_IDENT)
        next();
    if (tok != '{')
        return TI;
    next();
    v = 0;
    while (tok == T_IDENT) {
        id = tokname;
        next();
        if (tok == '=') {
            next();
            v = constexpr();
        }
        if (infunc)
            addlocal(id, TI, SC_ENUM, v);
        else
            gs_val[addglobal(id, TI, SC_ENUM)] = v;
        v++;
        if (tok != ',')
            break;
        next();
    }
    expect('}');
    return TI;
}

int declspec(int *psc)
{
    int sc, uns, sgn, lng, chr, base, any;
    sc = 0;
    uns = 0;
    sgn = 0;
    lng = 0;
    chr = 0;
    base = 0;
    any = 0;
    for (;;) {
        if (tok == K_TYPEDEF || tok == K_EXTERN || tok == K_STATIC || tok == K_AUTO ||
            tok == K_REGISTER) {
            if (sc)
                error("Two storage classes");
            sc = tok;
        } else if (tok == K_CONST || tok == K_VOLATILE)
            ;
        else if (tok == K_UNSIGNED)
            uns = 1;
        else if (tok == K_SIGNED)
            sgn = 1;
        else if (tok == K_LONG)
            lng = 1;
        else if (tok == K_CHAR)
            chr = 1;
        else if (tok == K_SHORT || tok == K_INT)
            any = 1;
        else if (tok == K_VOID)
            base = TV;
        else if (tok == K_STRUCT || tok == K_UNION) {
            base = structspec();
            continue;
        } else if (tok == K_ENUM) {
            base = enumspec();
            continue;
        } else if (tok == T_IDENT && !base && !uns && !sgn && !lng && !chr && !any &&
                   istypedef(tokname))
            base = typedeftype(tokname);
        else
            break;
        next();
    }
    if (!base) {
        if (chr)
            base = uns ? TUC : TC;
        else if (lng)
            base = uns ? TUL : TL;
        else
            base = uns ? TUI : TI;
    }
    *psc = sc;
    return base;
}

int funcsuffix(int ret)
{
    int np, fl, b, t, id, sc, i, start;
    int ptype[MAXFP];
    int pname[MAXFP];
    np = 0;
    fl = 0;
    if (tok == ')')
        fl = FN_NOPROTO;
    while (tok != ')' && tok != T_EOF) {
        if (tok == T_ELLIP) {
            next();
            fl = FN_VARARG;
            break;
        }
        b = declspec(&sc);
        t = declarator(b, &id);
        if (np == 0 && t == TV && tok == ')')
            break;
        if (ty_kind[t] == TY_ARRAY)
            t = ptr_to(ty_base[t]);
        else if (ty_kind[t] == TY_FUNC)
            t = ptr_to(t);
        if (!isscalar(t))
            error("Bad parameter");
        if (np < MAXFP) {
            ptype[np] = t;
            pname[np] = id;
            np++;
        }
        if (tok != ',')
            break;
        next();
    }
    expect(')');
    if (nparm + np > MAXPARM)
        fatal("Too many parameters");
    start = nparm;
    for (i = 0; i < np; i++) {
        pm_type[nparm] = ptype[i];
        pm_name[nparm] = pname[i];
        nparm++;
    }
    if (isstruct(ret) || ty_kind[ret] == TY_ARRAY)
        error("Bad return type");
    return newtype(TY_FUNC, ret, 0, start, np | fl);
}

int suffixes(int t)
{
    long n;
    if (tok == '[') {
        next();
        n = -1;
        if (tok != ']')
            n = constexpr();
        expect(']');
        t = suffixes(t);
        return array_of(t, n);
    }
    if (tok == '(') {
        next();
        return funcsuffix(t);
    }
    return t;
}

int subst(int t, int hole, int r)
{
    int k;
    if (t == hole)
        return r;
    k = ty_kind[t];
    if (k == TY_PTR)
        return ptr_to(subst(ty_base[t], hole, r));
    if (k == TY_ARRAY)
        return array_of(subst(ty_base[t], hole, r), ty_n[t]);
    if (k == TY_FUNC)
        return newtype(TY_FUNC, subst(ty_base[t], hole, r), 0, ty_n[t], ty_x[t]);
    return t;
}

int declarator(int t, int *pname)
{
    int hole, inner;
    *pname = -1;
    while (tok == '*') {
        next();
        while (tok == K_CONST || tok == K_VOLATILE)
            next();
        t = ptr_to(t);
    }
    if (tok == '(') {
        next();
        if (tok == '*' || tok == '(' || (tok == T_IDENT && !istypedef(tokname))) {
            if (nhole >= 8)
                fatal("Declarator too complex");
            if (!holes[nhole])
                holes[nhole] = newtype(TY_HOLE, 0, 0, 0, 0);
            hole = holes[nhole++];
            inner = declarator(hole, pname);
            nhole--;
            expect(')');
            t = suffixes(t);
            return subst(inner, hole, t);
        }
        return funcsuffix(t);
    }
    if (tok == T_IDENT) {
        *pname = tokname;
        next();
    }
    return suffixes(t);
}

/* ---- initializers ------------------------------------------------ */

/* An address constant: &global, a string, a function, +- a number.
   Sets oms (the symbol) and omv (the offset); 0 if n isn't one. */
int addrconst(int n)
{
    int op, l;
    op = nd_op[n];
    if (op == N_CAST)
        return addrconst(nd_l[n]);
    if (op == N_ADDR) {
        l = nd_l[n];
        omv = 0;
        if (nd_op[l] == N_GVAR) {
            oms = nd_sym[l];
            return 1;
        }
        if (nd_op[l] == N_SVAR || nd_op[l] == N_STR) {
            oms = -nd_sym[l];
            return 1;
        }
        return 0;
    }
    if ((op == N_ADD || op == N_SUB) && nd_op[nd_r[n]] == N_NUM && addrconst(nd_l[n])) {
        if (op == N_ADD)
            omv = omv + nd_val[nd_r[n]];
        else
            omv = omv - nd_val[nd_r[n]];
        return 1;
    }
    return 0;
}

void dscalar(int t)
{
    int n, br;
    long v;
    br = tok == '{';
    if (br)
        next();
    nnode = 0;
    n = conv(rvalue(assign()), t);
    if (br)
        expect('}');
    if (nd_op[n] == N_NUM) {
        v = nd_val[n];
        if (ischar(t))
            db(v);
        else if (islong(t)) {
            db(v >> 24);
            db(v >> 16);
            db(v >> 8);
            db(v);
        } else {
            db(v >> 8);
            db(v);
        }
        return;
    }
    if (tsize(t) == 2 && addrconst(n)) {
        db_flush();
        ot(" fdb ");
        osym(oms);
        ooff(omv);
        oc('\n');
        return;
    }
    error("Constant expected");
}

/* Data for an initializer of type t.  Returns the number of elements for
   an array (its size may not be known yet). */
int init_data(int t)
{
    int k, et, i, n, m, len;
    k = ty_kind[t];
    if (k == TY_ARRAY) {
        et = ty_base[t];
        n = ty_n[t];
        if (ischar(et) && tok == T_STR) {
            len = 0;
            while (tok == T_STR) {
                if (len + strn <= STRSZ - 1) {
                    memcpy(strtmp + len, strbuf, strn);
                    len = len + strn;
                }
                next();
            }
            if (n < 0)
                n = len + 1;
            dstring(strtmp, len < n ? len + 1 : len, n);
            return n;
        }
        expect('{');
        i = 0;
        while (tok != '}' && tok != T_EOF) {
            if (n >= 0 && i >= n) {
                error("Too many initializers");
                break;
            }
            init_data(et);
            i++;
            if (tok != ',')
                break;
            next();
        }
        expect('}');
        if (n < 0)
            n = i;
        dzero((n - i) * tsize(et));
        return n;
    }
    if (k == TY_STRUCT || k == TY_UNION) {
        expect('{');
        m = ty_n[t];
        i = 0;
        while (tok != '}' && tok != T_EOF && m >= 0) {
            init_data(mb_type[m]);
            i = i + tsize(mb_type[m]);
            m = k == TY_UNION ? -1 : mb_next[m];
            if (tok != ',')
                break;
            next();
        }
        expect('}');
        dzero(tsize(t) - i);
        return 1;
    }
    if (!isscalar(t)) {
        error("Can't initialize this");
        return 1;
    }
    dscalar(t);
    return 1;
}

/* Data or bss for a global or static: label l (>= 0: symbol, < 0: Ln).
   Returns the type, with an array's size filled in. */
int define_data(int s, int t)
{
    int n, sect;
    sect = cursect;
    if (tok == '=') {
        next();
        section(2);
        osym(s);
        oc('\n');
        n = init_data(t);
        db_flush();
        if (ty_kind[t] == TY_ARRAY && ty_n[t] < 0)
            t = array_of(ty_base[t], n);
    } else {
        if (tsize(t) < 0) {
            error("Size unknown");
            return t;
        }
        section(3);
        osym(s);
        ot(" rmb ");
        onum(tsize(t));
        oc('\n');
    }
    if (infunc)
        section(sect);
    return t;
}

/* ---- statements -------------------------------------------------- */

void gen_void(int n)
{
    if (nd_op[n] == N_POSTINC)
        nd_op[n] = N_PREINC;
    gen(n);
}

void local_decl(void)
{
    int base, sc, t, id, l, n;
    base = declspec(&sc);
    while (tok != ';' && tok != T_EOF) {
        nnode = 0;
        t = declarator(base, &id);
        if (id < 0) {
            error("Name expected");
            break;
        }
        if (sc == K_TYPEDEF)
            addlocal(id, t, SC_TYPEDEF, 0);
        else if (sc == K_EXTERN || ty_kind[t] == TY_FUNC)
            addglobal(id, t, SC_EXTERN);
        else if (sc == K_STATIC) {
            l = newlabel();
            t = define_data(-l, t);
            addlocal(id, t, SC_LSTATIC, l);
        } else {
            if (tsize(t) < 0)
                error("Size unknown");
            else
                curoff = curoff - tsize(t);
            if (-curoff > maxoff)
                maxoff = -curoff;
            addlocal(id, t, SC_AUTO, curoff);
            if (tok == '=') {
                next();
                if (!isscalar(t))
                    error("Can't initialize a local array or struct");
                n = node(N_LVAR, t, 0, 0);
                nd_val[n] = curoff;
                gen(mkassign(n, assign()));
            }
        }
        if (tok != ',')
            break;
        next();
    }
    expect(';');
}

void compound(void)
{
    int mark, off;
    expect('{');
    mark = nlsym;
    off = curoff;
    while (tok != '}' && tok != T_EOF) {
        if (isdeclstart())
            local_decl();
        else
            statement();
    }
    expect('}');
    popscope(mark);
    curoff = off;
}

void st_switch(void)
{
    int n, t, slot, ltest, lbrk, ofirst, odef, oinsw, off, i;
    next();
    expect('(');
    n = rvalue(expr());
    expect(')');
    t = nd_type[n];
    if (!isint(t) || islong(t))
        error("Switch needs a char or int");
    else
        n = conv(n, promote(t));
    gen(n);
    off = curoff;
    curoff = curoff - 2;
    if (-curoff > maxoff)
        maxoff = -curoff;
    slot = curoff;
    oc(' ');
    ot("std ");
    onum(slot);
    ot(",u\n");
    ltest = newlabel();
    lbrk = newlabel();
    jmp(ltest);
    ofirst = sw_first;
    odef = sw_def;
    oinsw = insw;
    sw_first = ncase;
    sw_def = 0;
    insw = 1;
    brk[nbrk++] = lbrk;
    statement();
    nbrk--;
    jmp(lbrk);
    label(ltest);
    oc(' ');
    ot("ldd ");
    onum(slot);
    ot(",u\n");
    for (i = sw_first; i < ncase; i++) {
        opi("cmpd", case_val[i] & 0xFFFF);
        opl("lbeq", case_lab[i]);
    }
    jmp(sw_def ? sw_def : lbrk);
    label(lbrk);
    ncase = sw_first;
    sw_first = ofirst;
    sw_def = odef;
    insw = oinsw;
    curoff = off;
}

/* a goto label's number; ngoto_at is its place in gl_ */
int ngoto_at;

int golabel(int id)
{
    int i;
    for (i = 0; i < ngoto; i++)
        if (gl_name[i] == id) {
            ngoto_at = i;
            return gl_lab[i];
        }
    if (ngoto >= MAXGOTO)
        fatal("Too many labels");
    gl_name[ngoto] = id;
    gl_lab[ngoto] = newlabel();
    gl_def[ngoto] = 0;
    ngoto_at = ngoto++;
    return gl_lab[ngoto_at];
}

void statement(void)
{
    int n, l1, l2, l3, l4;
    long v;
    nnode = 0;
    if (tok == '{') {
        compound();
        return;
    }
    if (tok == ';') {
        next();
        return;
    }
    if (tok == K_IF) {
        next();
        expect('(');
        n = expr();
        expect(')');
        l1 = newlabel();
        gen_cond(n, l1, 0);
        statement();
        if (tok == K_ELSE) {
            next();
            l2 = newlabel();
            jmp(l2);
            label(l1);
            statement();
            label(l2);
        } else
            label(l1);
        return;
    }
    if (tok == K_WHILE) {
        next();
        l1 = newlabel();
        l2 = newlabel();
        label(l1);
        expect('(');
        n = expr();
        expect(')');
        gen_cond(n, l2, 0);
        brk[nbrk++] = l2;
        cont[ncont++] = l1;
        statement();
        nbrk--;
        ncont--;
        jmp(l1);
        label(l2);
        return;
    }
    if (tok == K_DO) {
        next();
        l1 = newlabel();
        l2 = newlabel();
        l3 = newlabel();
        label(l1);
        brk[nbrk++] = l3;
        cont[ncont++] = l2;
        statement();
        nbrk--;
        ncont--;
        expect(K_WHILE);
        expect('(');
        nnode = 0;
        n = expr();
        expect(')');
        expect(';');
        label(l2);
        gen_cond(n, l1, 1);
        label(l3);
        return;
    }
    if (tok == K_FOR) {
        next();
        expect('(');
        if (tok != ';')
            gen_void(expr());
        expect(';');
        l1 = newlabel();
        l4 = newlabel();
        label(l1);
        nnode = 0;
        if (tok != ';')
            gen_cond(expr(), l4, 0);
        expect(';');
        l2 = l1;
        if (tok != ')') {
            l3 = newlabel();
            l2 = newlabel();
            jmp(l3);
            label(l2);
            nnode = 0;
            gen_void(expr());
            jmp(l1);
            label(l3);
        }
        expect(')');
        brk[nbrk++] = l4;
        cont[ncont++] = l2;
        statement();
        nbrk--;
        ncont--;
        jmp(l2);
        label(l4);
        return;
    }
    if (tok == K_SWITCH) {
        st_switch();
        return;
    }
    if (tok == K_CASE) {
        next();
        v = constexpr();
        expect(':');
        if (!insw)
            error("Case outside a switch");
        else if (ncase >= MAXCASE)
            fatal("Too many cases");
        else {
            l1 = newlabel();
            label(l1);
            case_val[ncase] = v;
            case_lab[ncase] = l1;
            ncase++;
        }
        statement();
        return;
    }
    if (tok == K_DEFAULT) {
        next();
        expect(':');
        if (!insw)
            error("Default outside a switch");
        else {
            sw_def = newlabel();
            label(sw_def);
        }
        statement();
        return;
    }
    if (tok == K_BREAK || tok == K_CONTINUE) {
        if (tok == K_BREAK) {
            if (nbrk)
                jmp(brk[nbrk - 1]);
            else
                error("Break outside a loop");
        } else {
            if (ncont)
                jmp(cont[ncont - 1]);
            else
                error("Continue outside a loop");
        }
        next();
        expect(';');
        return;
    }
    if (tok == K_RETURN) {
        next();
        if (tok != ';') {
            n = rvalue(expr());
            if (ty_kind[rettype] == TY_VOID)
                error("Return with a value in a void function");
            else
                gen(conv(n, rettype));
        }
        expect(';');
        jmp(retlabel);
        return;
    }
    if (tok == K_GOTO) {
        next();
        if (tok != T_IDENT)
            error("Label expected");
        else {
            jmp(golabel(tokname));
            next();
        }
        expect(';');
        return;
    }
    if (tok == T_IDENT) {
        skipsp();
        if (ch == ':') {
            l1 = golabel(tokname);
            if (gl_def[ngoto_at])
                error2("Label used twice: ", name(tokname));
            gl_def[ngoto_at] = 1;
            label(l1);
            next();
            next();
            statement();
            return;
        }
    }
    gen_void(expr());
    expect(';');
}

void funcdef(int g, int ft)
{
    int i, id, t, off, fl;
    if (gs_fl[g] & F_DEF)
        error2("Redefined: ", name(gs_name[g]));
    gs_fl[g] = gs_fl[g] | F_DEF;
    gs_type[g] = ft;
    nfuncs++;
    section(1);
    osym(g);
    oc('\n');
    op1("pshs", "u");
    op1("tfr", "s,u");
    fl = newlabel();
    ot(" leas -F");
    onum(fl);
    ot(",s\n");
    retlabel = newlabel();
    ngoto = 0;
    rettype = ty_base[ft];
    infunc = 1;
    curoff = 0;
    maxoff = 0;
    off = 4;
    for (i = 0; i < (ty_x[ft] & 255); i++) {
        t = pm_type[ty_n[ft] + i];
        id = pm_name[ty_n[ft] + i];
        if (id < 0)
            error("Parameter name missing");
        else
            addlocal(id, t, SC_AUTO, ischar(t) ? off + 1 : off);
        off = off + (islong(t) ? 4 : 2);
    }
    compound();
    for (i = 0; i < ngoto; i++)
        if (!gl_def[i])
            error2("No such label: ", name(gl_name[i]));
    label(retlabel);
    op1("tfr", "u,s");
    op1("puls", "u,pc");
    ot("F");
    onum(fl);
    ot(" equ ");
    onum(maxoff);
    oc('\n');
    popscope(0);
    infunc = 0;
}

void global_decl(void)
{
    int base, sc, t, id, g, gsc;
    base = declspec(&sc);
    while (tok != ';' && tok != T_EOF) {
        nnode = 0;
        t = declarator(base, &id);
        if (id < 0) {
            error("Name expected");
            break;
        }
        if (sc == K_TYPEDEF) {
            addglobal(id, t, SC_TYPEDEF);
        } else if (ty_kind[t] == TY_FUNC) {
            g = addglobal(id, t, sc == K_STATIC ? SC_STATIC : SC_GLOBAL);
            if (tok == '{') {
                funcdef(g, t);
                return;
            }
        } else {
            gsc = sc == K_STATIC ? SC_STATIC : sc == K_EXTERN ? SC_EXTERN : SC_GLOBAL;
            g = addglobal(id, t, gsc);
            if (gsc != SC_EXTERN) {
                if (gs_fl[g] & F_DEF)
                    error2("Redefined: ", name(id));
                gs_fl[g] = gs_fl[g] | F_DEF;
                gs_type[g] = define_data(g, gs_type[g]);
            } else if (tok == '=')
                error("Extern with an initializer");
        }
        if (tok != ',')
            break;
        next();
    }
    expect(';');
}

/* ---- code generation --------------------------------------------- */

/* A 16-bit value that can be an instruction's operand as it is. */
int is_simple(int n)
{
    int op, t, l;
    op = nd_op[n];
    t = nd_type[n];
    if (op == N_NUM)
        return !islong(t);
    if ((op == N_LVAR || op == N_GVAR || op == N_SVAR) && tsize(t) == 2 && isscalar(t))
        return 1;
    if (op == N_ADDR) {
        l = nd_l[n];
        return nd_op[l] == N_GVAR || nd_op[l] == N_SVAR || nd_op[l] == N_STR;
    }
    return 0;
}

void set_simple(int n)
{
    int op, l;
    op = nd_op[n];
    omv = 0;
    if (op == N_NUM) {
        om = M_IMM;
        omv = nd_val[n];
    } else if (op == N_LVAR) {
        om = M_LOC;
        omv = nd_val[n];
    } else if (op == N_GVAR) {
        om = M_GLB;
        oms = nd_sym[n];
    } else if (op == N_SVAR) {
        om = M_GLB;
        oms = -nd_sym[n];
    } else {
        l = nd_l[n];
        om = M_ISYM;
        oms = nd_op[l] == N_GVAR ? nd_sym[l] : -nd_sym[l];
    }
}

/* the pointer under constant offsets and pointer casts; the offset in *pk */
int strip(int p, long *pk)
{
    long k;
    k = 0;
    for (;;) {
        if ((nd_op[p] == N_ADD || nd_op[p] == N_SUB) && nd_op[nd_r[p]] == N_NUM) {
            if (nd_op[p] == N_ADD)
                k = k + nd_val[nd_r[p]];
            else
                k = k - nd_val[nd_r[p]];
            p = nd_l[p];
        } else if (nd_op[p] == N_CAST && tsize(nd_type[nd_l[p]]) == 2 && !ischar(nd_type[p]))
            p = nd_l[p];
        else
            break;
    }
    *pk = k;
    return p;
}

/* n is an lvalue whose address needs no code, or only a load of a
   simple pointer into X or Y (which keeps D) */
int lv_easy(int n)
{
    int op, p;
    long k;
    op = nd_op[n];
    if (op == N_LVAR || op == N_GVAR || op == N_SVAR || op == N_STR)
        return 1;
    if (op != N_DEREF)
        return 0;
    p = strip(nd_l[n], &k);
    if (nd_op[p] == N_ADDR)
        return lv_easy(nd_l[p]) && nd_op[nd_l[p]] != N_DEREF;
    if (nd_op[p] == N_NUM)
        return 1;
    return is_simple(p);
}

/* om for the easy lvalue n, with the pointer loaded into reg */
void lv_setup(int n, int reg)
{
    int op, p;
    long k;
    op = nd_op[n];
    omv = 0;
    if (op == N_LVAR) {
        om = M_LOC;
        omv = nd_val[n];
    } else if (op == N_GVAR) {
        om = M_GLB;
        oms = nd_sym[n];
    } else if (op == N_SVAR || op == N_STR) {
        om = M_GLB;
        oms = -nd_sym[n];
    } else {
        p = strip(nd_l[n], &k);
        if (nd_op[p] == N_ADDR) {
            lv_setup(nd_l[p], reg);
            omv = omv + k;
        } else if (nd_op[p] == N_NUM) {
            om = M_ABS;
            omv = nd_val[p] + k;
        } else {
            set_simple(p);
            opm(reg == 'x' ? "ldx" : "ldy", 0);
            om = reg == 'x' ? M_IX : M_IY;
            omv = k;
        }
    }
}

/* om for any lvalue: the address computed into reg if it must be */
void lv_any(int n, int reg)
{
    if (lv_easy(n)) {
        lv_setup(n, reg);
        return;
    }
    gen_addr(n);
    op1("tfr", reg == 'x' ? "d,x" : "d,y");
    om = reg == 'x' ? M_IX : M_IY;
    omv = 0;
}

void load(int t)
{
    if (ischar(t)) {
        opm("ldb", 0);
        op0(ty_kind[t] == TY_CHAR ? "sex" : "clra");
    } else if (islong(t)) {
        opm("ldd", 2);
        opm("ldx", 0);
    } else
        opm("ldd", 0);
}

void store(int t)
{
    if (ischar(t))
        opm("stb", 0);
    else if (islong(t)) {
        opm("std", 2);
        opm("stx", 0);
    } else
        opm("std", 0);
}

void gen_addr(int n)
{
    int op;
    op = nd_op[n];
    if (op == N_LVAR) {
        oc(' ');
        ot("leax ");
        onum(nd_val[n]);
        ot(",u\n");
        op1("tfr", "x,d");
    } else if (op == N_GVAR || op == N_SVAR || op == N_STR) {
        om = M_ISYM;
        omv = 0;
        oms = op == N_GVAR ? nd_sym[n] : -nd_sym[n];
        opm("ldd", 0);
    } else if (op == N_DEREF)
        gen(nd_l[n]);
    else
        error("Not an lvalue");
}

void convert(int f, int t)
{
    if (ty_kind[t] == TY_VOID)
        return;
    if (islong(t)) {
        if (!islong(f)) {
            if (isuns(f))
                op1("ldx", "#0");
            else
                call(H_SEXT);
        }
    } else if (ischar(t)) {
        if (ty_kind[f] != ty_kind[t])
            op0(ty_kind[t] == TY_CHAR ? "sex" : "clra");
    }
}

void shift_left(long k)
{
    if (k >= 16) {
        op0("clra");
        op0("clrb");
        return;
    }
    if (k >= 8) {
        op1("tfr", "b,a");
        op0("clrb");
        k = k - 8;
    }
    while (k-- > 0) {
        op0("aslb");
        op0("rola");
    }
}

void shift_right(long k, int uns)
{
    if (k >= 16) {
        if (uns) {
            op0("clra");
            op0("clrb");
            return;
        }
        k = 15;
    }
    if (k >= 8) {
        op1("tfr", "a,b");
        op0(uns ? "clra" : "sex");
        k = k - 8;
    }
    while (k-- > 0) {
        op0(uns ? "lsra" : "asra");
        op0("rorb");
    }
}

int helper(int op, int uns)
{
    if (op == N_MUL)
        return H_MUL;
    if (op == N_DIV)
        return uns ? H_DIVU : H_DIVS;
    if (op == N_MOD)
        return uns ? H_MODU : H_MODS;
    if (op == N_SHL)
        return H_SHL;
    return uns ? H_SHRU : H_SHRS;
}

int lhelper(int op, int uns)
{
    if (op == N_ADD)
        return H_LADD;
    if (op == N_SUB)
        return H_LSUB;
    if (op == N_MUL)
        return H_LMUL;
    if (op == N_DIV)
        return uns ? H_LDIVU : H_LDIVS;
    if (op == N_MOD)
        return uns ? H_LMODU : H_LMODS;
    if (op == N_AND)
        return H_LAND;
    if (op == N_OR)
        return H_LOR;
    if (op == N_XOR)
        return H_LXOR;
    if (op == N_SHL)
        return H_LSHL;
    return uns ? H_LSHRU : H_LSHRS;
}

int isinline(int op)
{
    return op == N_ADD || op == N_SUB || op == N_AND || op == N_OR || op == N_XOR;
}

/* D op= the operand in om (add, sub, and, or, xor) */
void arith(int op)
{
    char *a, *b;
    if (op == N_ADD) {
        opm("addd", 0);
        return;
    }
    if (op == N_SUB) {
        opm("subd", 0);
        return;
    }
    if (op == N_AND) {
        a = "anda";
        b = "andb";
    } else if (op == N_OR) {
        a = "ora";
        b = "orb";
    } else {
        a = "eora";
        b = "eorb";
    }
    opb(a, 0);
    opb(b, 1);
}

/* a simple operand that arith can use for op */
int arith_ok(int n, int op)
{
    if (!is_simple(n))
        return 0;
    if (op == N_ADD || op == N_SUB)
        return 1;
    return nd_op[n] != N_ADDR;
}

void gen_bin(int n)
{
    int op, l, r, uns, k;
    long v;
    op = nd_op[n];
    l = nd_l[n];
    r = nd_r[n];
    uns = isuns(nd_type[n]);
    if (nd_op[r] == N_NUM) {
        v = nd_val[r] & 0xFFFF;
        k = log2of(v);
        if (op == N_MUL && k >= 0) {
            gen(l);
            shift_left(k);
            return;
        }
        if (op == N_DIV && uns && k >= 0) {
            gen(l);
            shift_right(k, 1);
            return;
        }
        if (op == N_MOD && uns && k >= 0) {
            gen(l);
            om = M_IMM;
            omv = v - 1;
            arith(N_AND);
            return;
        }
        if (op == N_SHL) {
            gen(l);
            shift_left(v);
            return;
        }
        if (op == N_SHR) {
            gen(l);
            shift_right(v, uns);
            return;
        }
        if ((op == N_ADD || op == N_SUB || op == N_OR || op == N_XOR) && v == 0) {
            gen(l);
            return;
        }
    }
    if (isinline(op)) {
        if (arith_ok(r, op)) {
            gen(l);
            set_simple(r);
            arith(op);
            return;
        }
        if (op != N_SUB && arith_ok(l, op)) {
            gen(r);
            set_simple(l);
            arith(op);
            return;
        }
        gen(r);
        op1("pshs", "d");
        gen(l);
        om = M_STK;
        arith(op);
        return;
    }
    if (is_simple(r)) {
        gen(l);
        op1("tfr", "d,x");
        set_simple(r);
        opm("ldd", 0);
    } else {
        gen(r);
        op1("pshs", "d");
        gen(l);
        op1("tfr", "d,x");
        op1("puls", "d");
    }
    call(helper(op, uns));
}

void pushlong(void)
{
    op1("pshs", "d");
    op1("pshs", "x");
}

void gen_lbin(int n)
{
    int op;
    op = nd_op[n];
    gen(nd_l[n]);
    pushlong();
    gen(nd_r[n]);
    call(lhelper(op, isuns(nd_type[n])));
    op1("leas", "4,s");
}

int invert(int op)
{
    if (op == N_EQ)
        return N_NE;
    if (op == N_NE)
        return N_EQ;
    if (op == N_LT)
        return N_GE;
    if (op == N_GE)
        return N_LT;
    if (op == N_GT)
        return N_LE;
    return N_GT;
}

int swapped(int op)
{
    if (op == N_LT)
        return N_GT;
    if (op == N_GT)
        return N_LT;
    if (op == N_LE)
        return N_GE;
    if (op == N_GE)
        return N_LE;
    return op;
}

void branch(int op, int uns, int jt, int lab)
{
    char *s;
    if (!jt)
        op = invert(op);
    if (op == N_EQ)
        s = "lbeq";
    else if (op == N_NE)
        s = "lbne";
    else if (op == N_LT)
        s = uns ? "lblo" : "lblt";
    else if (op == N_GT)
        s = uns ? "lbhi" : "lbgt";
    else if (op == N_LE)
        s = uns ? "lbls" : "lble";
    else
        s = uns ? "lbhs" : "lbge";
    opl(s, lab);
}

void gen_cond(int n, int lab, int jt)
{
    int op, l, r, t, uns, l2;
    op = nd_op[n];
    l = nd_l[n];
    r = nd_r[n];
    if (op == N_NUM) {
        if ((nd_val[n] != 0) == jt)
            jmp(lab);
        return;
    }
    if (op == N_NOT) {
        gen_cond(l, lab, !jt);
        return;
    }
    if (op == N_LAND || op == N_LOR) {
        if ((op == N_LAND) == jt) {
            l2 = newlabel();
            gen_cond(l, l2, !jt);
            gen_cond(r, lab, jt);
            label(l2);
        } else {
            gen_cond(l, lab, jt);
            gen_cond(r, lab, jt);
        }
        return;
    }
    if (op >= N_EQ && op <= N_GE) {
        t = nd_type[l];
        uns = isuns(t);
        if (islong(t)) {
            gen(l);
            pushlong();
            gen(r);
            call(uns ? H_LCMPU : H_LCMP);
            op1("leas", "4,s");
            branch(op, 0, jt, lab);
            return;
        }
        if (nd_op[r] == N_NUM && nd_val[r] == 0 && (op == N_EQ || op == N_NE)) {
            gen(l);
            opi("subd", 0);
        } else if (is_simple(r)) {
            gen(l);
            set_simple(r);
            opm("cmpd", 0);
        } else if (is_simple(l)) {
            gen(r);
            set_simple(l);
            opm("cmpd", 0);
            op = swapped(op);
        } else {
            gen(r);
            op1("pshs", "d");
            gen(l);
            op1("cmpd", ",s++");
        }
        branch(op, uns, jt, lab);
        return;
    }
    gen(n);
    if (islong(nd_type[n])) {
        op1("pshs", "x,d");
        op1("ora", "1,s");
        op1("ora", "2,s");
        op1("ora", "3,s");
        op1("leas", "4,s");
    } else
        opi("subd", 0);
    opl(jt ? "lbne" : "lbeq", lab);
}

/* struct = struct: Y from, X to, a byte at a time */
void gen_scopy(int n)
{
    int sz, l1;
    sz = tsize(nd_type[n]);
    gen_addr(nd_r[n]);
    op1("pshs", "d");
    gen_addr(nd_l[n]);
    op1("tfr", "d,x");
    op1("puls", "y");
    l1 = newlabel();
    if (sz < 256) {
        opi("ldb", sz);
        label(l1);
        op1("lda", ",y+");
        op1("sta", ",x+");
        op0("decb");
    } else {
        opi("ldd", sz);
        op1("pshs", "d");
        label(l1);
        op1("lda", ",y+");
        op1("sta", ",x+");
        op1("ldd", ",s");
        opi("subd", 1);
        op1("std", ",s");
    }
    opl("bne", l1);
    if (sz >= 256)
        op1("leas", "2,s");
}

void gen_assign(int n)
{
    int l, t;
    l = nd_l[n];
    t = nd_type[l];
    if (lv_easy(l)) {
        gen(nd_r[n]);
        lv_setup(l, islong(t) ? 'y' : 'x');
    } else {
        gen_addr(l);
        op1("pshs", "d");
        gen(nd_r[n]);
        op1("puls", islong(t) ? "y" : "x");
        om = islong(t) ? M_IY : M_IX;
        omv = 0;
    }
    store(t);
}

void gen_asgop(int n)
{
    int l, r, t, bop, uns, easy;
    l = nd_l[n];
    r = nd_r[n];
    t = nd_type[n];
    bop = nd_val[n];
    uns = isuns(promote(t));
    easy = lv_easy(l);
    if (islong(t)) {
        if (easy)
            lv_setup(l, 'x');
        else {
            gen_addr(l);
            op1("pshs", "d");
            op1("ldy", ",s");
            om = M_IY;
            omv = 0;
        }
        load(t);
        pushlong();
        gen(r);
        call(lhelper(bop, uns));
        op1("leas", "4,s");
        if (easy)
            lv_setup(l, 'y');
        else {
            op1("puls", "y");
            om = M_IY;
            omv = 0;
        }
        store(t);
        return;
    }
    if (easy) {
        if (isinline(bop) && arith_ok(r, bop)) {
            lv_setup(l, 'x');
            save_om();
            load(t);
            set_simple(r);
            arith(bop);
            restore_om();
        } else {
            gen(r);
            op1("pshs", "d");
            lv_setup(l, 'x');
            save_om();
            load(t);
            if (isinline(bop)) {
                om = M_STK;
                arith(bop);
                restore_om();
            } else {
                op1("tfr", "d,x");
                op1("puls", "d");
                call(helper(bop, uns));
                lv_setup(l, 'x');
            }
        }
    } else {
        gen_addr(l);
        op1("pshs", "d");
        gen(r);
        op1("pshs", "d");
        op1("ldx", "2,s");
        om = M_IX;
        omv = 0;
        load(t);
        if (isinline(bop)) {
            om = M_STK;
            arith(bop);
        } else {
            op1("tfr", "d,x");
            op1("puls", "d");
            call(helper(bop, uns));
        }
        op1("puls", "x");
        om = M_IX;
        omv = 0;
    }
    store(t);
    if (ischar(t))
        convert(TI, t);
}

void gen_inc(int n)
{
    int l, t, post;
    long step;
    l = nd_l[n];
    t = nd_type[n];
    step = nd_val[n];
    post = nd_op[n] == N_POSTINC;
    if (islong(t)) {
        lv_any(l, 'y');
        save_om();
        load(t);
        pushlong();
        opi("ldx", step < 0 ? -1 : 0);
        opi("ldd", step & 0xFFFF);
        call(H_LADD);
        op1("leas", "4,s");
        restore_om();
        store(t);
        if (post) {
            pushlong();
            opi("ldx", step < 0 ? -1 : 0);
            opi("ldd", step & 0xFFFF);
            call(H_LSUB);
            op1("leas", "4,s");
        }
        return;
    }
    lv_any(l, 'x');
    if (ischar(t)) {
        opm("ldb", 0);
        opi("addb", step & 255);
        opm("stb", 0);
        if (post)
            opi("subb", step & 255);
        op0(ty_kind[t] == TY_CHAR ? "sex" : "clra");
        return;
    }
    opm("ldd", 0);
    opi("addd", step & 0xFFFF);
    opm("std", 0);
    if (post)
        opi("subd", step & 0xFFFF);
}

int push_args(int a)
{
    int b, e;
    if (!a)
        return 0;
    b = push_args(nd_r[a]);
    e = nd_l[a];
    gen(e);
    if (islong(nd_type[e])) {
        pushlong();
        return b + 4;
    }
    op1("pshs", "d");
    return b + 2;
}

void gen_call(int n)
{
    int f, bytes;
    f = nd_l[n];
    bytes = push_args(nd_r[n]);
    if (nd_op[f] == N_ADDR && nd_op[nd_l[f]] == N_GVAR) {
        oc(' ');
        ot("jsr ");
        osym(nd_sym[nd_l[f]]);
        oc('\n');
    } else {
        gen(f);
        op1("tfr", "d,x");
        op1("jsr", ",x");
    }
    if (bytes) {
        oc(' ');
        ot("leas ");
        onum(bytes);
        ot(",s\n");
    }
}

void gen(int n)
{
    int op, t, l, r, l1, l2;
    long v;
    op = nd_op[n];
    t = nd_type[n];
    l = nd_l[n];
    r = nd_r[n];
    if (op == N_NUM) {
        v = nd_val[n];
        if (islong(t))
            opi("ldx", (v >> 16) & 0xFFFF);
        v = v & 0xFFFF;
        if (v == 0) {
            op0("clra");
            op0("clrb");
        } else
            opi("ldd", v);
    } else if (op == N_LVAR || op == N_GVAR || op == N_SVAR || op == N_DEREF) {
        if (lv_easy(n))
            lv_setup(n, 'x');
        else {
            gen(l);
            op1("tfr", "d,x");
            om = M_IX;
            omv = 0;
        }
        load(t);
    } else if (op == N_ADDR)
        gen_addr(l);
    else if (op == N_CAST) {
        gen(l);
        convert(nd_type[l], t);
    } else if (op == N_NEG) {
        gen(l);
        if (islong(t))
            call(H_LNEG);
        else {
            op0("nega");
            op0("negb");
            op1("sbca", "#0");
        }
    } else if (op == N_COM) {
        gen(l);
        op0("coma");
        op0("comb");
        if (islong(t)) {
            op1("exg", "d,x");
            op0("coma");
            op0("comb");
            op1("exg", "d,x");
        }
    } else if (op == N_NOT || (op >= N_EQ && op <= N_LOR)) {
        l1 = newlabel();
        l2 = newlabel();
        gen_cond(n, l1, 1);
        op0("clra");
        op0("clrb");
        opl("bra", l2);
        label(l1);
        opi("ldd", 1);
        label(l2);
    } else if (op >= N_ADD && op <= N_SHR) {
        if (islong(t))
            gen_lbin(n);
        else
            gen_bin(n);
    } else if (op == N_ASSIGN)
        gen_assign(n);
    else if (op == N_SCOPY)
        gen_scopy(n);
    else if (op == N_ASGOP)
        gen_asgop(n);
    else if (op == N_PREINC || op == N_POSTINC)
        gen_inc(n);
    else if (op == N_COND) {
        l1 = newlabel();
        l2 = newlabel();
        gen_cond(l, l1, 0);
        gen(nd_l[r]);
        jmp(l2);
        label(l1);
        gen(nd_r[r]);
        label(l2);
    } else if (op == N_COMMA) {
        gen_void(l);
        gen(r);
    } else if (op == N_CALL)
        gen_call(n);
    else
        error("Can't compile this");
}

/* ---- main -------------------------------------------------------- */

void finish(void)
{
    int g, i, sc, fl;
    section(0);
    if (cursect)
        op0("endsection");
    for (g = 0; g < ngsym; g++) {
        sc = gs_sc[g];
        fl = gs_fl[g];
        if (sc == SC_TYPEDEF || sc == SC_ENUM)
            continue;
        if (fl & F_DEF) {
            if (sc != SC_STATIC) {
                ot(" export _");
                ot(name(gs_name[g]));
                oc('\n');
            }
        } else if (fl & F_USED) {
            if (sc == SC_STATIC)
                error2("Static never defined: ", name(gs_name[g]));
            ot(" import _");
            ot(name(gs_name[g]));
            oc('\n');
        }
    }
    for (i = 0; i < NHELP; i++)
        if (hused[i])
            op1("import", helpers[i]);
}

int main(int argc, char **argv)
{
    char *in;
    int i, n;
    in = 0;
    outname = 0;
    incdir = "INCLUDE/";
#ifdef __MINI09__
    names = (char *)0x8000;
    mactext = names + NAMESZ;
    bank(3);
#else
    names = namebuf;
    mactext = macbuf;
#endif
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-I") == 0 && i + 1 < argc)
            incdir = argv[++i];
        else if (!in)
            in = argv[i];
        else
            outname = argv[i];
    }
    putstr("MINI09 CC 0.1\n");
    if (!in) {
        putstr("Usage: CC FILE.C [OUT.ASM] [-I DIR/]\n");
        return 1;
    }
    for (i = 0; i < NHASH; i++)
        nm_head[i] = -1;
    for (i = 0; kwords[i]; i++)
        lookup(kwords[i]);
    predef("__MINI09__", "1");
    for (i = 0; i <= TUL; i++)
        newtype(i, 0, i == TC || i == TUC || i == TV ? 1 : i >= TL ? 4 : 2, 0, 0);
    if (!outname) {
        n = strlen(in);
        outname = strtmp;
        strcpy(outname, in);
        for (i = n; i > 0 && outname[i - 1] != '.' && outname[i - 1] != '/'; i--)
            ;
        if (i == 0 || outname[i - 1] != '.')
            i = n + 1;
        outname[i - 1] = 0;
        strcat(outname, outname[i] == 'c' ? ".asm" : ".ASM");
        outname = strcpy(argbuf, outname);
    }
    if (!pushfile(in)) {
        putstr("Can't open ");
        putstr(in);
        putchar('\n');
        return 1;
    }
    out = fopen(outname, "w");
    if (!out) {
        putstr("Can't write ");
        putstr(outname);
        putchar('\n');
        return 1;
    }
    ot("; ");
    ot(in);
    ot(" by MINI09 CC 0.1\n");
    nextch();
    bol = 1;
    next();
    while (tok != T_EOF) {
        if (tok == ';')
            next();
        else
            global_decl();
    }
    if (ifdepth)
        error("Missing #endif");
    finish();
    fclose(out);
    if (errors) {
        remove(outname);
        putnum(errors);
        putstr(" error(s), no output written\n");
        return 1;
    }
    putstr(in);
    putstr(": ");
    putnum(src_line[0] - 1);
    putstr(" lines, ");
    putnum(nfuncs);
    putstr(" functions: ");
    putstr(outname);
    putchar('\n');
    return 0;
}
