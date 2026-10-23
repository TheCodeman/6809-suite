/*
 * GEN - the fourth pass of CC: code.  See cc.md.
 *
 *     GEN FILE.T [FILE.ASM]
 *
 * Reads what SEMA wrote, and FILE.N beside it.  Copies the assembler
 * lines through, with each @n made the name it stands for, and turns
 * each expression tree into code:
 *
 *     !N op kind size l r val sym    a node; l and r are the numbers of
 *                                    nodes before it in the tree, or -1
 *     !G n                           code for the tree whose root is n
 *     !C n lab jt                    jump to lab if n is true (jt) or
 *                                    false (!jt)
 *
 * Then imports the runtime helpers the code calls.
 *
 *     !B                             #pragma bank: the file's code goes in
 *                                    section "banked", each function's
 *                                    body labelled B_name, and a stub in
 *                                    section code for each, called by
 *                                    other files and through pointers:
 *
 *         _name   jsr __bcall        CRT0B switches the page in and out
 *                 fcb __bank         the page (LINK fills it in)
 *                 fdb B_name
 *
 * Calls inside the file go to B_name directly.  SEMA writes !B at the
 * end, so the first time through finds it, and the functions.
 *
 * GEN goes through FILE.T twice.  The first time it writes nothing, but
 * works out where each label will be, counting every branch as long and
 * every instruction at its longest.  The second time a long branch that
 * reaches its label by those counts is written short: they can only
 * shrink, so it still does.
 */
#include "cc.h"
#define WANT_NAMES
#define WANT_RFILE
#define WANT_OUT
#define LINE_OUT
#include "common.c"

/* operand modes */
#define M_IMM  1                /* #v */
#define M_ISYM 2                /* #sym+v */
#define M_LOC  3                /* v,u */
#define M_GLB  4                /* sym+v */
#define M_IX   5                /* v,x */
#define M_IY   6                /* v,y */
#define M_ABS  7                /* v */
#define M_STK  8                /* ,s++ (or ,s+ for a byte) */
#define M_DX   9                /* d,x: for a load only */

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

/* types: just a kind and a size; the basic types are at their kind */
#define GTYPES 64
int ty_kind[GTYPES], ty_size[GTYPES];
int ntypes;

/* the tree */
int nd_op[MAXNODE], nd_type[MAXNODE], nd_l[MAXNODE], nd_r[MAXNODE];
int nd_sym[MAXNODE];
long nd_val[MAXNODE];
int nnode;

int nlabel;
int banked;                     /* !B */
char *fnhere;                   /* a function defined in this file */
int incodet;                    /* FILE.T's section code */
int om, oms;
long omv;
int s_om, s_oms;
long s_omv;

char line[STRSZ];
char *lp;
char *iname;

char *curfile(void)
{
    return iname;
}

/* the type with this kind and size */
int gtype(int kind, int size)
{
    int i;
    if (kind <= TY_ULONG)
        return kind;
    for (i = TY_ULONG + 1; i < ntypes; i++)
        if (ty_kind[i] == kind && ty_size[i] == size)
            return i;
    if (ntypes >= GTYPES)
        fatal("Too many types");
    ty_kind[ntypes] = kind;
    ty_size[ntypes] = size;
    return ntypes++;
}

int tsize(int t)
{
    return ty_size[t];
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

int promote(int t)
{
    if (ischar(t))
        return TI;
    return t;
}


/* GEN's labels are negative, written M1, M2 ... */
int newlabel(void)
{
    return -++nlabel;
}

void call(int h)
{
    hused[h] = 1;
    op1("jsr", helpers[h]);
}


void osym(int s)
{
    if (s >= 0) {
        oc('_');
        ot(name(s));
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
    } else if (om == M_DX)
        ot("d,x");
    else
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

int log2of(long v)
{
    int k;
    for (k = 0; k < 16; k++)
        if (v == (1L << k))
            return k;
    return -1;
}


void gen(int n);
void gen_cond(int n, int lab, int jt);
void gen_addr(int n);

void gen_void(int n)
{
    if (nd_op[n] == N_POSTINC)
        nd_op[n] = N_PREINC;
    gen(n);
}


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
    int f, bytes, s;
    f = nd_l[n];
    bytes = push_args(nd_r[n]);
    if (nd_op[f] == N_ADDR && nd_op[nd_l[f]] == N_GVAR) {
        s = nd_sym[nd_l[f]];
        oc(' ');
        ot("jsr ");
        if (banked && s >= 0 && fnhere[s])
            oc('B');            /* in the same bank */
        osym(s);
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

/* a pointer that is_simple: a variable or an array's address */
int simple_ptr(int a)
{
    return nd_op[a] != N_NUM && isptr(nd_type[a]) && is_simple(a);
}

/* p is a simple pointer + an int: code for the int, the pointer into X
   and om = d,x (if it is) */
int dx_index(int p)
{
    int a, i;
    if (nd_op[p] != N_ADD)
        return 0;
    a = nd_r[p];
    i = nd_l[p];
    if (!simple_ptr(a)) {
        a = nd_l[p];
        i = nd_r[p];
    }
    if (!simple_ptr(a) || isptr(nd_type[i]) || tsize(nd_type[i]) != 2)
        return 0;
    gen(i);
    set_simple(a);
    opm("ldx", 0);
    om = M_DX;
    omv = 0;
    return 1;
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
        else if (op == N_DEREF && !islong(t) && dx_index(l))
            ;
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


/* ---- reading SEMA's lines ---------------------------------------- */

/* a line into line[], without its newline; 0 at the end of the file */
int rline(void)
{
    int c, i;
    i = 0;
    for (;;) {
        c = fgetc(in);
        if (c == EOF) {
            if (i == 0)
                return 0;
            break;
        }
        if (c == '\n')
            break;
        if (i < STRSZ - 1)
            line[i++] = c;
    }
    line[i] = 0;
    lp = line;
    return 1;
}

long rval(void)
{
    long v;
    int neg;
    while (*lp == ' ')
        lp++;
    neg = 0;
    if (*lp == '-') {
        neg = 1;
        lp++;
    }
    v = 0;
    while (isdig(*lp))
        v = v * 10 + *lp++ - '0';
    if (neg)
        v = -v;
    return tr32(v);
}

/* !N op kind size l r val sym */
void rnode(void)
{
    int n, k;
    if (nnode >= MAXNODE)
        fatal("Expression too complex");
    n = nnode++;
    lp = line + 2;
    nd_op[n] = rval();
    k = rval();
    nd_type[n] = gtype(k, rval());
    nd_l[n] = rval();
    nd_r[n] = rval();
    nd_val[n] = rval();
    nd_sym[n] = rval();
    /* an argument list ends with 0 */
    if ((nd_op[n] == N_CALL || nd_op[n] == N_ARG) && nd_r[n] < 0)
        nd_r[n] = 0;
}

/* a line of assembler, with @n made _name; in a banked file, the code
   section is "banked" and a function's label B_name */
void copyline(void)
{
    char *p;
    int s;
    p = line;
    if (strcmp(p, " section code") == 0) {
        incodet = 1;
        if (banked) {
            ot(" section banked\n");
            return;
        }
    } else if (strcmp(p, " endsection") == 0)
        incodet = 0;
    else if (incodet && *p == '@') {
        lp = p + 1;
        s = rval();
        if (!*lp && s >= 0 && s < MAXNAME) {
            fnhere[s] = 1;
            if (banked) {
                if (strlen(name(s)) > 29)
                    error2("Name too long for a banked function: ", name(s));
                ot("B_");
                ot(name(s));
                oc('\n');
                return;
            }
        }
    }
    /* a label that a waiting jump goes to */
    if (*p == 'L' && isdig(p[1])) {
        lp = p + 1;
        rval();
        if (!*lp) {
            lp = p + 1;
            label(rval());
            return;
        }
    }
    while (*p) {
        if (*p == '@') {
            lp = p + 1;
            oc('_');
            ot(name(rval()));
            p = lp;
        } else
            oc(*p++);
    }
    oc('\n');
}

/* the names, as PARSE wrote them */
void rnames(char *file)
{
    int c;
    in = openin(file);
    nnames = 0;
    nnamech = 0;
    nm_off[0] = 0;
    while ((c = fgetc(in)) != EOF) {
        if (nnamech >= NAMESZ)
            fatal("Too many names");
        names[nnamech++] = c;
        if (c == 0) {
            if (++nnames >= MAXNAME)
                fatal("Too many names");
            nm_off[nnames] = nnamech;
        }
    }
    fclose(in);
}

/* ---- short branches ---------------------------------------------- */

#define MAXLAB  2560            /* SEMA's labels, L1 ... */
#define MAXMLAB 1024            /* GEN's, M1 ... */
int *lpos, *mpos;               /* where each is, from the first time */
int pass, pc, incode;

/* the place for label s (L12, M3) in lpos or mpos, or 0 */
int *labslot(char *s)
{
    int n, m;
    m = *s++;
    if ((m != 'L' && m != 'M') || !isdig(*s))
        return 0;
    n = 0;
    while (isdig(*s) && n < 10000)
        n = n * 10 + *s++ - '0';
    if (*s)
        return 0;
    if (m == 'L')
        return n < MAXLAB ? lpos + n : 0;
    return n < MAXMLAB ? mpos + n : 0;
}

/* w is one of the words in list, which has a space before and after
   each */
int inwords(char *w, char *list)
{
    char *p, *q;
    for (p = list; *p; p++) {
        if (*p != ' ' || !p[1])
            continue;
        for (q = w; *q && *q == p[1 + (q - w)]; q++)
            ;
        if (!*q && p[1 + (q - w)] == ' ')
            return 1;
    }
    return 0;
}

/* the bytes of fcb's or fdb's numbers */
int nitems(char *a)
{
    int n;
    n = 1;
    while (*a)
        if (*a++ == ',')
            n++;
    return n;
}

/* the offset bytes of an indexed operand */
int ixoff(char *a)
{
    long v;
    int neg;
    if (*a == ',' || ((*a == 'a' || *a == 'b' || *a == 'd') && a[1] == ','))
        return 0;
    neg = 0;
    if (*a == '-') {
        neg = 1;
        a++;
    }
    if (!isdig(*a))
        return 2;               /* a symbol: at its longest */
    v = 0;
    while (isdig(*a) && v < 100000)
        v = v * 10 + *a++ - '0';
    if (neg)
        v = -v;
    if (v >= -16 && v <= 15)
        return 0;
    if (v >= -128 && v <= 127)
        return 1;
    return 2;
}

/* the most bytes instruction op arg can take */
int isize(char *op, char *a)
{
    int pre;
    if (!*a)
        return 1;               /* clra, sex, rts ... */
    if (strcmp(op, "fcb") == 0)
        return nitems(a);
    if (strcmp(op, "fdb") == 0)
        return 2 * nitems(a);
    if (inwords(op, " pshs puls pshu pulu tfr exg andcc orcc "))
        return 2;
    if (strcmp(op, "lbra") == 0 || strcmp(op, "lbsr") == 0)
        return 3;
    if (op[0] == 'l' && op[1] == 'b')
        return 4;
    if (op[0] == 'b' && strcmp(op, "bita") && strcmp(op, "bitb"))
        return 2;
    if (inwords(op, " export import "))
        return 0;
    pre = inwords(op, " ldy sty lds sts cmpd cmpy cmps cmpu ");
    if (*a == '#')
        return 2 + pre + inwords(op, " ldd ldx ldy ldu lds addd subd cmpd cmpx cmpy cmpu cmps ");
    if (strchr(a, ','))
        return 2 + pre + ixoff(a);
    return 3 + pre;
}

/* a line of output */
void outline(char *s)
{
    char op[8], *a;
    int i, d, *p, sz;
    if (*s && *s != ' ') {
        /* a label (or F1 equ 2) */
        p = labslot(s);
        if (p && pass == 1)
            *p = pc;
    } else {
        a = s + 1;
        i = 0;
        while (*a && *a != ' ') {
            if (i < 7)
                op[i++] = *a;
            a++;
        }
        op[i] = 0;
        while (*a == ' ')
            a++;
        if (strcmp(op, "section") == 0)
            incode = strcmp(a, "code") == 0 || strcmp(a, "banked") == 0;
        else if (strcmp(op, "endsection") == 0)
            incode = 0;
        else if (incode) {
            sz = isize(op, a);
            if (pass == 2 && op[0] == 'l' && op[1] == 'b' && strcmp(op, "lbsr")) {
                p = labslot(a);
                if (p) {
                    d = *p - pc;
                    if (d >= -126 && d <= 129) {
                        s[1] = ' ';     /* " lbne L5" -> "  bne L5" */
                        s++;
                    }
                }
            }
            pc = pc + sz;
        }
    }
    if (pass == 2) {
        fputs(s, out);
        fputc('\n', out);
    }
}

/* the banked functions' stubs, in common code */
void stubs(void)
{
    int s;
    op1("section", "code");
    for (s = 0; s < nnames; s++)
        if (fnhere[s]) {
            osym(s);
            ot(" jsr __bcall\n");
            op1("fcb", "__bank");
            ot(" fdb B");
            osym(s);
            oc('\n');
        }
    op0("endsection");
    op1("import", "__bcall");
    op1("import", "__bank");
}

/* once through FILE.T */
void genfile(void)
{
    int i, n, lab;
    nlabel = 0;
    nnode = 0;
    pendjmp = 0;
    pc = 0;
    incode = 0;
    incodet = 0;
    for (i = 0; i < NHELP; i++)
        hused[i] = 0;
    in = openin(iname);
    while (rline()) {
        if (line[0] != '!') {
            copyline();
            continue;
        }
        if (line[1] == 'N') {
            rnode();
            continue;
        }
        if (line[1] == 'B') {
            banked = 1;
            continue;
        }
        lp = line + 2;
        n = rval();
        if (n < 0 || n >= nnode)
            fatal("Bad tree file");
        if (line[1] == 'G')
            gen(n);
        else if (line[1] == 'C') {
            lab = rval();
            gen_cond(n, lab, rval());
        } else
            fatal("Bad tree file");
        nnode = 0;
    }
    flushjmp();
    if (banked && pass == 2)
        stubs();
    for (i = 0; i < NHELP; i++)
        if (hused[i])
            op1("import", helpers[i]);
    fclose(in);
}

char oname[PATHSZ], nfile[PATHSZ];

int main(int argc, char **argv)
{
    char *o;
    int i;
    iname = 0;
    o = 0;
    for (i = 1; i < argc; i++) {
        if (!iname)
            iname = argv[i];
        else
            o = argv[i];
    }
    if (!iname) {
        putstr("Usage: GEN FILE.T [FILE.ASM]\n");
        return 1;
    }
#ifdef __MINI09__
    names = (char *)0x8000;
    lpos = (int *)(0x8000 + NAMESZ);
    mpos = lpos + MAXLAB;
    fnhere = (char *)(mpos + MAXMLAB);
    bank(3);
#else
    names = malloc(NAMESZ);
    lpos = malloc(MAXLAB * sizeof(int));
    mpos = malloc(MAXMLAB * sizeof(int));
    fnhere = malloc(MAXNAME);
#endif
    for (i = 0; i < MAXNAME; i++)
        fnhere[i] = 0;
    for (i = 0; i < MAXLAB; i++)
        lpos[i] = 0;
    for (i = 0; i < MAXMLAB; i++)
        mpos[i] = 0;
    rnames(outext(nfile, iname, ".n", ".N"));
    for (i = 0; i <= TY_ULONG; i++) {
        ty_kind[i] = i;
        ty_size[i] = i == TY_CHAR || i == TY_UCHAR || i == TY_VOID ? 1 : i >= TY_LONG ? 4 : 2;
    }
    ntypes = TY_ULONG + 1;
    if (!o)
        o = outext(oname, iname, ".asm", ".ASM");
    openout(o);
    pass = 1;
    genfile();
    if (errors)
        closeout();
    pass = 2;
    genfile();
    closeout();
    if (banked) {
        /* FILE.B, empty: tells CC.PRG to link with CRT0B.O */
        openout(outext(nfile, iname, ".b", ".B"));
        closeout();
    }
    return 0;
}
