/*
 * PARSE - the second pass of CC: the syntax.  See cc.md.
 *
 *     PARSE FILE.I [FILE.A]
 *
 * Reads what CPP wrote and checks it against C's grammar.  Writes the
 * tree file (cc.h has its format) for SEMA, and FILE.N, every name in
 * the order of its number, for SEMA's messages and GEN's output.
 *
 * The one thing PARSE must know about meaning is which names are
 * typedefs, to tell a declaration or a cast from an expression.
 */
#include "cc.h"
#define WANT_NAMES
#define WANT_LOOKUP
#define WANT_WFILE
#include "common.c"
#include "lex.c"

/* typedef names: the global ones, and a stack of names declared in the
   blocks that are open (a local can hide a typedef) */
char p_gtd[MAXNAME];
int p_lsym[MAXNAME];
int ps_name[MAXSCOPE], ps_prev[MAXSCOPE];
char ps_td[MAXSCOPE];
int nscope, infunc;
int wline, wfile;
char strtmp[STRSZ];

void pexpr(void);
void passign(void);
void pcond(void);
void punary(void);
int pdeclspec(void);
void pdeclarator(int *pname);
void pstmt(void);
void pblock(void);

void newname(int id)
{
    p_gtd[id] = 0;
    p_lsym[id] = -1;
}

/* a tag, with the line and file first if they have changed */
void wtag(int t)
{
    if (pragbank == 1) {
        wbyte(X_BANK);
        pragbank = 2;
    }
    if (src_name[0] != wfile) {
        wfile = src_name[0];
        wbyte(X_FILE);
        wnum(wfile);
    }
    if (tokline != wline) {
        wline = tokline;
        wbyte(X_LINE);
        wnum(wline);
    }
    wbyte(t);
}

int istypedef(int id)
{
    int l;
    l = p_lsym[id];
    if (l >= 0)
        return ps_td[l];
    return p_gtd[id];
}

/* id is declared here: as a typedef (td) or as something else */
void declare(int id, int td)
{
    int l;
    if (!infunc) {
        p_gtd[id] = td;
        return;
    }
    if (nscope >= MAXSCOPE)
        fatal("Too many locals");
    l = nscope++;
    ps_name[l] = id;
    ps_td[l] = td;
    ps_prev[l] = p_lsym[id];
    p_lsym[id] = l;
}

void popscope(int mark)
{
    while (nscope > mark) {
        nscope--;
        p_lsym[ps_name[nscope]] = ps_prev[nscope];
    }
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

/* ---- expressions: written postfix -------------------------------- */

/* adjacent strings, joined, into strtmp -> the length */
int pstrings(void)
{
    int len;
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
    return len;
}

void wstr(int t, int len)
{
    int i;
    wtag(t);
    wnum(len);
    for (i = 0; i < len; i++)
        wbyte(strtmp[i]);
}

void pprimary(void)
{
    if (tok == T_NUM) {
        wtag(A_NUM);
        wnum(toktype);
        wnum(tokval);
        next();
        return;
    }
    if (tok == T_STR) {
        wstr(A_STR, pstrings());
        return;
    }
    if (tok == T_IDENT) {
        wtag(A_IDENT);
        wnum(tokname);
        next();
        return;
    }
    if (tok == '(') {
        next();
        pexpr();
        expect(')');
        return;
    }
    error("Expression expected");
    if (tok != ';' && tok != '}' && tok != ')' && tok != T_EOF)
        next();
}

void ppostfix(void)
{
    int n;
    for (;;) {
        if (tok == '[') {
            next();
            pexpr();
            expect(']');
            wtag(A_INDEX);
        } else if (tok == '(') {
            next();
            n = 0;
            while (tok != ')' && tok != T_EOF) {
                passign();
                n++;
                if (tok != ',')
                    break;
                next();
            }
            expect(')');
            wtag(A_CALL);
            wnum(n);
        } else if (tok == '.' || tok == T_ARROW) {
            n = tok == T_ARROW;
            next();
            if (tok != T_IDENT)
                error("Member name expected");
            else {
                wtag(A_MEMBER);
                wnum(n);
                wnum(tokname);
                next();
            }
        } else if (tok == T_INC || tok == T_DEC) {
            wtag(A_INC);
            wnum(tok == T_INC ? 1 : -1);
            wnum(1);
            next();
        } else
            return;
    }
}

void ptypename(void)
{
    int id;
    pdeclspec();
    pdeclarator(&id);
    if (id >= 0)
        error("Unexpected name");
}

void punary(void)
{
    int t;
    t = tok;
    if (t == T_INC || t == T_DEC) {
        next();
        punary();
        wtag(A_INC);
        wnum(t == T_INC ? 1 : -1);
        wnum(0);
        return;
    }
    if (t == '&' || t == '*' || t == '!') {
        next();
        punary();
        wtag(t == '&' ? A_ADDR : t == '*' ? A_DEREF : A_NOT);
        return;
    }
    if (t == '-' || t == '+' || t == '~') {
        next();
        punary();
        wtag(A_UNARY);
        wnum(t);
        return;
    }
    if (t == K_SIZEOF) {
        next();
        if (tok == '(') {
            next();
            if (istypestart()) {
                wtag(A_SIZEOFT);
                ptypename();
                expect(')');
                return;
            }
            pexpr();
            expect(')');
            ppostfix();
        } else
            punary();
        wtag(A_SIZEOFE);
        return;
    }
    if (t == '(') {
        next();
        if (istypestart()) {
            wtag(A_CASTT);
            ptypename();
            expect(')');
            punary();
            wtag(A_CAST);
            return;
        }
        pexpr();
        expect(')');
        ppostfix();
        return;
    }
    pprimary();
    ppostfix();
}

void pbinary(int minp)
{
    int t, p;
    punary();
    for (;;) {
        t = tok;
        p = binprec(t);
        if (p == 0 || p < minp)
            return;
        next();
        pbinary(p + 1);
        wtag(A_BIN);
        wnum(tokbinop(t));
    }
}

void pcond(void)
{
    pbinary(1);
    if (tok != '?')
        return;
    next();
    pexpr();
    expect(':');
    pcond();
    wtag(A_COND);
}

void passign(void)
{
    int op;
    pcond();
    if (tok == '=') {
        next();
        passign();
        wtag(A_ASSIGN);
    } else if (tok == T_ASGN) {
        op = tokbinop(tokop);
        next();
        passign();
        wtag(A_ASGOP);
        wnum(op);
    }
}

void pexpr(void)
{
    passign();
    while (tok == ',') {
        next();
        passign();
        wtag(A_COMMA);
    }
}

/* a whole expression, or A_NONE if tok is end */
void pfull(int end)
{
    if (tok == end && end)
        wtag(A_NONE);
    else {
        pexpr();
        wtag(A_END);
    }
}

void pconst(void)
{
    pcond();
    wtag(A_END);
}

/* ---- declarations ------------------------------------------------ */

void pstruct(void)
{
    int isun, tag, id;
    isun = tok == K_UNION;
    next();
    tag = -1;
    if (tok == T_IDENT) {
        tag = tokname;
        next();
    }
    wtag(B_STRUCT);
    wnum(isun);
    wnum(tag);
    if (tok != '{') {
        if (tag < 0)
            error("Struct name expected");
        wnum(0);
        return;
    }
    wnum(1);
    next();
    while (tok != '}' && tok != T_EOF) {
        wtag(M_DECL);
        pdeclspec();
        for (;;) {
            wtag(M_ITEM);
            pdeclarator(&id);
            if (tok != ',')
                break;
            next();
        }
        wtag(M_DONE);
        expect(';');
    }
    expect('}');
    wtag(M_END);
}

void penum(void)
{
    int id;
    next();
    if (tok == T_IDENT)
        next();
    wtag(B_ENUM);
    if (tok != '{') {
        wnum(0);
        return;
    }
    wnum(1);
    next();
    while (tok == T_IDENT) {
        id = tokname;
        next();
        wtag(E_ITEM);
        wnum(id);
        if (tok == '=') {
            next();
            wnum(1);
            pconst();
        } else
            wnum(0);
        declare(id, 0);
        if (tok != ',')
            break;
        next();
    }
    wtag(E_END);
    expect('}');
}

/* DS, the struct, enum or typedef if there is one, then B_BASIC with
   the storage class and the basic type (0 if one came before) */
int pdeclspec(void)
{
    int sc, uns, sgn, lng, chr, base, any;
    sc = 0;
    uns = 0;
    sgn = 0;
    lng = 0;
    chr = 0;
    base = 0;
    any = 0;
    wtag(DS);
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
            pstruct();
            base = -1;
            continue;
        } else if (tok == K_ENUM) {
            penum();
            base = -1;
            continue;
        } else if (tok == T_IDENT && !base && !uns && !sgn && !lng && !chr && !any &&
                   istypedef(tokname)) {
            wtag(B_TYPEDEF);
            wnum(tokname);
            base = -1;
        } else
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
    wtag(B_BASIC);
    wnum(sc);
    wnum(base < 0 ? 0 : base);
    return sc;
}

void pfuncsuffix(void)
{
    int fl, id;
    fl = 0;
    if (tok == ')')
        fl = FN_NOPROTO;
    while (tok != ')' && tok != T_EOF) {
        if (tok == T_ELLIP) {
            next();
            fl = FN_VARARG;
            break;
        }
        wtag(P_PARAM);
        pdeclspec();
        pdeclarator(&id);
        if (tok != ',')
            break;
        next();
    }
    expect(')');
    wtag(P_END);
    wnum(fl);
}

void psuffixes(void)
{
    if (tok == '[') {
        next();
        wtag(S_ARRAY);
        if (tok != ']')
            pconst();
        else
            wtag(A_NONE);
        expect(']');
        psuffixes();
        return;
    }
    if (tok == '(') {
        next();
        wtag(S_FUNC);
        pfuncsuffix();
        return;
    }
    wtag(S_SEND);
}

void pdeclarator(int *pname)
{
    *pname = -1;
    while (tok == '*') {
        next();
        while (tok == K_CONST || tok == K_VOLATILE)
            next();
        wtag(D_PTR);
    }
    if (tok == '(') {
        next();
        if (tok == '*' || tok == '(' || (tok == T_IDENT && !istypedef(tokname))) {
            wtag(D_NEST);
            pdeclarator(pname);
            expect(')');
            psuffixes();
            return;
        }
        wtag(D_ANON);
        wtag(S_FUNC);
        pfuncsuffix();
        return;
    }
    if (tok == T_IDENT) {
        *pname = tokname;
        wtag(D_NAME);
        wnum(tokname);
        next();
    } else
        wtag(D_ANON);
    psuffixes();
}

void pinit(void)
{
    int len;
    if (tok == '{') {
        next();
        wtag(V_LIST);
        while (tok != '}' && tok != T_EOF) {
            pinit();
            if (tok != ',')
                break;
            next();
        }
        expect('}');
        wtag(V_LEND);
        return;
    }
    if (tok == T_STR) {
        len = pstrings();
        if (tok != ',' && tok != '}' && tok != ';')
            error("A string must be on its own here");
        wstr(V_STRING, len);
        return;
    }
    wtag(V_EXPR);
    passign();
    wtag(A_END);
}

/* a declaration, global or local */
void pdecl(void)
{
    int sc, id;
    wtag(DECL);
    sc = pdeclspec();
    while (tok != ';' && tok != T_EOF) {
        wtag(I_DECL);
        pdeclarator(&id);
        if (id < 0) {
            error("Name expected");
            break;
        }
        declare(id, sc == K_TYPEDEF);
        if (tok == '{') {
            if (infunc)
                error("A function inside a function");
            wtag(I_FUNC);
            infunc = 1;
            pblock();
            infunc = 0;
            popscope(0);
            wtag(I_END);
            return;
        }
        if (tok == '=') {
            next();
            wtag(I_INIT);
            pinit();
        } else
            wtag(I_NONE);
        if (tok != ',')
            break;
        next();
    }
    wtag(I_END);
    expect(';');
}

/* ---- statements -------------------------------------------------- */

void pblock(void)
{
    int mark;
    expect('{');
    wtag(S_BLOCK);
    mark = nscope;
    while (tok != '}' && tok != T_EOF) {
        if (isdeclstart())
            pdecl();
        else
            pstmt();
    }
    expect('}');
    wtag(S_BEND);
    popscope(mark);
}

void pstmt(void)
{
    int t;
    t = tok;
    if (t == '{') {
        pblock();
        return;
    }
    if (t == ';') {
        wtag(S_EMPTY);
        next();
        return;
    }
    if (t == K_IF || t == K_WHILE || t == K_SWITCH) {
        next();
        wtag(t == K_IF ? S_IF : t == K_WHILE ? S_WHILE : S_SWITCH);
        expect('(');
        pfull(0);
        expect(')');
        pstmt();
        if (t == K_IF) {
            if (tok == K_ELSE) {
                next();
                wtag(S_ELSE);
                pstmt();
            } else
                wtag(S_NOELSE);
        }
        return;
    }
    if (t == K_DO) {
        next();
        wtag(S_DO);
        pstmt();
        expect(K_WHILE);
        expect('(');
        pfull(0);
        expect(')');
        expect(';');
        return;
    }
    if (t == K_FOR) {
        next();
        expect('(');
        wtag(S_FOR);
        pfull(';');
        expect(';');
        pfull(';');
        expect(';');
        pfull(')');
        expect(')');
        pstmt();
        return;
    }
    if (t == K_CASE) {
        next();
        wtag(S_CASE);
        pconst();
        expect(':');
        pstmt();
        return;
    }
    if (t == K_DEFAULT) {
        next();
        expect(':');
        wtag(S_DEFAULT);
        pstmt();
        return;
    }
    if (t == K_BREAK || t == K_CONTINUE) {
        wtag(t == K_BREAK ? S_BREAK : S_CONT);
        next();
        expect(';');
        return;
    }
    if (t == K_RETURN) {
        next();
        wtag(S_RETURN);
        pfull(';');
        expect(';');
        return;
    }
    if (t == K_GOTO) {
        next();
        if (tok != T_IDENT)
            error("Label expected");
        else {
            wtag(S_GOTO);
            wnum(tokname);
            next();
        }
        expect(';');
        return;
    }
    if (t == T_IDENT) {
        skipsp();
        if (ch == ':') {
            wtag(S_LABEL);
            wnum(tokname);
            next();
            next();
            pstmt();
            return;
        }
    }
    wtag(S_EXPR);
    pfull(0);
    expect(';');
}

/* ---- main -------------------------------------------------------- */

char oname[PATHSZ];

int main(int argc, char **argv)
{
    char *in, *o;
    int i;
    in = 0;
    o = 0;
#ifdef __MINI09__
    names = (char *)0x8000;
    bank(3);
#else
    names = malloc(NAMESZ);
#endif
    for (i = 1; i < argc; i++) {
        if (!in)
            in = argv[i];
        else
            o = argv[i];
    }
    if (!in) {
        putstr("Usage: PARSE FILE.I [FILE.A]\n");
        return 1;
    }
    initnames();
    src_f[0] = fopen(in, "r");
    if (!src_f[0]) {
        putstr("Can't open ");
        putstr(in);
        putchar('\n');
        return 1;
    }
    src_line[0] = 1;
    src_name[0] = -1;           /* (its name isn't wanted in FILE.N) */
    firstname = in;
    src_pb[0] = -2;
    nsrc = 1;
    if (!o)
        o = outext(oname, in, ".a", ".A");
    openout(o);
    wfile = -1;
    nextch();
    bol = 1;
    next();
    while (tok != T_EOF) {
        if (tok == ';')
            next();
        else
            pdecl();
    }
    wtag(X_EOF);
    fclose(src_f[0]);
    closeout();
    /* the names, for SEMA and GEN */
    openout(outext(oname, o, ".n", ".N"));
    for (i = 0; i < nnames; i++) {
        fputs(name(i), out);
        fputc(0, out);
    }
    closeout();
    return 0;
}
