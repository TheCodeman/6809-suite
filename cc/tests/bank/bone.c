/* banked: calls the other banks, common code and LIBC */
#pragma bank
#include <stdio.h>
#include <string.h>

int two(int x);
int twice(int x);
extern int counter;

static int sq(int x)
{
    return x * x;
}

int one(int x)
{
    return sq(x) + two(x);      /* sq: in this bank; two: maybe not */
}

/* calls itself through the other bank and back */
int fibtwo(int n);

int fib(int n)
{
    if (n < 2)
        return n;
    return fibtwo(n - 1) + fibtwo(n - 2);
}

int apply(int (*f)(int), int x)
{
    return f(x) + 1;
}

int (*pickfn(int which))(int)
{
    if (which)
        return sq;
    return twice;
}

int filetest(char *name)
{
    FILE *f;
    char buf[40];
    int n;
    f = fopen(name, "w");
    if (!f)
        return -1;
    fprintf(f, "banked %d", 42);
    fclose(f);
    f = fopen(name, "r");
    if (!f)
        return -2;
    n = fread(buf, 1, sizeof buf - 1, f);
    fclose(f);
    buf[n] = 0;
    printf("read \"%s\"\n", buf);
    return strlen(buf);
}

static int keys[] = { 9, 3, 7, 1, 8 };

static int cmp(int a, int b)
{
    counter++;
    return a - b;
}

int sorted(void)
{
    int i, j, t, n;
    n = sizeof keys / sizeof keys[0];
    for (i = 1; i < n; i++)
        for (j = i; j > 0 && cmp(keys[j - 1], keys[j]) > 0; j--) {
            t = keys[j];
            keys[j] = keys[j - 1];
            keys[j - 1] = t;
        }
    t = 0;
    for (i = 0; i < n; i++)
        t = t * 10 + keys[i];
    return t;
}
