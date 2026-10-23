/* stdio.h - MINI09 CC */
#ifndef _STDIO_H
#define _STDIO_H

#define EOF     -1
#define NULL    0

/* 15 bytes, laid out in lib/stdio.asm */
typedef struct { char _f[15]; } FILE;
extern FILE _iob[];
#define stdin   (&_iob[0])
#define stdout  (&_iob[1])
#define stderr  (&_iob[2])

FILE *fopen(char *name, char *mode);    /* mode "r" or "w" */
int fclose(FILE *f);
int fgetc(FILE *f);
int ungetc(int c, FILE *f);
int fputc(int c, FILE *f);
int fputs(char *s, FILE *f);
char *fgets(char *s, int n, FILE *f);
/* buf below $8000: the window holds the file while it is copied */
unsigned fread(void *buf, unsigned size, unsigned n, FILE *f);
unsigned fwrite(void *buf, unsigned size, unsigned n, FILE *f);
int putchar(int c);
int getchar(void);
int puts(char *s);
int remove(char *name);
int printf(char *fmt, ...);
int fprintf(FILE *f, char *fmt, ...);
int sprintf(char *s, char *fmt, ...);
#define getc(f)     fgetc(f)
#define putc(c, f)  fputc(c, f)

#endif
