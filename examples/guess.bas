10 REM Guess the number
20 RANDOMIZE
30 N=RND(100)+1:T=0
40 PRINT "I'm thinking of a number from 1 to 100."
50 INPUT "Your guess";G
60 T=T+1
70 IF G<N THEN PRINT "Higher!":GOTO 50
80 IF G>N THEN PRINT "Lower!":GOTO 50
90 PRINT "Got it in ";T;" tries."
100 INPUT "Again (Y/N)";A$
110 IF LEFT$(A$,1)="Y" OR LEFT$(A$,1)="y" THEN 30
