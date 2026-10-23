/* banked filler, made by tools/banktest.py --mkbig */
#pragma bank

int big0(int x);
int big1(int x);
int big2(int x);
int big3(int x);
int big4(int x);
int big5(int x);
int big6(int x);
int big7(int x);
int big8(int x);
int big9(int x);
int big10(int x);
int big11(int x);
int big12(int x);
int big13(int x);
int big14(int x);
int big15(int x);
int big16(int x);
int big17(int x);
int big18(int x);
int big19(int x);
int big20(int x);
int big21(int x);
int big22(int x);
int big23(int x);
int big24(int x);
int big25(int x);
int big26(int x);
int big27(int x);
int big28(int x);
int big29(int x);
int big30(int x);
int big31(int x);
int big32(int x);
int big33(int x);
int big34(int x);
int big35(int x);
int big36(int x);
int big37(int x);
int big38(int x);
int big39(int x);
int big40(int x);
int big41(int x);
int big42(int x);
int big43(int x);
int big44(int x);
int big45(int x);
int big46(int x);
int big47(int x);
int big48(int x);
int big49(int x);
int big50(int x);
int big51(int x);
int big52(int x);
int big53(int x);
int big54(int x);
int big55(int x);
int big56(int x);
int big57(int x);
int big58(int x);
int big59(int x);
int big60(int x);
int big61(int x);
int big62(int x);
int big63(int x);
int big64(int x);
int big65(int x);
int big66(int x);
int big67(int x);
int big68(int x);
int big69(int x);
int big70(int x);
int big71(int x);
int big72(int x);
int big73(int x);
int big74(int x);
int big75(int x);
int big76(int x);
int big77(int x);
int big78(int x);
int big79(int x);

int big40(int x)
{
    int a, b, i;
    a = x * 2 + 40;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 0 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 10);
        b = b * 3 + a % 7;
    }
    switch (a & 3) {
    case 0: b = b + 40;
        break;
    case 1: b = b - 40;
        break;
    case 2: b = b ^ 120;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big41(int x)
{
    int a, b, i;
    a = x * 3 + 41;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 1 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 11);
        b = b * 3 + a % 8;
    }
    switch (a & 3) {
    case 0: b = b + 41;
        break;
    case 1: b = b - 41;
        break;
    case 2: b = b ^ 123;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big42(int x)
{
    int a, b, i;
    a = x * 4 + 42;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 2 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 12);
        b = b * 3 + a % 2;
    }
    switch (a & 3) {
    case 0: b = b + 42;
        break;
    case 1: b = b - 42;
        break;
    case 2: b = b ^ 126;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big43(int x)
{
    int a, b, i;
    a = x * 5 + 43;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 3 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 13);
        b = b * 3 + a % 3;
    }
    switch (a & 3) {
    case 0: b = b + 43;
        break;
    case 1: b = b - 43;
        break;
    case 2: b = b ^ 129;
        break;
    default: b = ~b;
    }
    if (x > 0)
        b = b + big3(x - 1);
    return a + b;
}

int big44(int x)
{
    int a, b, i;
    a = x * 6 + 44;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 4 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 14);
        b = b * 3 + a % 4;
    }
    switch (a & 3) {
    case 0: b = b + 44;
        break;
    case 1: b = b - 44;
        break;
    case 2: b = b ^ 132;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big45(int x)
{
    int a, b, i;
    a = x * 7 + 45;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 0 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 15);
        b = b * 3 + a % 5;
    }
    switch (a & 3) {
    case 0: b = b + 45;
        break;
    case 1: b = b - 45;
        break;
    case 2: b = b ^ 135;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big46(int x)
{
    int a, b, i;
    a = x * 8 + 46;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 1 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 16);
        b = b * 3 + a % 6;
    }
    switch (a & 3) {
    case 0: b = b + 46;
        break;
    case 1: b = b - 46;
        break;
    case 2: b = b ^ 138;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big47(int x)
{
    int a, b, i;
    a = x * 9 + 47;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 2 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 17);
        b = b * 3 + a % 7;
    }
    switch (a & 3) {
    case 0: b = b + 47;
        break;
    case 1: b = b - 47;
        break;
    case 2: b = b ^ 141;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big48(int x)
{
    int a, b, i;
    a = x * 10 + 48;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 3 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 18);
        b = b * 3 + a % 8;
    }
    switch (a & 3) {
    case 0: b = b + 48;
        break;
    case 1: b = b - 48;
        break;
    case 2: b = b ^ 144;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big49(int x)
{
    int a, b, i;
    a = x * 11 + 49;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 4 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 19);
        b = b * 3 + a % 2;
    }
    switch (a & 3) {
    case 0: b = b + 49;
        break;
    case 1: b = b - 49;
        break;
    case 2: b = b ^ 147;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big50(int x)
{
    int a, b, i;
    a = x * 12 + 50;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 0 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 20);
        b = b * 3 + a % 3;
    }
    switch (a & 3) {
    case 0: b = b + 50;
        break;
    case 1: b = b - 50;
        break;
    case 2: b = b ^ 150;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big51(int x)
{
    int a, b, i;
    a = x * 13 + 51;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 1 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 21);
        b = b * 3 + a % 4;
    }
    switch (a & 3) {
    case 0: b = b + 51;
        break;
    case 1: b = b - 51;
        break;
    case 2: b = b ^ 153;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big52(int x)
{
    int a, b, i;
    a = x * 1 + 52;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 2 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 22);
        b = b * 3 + a % 5;
    }
    switch (a & 3) {
    case 0: b = b + 52;
        break;
    case 1: b = b - 52;
        break;
    case 2: b = b ^ 156;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big53(int x)
{
    int a, b, i;
    a = x * 2 + 53;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 3 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 23);
        b = b * 3 + a % 6;
    }
    switch (a & 3) {
    case 0: b = b + 53;
        break;
    case 1: b = b - 53;
        break;
    case 2: b = b ^ 159;
        break;
    default: b = ~b;
    }
    if (x > 0)
        b = b + big13(x - 1);
    return a + b;
}

int big54(int x)
{
    int a, b, i;
    a = x * 3 + 54;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 4 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 24);
        b = b * 3 + a % 7;
    }
    switch (a & 3) {
    case 0: b = b + 54;
        break;
    case 1: b = b - 54;
        break;
    case 2: b = b ^ 162;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big55(int x)
{
    int a, b, i;
    a = x * 4 + 55;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 0 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 25);
        b = b * 3 + a % 8;
    }
    switch (a & 3) {
    case 0: b = b + 55;
        break;
    case 1: b = b - 55;
        break;
    case 2: b = b ^ 165;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big56(int x)
{
    int a, b, i;
    a = x * 5 + 56;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 1 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 26);
        b = b * 3 + a % 2;
    }
    switch (a & 3) {
    case 0: b = b + 56;
        break;
    case 1: b = b - 56;
        break;
    case 2: b = b ^ 168;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big57(int x)
{
    int a, b, i;
    a = x * 6 + 57;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 2 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 27);
        b = b * 3 + a % 3;
    }
    switch (a & 3) {
    case 0: b = b + 57;
        break;
    case 1: b = b - 57;
        break;
    case 2: b = b ^ 171;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big58(int x)
{
    int a, b, i;
    a = x * 7 + 58;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 3 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 28);
        b = b * 3 + a % 4;
    }
    switch (a & 3) {
    case 0: b = b + 58;
        break;
    case 1: b = b - 58;
        break;
    case 2: b = b ^ 174;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big59(int x)
{
    int a, b, i;
    a = x * 8 + 59;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 4 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 29);
        b = b * 3 + a % 5;
    }
    switch (a & 3) {
    case 0: b = b + 59;
        break;
    case 1: b = b - 59;
        break;
    case 2: b = b ^ 177;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big60(int x)
{
    int a, b, i;
    a = x * 9 + 60;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 0 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 30);
        b = b * 3 + a % 6;
    }
    switch (a & 3) {
    case 0: b = b + 60;
        break;
    case 1: b = b - 60;
        break;
    case 2: b = b ^ 180;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big61(int x)
{
    int a, b, i;
    a = x * 10 + 61;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 1 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 31);
        b = b * 3 + a % 7;
    }
    switch (a & 3) {
    case 0: b = b + 61;
        break;
    case 1: b = b - 61;
        break;
    case 2: b = b ^ 183;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big62(int x)
{
    int a, b, i;
    a = x * 11 + 62;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 2 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 1);
        b = b * 3 + a % 8;
    }
    switch (a & 3) {
    case 0: b = b + 62;
        break;
    case 1: b = b - 62;
        break;
    case 2: b = b ^ 186;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big63(int x)
{
    int a, b, i;
    a = x * 12 + 63;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 3 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 2);
        b = b * 3 + a % 2;
    }
    switch (a & 3) {
    case 0: b = b + 63;
        break;
    case 1: b = b - 63;
        break;
    case 2: b = b ^ 189;
        break;
    default: b = ~b;
    }
    if (x > 0)
        b = b + big23(x - 1);
    return a + b;
}

int big64(int x)
{
    int a, b, i;
    a = x * 13 + 64;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 4 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 3);
        b = b * 3 + a % 3;
    }
    switch (a & 3) {
    case 0: b = b + 64;
        break;
    case 1: b = b - 64;
        break;
    case 2: b = b ^ 192;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big65(int x)
{
    int a, b, i;
    a = x * 1 + 65;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 0 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 4);
        b = b * 3 + a % 4;
    }
    switch (a & 3) {
    case 0: b = b + 65;
        break;
    case 1: b = b - 65;
        break;
    case 2: b = b ^ 195;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big66(int x)
{
    int a, b, i;
    a = x * 2 + 66;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 1 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 5);
        b = b * 3 + a % 5;
    }
    switch (a & 3) {
    case 0: b = b + 66;
        break;
    case 1: b = b - 66;
        break;
    case 2: b = b ^ 198;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big67(int x)
{
    int a, b, i;
    a = x * 3 + 67;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 2 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 6);
        b = b * 3 + a % 6;
    }
    switch (a & 3) {
    case 0: b = b + 67;
        break;
    case 1: b = b - 67;
        break;
    case 2: b = b ^ 201;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big68(int x)
{
    int a, b, i;
    a = x * 4 + 68;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 3 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 7);
        b = b * 3 + a % 7;
    }
    switch (a & 3) {
    case 0: b = b + 68;
        break;
    case 1: b = b - 68;
        break;
    case 2: b = b ^ 204;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big69(int x)
{
    int a, b, i;
    a = x * 5 + 69;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 4 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 8);
        b = b * 3 + a % 8;
    }
    switch (a & 3) {
    case 0: b = b + 69;
        break;
    case 1: b = b - 69;
        break;
    case 2: b = b ^ 207;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big70(int x)
{
    int a, b, i;
    a = x * 6 + 70;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 0 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 9);
        b = b * 3 + a % 2;
    }
    switch (a & 3) {
    case 0: b = b + 70;
        break;
    case 1: b = b - 70;
        break;
    case 2: b = b ^ 210;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big71(int x)
{
    int a, b, i;
    a = x * 7 + 71;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 1 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 10);
        b = b * 3 + a % 3;
    }
    switch (a & 3) {
    case 0: b = b + 71;
        break;
    case 1: b = b - 71;
        break;
    case 2: b = b ^ 213;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big72(int x)
{
    int a, b, i;
    a = x * 8 + 72;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 2 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 11);
        b = b * 3 + a % 4;
    }
    switch (a & 3) {
    case 0: b = b + 72;
        break;
    case 1: b = b - 72;
        break;
    case 2: b = b ^ 216;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big73(int x)
{
    int a, b, i;
    a = x * 9 + 73;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 3 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 12);
        b = b * 3 + a % 5;
    }
    switch (a & 3) {
    case 0: b = b + 73;
        break;
    case 1: b = b - 73;
        break;
    case 2: b = b ^ 219;
        break;
    default: b = ~b;
    }
    if (x > 0)
        b = b + big33(x - 1);
    return a + b;
}

int big74(int x)
{
    int a, b, i;
    a = x * 10 + 74;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 4 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 13);
        b = b * 3 + a % 6;
    }
    switch (a & 3) {
    case 0: b = b + 74;
        break;
    case 1: b = b - 74;
        break;
    case 2: b = b ^ 222;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big75(int x)
{
    int a, b, i;
    a = x * 11 + 75;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 0 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 14);
        b = b * 3 + a % 7;
    }
    switch (a & 3) {
    case 0: b = b + 75;
        break;
    case 1: b = b - 75;
        break;
    case 2: b = b ^ 225;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big76(int x)
{
    int a, b, i;
    a = x * 12 + 76;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 1 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 15);
        b = b * 3 + a % 8;
    }
    switch (a & 3) {
    case 0: b = b + 76;
        break;
    case 1: b = b - 76;
        break;
    case 2: b = b ^ 228;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big77(int x)
{
    int a, b, i;
    a = x * 13 + 77;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 2 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 16);
        b = b * 3 + a % 2;
    }
    switch (a & 3) {
    case 0: b = b + 77;
        break;
    case 1: b = b - 77;
        break;
    case 2: b = b ^ 231;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big78(int x)
{
    int a, b, i;
    a = x * 1 + 78;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 3 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 17);
        b = b * 3 + a % 3;
    }
    switch (a & 3) {
    case 0: b = b + 78;
        break;
    case 1: b = b - 78;
        break;
    case 2: b = b ^ 234;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big79(int x)
{
    int a, b, i;
    a = x * 2 + 79;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 4 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 18);
        b = b * 3 + a % 4;
    }
    switch (a & 3) {
    case 0: b = b + 79;
        break;
    case 1: b = b - 79;
        break;
    case 2: b = b ^ 237;
        break;
    default: b = ~b;
    }
    return a + b;
}
