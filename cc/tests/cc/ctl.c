#include <stdio.h>

int classify(int n)
{
    switch (n) {
    case 0:
        return 100;
    case 1:
    case 2:
        return 200;
    case -5:
        return 300;
    case 1000:
        n = 7;
        break;
    default:
        return -1;
    }
    return n;
}

int fact(int n) { return n <= 1 ? 1 : n * fact(n - 1); }

static int counter;
static int bump(void) { return ++counter; }

int main(void)
{
    int i, j, s;
    s = 0;
    for (i = 0; i < 10; i++) {
        if (i == 3)
            continue;
        if (i == 8)
            break;
        s += i;
    }
    printf("for %d %d\n", s, i);
    i = 0; s = 0;
    while (i < 100) {
        i += 7;
        if (i % 2)
            continue;
        s++;
    }
    printf("while %d %d\n", i, s);
    i = 10;
    do {
        i--;
    } while (i > 5);
    printf("do %d\n", i);
    do i++; while (0);
    printf("do1 %d\n", i);
    for (i = 0; i < 3; i++)
        for (j = 0; j < 3; j++) {
            if (j == i)
                continue;
            printf("%d%d ", i, j);
        }
    printf("\n");
    printf("switch %d %d %d %d %d %d\n", classify(0), classify(1), classify(2),
           classify(-5), classify(1000), classify(9));
    s = 0;
    for (i = 0; i < 6; i++) {
        switch (i & 3) {
        case 0: s += 1;
        case 1: s += 10; break;
        case 2: { int k; k = 5; s += k * 100; } break;
        }
    }
    printf("fall %d\n", s);
    i = 0;
again:
    i++;
    if (i < 5)
        goto again;
    printf("goto %d\n", i);
    printf("fact %d\n", fact(7));
    for (;;) {
        if (bump() > 3)
            break;
    }
    printf("static %d\n", counter);
    s = 0;
    for (i = 0; i < 5 && s < 6; i++)
        s += i;
    printf("andcond %d %d\n", i, s);
    if (!(i == 4) || s > 100)
        printf("wrong\n");
    else
        printf("else ok\n");
    i = 3;
    if (i) if (i > 5) printf("x\n"); else printf("dangling ok\n");
    {
        int i;
        i = 99;
        printf("inner %d\n", i);
    }
    printf("outer %d\n", i);
    return 0;
}
