/* Banked code: main and a callback stay in common memory; bone.c,
   btwo.c and big.c are banked (#pragma bank).  tools/banktest.py builds
   it on the PC and with CC.PRG on MINI09, and runs it. */
#include <stdio.h>

int one(int x);
int two(int x);
long twolong(long x);
int fib(int n);
int apply(int (*f)(int), int x);
int (*pickfn(int which))(int);
int filetest(char *name);
int bigsum(int x);
int sorted(void);

int counter;
char *greeting = "common data";

/* called back from banked code */
int twice(int x)
{
    counter++;
    return 2 * x;
}

int main(int argc, char **argv)
{
    int (*f)(int);
    printf("%s\n", greeting);
    printf("one %d\n", one(5));
    printf("two %d\n", two(7));
    printf("long %ld\n", twolong(100000L));
    printf("fib %d\n", fib(15));
    printf("apply %d %d\n", apply(twice, 21), apply(two, 1));
    f = pickfn(1);
    printf("pick %d\n", f(10));
    f = pickfn(0);
    printf("pick %d\n", f(10));
    printf("file %d\n", filetest("BANK.TXT"));
    printf("big %d\n", bigsum(3));
    printf("sorted %d\n", sorted());
    printf("counter %d\n", counter);
    return 0;
}
