/* string.h - MINI09 CC */
#ifndef _STRING_H
#define _STRING_H

#define NULL    0
typedef unsigned size_t;

size_t strlen(char *s);
char *strcpy(char *d, char *s);
char *strcat(char *d, char *s);
int strcmp(char *a, char *b);
int strncmp(char *a, char *b, size_t n);
char *strchr(char *s, int c);
char *strrchr(char *s, int c);
void *memcpy(void *d, void *s, size_t n);
void *memmove(void *d, void *s, size_t n);
void *memset(void *d, int c, size_t n);
int memcmp(void *a, void *b, size_t n);

#endif
