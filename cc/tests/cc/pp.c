#include <stdio.h>
#define N 10
#define SQ(x) ((x) * (x))
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define STR "macro string"
#define EMPTY
#define TWICE(f, v) f(f(v))
#define NEG -
#if N > 5 && defined(SQ)
int big = 1;
#else
int big = 0;
#endif
#ifdef NOPE
#error should not see this
#elif N == 10
int ten = 1;
#else
int ten = 0;
#endif
#ifndef N
int bad;
#endif
#if 0
this is not C at all '
#if 1
#endif
#endif
#undef N
#define N 20

int main(void)
{
    int a;
    a = 3;
    printf("%d %d %d %d\n", N, SQ(a + 1), MAX(a, 7), TWICE(SQ, 2));
    printf("%s %d %d EMPTY\n", STR, big, ten EMPTY);
    printf("%d\n", NEG N);
    /* comment with "quotes" and 'x' */ // line comment
    printf("chars %d %d %d %d %d\n", '\n', '\0', '\\', '\x41', '\101');
    printf("tab[\t] q[\"] %c\n", '\'');
    printf("concat " "strings\n");
#if MAX(1, 2) == 2
    printf("if-macro ok\n");
#endif
    printf("line %d\n", __LINE__);
    return 0;
}
