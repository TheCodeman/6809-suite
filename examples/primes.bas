10 REM Sieve of Eratosthenes: primes below 1000, and how long it took
20 N=1000:DIM F(1000)
30 T=TIMER:C=0
40 FOR I=2 TO N-1
50 IF F(I) THEN 90
60 C=C+1:PRINT I,
70 J=I*I:IF J>=N OR J<0 THEN 90
80 FOR K=J TO N-1 STEP I:F(K)=1:NEXT K
90 NEXT I
100 PRINT:PRINT C;" primes in ";(TIMER-T)/100;" seconds"
