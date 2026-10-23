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

int big0(int x)
{
    int a, b, i;
    a = x * 1 + 0;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 0 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 1);
        b = b * 3 + a % 2;
    }
    switch (a & 3) {
    case 0: b = b + 0;
        break;
    case 1: b = b - 0;
        break;
    case 2: b = b ^ 0;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big1(int x)
{
    int a, b, i;
    a = x * 2 + 1;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 1 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 2);
        b = b * 3 + a % 3;
    }
    switch (a & 3) {
    case 0: b = b + 1;
        break;
    case 1: b = b - 1;
        break;
    case 2: b = b ^ 3;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big2(int x)
{
    int a, b, i;
    a = x * 3 + 2;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 2 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 3);
        b = b * 3 + a % 4;
    }
    switch (a & 3) {
    case 0: b = b + 2;
        break;
    case 1: b = b - 2;
        break;
    case 2: b = b ^ 6;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big3(int x)
{
    int a, b, i;
    a = x * 4 + 3;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 3 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 4);
        b = b * 3 + a % 5;
    }
    switch (a & 3) {
    case 0: b = b + 3;
        break;
    case 1: b = b - 3;
        break;
    case 2: b = b ^ 9;
        break;
    default: b = ~b;
    }
    if (x > 0)
        b = b + big43(x - 1);
    return a + b;
}

int big4(int x)
{
    int a, b, i;
    a = x * 5 + 4;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 4 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 5);
        b = b * 3 + a % 6;
    }
    switch (a & 3) {
    case 0: b = b + 4;
        break;
    case 1: b = b - 4;
        break;
    case 2: b = b ^ 12;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big5(int x)
{
    int a, b, i;
    a = x * 6 + 5;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 0 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 6);
        b = b * 3 + a % 7;
    }
    switch (a & 3) {
    case 0: b = b + 5;
        break;
    case 1: b = b - 5;
        break;
    case 2: b = b ^ 15;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big6(int x)
{
    int a, b, i;
    a = x * 7 + 6;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 1 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 7);
        b = b * 3 + a % 8;
    }
    switch (a & 3) {
    case 0: b = b + 6;
        break;
    case 1: b = b - 6;
        break;
    case 2: b = b ^ 18;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big7(int x)
{
    int a, b, i;
    a = x * 8 + 7;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 2 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 8);
        b = b * 3 + a % 2;
    }
    switch (a & 3) {
    case 0: b = b + 7;
        break;
    case 1: b = b - 7;
        break;
    case 2: b = b ^ 21;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big8(int x)
{
    int a, b, i;
    a = x * 9 + 8;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 3 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 9);
        b = b * 3 + a % 3;
    }
    switch (a & 3) {
    case 0: b = b + 8;
        break;
    case 1: b = b - 8;
        break;
    case 2: b = b ^ 24;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big9(int x)
{
    int a, b, i;
    a = x * 10 + 9;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 4 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 10);
        b = b * 3 + a % 4;
    }
    switch (a & 3) {
    case 0: b = b + 9;
        break;
    case 1: b = b - 9;
        break;
    case 2: b = b ^ 27;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big10(int x)
{
    int a, b, i;
    a = x * 11 + 10;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 0 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 11);
        b = b * 3 + a % 5;
    }
    switch (a & 3) {
    case 0: b = b + 10;
        break;
    case 1: b = b - 10;
        break;
    case 2: b = b ^ 30;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big11(int x)
{
    int a, b, i;
    a = x * 12 + 11;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 1 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 12);
        b = b * 3 + a % 6;
    }
    switch (a & 3) {
    case 0: b = b + 11;
        break;
    case 1: b = b - 11;
        break;
    case 2: b = b ^ 33;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big12(int x)
{
    int a, b, i;
    a = x * 13 + 12;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 2 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 13);
        b = b * 3 + a % 7;
    }
    switch (a & 3) {
    case 0: b = b + 12;
        break;
    case 1: b = b - 12;
        break;
    case 2: b = b ^ 36;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big13(int x)
{
    int a, b, i;
    a = x * 1 + 13;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 3 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 14);
        b = b * 3 + a % 8;
    }
    switch (a & 3) {
    case 0: b = b + 13;
        break;
    case 1: b = b - 13;
        break;
    case 2: b = b ^ 39;
        break;
    default: b = ~b;
    }
    if (x > 0)
        b = b + big53(x - 1);
    return a + b;
}

int big14(int x)
{
    int a, b, i;
    a = x * 2 + 14;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 4 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 15);
        b = b * 3 + a % 2;
    }
    switch (a & 3) {
    case 0: b = b + 14;
        break;
    case 1: b = b - 14;
        break;
    case 2: b = b ^ 42;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big15(int x)
{
    int a, b, i;
    a = x * 3 + 15;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 0 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 16);
        b = b * 3 + a % 3;
    }
    switch (a & 3) {
    case 0: b = b + 15;
        break;
    case 1: b = b - 15;
        break;
    case 2: b = b ^ 45;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big16(int x)
{
    int a, b, i;
    a = x * 4 + 16;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 1 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 17);
        b = b * 3 + a % 4;
    }
    switch (a & 3) {
    case 0: b = b + 16;
        break;
    case 1: b = b - 16;
        break;
    case 2: b = b ^ 48;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big17(int x)
{
    int a, b, i;
    a = x * 5 + 17;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 2 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 18);
        b = b * 3 + a % 5;
    }
    switch (a & 3) {
    case 0: b = b + 17;
        break;
    case 1: b = b - 17;
        break;
    case 2: b = b ^ 51;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big18(int x)
{
    int a, b, i;
    a = x * 6 + 18;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 3 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 19);
        b = b * 3 + a % 6;
    }
    switch (a & 3) {
    case 0: b = b + 18;
        break;
    case 1: b = b - 18;
        break;
    case 2: b = b ^ 54;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big19(int x)
{
    int a, b, i;
    a = x * 7 + 19;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 4 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 20);
        b = b * 3 + a % 7;
    }
    switch (a & 3) {
    case 0: b = b + 19;
        break;
    case 1: b = b - 19;
        break;
    case 2: b = b ^ 57;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big20(int x)
{
    int a, b, i;
    a = x * 8 + 20;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 0 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 21);
        b = b * 3 + a % 8;
    }
    switch (a & 3) {
    case 0: b = b + 20;
        break;
    case 1: b = b - 20;
        break;
    case 2: b = b ^ 60;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big21(int x)
{
    int a, b, i;
    a = x * 9 + 21;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 1 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 22);
        b = b * 3 + a % 2;
    }
    switch (a & 3) {
    case 0: b = b + 21;
        break;
    case 1: b = b - 21;
        break;
    case 2: b = b ^ 63;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big22(int x)
{
    int a, b, i;
    a = x * 10 + 22;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 2 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 23);
        b = b * 3 + a % 3;
    }
    switch (a & 3) {
    case 0: b = b + 22;
        break;
    case 1: b = b - 22;
        break;
    case 2: b = b ^ 66;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big23(int x)
{
    int a, b, i;
    a = x * 11 + 23;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 3 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 24);
        b = b * 3 + a % 4;
    }
    switch (a & 3) {
    case 0: b = b + 23;
        break;
    case 1: b = b - 23;
        break;
    case 2: b = b ^ 69;
        break;
    default: b = ~b;
    }
    if (x > 0)
        b = b + big63(x - 1);
    return a + b;
}

int big24(int x)
{
    int a, b, i;
    a = x * 12 + 24;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 4 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 25);
        b = b * 3 + a % 5;
    }
    switch (a & 3) {
    case 0: b = b + 24;
        break;
    case 1: b = b - 24;
        break;
    case 2: b = b ^ 72;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big25(int x)
{
    int a, b, i;
    a = x * 13 + 25;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 0 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 26);
        b = b * 3 + a % 6;
    }
    switch (a & 3) {
    case 0: b = b + 25;
        break;
    case 1: b = b - 25;
        break;
    case 2: b = b ^ 75;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big26(int x)
{
    int a, b, i;
    a = x * 1 + 26;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 1 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 27);
        b = b * 3 + a % 7;
    }
    switch (a & 3) {
    case 0: b = b + 26;
        break;
    case 1: b = b - 26;
        break;
    case 2: b = b ^ 78;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big27(int x)
{
    int a, b, i;
    a = x * 2 + 27;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 2 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 28);
        b = b * 3 + a % 8;
    }
    switch (a & 3) {
    case 0: b = b + 27;
        break;
    case 1: b = b - 27;
        break;
    case 2: b = b ^ 81;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big28(int x)
{
    int a, b, i;
    a = x * 3 + 28;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 3 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 29);
        b = b * 3 + a % 2;
    }
    switch (a & 3) {
    case 0: b = b + 28;
        break;
    case 1: b = b - 28;
        break;
    case 2: b = b ^ 84;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big29(int x)
{
    int a, b, i;
    a = x * 4 + 29;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 4 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 30);
        b = b * 3 + a % 3;
    }
    switch (a & 3) {
    case 0: b = b + 29;
        break;
    case 1: b = b - 29;
        break;
    case 2: b = b ^ 87;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big30(int x)
{
    int a, b, i;
    a = x * 5 + 30;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 0 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 31);
        b = b * 3 + a % 4;
    }
    switch (a & 3) {
    case 0: b = b + 30;
        break;
    case 1: b = b - 30;
        break;
    case 2: b = b ^ 90;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big31(int x)
{
    int a, b, i;
    a = x * 6 + 31;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 1 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 1);
        b = b * 3 + a % 5;
    }
    switch (a & 3) {
    case 0: b = b + 31;
        break;
    case 1: b = b - 31;
        break;
    case 2: b = b ^ 93;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big32(int x)
{
    int a, b, i;
    a = x * 7 + 32;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 2 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 2);
        b = b * 3 + a % 6;
    }
    switch (a & 3) {
    case 0: b = b + 32;
        break;
    case 1: b = b - 32;
        break;
    case 2: b = b ^ 96;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big33(int x)
{
    int a, b, i;
    a = x * 8 + 33;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 3 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 3);
        b = b * 3 + a % 7;
    }
    switch (a & 3) {
    case 0: b = b + 33;
        break;
    case 1: b = b - 33;
        break;
    case 2: b = b ^ 99;
        break;
    default: b = ~b;
    }
    if (x > 0)
        b = b + big73(x - 1);
    return a + b;
}

int big34(int x)
{
    int a, b, i;
    a = x * 9 + 34;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 4 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 4);
        b = b * 3 + a % 8;
    }
    switch (a & 3) {
    case 0: b = b + 34;
        break;
    case 1: b = b - 34;
        break;
    case 2: b = b ^ 102;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big35(int x)
{
    int a, b, i;
    a = x * 10 + 35;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 0 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 5);
        b = b * 3 + a % 2;
    }
    switch (a & 3) {
    case 0: b = b + 35;
        break;
    case 1: b = b - 35;
        break;
    case 2: b = b ^ 105;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big36(int x)
{
    int a, b, i;
    a = x * 11 + 36;
    b = a ^ (x << 2);
    for (i = 0; i < 2; i++) {
        if (b & 1)
            b = b + 1 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 6);
        b = b * 3 + a % 3;
    }
    switch (a & 3) {
    case 0: b = b + 36;
        break;
    case 1: b = b - 36;
        break;
    case 2: b = b ^ 108;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big37(int x)
{
    int a, b, i;
    a = x * 12 + 37;
    b = a ^ (x << 2);
    for (i = 0; i < 3; i++) {
        if (b & 1)
            b = b + 2 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 7);
        b = b * 3 + a % 4;
    }
    switch (a & 3) {
    case 0: b = b + 37;
        break;
    case 1: b = b - 37;
        break;
    case 2: b = b ^ 111;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big38(int x)
{
    int a, b, i;
    a = x * 13 + 38;
    b = a ^ (x << 2);
    for (i = 0; i < 4; i++) {
        if (b & 1)
            b = b + 3 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 8);
        b = b * 3 + a % 5;
    }
    switch (a & 3) {
    case 0: b = b + 38;
        break;
    case 1: b = b - 38;
        break;
    case 2: b = b ^ 114;
        break;
    default: b = ~b;
    }
    return a + b;
}

int big39(int x)
{
    int a, b, i;
    a = x * 1 + 39;
    b = a ^ (x << 2);
    for (i = 0; i < 5; i++) {
        if (b & 1)
            b = b + 4 * i;
        else
            b = b - x + i;
        a = (a >> 1) + (b & 9);
        b = b * 3 + a % 6;
    }
    switch (a & 3) {
    case 0: b = b + 39;
        break;
    case 1: b = b - 39;
        break;
    case 2: b = b ^ 117;
        break;
    default: b = ~b;
    }
    return a + b;
}

int bigsum(int x)
{
    int s;
    s = 0;
    s = s + big0(x);
    s = s + big1(x);
    s = s + big2(x);
    s = s + big3(x);
    s = s + big4(x);
    s = s + big5(x);
    s = s + big6(x);
    s = s + big7(x);
    s = s + big8(x);
    s = s + big9(x);
    s = s + big10(x);
    s = s + big11(x);
    s = s + big12(x);
    s = s + big13(x);
    s = s + big14(x);
    s = s + big15(x);
    s = s + big16(x);
    s = s + big17(x);
    s = s + big18(x);
    s = s + big19(x);
    s = s + big20(x);
    s = s + big21(x);
    s = s + big22(x);
    s = s + big23(x);
    s = s + big24(x);
    s = s + big25(x);
    s = s + big26(x);
    s = s + big27(x);
    s = s + big28(x);
    s = s + big29(x);
    s = s + big30(x);
    s = s + big31(x);
    s = s + big32(x);
    s = s + big33(x);
    s = s + big34(x);
    s = s + big35(x);
    s = s + big36(x);
    s = s + big37(x);
    s = s + big38(x);
    s = s + big39(x);
    s = s + big40(x);
    s = s + big41(x);
    s = s + big42(x);
    s = s + big43(x);
    s = s + big44(x);
    s = s + big45(x);
    s = s + big46(x);
    s = s + big47(x);
    s = s + big48(x);
    s = s + big49(x);
    s = s + big50(x);
    s = s + big51(x);
    s = s + big52(x);
    s = s + big53(x);
    s = s + big54(x);
    s = s + big55(x);
    s = s + big56(x);
    s = s + big57(x);
    s = s + big58(x);
    s = s + big59(x);
    s = s + big60(x);
    s = s + big61(x);
    s = s + big62(x);
    s = s + big63(x);
    s = s + big64(x);
    s = s + big65(x);
    s = s + big66(x);
    s = s + big67(x);
    s = s + big68(x);
    s = s + big69(x);
    s = s + big70(x);
    s = s + big71(x);
    s = s + big72(x);
    s = s + big73(x);
    s = s + big74(x);
    s = s + big75(x);
    s = s + big76(x);
    s = s + big77(x);
    s = s + big78(x);
    s = s + big79(x);
    return s;
}
