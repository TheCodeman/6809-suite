/*
 * CLIB - the parts of the C library written in C: printf and friends,
 * fgets, atoi, malloc, ctype, rand.  Compiled by CC; link it before
 * LIBC.O: CRT0.O PROG.O CLIB.O LIBC.O.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

/* ---- printf ------------------------------------------------------- */

static FILE *pf_file;           /* where the output goes: a file, */
static char *pf_buf;            /* or a string if this isn't 0 */
static int pf_n;

static void pf_out(int c)
{
    if (pf_buf)
        *pf_buf++ = c;
    else
        fputc(c, pf_file);
    pf_n++;
}

static void pf_pad(int n, int c)
{
    while (n-- > 0)
        pf_out(c);
}

/* the digits of v, backwards, into buf -> how many */
static int pf_digits(char *buf, unsigned long v, int base, int upper)
{
    int n, d;
    n = 0;
    do {
        d = v % base;
        buf[n++] = d < 10 ? '0' + d : (upper ? 'A' : 'a') + d - 10;
        v = v / base;
    } while (v);
    return n;
}

static int pf_format(char *fmt, va_list ap)
{
    char buf[12];
    char *s;
    int c, left, zero, width, prec, isl, neg, n, base, i;
    unsigned long v;
    long sv;
    pf_n = 0;
    while ((c = *fmt++) != 0) {
        if (c != '%') {
            pf_out(c);
            continue;
        }
        left = zero = 0;
        for (;;) {
            if (*fmt == '-')
                left = 1;
            else if (*fmt == '0')
                zero = 1;
            else
                break;
            fmt++;
        }
        width = 0;
        if (*fmt == '*') {
            width = va_arg(ap, int);
            fmt++;
        } else
            while (*fmt >= '0' && *fmt <= '9')
                width = width * 10 + *fmt++ - '0';
        prec = -1;
        if (*fmt == '.') {
            fmt++;
            prec = 0;
            if (*fmt == '*') {
                prec = va_arg(ap, int);
                fmt++;
            } else
                while (*fmt >= '0' && *fmt <= '9')
                    prec = prec * 10 + *fmt++ - '0';
        }
        isl = 0;
        if (*fmt == 'l') {
            isl = 1;
            fmt++;
        }
        c = *fmt++;
        if (c == 0)
            break;
        neg = 0;
        base = 0;
        if (c == 'd' || c == 'i') {
            if (isl)
                sv = va_arg(ap, long);
            else
                sv = va_arg(ap, int);
            if (sv < 0) {
                neg = 1;
                sv = -sv;
            }
            v = sv;
            base = 10;
        } else if (c == 'u' || c == 'x' || c == 'X' || c == 'o') {
            if (isl)
                v = va_arg(ap, unsigned long);
            else
                v = va_arg(ap, unsigned);
            base = c == 'u' ? 10 : c == 'o' ? 8 : 16;
        } else if (c == 'c') {
            buf[0] = va_arg(ap, int);
            s = buf;
            n = 1;
        } else if (c == 's') {
            s = va_arg(ap, char *);
            if (!s)
                s = "(null)";
            n = strlen(s);
            if (prec >= 0 && n > prec)
                n = prec;
        } else {
            pf_out(c);
            continue;
        }
        if (base) {
            n = pf_digits(buf, v, base, c == 'X');
            width = width - neg;
            if (left || !zero)
                pf_pad(left ? 0 : width - n, ' ');
            if (neg)
                pf_out('-');
            if (zero && !left)
                pf_pad(width - n, '0');
            for (i = n; i > 0; i--)
                pf_out(buf[i - 1]);
            if (left)
                pf_pad(width - n, ' ');
        } else {
            if (!left)
                pf_pad(width - n, ' ');
            for (i = 0; i < n; i++)
                pf_out(s[i]);
            if (left)
                pf_pad(width - n, ' ');
        }
    }
    return pf_n;
}

int printf(char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    pf_file = stdout;
    pf_buf = 0;
    return pf_format(fmt, ap);
}

int fprintf(FILE *f, char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    pf_file = f;
    pf_buf = 0;
    return pf_format(fmt, ap);
}

int sprintf(char *s, char *fmt, ...)
{
    va_list ap;
    int n;
    va_start(ap, fmt);
    pf_buf = s;
    n = pf_format(fmt, ap);
    *pf_buf = 0;
    pf_buf = 0;
    return n;
}

/* ---- stdio -------------------------------------------------------- */

char *fgets(char *s, int n, FILE *f)
{
    int c, i;
    i = 0;
    while (i < n - 1) {
        c = fgetc(f);
        if (c == EOF)
            break;
        s[i++] = c;
        if (c == '\n')
            break;
    }
    if (i == 0)
        return 0;
    s[i] = 0;
    return s;
}

/* ---- stdlib ------------------------------------------------------- */

long atol(char *s)
{
    long v;
    int neg;
    while (*s == ' ' || *s == '\t')
        s++;
    neg = 0;
    if (*s == '-') {
        neg = 1;
        s++;
    } else if (*s == '+')
        s++;
    v = 0;
    while (*s >= '0' && *s <= '9')
        v = v * 10 + *s++ - '0';
    return neg ? -v : v;
}

int atoi(char *s)
{
    return atol(s);
}

int abs(int n)
{
    return n < 0 ? -n : n;
}

long labs(long n)
{
    return n < 0 ? -n : n;
}

static unsigned long rnd = 1;

int rand(void)
{
    rnd = rnd * 1103515245 + 12345;
    return (rnd >> 16) & 32767;
}

void srand(unsigned seed)
{
    rnd = seed;
}

/*
 * malloc: first fit from a list of free blocks, kept in address order so
 * that neighbours join again.  Each block starts with its size in bytes
 * (header included); a free one has the next free block after that.  The
 * heap is the RAM from the end of the program (_heap, set by CRT0) up to
 * $7FFF.
 */
extern char *_heap;
static unsigned *freelist;
static int heapinit;

void *malloc(size_t n)
{
    unsigned *p, *q, *prev;
    if (!heapinit) {
        heapinit = 1;
        freelist = (unsigned *)_heap;
        freelist[0] = 0x8000 - (unsigned)_heap;
        freelist[1] = 0;
    }
    n = (n + 3) & ~1;           /* the size word, and room for a link */
    if (n < 4)
        return 0;               /* (n was close to 65536) */
    prev = 0;
    for (p = freelist; p; p = (unsigned *)p[1]) {
        if (p[0] >= n) {
            if (p[0] - n >= 6) {        /* split: the end is handed out */
                p[0] -= n;
                q = (unsigned *)((char *)p + p[0]);
                q[0] = n;
                return q + 1;
            }
            if (prev)
                prev[1] = p[1];
            else
                freelist = (unsigned *)p[1];
            return p + 1;
        }
        prev = p;
    }
    return 0;
}

void *calloc(size_t n, size_t size)
{
    char *p;
    p = malloc(n * size);
    if (p)
        memset(p, 0, n * size);
    return p;
}

void free(void *ptr)
{
    unsigned *b, *p, *prev;
    if (!ptr)
        return;
    b = (unsigned *)ptr - 1;
    prev = 0;
    for (p = freelist; p && p < b; p = (unsigned *)p[1])
        prev = p;
    b[1] = (unsigned)p;
    if (p && (char *)b + b[0] == (char *)p) {   /* join the next */
        b[0] += p[0];
        b[1] = p[1];
    }
    if (prev) {
        prev[1] = (unsigned)b;
        if ((char *)prev + prev[0] == (char *)b) {  /* join the previous */
            prev[0] += b[0];
            prev[1] = b[1];
        }
    } else
        freelist = b;
}

/* ---- ctype -------------------------------------------------------- */

int isdigit(int c) { return c >= '0' && c <= '9'; }
int isupper(int c) { return c >= 'A' && c <= 'Z'; }
int islower(int c) { return c >= 'a' && c <= 'z'; }
int isalpha(int c) { return isupper(c) || islower(c); }
int isalnum(int c) { return isalpha(c) || isdigit(c); }
int isxdigit(int c) { return isdigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); }
int isspace(int c) { return c == ' ' || (c >= 9 && c <= 13); }
int isprint(int c) { return c >= 32 && c < 127; }
int iscntrl(int c) { return (c >= 0 && c < 32) || c == 127; }
int ispunct(int c) { return isprint(c) && c != ' ' && !isalnum(c); }
int toupper(int c) { return islower(c) ? c - 32 : c; }
int tolower(int c) { return isupper(c) ? c + 32 : c; }
