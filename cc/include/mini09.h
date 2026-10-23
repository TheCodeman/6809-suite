/* mini09.h - MINI09 CC: the board's extras */
#ifndef _MINI09_H
#define _MINI09_H

/* Map RAM page 3-6 into $8000-$BFFF; returns the page that was there.
   (Pages 7-31 hold LIBC's file buffers.) */
int bank(int page);
#define WINDOW  ((char *)0x8000)

#endif
