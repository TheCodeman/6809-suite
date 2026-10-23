#include <stdio.h>

int g = 7;
unsigned ug = 40000;
char gc = -3;
unsigned char guc = 200;
long gl = 100000;
unsigned long gul = 3000000000;
int garr[5] = { 1, 2, 3, 4, 5 };

int sq(int x) { return x * x; }
long lsq(long x) { return x * x; }

int main(void)
{
    int a, b, c;
    unsigned u, v;
    char ch;
    unsigned char uc;
    long l, m;
    unsigned long ul;

    a = 1234; b = -56;
    printf("add %d sub %d mul %d div %d mod %d\n", a + b, a - b, a * b, a / b, a % b);
    printf("neg %d not %d cpl %d\n", -a, !a, ~a);
    printf("and %d or %d xor %d shl %d shr %d\n", a & 0xF0, a | 3, a ^ 0x55, a << 3, b >> 2);
    printf("rel %d %d %d %d %d %d\n", a < b, a > b, a <= 1234, a >= 1235, a == 1234, a != b);
    printf("log %d %d %d %d\n", a && b, a && 0, 0 || b, 0 || 0);
    u = 50000; v = 7;
    printf("u %u %u %u %u %u\n", u + v, u / v, u % v, u >> 4, u * 3);
    printf("urel %d %d\n", u > 1000, (int)u < 1000);
    ch = -100; uc = 250;
    printf("char %d %d %d %d\n", ch, uc, ch + uc, (char)(uc + 10));
    printf("globals %d %u %d %d %ld %lu\n", g, ug, gc, guc, gl, gul);
    l = 123456; m = -789;
    printf("long %ld %ld %ld %ld %ld\n", l + m, l - m, l * m, l / m, l % m);
    printf("long2 %ld %ld %ld %lx\n", l << 4, m >> 3, -l, l & 0xFF00FF);
    printf("lrel %d %d %d %d\n", l > m, l < m, l == 123456, m != -789);
    ul = 4000000000;
    printf("ulong %lu %lu %lu\n", ul / 3, ul % 1000, ul >> 8);
    l = a; m = b; ul = u;
    printf("widen %ld %ld %lu\n", l, m, ul);
    a = l; c = 70000L;
    printf("narrow %d %d\n", a, c);
    a = 10;
    a += 5; printf("%d ", a);
    a -= 3; printf("%d ", a);
    a *= 4; printf("%d ", a);
    a /= 5; printf("%d ", a);
    a %= 6; printf("%d ", a);
    a <<= 4; printf("%d ", a);
    a >>= 1; printf("%d ", a);
    a |= 1; printf("%d ", a);
    a &= 0x1C; printf("%d ", a);
    a ^= 0xFF; printf("%d\n", a);
    l = 5; l += 100000; l *= 3; l -= 1; l /= 7; printf("lasg %ld\n", l);
    a = 5;
    b = a++; c = ++a;
    printf("inc %d %d %d\n", a, b, c);
    b = a--; c = --a;
    printf("dec %d %d %d\n", a, b, c);
    l = 65535; l++; printf("linc %ld\n", l);
    printf("cond %d %d\n", a > 2 ? 10 : 20, a < 2 ? 10 : 20);
    printf("call %d %ld\n", sq(sq(3)), lsq(1000));
    printf("comma %d\n", (a = 3, a + 4));
    printf("arr %d %d\n", garr[2], garr[1] + garr[4]);
    printf("sizeof %d %d %d %d %d\n", (int)sizeof(char), (int)sizeof(int), (int)sizeof(long), (int)sizeof(garr), (int)sizeof(char *));
    printf("hex %x %X %o %08x\n", 0xBEEF, 0xBEEF, 8, 0x1234);
    printf("%5d|%-5d|%05d|%s|%10s|%-6s|%c\n", 42, 42, -42, "str", "right", "left", 'Z');
    printf("const %d %d %d\n", 3 + 4 * 5, (100 - 1) / 9, 1 << 10);
    printf("%d\n", 0x7FFF + 1 < 0);
    return 0;
}
