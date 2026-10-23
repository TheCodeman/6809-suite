/*
 * common.c - the parts more than one pass needs.  A pass includes cc.h,
 * says which parts it wants (WANT_NAMES, WANT_OUT, WANT_RFILE,
 * WANT_WFILE), defines curfile() and keeps tokline, then includes this.
 */

FILE *out;
char *outname;
int errors;
int tokline;
char *curfile(void);

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
    unsigned long u;
    u = v;
    if (v < 0) {
        putchar('-');
        u = -v;                 /* (right for -2147483648 too) */
    }
    i = 0;
    do {
        b[i++] = '0' + u % 10;
        u = u / 10;
    } while (u);
    while (i)
        putchar(b[--i]);
}

/* the output is no good: remove it and stop */
void giveup(void)
{
    if (out) {
        fclose(out);
        remove(outname);
    }
    exit(1);
}

void error2(char *msg, char *arg)
{
    putstr(curfile());
    putchar(':');
    putnum(tokline);
    putstr(": ");
    putstr(msg);
    if (arg)
        putstr(arg);
    putchar('\n');
    if (++errors >= 20) {
        putstr("Too many errors\n");
        giveup();
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

/* name with its extension (from the last '.') changed to ext; in buf */
char *newext(char *buf, char *name, char *ext)
{
    int i, n;
    n = strlen(name);
    if (n > PATHSZ - 6)
        n = PATHSZ - 6;
    memcpy(buf, name, n);
    buf[n] = 0;
    for (i = n; i > 0 && buf[i - 1] != '.' && buf[i - 1] != '/'; i--)
        ;
    if (i > 0 && buf[i - 1] == '.')
        buf[i - 1] = 0;
    strcat(buf, ext);
    return buf;
}

/* name with its extension changed to lo, or to up if name's extension
   is in capitals (FILE.C -> FILE.I, file.c -> file.i); in buf */
char *outext(char *buf, char *name, char *lo, char *up)
{
    char *p;
    p = strrchr(name, '.');
    if (p && p[1] >= 'A' && p[1] <= 'Z')
        return newext(buf, name, up);
    return newext(buf, name, lo);
}

/* open out for writing, or stop */
void openout(char *name)
{
    outname = name;
    out = fopen(name, "w");
    if (!out) {
        putstr("Can't write ");
        putstr(name);
        putchar('\n');
        exit(1);
    }
}

/* close the output; with errors, remove it and stop */
void closeout(void)
{
    fclose(out);
    if (errors) {
        remove(outname);
        putnum(errors);
        putstr(" error(s), no output written\n");
        exit(1);
    }
    out = 0;
}

#ifdef WANT_NAMES
/* ---- names ------------------------------------------------------- */

char *names;
int nnamech, nnames;
int nm_off[MAXNAME];

char *name(int id)
{
    return names + nm_off[id];
}

#ifdef WANT_LOOKUP
int nm_next[MAXNAME], nm_head[NHASH];
void newname(int id);           /* the pass sets up its own tables */

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
    newname(nnames);
    return nnames++;
}

void initnames(void)
{
    int i;
    for (i = 0; i < NHASH; i++)
        nm_head[i] = -1;
    for (i = 0; kwords[i]; i++)
        lookup(kwords[i]);
}
#endif
#endif

#ifdef WANT_RFILE
/* ---- reading the tree file or the names ------------------------- */

FILE *in;

/* a number, as wnum wrote it */
long rnum(void)
{
    int c;
    long v;
    c = fgetc(in);
    if (c < 0xF0)
        return c;
    if (c == 0xF0) {
        v = fgetc(in);
        v = (v << 8) | fgetc(in);
        if (v > 32767)
            v = v - 65536;
        return v;
    }
    v = fgetc(in);
    v = (v << 8) | fgetc(in);
    v = (v << 8) | fgetc(in);
    v = (v << 8) | fgetc(in);
    return tr32(v);
}

FILE *openin(char *name)
{
    FILE *f;
    f = fopen(name, "r");
    if (!f) {
        putstr("Can't open ");
        putstr(name);
        putchar('\n');
        exit(1);
    }
    return f;
}
#endif

#ifdef WANT_WFILE
/* ---- writing the tree file --------------------------------------- */

void wbyte(int c)
{
    fputc(c, out);
}

void wnum(long v)
{
    v = tr32(v);
    if (v >= 0 && v < 0xF0)
        wbyte(v);
    else if (v >= -32768 && v <= 32767) {
        wbyte(0xF0);
        wbyte((v >> 8) & 255);
        wbyte(v & 255);
    } else {
        wbyte(0xF1);
        wbyte((v >> 24) & 255);
        wbyte((v >> 16) & 255);
        wbyte((v >> 8) & 255);
        wbyte(v & 255);
    }
}
#endif

#ifdef WANT_OUT
/* ---- assembler output -------------------------------------------- */

void onum(long v);

#ifdef LINE_OUT
/* the pass takes the output a line at a time: outline() */
char obuf[STRSZ];
int obn;
void outline(char *s);

void putout(int c)
{
    if (c == '\n') {
        obuf[obn] = 0;
        obn = 0;
        outline(obuf);
    } else if (obn < STRSZ - 1)
        obuf[obn++] = c;
}

void putsout(char *s)
{
    while (*s)
        putout(*s++);
}
#else
#define putout(c) fputc(c, out)
#define putsout(s) fputs(s, out)
#endif

/* A jump waits in pendjmp until something else is written, so that one
   to the label right after it can be dropped. */
int pendjmp;

void olab(int l);

void flushjmp(void)
{
    int l;
    l = pendjmp;
    pendjmp = 0;
    if (l) {
        putsout(" lbra ");
        olab(l);
        putout('\n');
    }
}

void ot(char *s)
{
    if (pendjmp)
        flushjmp();
    putsout(s);
}

void oc(int c)
{
    if (pendjmp)
        flushjmp();
    putout(c);
}

void onum(long v)
{
    char b[12];
    int i;
    unsigned long u;
    u = v;
    if (v < 0) {
        oc('-');
        u = -v;                 /* (right for -2147483648 too) */
    }
    i = 0;
    do {
        b[i++] = '0' + u % 10;
        u = u / 10;
    } while (u);
    while (i)
        oc(b[--i]);
}

/* SEMA's labels are L1, L2 ...; GEN's are negative, M1, M2 ... */
void olab(int l)
{
    if (l < 0) {
        oc('M');
        onum(-l);
    } else {
        oc('L');
        onum(l);
    }
}

void label(int l)
{
    if (pendjmp == l)
        pendjmp = 0;
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
    if (pendjmp)
        flushjmp();
    pendjmp = l;
}
#endif
