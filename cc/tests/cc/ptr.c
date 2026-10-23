#include <stdio.h>
#include <string.h>

struct point { int x, y; };
struct rect { struct point a, b; char name[6]; struct rect *next; };
union word { int w; char b[2]; };
typedef struct node { int val; struct node *next; } Node;
enum color { RED, GREEN = 5, BLUE };

struct point origin = { 3, 4 };
char *words[] = { "zero", "one", "two", 0 };
int grid[3][4];
char msg[] = "hi there";
long lv[3] = { 1, -2, 70000 };
Node nodes[4];

int add(int a, int b) { return a + b; }
int sub(int a, int b) { return a - b; }
int (*ops[2])(int, int) = { add, sub };

int apply(int (*f)(int, int), int a, int b) { return f(a, b); }

void swap(int *a, int *b) { int t; t = *a; *a = *b; *b = t; }

int area(struct rect *r) { return (r->b.x - r->a.x) * (r->b.y - r->a.y); }

void mid(struct point *m, struct point *p, struct point *q)
{
    struct point t;
    t.x = (p->x + q->x) / 2;
    t.y = (p->y + q->y) / 2;
    *m = t;
}

int sumlist(Node *n) { int s; for (s = 0; n; n = n->next) s += n->val; return s; }

int main(void)
{
    int a, b, i, j, *p, **pp;
    char buf[32], *s;
    struct rect r, r2, *rp;
    struct point pt;
    union word w;
    int (*f)(int, int);
    long *lp;

    a = 1; b = 2;
    swap(&a, &b);
    printf("swap %d %d\n", a, b);
    p = &a; pp = &p;
    **pp = 42;
    printf("pp %d %d\n", a, *p);
    for (i = 0; i < 3; i++)
        for (j = 0; j < 4; j++)
            grid[i][j] = i * 10 + j;
    printf("grid %d %d %d %d\n", grid[1][2], grid[2][3], *grid[1], *(*(grid + 2) + 1));
    p = &grid[1][0];
    printf("ptrarith %d %d %d\n", p[5], *(p + 2), (int)(&grid[2][1] - p));
    p++; p += 2; printf("ptrinc %d\n", *p);
    printf("cmp %d %d\n", p > &grid[0][0], p == &grid[1][3]);
    r.a.x = 1; r.a.y = 2; r.b = origin; r.b.x += 10;
    strcpy(r.name, "box");
    r.next = 0;
    printf("rect %d %d %d %s %d\n", r.b.x, r.b.y, area(&r), r.name, (int)sizeof(struct rect));
    r2 = r;
    r2.a.x = 5;
    printf("copy %d %d %s\n", r2.a.x, r.a.x, r2.name);
    rp = &r2;
    rp->next = &r;
    printf("arrow %d %c\n", rp->next->a.x, rp->next->name[1]);
    mid(&pt, &r.a, &r.b);
    printf("mid %d %d\n", pt.x, pt.y);
    w.w = 0x1234;
    printf("union %x %x %d\n", w.b[0], w.b[1], (int)sizeof(w));
    printf("enum %d %d %d\n", RED, GREEN, BLUE);
    for (i = 0; words[i]; i++)
        printf("%s ", words[i]);
    printf("%d %c\n", (int)sizeof(msg), msg[3]);
    f = add;
    printf("fptr %d %d %d %d\n", f(2, 3), (*f)(4, 5), ops[1](10, 3), apply(sub, 7, 9));
    for (i = 0; i < 4; i++) {
        nodes[i].val = i + 1;
        nodes[i].next = i < 3 ? &nodes[i + 1] : 0;
    }
    printf("list %d\n", sumlist(nodes));
    lp = lv;
    printf("long* %ld %ld %ld\n", *lp, lp[1], *(lp + 2));
    s = buf;
    for (i = 0; msg[i]; i++)
        *s++ = msg[i] - 32 * (msg[i] >= 'a');
    *s = 0;
    printf("upper %s %d\n", buf, (int)(s - buf));
    printf("str %c %d\n", "abc"[1], (int)strlen("hello"));
    s = msg;
    while (*s && *s != ' ')
        s++;
    printf("scan %s\n", s);
    return 0;
}
