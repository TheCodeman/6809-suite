/* stdarg.h - MINI09 CC.  Arguments are pushed right to left, each one
   2 bytes (a char is widened) or 4 (a long), so the next argument is
   just above the last named one.  Use va_arg(ap, int) for a char. */
#ifndef _STDARG_H
#define _STDARG_H

typedef char *va_list;
#define va_start(ap, last)  (ap = (char *)&last + sizeof(last))
#define va_arg(ap, t)       (*(t *)((ap += sizeof(t)) - sizeof(t)))
#define va_end(ap)

#endif
