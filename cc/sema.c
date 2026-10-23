/*
 * SEMA - the third pass of CC: symbols, types and meaning.  See cc.md.
 *
 *     SEMA FILE.A [FILE.T]
 *
 * Reads PARSE's tree file (and FILE.N beside it, for names in messages).
 * Keeps the symbol tables and types, checks and converts, folds
 * constants, lays out data and frames, and writes the assembler for
 * everything but expressions.  Each expression is written as its tree,
 * in lines that start with '!', for GEN to turn into code.  A global's
 * name is written @n, its number; GEN puts the name in.
 */
#include "cc.h"
#define WANT_RFILE
#define WANT_OUT
#include "common.c"

/*
 * The tables are in WINSZ bytes of their own: on MINI09 the RAM page at
 * $8000 (page 3), on the PC the same amount from malloc.  walloc() deals
 * them out at the start.  (LIBC maps its file buffers there during a file
 * call, so nothing handed to LIBC's file calls may be in them.)
 */
#define WINSZ 16384
char *wtop, *wend;

/* names: SEMA only has their numbers */
int *nm_gsym;
char *nname, *fname;
char *namefile;
int curfid;

/* types */
char *ty_kind;
int *ty_base, *ty_size, *ty_n, *ty_x;
int ntypes;
int *mb_name, *mb_type, *mb_off, *mb_next;
int nmemb;
int *pm_type, *pm_name;
int nparm;
int holes[8];
int nhole;

/* symbols */
int *gs_name, *gs_type, *gs_val;
char *gs_sc, *gs_fl;
int ngsym;
int *ls_name, *ls_type, *ls_val;
char *ls_sc;
int nlsym;

/* tree */
int *nd_op, *nd_type, *nd_l, *nd_r, *nd_sym;
long *nd_val;
int nnode;
int *stk;
int nstk;
int tstk[8];
int ntstk;

/* code */
int nlabel, cursect, retlabel, rettype, curoff, maxoff, infunc, nfuncs;
int *brk, *cont;
int nbrk, ncont;
int *case_lab, *case_val;
int ncase, sw_first, sw_def, insw;
int *gl_name, *gl_lab;
char *gl_def;
int ngoto;
int ngoto_at;
int oms;
long omv;
int dbn;
int *dbuf;
char *strtmp;

int sexpr(void);
int sdeclspec(int *psc);
int sdeclarator(int t, int *pname);
void sstmt(void);
void sblock(void);
int init_data(int t);

/* ---- reading the tree file --------------------------------------- */

int pk;                         /* a tag read ahead, or -1 */
int banked;                     /* #pragma bank: GEN puts the code in banks */

int rdraw(void)
{
    int t;
    for (;;) {
        t = fgetc(in);
        if (t == X_LINE)
            tokline = rnum();
        else if (t == X_FILE)
            curfid = rnum();
        else if (t == X_BANK)
            banked = 1;
        else if (t == EOF)
            return X_EOF;
        else
            return t;
    }
}

int rd(void)
{
    int t;
    if (pk >= 0) {
        t = pk;
        pk = -1;
        return t;
    }
    return rdraw();
}

int peek(void)
{
    if (pk < 0)
        pk = rdraw();
    return pk;
}

void bad(void)
{
    fatal("The tree file is damaged");
}

void need(int t)
{
    if (rd() != t)
        bad();
}

/* len bytes into strtmp */
int rdstr(void)
{
    int len, i;
    len = rnum();
    if (len < 0 || len >= STRSZ)
        bad();
    for (i = 0; i < len; i++)
        strtmp[i] = fgetc(in);
    strtmp[len] = 0;
    return len;
}

#define NNAMESZ 64

/* name number id, from FILE.N, into buf (only for messages) */
char *sname(int id, char *buf)
{
    FILE *f;
    int c, i;
    strcpy(buf, "?");
    f = fopen(namefile, "r");
    if (!f)
        return buf;
    while (id > 0) {
        c = fgetc(f);
        if (c == EOF)
            break;
        if (c == 0)
            id--;
    }
    i = 0;
    while ((c = fgetc(f)) > 0 && i < NNAMESZ - 1)
        buf[i++] = c;
    buf[i] = 0;
    fclose(f);
    return buf;
}

char *name(int id)
{
    return sname(id, nname);
}

char *curfile(void)
{
    return sname(curfid, fname);
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
    return ntypes++;
}

int ptr_to(int t)
{
    int i;
    for (i = TUL + 1; i < ntypes; i++)
        if (ty_kind[i] == TY_PTR && ty_base[i] == t)
            return i;
    return newtype(TY_PTR, t, 2, 0, 0);
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
    return l;
}

/* the innermost local named id, or -1 */
int lfind(int id)
{
    int l;
    for (l = nlsym - 1; l >= 0; l--)
        if (ls_name[l] == id)
            return l;
    return -1;
}

void popscope(int mark)
{
    nlsym = mark;
}

/* the struct or union with this tag, or 0 */
int tagtype(int tag)
{
    int t;
    for (t = ntypes - 1; t > TUL; t--)
        if ((ty_kind[t] == TY_STRUCT || ty_kind[t] == TY_UNION) && ty_x[t] == tag)
            return t;
    return 0;
}

int typedeftype(int id)
{
    int l;
    l = lfind(id);
    if (l >= 0)
        return ls_type[l];
    return gs_type[nm_gsym[id]];
}

/* ---- output ------------------------------------------------------ */

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

/* a symbol: a global by its name's number (@n), or a label */
void osym(int s)
{
    if (s >= 0) {
        oc('@');
        onum(gs_name[s]);
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

/* ---- writing a tree for GEN -------------------------------------- */

int wn;                         /* nodes written for this tree */

/* n and what is below it, children first -> its number in the record */
int wtree(int n)
{
    int l, r, t, s;
    l = nd_l[n];
    r = nd_r[n];
    if (nd_op[n] >= N_ADDR && l >= 0)
        l = wtree(l);
    else
        l = -1;
    if (nd_op[n] == N_CALL || nd_op[n] == N_ARG) {
        if (r)                  /* 0 ends an argument list */
            r = wtree(r);
        else
            r = -1;
    } else if (nd_op[n] >= N_ADD && r >= 0 && nd_op[n] != N_PREINC &&
        nd_op[n] != N_POSTINC)
        r = wtree(r);
    else
        r = -1;
    t = nd_type[n];
    s = nd_sym[n];
    if (nd_op[n] == N_GVAR) {
        gs_fl[s] = gs_fl[s] | F_USED;
        s = gs_name[s];
    }
    ot("!N ");
    onum(nd_op[n]);
    oc(' ');
    onum(ty_kind[t]);
    oc(' ');
    onum(ty_size[t]);
    oc(' ');
    onum(l);
    oc(' ');
    onum(r);
    oc(' ');
    onum(nd_val[n]);
    oc(' ');
    onum(s);
    oc('\n');
    return wn++;
}

void gen(int n)
{
    wn = 0;
    n = wtree(n);
    ot("!G ");
    onum(n);
    oc('\n');
}

void gen_cond(int n, int lab, int jt)
{
    wn = 0;
    n = wtree(n);
    ot("!C ");
    onum(n);
    oc(' ');
    onum(lab);
    oc(' ');
    onum(jt);
    oc('\n');
}

void gen_void(int n)
{
    if (nd_op[n] == N_POSTINC)
        nd_op[n] = N_PREINC;
    gen(n);
}

int newlabel(void)
{
    return ++nlabel;
}

/* ---- trees ------------------------------------------------------- */

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

int mkmember(int n, int arrow, int id)
{
    int st, m, p, mt;
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

/* a call: the function at stk[base], then its arguments */
int mkcall(int base, int nargs)
{
    int f, ft, np, i, a, head, tail, fl, t;
    f = rvalue(stk[base]);
    if (!isptr(nd_type[f]) || ty_kind[ty_base[nd_type[f]]] != TY_FUNC) {
        error("Not a function");
        ft = 0;
    } else
        ft = ty_base[nd_type[f]];
    np = ft ? ty_x[ft] & 255 : 0;
    fl = ft ? ty_x[ft] & (FN_VARARG | FN_NOPROTO) : FN_NOPROTO;
    head = 0;
    tail = 0;
    for (i = 0; i < nargs; i++) {
        a = rvalue(stk[base + 1 + i]);
        t = nd_type[a];
        if (i < np)
            a = conv(a, pm_type[ty_n[ft] + i]);
        else if (!fl) {
            error("Too many arguments");
            break;
        } else if (isscalar(t))
            a = conv(a, promote(t));
        if (!isscalar(nd_type[a]))
            error("Bad argument");
        a = node(N_ARG, nd_type[a], a, 0);
        if (tail)
            nd_r[tail] = a;
        else
            head = a;
        tail = a;
    }
    if (nargs < np)
        error("Too few arguments");
    return node(N_CALL, ft ? ty_base[ft] : TI, f, head);
}

/* a string literal (in strtmp) -> its node; the bytes go in strings */
int mkstring(int len)
{
    int l, t, n;
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

int mkident(int id)
{
    int l, g, n;
    l = lfind(id);
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

/* ---- expressions ------------------------------------------------- */

void push(int n)
{
    if (nstk >= MAXSTK)
        fatal("Expression too complex");
    stk[nstk++] = n;
}

int pop(void)
{
    if (nstk <= 0)
        bad();
    return stk[--nstk];
}

int stypename(void)
{
    int t, sc, id;
    t = sdeclspec(&sc);
    return sdeclarator(t, &id);
}

/* the expression up to A_END -> its tree */
int sexpr(void)
{
    int t, n, a, b, c, ta, tb, op, base;
    base = nstk;
    for (;;) {
        t = rd();
        if (t == A_END) {
            if (nstk != base + 1)
                bad();
            return pop();
        }
        if (t == A_NUM) {
            op = rnum();
            push(mknum(rnum(), op));
        } else if (t == A_STR)
            push(mkstring(rdstr()));
        else if (t == A_IDENT)
            push(mkident(rnum()));
        else if (t == A_BIN) {
            op = rnum();
            b = pop();
            a = pop();
            push(mkbin(op, a, b));
        } else if (t == A_COND) {
            b = pop();
            a = pop();
            c = rvalue(pop());
            a = rvalue(a);
            b = rvalue(b);
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
                push(nd_val[c] ? a : b);
            else
                push(node(N_COND, t, c, node(N_COLON, t, a, b)));
        } else if (t == A_ASSIGN) {
            b = pop();
            push(mkassign(pop(), b));
        } else if (t == A_ASGOP) {
            op = rnum();
            b = pop();
            push(mkasgop(op, pop(), b));
        } else if (t == A_COMMA) {
            b = rvalue(pop());
            a = pop();
            push(node(N_COMMA, nd_type[b], a, b));
        } else if (t == A_INDEX) {
            b = pop();
            a = pop();
            push(mkderef(mkbin(N_ADD, a, b)));
        } else if (t == A_CALL) {
            op = rnum();
            if (nstk - op - 1 < base)
                bad();
            n = mkcall(nstk - op - 1, op);
            nstk = nstk - op - 1;
            push(n);
        } else if (t == A_MEMBER) {
            op = rnum();
            a = rnum();
            push(mkmember(pop(), op, a));
        } else if (t == A_INC) {
            op = rnum();
            a = rnum();
            push(mkinc(pop(), op, a));
        } else if (t == A_ADDR) {
            n = pop();
            if (ty_kind[nd_type[n]] == TY_FUNC || nd_op[n] == N_STR)
                push(rvalue(n));
            else
                push(addr_of(n));
        } else if (t == A_DEREF)
            push(mkderef(pop()));
        else if (t == A_UNARY) {
            op = rnum();
            n = rvalue(pop());
            if (!isint(nd_type[n]))
                error("Bad operand");
            else {
                n = conv(n, promote(nd_type[n]));
                if (op != '+')
                    n = fold(node(op == '-' ? N_NEG : N_COM, nd_type[n], n, 0));
            }
            push(n);
        } else if (t == A_NOT) {
            n = rvalue(pop());
            if (!isscalar(nd_type[n]))
                error("Bad operand");
            push(fold(node(N_NOT, TI, n, 0)));
        } else if (t == A_SIZEOFE || t == A_SIZEOFT) {
            if (t == A_SIZEOFE)
                t = nd_type[pop()];
            else
                t = stypename();
            if (tsize(t) < 0)
                error("Size unknown");
            push(mknum(tsize(t), TUI));
        } else if (t == A_CASTT) {
            if (ntstk >= 8)
                fatal("Expression too complex");
            tstk[ntstk++] = stypename();
        } else if (t == A_CAST) {
            n = rvalue(pop());
            push(conv(n, tstk[--ntstk]));
        } else
            bad();
    }
}

long sconst(void)
{
    int n;
    n = sexpr();
    if (nd_op[n] != N_NUM) {
        error("Constant expected");
        return 0;
    }
    return nd_val[n];
}

/* ---- declarations ------------------------------------------------ */

int sstruct(void)
{
    int isun, tag, t, off, size, b, mt, id, last, m, sc;
    isun = rnum();
    tag = rnum();
    t = 0;
    if (tag >= 0)
        t = tagtype(tag);
    if (!rnum()) {
        if (!t && tag >= 0) {
            t = newtype(isun ? TY_UNION : TY_STRUCT, 0, -1, -1, tag);
        }
        return t;
    }
    if (!t || ty_size[t] >= 0) {
        t = newtype(isun ? TY_UNION : TY_STRUCT, 0, -1, -1, tag);
    }
    off = 0;
    size = 0;
    last = -1;
    while (rd() == M_DECL) {
        b = sdeclspec(&sc);
        while (rd() == M_ITEM) {
            mt = sdeclarator(b, &id);
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
        }
    }
    ty_size[t] = isun ? size : off;
    return t;
}

int senum(void)
{
    int id;
    long v;
    if (!rnum())
        return TI;
    v = 0;
    while (rd() == E_ITEM) {
        id = rnum();
        if (rnum())
            v = sconst();
        if (infunc)
            addlocal(id, TI, SC_ENUM, v);
        else
            gs_val[addglobal(id, TI, SC_ENUM)] = v;
        v++;
    }
    return TI;
}

int sdeclspec(int *psc)
{
    int base, t, k;
    need(DS);
    base = 0;
    for (;;) {
        t = rd();
        if (t == B_STRUCT)
            base = sstruct();
        else if (t == B_ENUM)
            base = senum();
        else if (t == B_TYPEDEF)
            base = typedeftype(rnum());
        else if (t == B_BASIC) {
            *psc = rnum();
            k = rnum();
            if (!base)
                base = k;
            return base;
        } else
            bad();
    }
}

int sfuncsuffix(int ret)
{
    int np, fl, b, t, id, sc, i, start;
    int ptype[MAXFP];
    int pname[MAXFP];
    np = 0;
    while (rd() == P_PARAM) {
        b = sdeclspec(&sc);
        t = sdeclarator(b, &id);
        if (np == 0 && t == TV && peek() == P_END)
            continue;
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
    }
    fl = rnum();
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

int ssuffixes(int t)
{
    long n;
    int k;
    k = rd();
    if (k == S_ARRAY) {
        n = -1;
        if (peek() == A_NONE)
            rd();
        else
            n = sconst();
        t = ssuffixes(t);
        return array_of(t, n);
    }
    if (k == S_FUNC)
        return sfuncsuffix(t);
    if (k != S_SEND)
        bad();
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

int sdeclarator(int t, int *pname)
{
    int hole, inner, k;
    *pname = -1;
    for (;;) {
        k = rd();
        if (k == D_PTR)
            t = ptr_to(t);
        else if (k == D_NEST) {
            if (nhole >= 8)
                fatal("Declarator too complex");
            if (!holes[nhole])
                holes[nhole] = newtype(TY_HOLE, 0, 0, 0, 0);
            hole = holes[nhole++];
            inner = sdeclarator(hole, pname);
            nhole--;
            t = ssuffixes(t);
            return subst(inner, hole, t);
        } else if (k == D_NAME) {
            *pname = rnum();
            return ssuffixes(t);
        } else if (k == D_ANON)
            return ssuffixes(t);
        else
            bad();
    }
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

/* skip an initializer that can't be used */
void skipinit(void)
{
    int t;
    t = rd();
    if (t == V_LIST) {
        while (peek() != V_LEND)
            skipinit();
        rd();
    } else if (t == V_STRING)
        rdstr();
    else if (t == V_EXPR)
        sexpr();
    else
        bad();
}

/* V_EXPR or V_STRING -> the tree; a list is an error */
int sinitexpr(void)
{
    int t;
    t = rd();
    if (t == V_EXPR)
        return sexpr();
    if (t == V_STRING)
        return mkstring(rdstr());
    if (t == V_LIST) {
        pk = t;
        skipinit();
        error("Can't initialize this with a list");
    } else
        bad();
    return mknum(0, TI);
}

void dscalar(int t)
{
    int n, br;
    long v;
    br = peek() == V_LIST;
    if (br)
        rd();
    nnode = 0;
    n = conv(rvalue(sinitexpr()), t);
    if (br) {
        if (peek() != V_LEND) {
            error("Too many initializers");
            while (peek() != V_LEND)
                skipinit();
        }
        rd();
    }
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
        if (ischar(et) && peek() == V_STRING) {
            rd();
            len = rdstr();
            if (n < 0)
                n = len + 1;
            dstring(strtmp, len < n ? len + 1 : len, n);
            return n;
        }
        if (peek() != V_LIST) {
            error("Expected {");
            skipinit();
            return n < 0 ? 0 : n;
        }
        rd();
        i = 0;
        while (peek() != V_LEND) {
            if (n >= 0 && i >= n) {
                error("Too many initializers");
                while (peek() != V_LEND)
                    skipinit();
                break;
            }
            init_data(et);
            i++;
        }
        rd();
        if (n < 0)
            n = i;
        dzero((n - i) * tsize(et));
        return n;
    }
    if (k == TY_STRUCT || k == TY_UNION) {
        if (peek() != V_LIST) {
            error("Expected {");
            skipinit();
            return 1;
        }
        rd();
        m = ty_n[t];
        i = 0;
        while (peek() != V_LEND && m >= 0) {
            init_data(mb_type[m]);
            i = i + tsize(mb_type[m]);
            m = k == TY_UNION ? -1 : mb_next[m];
        }
        if (peek() != V_LEND) {
            error("Too many initializers");
            while (peek() != V_LEND)
                skipinit();
        }
        rd();
        dzero(tsize(t) - i);
        return 1;
    }
    if (!isscalar(t)) {
        error("Can't initialize this");
        skipinit();
        return 1;
    }
    dscalar(t);
    return 1;
}

/* Data or bss for a global or static: label l (>= 0: symbol, < 0: Ln),
   with an initializer if init.  Returns the type, with an array's size
   filled in. */
int define_data(int s, int t, int init)
{
    int n, sect;
    sect = cursect;
    if (init) {
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

/* after DECL, in a function */
void local_decl(void)
{
    int base, sc, t, id, l, n, k;
    base = sdeclspec(&sc);
    while (rd() == I_DECL) {
        nnode = 0;
        t = sdeclarator(base, &id);
        k = rd();
        if (k == I_FUNC)
            bad();
        if (sc == K_TYPEDEF)
            addlocal(id, t, SC_TYPEDEF, 0);
        else if (sc == K_EXTERN || ty_kind[t] == TY_FUNC)
            addglobal(id, t, SC_EXTERN);
        else if (sc == K_STATIC) {
            l = newlabel();
            t = define_data(-l, t, k == I_INIT);
            addlocal(id, t, SC_LSTATIC, l);
            continue;
        } else {
            if (tsize(t) < 0)
                error("Size unknown");
            else
                curoff = curoff - tsize(t);
            if (-curoff > maxoff)
                maxoff = -curoff;
            addlocal(id, t, SC_AUTO, curoff);
            if (k == I_INIT) {
                if (!isscalar(t)) {
                    error("Can't initialize a local array or struct");
                    skipinit();
                } else {
                    n = node(N_LVAR, t, 0, 0);
                    nd_val[n] = curoff;
                    gen(mkassign(n, sinitexpr()));
                }
            }
            continue;
        }
        if (k == I_INIT) {
            error("Can't initialize this");
            skipinit();
        }
    }
}

void sblock(void)
{
    int mark, off;
    mark = nlsym;
    off = curoff;
    while (peek() != S_BEND) {
        if (peek() == DECL) {
            rd();
            local_decl();
        } else
            sstmt();
    }
    rd();
    popscope(mark);
    curoff = off;
}

void st_switch(void)
{
    int n, t, slot, ltest, lbrk, ofirst, odef, oinsw, off, i;
    n = rvalue(sexpr());
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
    sstmt();
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

/* an optional expression: 1 and the tree in *pn, or 0 for A_NONE */
int optexpr(int *pn)
{
    if (peek() == A_NONE) {
        rd();
        return 0;
    }
    *pn = sexpr();
    return 1;
}

void sstmt(void)
{
    int n, l1, l2, l3, l4, t, id;
    long v;
    nnode = 0;
    t = rd();
    if (t == S_BLOCK) {
        sblock();
        return;
    }
    if (t == S_EMPTY)
        return;
    if (t == S_EXPR) {
        gen_void(sexpr());
        return;
    }
    if (t == S_IF) {
        n = sexpr();
        l1 = newlabel();
        gen_cond(n, l1, 0);
        sstmt();
        if (rd() == S_ELSE) {
            l2 = newlabel();
            jmp(l2);
            label(l1);
            sstmt();
            label(l2);
        } else
            label(l1);
        return;
    }
    if (t == S_WHILE) {
        l1 = newlabel();
        l2 = newlabel();
        label(l1);
        n = sexpr();
        gen_cond(n, l2, 0);
        brk[nbrk++] = l2;
        cont[ncont++] = l1;
        sstmt();
        nbrk--;
        ncont--;
        jmp(l1);
        label(l2);
        return;
    }
    if (t == S_DO) {
        l1 = newlabel();
        l2 = newlabel();
        l3 = newlabel();
        label(l1);
        brk[nbrk++] = l3;
        cont[ncont++] = l2;
        sstmt();
        nbrk--;
        ncont--;
        nnode = 0;
        n = sexpr();
        label(l2);
        gen_cond(n, l1, 1);
        label(l3);
        return;
    }
    if (t == S_FOR) {
        if (optexpr(&n))
            gen_void(n);
        l1 = newlabel();
        l4 = newlabel();
        label(l1);
        nnode = 0;
        if (optexpr(&n))
            gen_cond(n, l4, 0);
        l2 = l1;
        nnode = 0;
        if (optexpr(&n)) {
            l3 = newlabel();
            l2 = newlabel();
            jmp(l3);
            label(l2);
            gen_void(n);
            jmp(l1);
            label(l3);
        }
        brk[nbrk++] = l4;
        cont[ncont++] = l2;
        sstmt();
        nbrk--;
        ncont--;
        jmp(l2);
        label(l4);
        return;
    }
    if (t == S_SWITCH) {
        st_switch();
        return;
    }
    if (t == S_CASE) {
        v = sconst();
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
        sstmt();
        return;
    }
    if (t == S_DEFAULT) {
        if (!insw)
            error("Default outside a switch");
        else {
            sw_def = newlabel();
            label(sw_def);
        }
        sstmt();
        return;
    }
    if (t == S_BREAK) {
        if (nbrk)
            jmp(brk[nbrk - 1]);
        else
            error("Break outside a loop");
        return;
    }
    if (t == S_CONT) {
        if (ncont)
            jmp(cont[ncont - 1]);
        else
            error("Continue outside a loop");
        return;
    }
    if (t == S_RETURN) {
        if (optexpr(&n)) {
            n = rvalue(n);
            if (ty_kind[rettype] == TY_VOID)
                error("Return with a value in a void function");
            else
                gen(conv(n, rettype));
        }
        jmp(retlabel);
        return;
    }
    if (t == S_GOTO) {
        jmp(golabel(rnum()));
        return;
    }
    if (t == S_LABEL) {
        id = rnum();
        l1 = golabel(id);
        if (gl_def[ngoto_at])
            error2("Label used twice: ", name(id));
        gl_def[ngoto_at] = 1;
        label(l1);
        sstmt();
        return;
    }
    bad();
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
    need(S_BLOCK);
    sblock();
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

/* after DECL, outside functions */
void global_decl(void)
{
    int base, sc, t, id, g, gsc, k;
    base = sdeclspec(&sc);
    while (rd() == I_DECL) {
        nnode = 0;
        t = sdeclarator(base, &id);
        k = rd();
        if (sc == K_TYPEDEF) {
            addglobal(id, t, SC_TYPEDEF);
        } else if (ty_kind[t] == TY_FUNC) {
            g = addglobal(id, t, sc == K_STATIC ? SC_STATIC : SC_GLOBAL);
            if (k == I_FUNC) {
                funcdef(g, t);
                continue;
            }
        } else {
            gsc = sc == K_STATIC ? SC_STATIC : sc == K_EXTERN ? SC_EXTERN : SC_GLOBAL;
            g = addglobal(id, t, gsc);
            if (gsc != SC_EXTERN) {
                if (gs_fl[g] & F_DEF)
                    error2("Redefined: ", name(id));
                gs_fl[g] = gs_fl[g] | F_DEF;
                gs_type[g] = define_data(g, gs_type[g], k == I_INIT);
                continue;
            }
        }
        if (k == I_FUNC) {
            error("Not a function");
            need(S_BLOCK);
            sblock();
        } else if (k == I_INIT) {
            error("Can't initialize this");
            skipinit();
        }
    }
}

/* ---- main -------------------------------------------------------- */

void finish(void)
{
    int g, sc, fl;
    section(0);
    if (cursect)
        op0("endsection");
    if (banked)
        ot("!B\n");
    for (g = 0; g < ngsym; g++) {
        sc = gs_sc[g];
        fl = gs_fl[g];
        if (sc == SC_TYPEDEF || sc == SC_ENUM)
            continue;
        if (fl & F_DEF) {
            if (sc != SC_STATIC) {
                ot(" export @");
                onum(gs_name[g]);
                oc('\n');
            }
        } else if (fl & F_USED) {
            if (sc == SC_STATIC)
                error2("Static never defined: ", name(gs_name[g]));
            ot(" import @");
            onum(gs_name[g]);
            oc('\n');
        }
    }
    flushjmp();
}

char oname[PATHSZ], nfile[PATHSZ];

/* n bytes of the tables' space */
char *walloc(int n)
{
    char *p;
    if (n > wend - wtop)
        fatal("Tables too big");
    p = wtop;
    wtop = wtop + n;
    return p;
}

void walloc_tables(void)
{
#ifdef __MINI09__
    wtop = (char *)0x8000;
    bank(3);
    wend = wtop + WINSZ;
#else
    wtop = malloc(WINSZ * 4);   /* ints and longs are bigger here */
    wend = wtop + WINSZ * 4;
#endif
    nm_gsym = (int *)walloc(MAXNAME * sizeof(int));
    ty_kind = walloc(MAXTYPE);
    ty_base = (int *)walloc(MAXTYPE * sizeof(int));
    ty_size = (int *)walloc(MAXTYPE * sizeof(int));
    ty_n = (int *)walloc(MAXTYPE * sizeof(int));
    ty_x = (int *)walloc(MAXTYPE * sizeof(int));
    mb_name = (int *)walloc(MAXMEMB * sizeof(int));
    mb_type = (int *)walloc(MAXMEMB * sizeof(int));
    mb_off = (int *)walloc(MAXMEMB * sizeof(int));
    mb_next = (int *)walloc(MAXMEMB * sizeof(int));
    pm_type = (int *)walloc(MAXPARM * sizeof(int));
    pm_name = (int *)walloc(MAXPARM * sizeof(int));
    gs_name = (int *)walloc(MAXGSYM * sizeof(int));
    gs_type = (int *)walloc(MAXGSYM * sizeof(int));
    gs_val = (int *)walloc(MAXGSYM * sizeof(int));
    gs_sc = walloc(MAXGSYM);
    gs_fl = walloc(MAXGSYM);
    ls_name = (int *)walloc(MAXLSYM * sizeof(int));
    ls_type = (int *)walloc(MAXLSYM * sizeof(int));
    ls_val = (int *)walloc(MAXLSYM * sizeof(int));
    ls_sc = walloc(MAXLSYM);
    nd_op = (int *)walloc(MAXNODE * sizeof(int));
    nd_type = (int *)walloc(MAXNODE * sizeof(int));
    nd_l = (int *)walloc(MAXNODE * sizeof(int));
    nd_r = (int *)walloc(MAXNODE * sizeof(int));
    nd_sym = (int *)walloc(MAXNODE * sizeof(int));
    nd_val = (long *)walloc(MAXNODE * sizeof(long));
    case_lab = (int *)walloc(MAXCASE * sizeof(int));
    case_val = (int *)walloc(MAXCASE * sizeof(int));
    strtmp = walloc(STRSZ);
    nname = walloc(NNAMESZ);
    fname = walloc(NNAMESZ);
    stk = (int *)walloc(MAXSTK * sizeof(int));
    brk = (int *)walloc(MAXLOOP * sizeof(int));
    cont = (int *)walloc(MAXLOOP * sizeof(int));
    gl_name = (int *)walloc(MAXGOTO * sizeof(int));
    gl_lab = (int *)walloc(MAXGOTO * sizeof(int));
    gl_def = walloc(MAXGOTO);
    dbuf = (int *)walloc(16 * sizeof(int));
}

int main(int argc, char **argv)
{
    char *iname, *o;
    int i, t;
    iname = 0;
    o = 0;
    for (i = 1; i < argc; i++) {
        if (!iname)
            iname = argv[i];
        else
            o = argv[i];
    }
    if (!iname) {
        putstr("Usage: SEMA FILE.A [FILE.T]\n");
        return 1;
    }
    namefile = outext(nfile, iname, ".n", ".N");
    walloc_tables();
    for (i = 0; i < MAXNAME; i++)
        nm_gsym[i] = -1;
    for (i = 0; i <= TUL; i++)
        newtype(i, 0, i == TC || i == TUC || i == TV ? 1 : i >= TL ? 4 : 2, 0, 0);
    in = openin(iname);
    pk = -1;
    if (!o)
        o = outext(oname, iname, ".t", ".T");
    openout(o);
    for (;;) {
        t = rd();
        if (t == X_EOF)
            break;
        if (t != DECL)
            bad();
        global_decl();
    }
    finish();
    fclose(in);
    closeout();
    return 0;
}
