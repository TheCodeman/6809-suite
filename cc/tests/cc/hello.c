int puts(char *s);
int main(int argc, char **argv)
{
    int i;
    puts("hello, world");
    for (i = 1; i < argc; i++)
        puts(argv[i]);
    return 0;
}
