/*
 * CPP - the preprocessor, the first pass of CC.  See cc.md.
 *
 *     CPP FILE.C [FILE.I] [-I DIR]
 *
 * Reads the source with its #includes, expands macros, drops what #if
 * leaves out, and writes the tokens that are left as plain C, with
 * #line "file" marks so that later passes can name the right line.
 */
#include "cc.h"
#define WANT_NAMES
#define WANT_LOOKUP
#define WANT_PP
#include "common.c"
#include "lex.c"

int oline, ofile, obol;

void newname(int id)
{
    nm_mac[id] = -1;
}

void out1(int c)
{
    fputc(c, out);
}

void outs(char *s)
{
    while (*s)
        fputc(*s++, out);
}

/* v as an unsigned 32-bit number (a number token is never negative) */
void outn(long v)
{
    char b[12];
    int i;
    unsigned long u;
    u = v;
    u = u & 0xFFFFFFFF;
    i = 0;
    do {
        b[i++] = '0' + u % 10;
        u = u / 10;
    } while (u);
    while (i)
        out1(b[--i]);
}

/* a character of a string or character constant */
void outq(int c, int q)
{
    c = c & 255;
    if (c < 32 || c > 126 || c == q || c == '\\') {
        out1('\\');
        out1('0' + ((c >> 6) & 7));
        out1('0' + ((c >> 3) & 7));
        out1('0' + (c & 7));
    } else
        out1(c);
}

int curfileid(void)
{
    int i;
    for (i = nsrc - 1; i > 0; i--)
        if (src_f[i])
            break;
    return src_name[i];
}

/* the token in tok, on its line */
void outtok(void)
{
    int f, i, t;
    if (pragbank == 1) {
        if (!obol)
            out1('\n');
        outs("#pragma bank\n");
        pragbank = 2;
        ofile = -1;
        obol = 1;
    }
    f = curfileid();
    if (f != ofile || tokline < oline || tokline - oline > 8) {
        if (!obol)
            out1('\n');
        outs("#line ");
        outn(tokline);
        outs(" \"");
        outs(name(f));
        outs("\"\n");
        oline = tokline;
        ofile = f;
        obol = 1;
    }
    while (oline < tokline) {
        out1('\n');
        oline++;
        obol = 1;
    }
    if (!obol)
        out1(' ');
    obol = 0;
    t = tok;
    if (t == T_IDENT)
        outs(name(tokname));
    else if (t >= K_BASE)
        outs(kwords[t - K_BASE]);
    else if (t == T_NUM) {
        if (toktype == TI && tokval < 0) {
            out1('\'');
            outq(tokval, '\'');
            out1('\'');
        } else {
            outn(tokval);
            if (toktype == TUI || toktype == TUL)
                out1('U');
            if (toktype == TL || toktype == TUL)
                out1('L');
        }
    } else if (t == T_STR) {
        out1('"');
        for (i = 0; i < strn; i++)
            outq(strbuf[i], '"');
        out1('"');
    } else if (t == T_EQ)
        outs("==");
    else if (t == T_NE)
        outs("!=");
    else if (t == T_LE)
        outs("<=");
    else if (t == T_GE)
        outs(">=");
    else if (t == T_LAND)
        outs("&&");
    else if (t == T_LOR)
        outs("||");
    else if (t == T_SHL)
        outs("<<");
    else if (t == T_SHR)
        outs(">>");
    else if (t == T_INC)
        outs("++");
    else if (t == T_DEC)
        outs("--");
    else if (t == T_ARROW)
        outs("->");
    else if (t == T_ELLIP)
        outs("...");
    else if (t == T_ASGN) {
        if (tokop == T_SHL)
            outs("<<");
        else if (tokop == T_SHR)
            outs(">>");
        else
            out1(tokop);
        out1('=');
    } else
        out1(t);
}

char oname[PATHSZ];

int main(int argc, char **argv)
{
    char *in, *o;
    int i;
    char namebuf[1];
    in = 0;
    o = 0;
    incdir = "INCLUDE/";
#ifdef __MINI09__
    names = (char *)0x8000;
    mactext = names + NAMESZ;
    bank(3);
#else
    names = malloc(NAMESZ);
    mactext = malloc(MACSZ);
#endif
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-I") == 0 && i + 1 < argc)
            incdir = argv[++i];
        else if (!in)
            in = argv[i];
        else
            o = argv[i];
    }
    if (!in) {
        putstr("Usage: CPP FILE.C [FILE.I] [-I DIR/]\n");
        return 1;
    }
    initnames();
    predef("__MINI09__", "1");
    if (!o)
        o = outext(oname, in, ".i", ".I");
    if (!pushfile(in)) {
        putstr("Can't open ");
        putstr(in);
        putchar('\n');
        return 1;
    }
    openout(o);
    ofile = -1;
    obol = 1;
    nextch();
    bol = 1;
    next();
    while (tok != T_EOF) {
        outtok();
        next();
    }
    if (ifdepth)
        error("Missing #endif");
    if (!obol)
        out1('\n');
    closeout();
    return 0;
}
