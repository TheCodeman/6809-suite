/*
 * cc09 - CC on the PC: runs the four passes (cpp09, parse09, sema09,
 * gen09, built with gcc from the same sources as the MINI09 programs)
 * one after the other, with the files between them in a temporary
 * folder.  See cc.md.
 *
 *     cc09 [-I DIR/] [-k] FILE.C [OUT.ASM]
 *
 * -k keeps the temporary folder (FILE.I, .A, .N, .T) and says where.
 * A file with #pragma bank needs CRT0B.O in place of CRT0.O: cc09 says
 * so.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

static char bindir[4096];
static char tmpdir[] = "/tmp/cc09XXXXXX";
static int keep;

static void cleanup(void)
{
    static char *ext[] = { "i", "a", "n", "t", "b", 0 };
    char path[4200];
    int i;
    if (keep) {
        fprintf(stderr, "cc09: passes' files kept in %s\n", tmpdir);
        return;
    }
    for (i = 0; ext[i]; i++) {
        snprintf(path, sizeof path, "%s/x.%s", tmpdir, ext[i]);
        unlink(path);
    }
    rmdir(tmpdir);
}

/* run bindir/prog with args; nonzero if it failed */
static int run(char *prog, char **args)
{
    char path[4200];
    char *argv[8];
    int i, st;
    pid_t pid;
    snprintf(path, sizeof path, "%s%s", bindir, prog);
    argv[0] = path;
    for (i = 0; args[i]; i++)
        argv[i + 1] = args[i];
    argv[i + 1] = 0;
    fflush(stdout);
    pid = fork();
    if (pid == 0) {
        execv(path, argv);
        perror(path);
        _exit(127);
    }
    if (pid < 0 || waitpid(pid, &st, 0) < 0)
        return 1;
    return !WIFEXITED(st) || WEXITSTATUS(st) != 0;
}

int main(int argc, char **argv)
{
    char *in = 0, *out = 0, *inc = 0, *p;
    char fi[64], fa[64], ft[64], outbuf[4096];
    char *a1[6], *a2[3], *a3[3], *a4[3];
    int i, n, bad;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-I") == 0 && i + 1 < argc)
            inc = argv[++i];
        else if (strcmp(argv[i], "-k") == 0)
            keep = 1;
        else if (!in)
            in = argv[i];
        else
            out = argv[i];
    }
    if (!in) {
        fprintf(stderr, "Usage: cc09 [-I DIR/] [-k] FILE.C [OUT.ASM]\n");
        return 1;
    }
    /* the passes are beside cc09 */
    p = strrchr(argv[0], '/');
    n = p ? p - argv[0] + 1 : 0;
    if (n >= (int)sizeof bindir - 16)
        return 1;
    memcpy(bindir, argv[0], n);
    bindir[n] = 0;
    if (!out) {
        /* FILE.C -> FILE.ASM, file.c -> file.asm */
        snprintf(outbuf, sizeof outbuf - 8, "%s", in);
        p = strrchr(outbuf, '.');
        if (p && !strchr(p, '/'))
            *p = 0;
        else
            p = 0;
        n = p && p[1] >= 'A' && p[1] <= 'Z';
        strcat(outbuf, n ? ".ASM" : ".asm");
        out = outbuf;
    }
    if (!mkdtemp(tmpdir)) {
        perror("cc09: mkdtemp");
        return 1;
    }
    snprintf(fi, sizeof fi, "%s/x.i", tmpdir);
    snprintf(fa, sizeof fa, "%s/x.a", tmpdir);
    snprintf(ft, sizeof ft, "%s/x.t", tmpdir);

    n = 0;
    if (inc) {
        a1[n++] = "-I";
        a1[n++] = inc;
    }
    a1[n++] = in;
    a1[n++] = fi;
    a1[n] = 0;
    a2[0] = fi; a2[1] = fa; a2[2] = 0;
    a3[0] = fa; a3[1] = ft; a3[2] = 0;
    a4[0] = ft; a4[1] = out; a4[2] = 0;
    bad = run("cpp09", a1) || run("parse09", a2) || run("sema09", a3) ||
        run("gen09", a4);
    snprintf(outbuf, sizeof outbuf, "%s/x.b", tmpdir);
    if (!bad && access(outbuf, F_OK) == 0)
        fprintf(stderr, "cc09: %s is banked: link it with crt0b.o\n", in);
    cleanup();
    return bad;
}
