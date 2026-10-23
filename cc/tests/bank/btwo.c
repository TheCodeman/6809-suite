/* banked */
#pragma bank

int fib(int n);

int two(int x)
{
    switch (x) {
    case 1: return 100;
    case 5: return 500;
    case 7: return 700;
    }
    return -1;
}

long twolong(long x)
{
    return x * 3 + 1;
}

int fibtwo(int n)
{
    return fib(n);
}
