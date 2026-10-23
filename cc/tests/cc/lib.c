#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <mini09.h>

char *strtok0(char *s);

int main(int argc, char **argv)
{
    FILE *f;
    char line[40], buf[64], *p, *q, *r;
    int c, n, i;

    f = fopen("OUT.TXT", "w");
    for (i = 1; i <= 3; i++)
        fprintf(f, "line %d of %s\n", i, "OUT.TXT");
    fputs("last\n", f);
    fclose(f);
    f = fopen("OUT.TXT", "r");
    n = 0;
    while (fgets(line, sizeof(line), f)) {
        n++;
        printf("[%s]", strtok0(line));
    }
    fclose(f);
    printf(" %d lines\n", n);
    f = fopen("OUT.TXT", "r");
    n = 0;
    while ((c = getc(f)) != EOF)
        if (isdigit(c))
            n += c - '0';
    fclose(f);
    printf("digits %d\n", n);
    n = remove("OUT.TXT");
    printf("remove %d %d\n", n, fopen("OUT.TXT", "r") == NULL);
    sprintf(buf, "%s-%d-%x-%ld", "sp", -7, 255, 123456789L);
    printf("%s %d\n", buf, (int)strlen(buf));
    printf("atoi %d %d %ld %d %ld\n", atoi("  -123"), atoi("+45x"), atol("2000000000"), abs(-9), labs(-70000L));
    printf("ctype %c%c%c %d%d%d%d\n", toupper('a'), tolower('Q'), toupper('5'),
           isalpha('x'), isspace('\t'), ispunct('!'), isxdigit('g'));
    p = malloc(100);
    q = malloc(200);
    strcpy(p, "heap one");
    strcpy(q, "heap two");
    printf("malloc %s, %s %d\n", p, q, p != q);
    free(q);
    r = malloc(200);
    printf("reuse %d\n", r == q);
    q = r;
    r = malloc(50);
    free(q);
    free(r);
    p = malloc(300);
    printf("joined %d\n", p != 0);
    free(p);
    p = calloc(10, 3);
    for (n = i = 0; i < 30; i++)
        n += p[i];
    printf("calloc %d\n", n);
    printf("big %d\n", malloc(12000) != 0 && malloc(12000) == 0);
    printf("args %d %s %s\n", argc, argv[1], argv[argc - 1]);
    srand(1);
    n = rand();
    srand(1);
    printf("rand %d\n", n == rand());
    i = bank(3);
    WINDOW[0] = 'W';
    WINDOW[1] = 0;
    bank(4);
    WINDOW[0] = 'X';
    bank(3);
    printf("bank %s\n", WINDOW);
    /* the program's page stays in the window while files are used */
    f = fopen("BLK.TXT", "w");
    for (i = 0; i < 20; i++)
        fputc('a' + i, f);
    n = fwrite("0123456789", 1, 10, f);
    fclose(f);
    printf("fwrite %d %s\n", n, WINDOW);
    f = fopen("BLK.TXT", "r");
    c = fgetc(f);
    ungetc(c, f);
    n = fread(buf, 2, 20, f);
    buf[30] = 0;
    printf("fread %d %s %c %d\n", n, buf, WINDOW[0], fgetc(f));
    fclose(f);
    printf("%s\n", WINDOW);
    printf("%%|%5s|%-3c|%.2s|%u\n", "ab", 'z', "xyz", 0xFFFF);
    return 0;
}

char *strtok0(char *s)
{
    char *e;
    e = strchr(s, '\n');
    if (e)
        *e = 0;
    return s;
}
