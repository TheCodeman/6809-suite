/*
 * lex.c - the input and the lexer, for CPP (WANT_PP: with macros,
 * #include and #if) and PARSE (which only sees #line).
 */

FILE *src_f[MAXSRC];
int src_line[MAXSRC], src_name[MAXSRC], src_pb[MAXSRC];
int nsrc;
int lastfile;                   /* CPP: the file the last #line named */

int ch, tok, toktype, tokname, tokop, bol;
int pragbank;                   /* #pragma bank: 1 once seen, 2 once passed on */
long tokval;
char strbuf[STRSZ];
int strn;

#ifdef WANT_PP
char *src_p[MAXSRC];
int src_mac[MAXSRC], src_mark[MAXSRC];
char expbuf[EXPSZ];
int expend;
char argbuf[ARGSZ];
char *mactext;
int nm_mac[MAXNAME];
int mac_off[MAXMAC], mac_np[MAXMAC];
char mac_busy[MAXMAC];
int nmac, macend;
char iftaken[MAXIF];
int ifdepth;
int pp_line, pp_if;
char *incdir;
int expand(int m);
long ppcond(void);
#endif

void next(void);

int curline(void)
{
    int i;
    for (i = nsrc - 1; i > 0; i--)
        if (src_f[i])
            break;
    return src_line[i];
}

char *firstname;                /* PARSE's input, until a #line names a file */

char *curfile(void)
{
    int i;
    for (i = nsrc - 1; i > 0; i--)
        if (src_f[i])
            break;
    if (src_name[i] < 0)
        return firstname;
    return name(src_name[i]);
}

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
#ifdef WANT_PP
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
#endif
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
    lastfile = -1;
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

#ifdef WANT_PP
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
/* ---- #if expressions -------------------------------------------- */

int ppprec(int t)
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

long ppunary(void)
{
    int t;
    long v;
    t = tok;
    if (t == '-' || t == '+' || t == '~' || t == '!') {
        next();
        v = ppunary();
        if (t == '-')
            return tr32(-v);
        if (t == '~')
            return tr32(~v);
        if (t == '!')
            return !v;
        return v;
    }
    if (t == T_NUM) {
        v = tokval;
        next();
        return v;
    }
    if (t == '(') {
        next();
        v = ppcond();
        if (tok == ')')
            next();
        else
            error("Bad #if");
        return v;
    }
    error("Bad #if");
    return 0;
}

long ppbin(int minp)
{
    long a, b;
    int t, p;
    a = ppunary();
    for (;;) {
        t = tok;
        p = ppprec(t);
        if (p == 0 || p < minp)
            return a;
        next();
        b = ppbin(p + 1);
        if (t == '*')
            a = tr32(a) * tr32(b);
        else if (t == '/' || t == '%') {
            if (b == 0) {
                error("Division by zero");
                a = 0;
            } else if (t == '/')
                a = a / b;
            else
                a = a % b;
        } else if (t == '+')
            a = a + b;
        else if (t == '-')
            a = a - b;
        else if (t == T_SHL)
            a = b > 31 ? 0 : tr32(a) << b;
        else if (t == T_SHR)
            a = a >> (b > 31 ? 31 : b);
        else if (t == '<')
            a = a < b;
        else if (t == '>')
            a = a > b;
        else if (t == T_LE)
            a = a <= b;
        else if (t == T_GE)
            a = a >= b;
        else if (t == T_EQ)
            a = a == b;
        else if (t == T_NE)
            a = a != b;
        else if (t == '&')
            a = a & b;
        else if (t == '^')
            a = a ^ b;
        else if (t == '|')
            a = a | b;
        else if (t == T_LAND)
            a = a && b;
        else
            a = a || b;
        a = tr32(a);
    }
}

long ppcond(void)
{
    long c, a, b;
    c = ppbin(1);
    if (tok != '?')
        return c;
    next();
    a = ppcond();
    if (tok == ':')
        next();
    else
        error("Bad #if");
    b = ppcond();
    return c ? a : b;
}

int pp_eval(void)
{
    long v;
    pp_line = 1;
    pp_if = 1;
    next();
    v = ppcond();
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
    else if (strcmp(strbuf, "pragma") == 0) {
        skipsp();
        if (isid1(ch)) {
            readident();
            if (strcmp(strbuf, "bank") == 0 && !pragbank)
                pragbank = 1;
        }
    }
    skipline();
}
#else
/* PARSE: #line N "file", from CPP; the next line is line N */
void directive(void)
{
    int n;
    skipsp();
    readident();
    if (strcmp(strbuf, "pragma") == 0) {
        skipsp();
        readident();
        if (strcmp(strbuf, "bank") == 0)
            pragbank = 1;
        skipline();
        return;
    }
    if (strcmp(strbuf, "line") != 0) {
        error("Unexpected #");
        skipline();
        return;
    }
    skipsp();
    n = 0;
    while (isdig(ch)) {
        n = n * 10 + ch - '0';
        nextch();
    }
    skipsp();
    if (ch == '"') {
        nextch();
        strn = 0;
        while (ch != '"' && ch != '\n' && ch != EOF) {
            if (strn < STRSZ - 1)
                strbuf[strn++] = ch;
            nextch();
        }
        strbuf[strn] = 0;
        src_name[0] = lookup(strbuf);
    }
    skipline();
    src_line[0] = n - 1;
}
#endif

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
#ifdef WANT_PP
                if (pp_line) {
                    tok = T_EOL;
                    return;
                }
#endif
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
#ifdef WANT_PP
        if (ch == '#' && bol && src_f[nsrc - 1]) {
#else
        if (ch == '#' && bol) {
#endif
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
#ifdef WANT_PP
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
#endif
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

#ifndef WANT_PP
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
#endif
