/* stdlib.h - MINI09 CC */
#ifndef _STDLIB_H
#define _STDLIB_H

#define NULL    0
#define RAND_MAX 32767
typedef unsigned size_t;

void exit(int status);
int atoi(char *s);
long atol(char *s);
int abs(int n);
long labs(long n);
void *malloc(size_t n);
void *calloc(size_t n, size_t size);
void free(void *p);
int rand(void);
void srand(unsigned seed);

#endif
