// ane_initwrap4.c — v4: inert main + post-boot child worker.
//
// Design rationale (learned the hard way):
//  - v1/v2/v3b (modifying mounts/writes/labels before init runs) all left the
//    device stuck at the bootloader warning screen; the common denominator was
//    activity BEFORE the kernel's init chain finished.
//  - SELinux label strings cannot be validated before the policy is loaded, so
//    files we created pre-policy ended up unlabeled and unreadable by `shell`.
//  - Android re-applies /cache's 0770 perms at boot, so pre-boot chmods die.
//
// v4 therefore does NOTHING in the main path except fork a worker and exec the
// real init.  The worker (uid 0, "kernel" sid => powerful post-policy):
//   1. waits for init to mount sysfs, then reads /sys/fs/pstore/pmsg-ramoops-0
//      into memory (pre/post-policy both fine for uid0),
//   2. polls until setxattr("security.selinux", ...) starts succeeding
//      (== policy is live),
//   3. waits for /data/local/tmp to appear (vold mounts /data),
//   4. writes the dump + a report there, then relabels/chmods everything we
//      ever wrote (so a plain `adb shell` can finally read it),
//   5. exits.  No mounts, no early state changes, no raw block access.
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <sys/reboot.h>
#include <sys/syscall.h>

#define PSTORE "/sys/fs/pstore/pmsg-ramoops-0"
#define MAXBUF (8*1024*1024)

static char rep[16384]; static size_t rl = 0;

static void rlog(const char *f, ...) {
    char b[384]; va_list ap; va_start(ap, f);
    int n = vsnprintf(b, sizeof b, f, ap); va_end(ap);
    if (n < 0) return;
    if ((size_t)n >= sizeof b) n = sizeof b - 1;
    if (rl + (size_t)n + 2 >= sizeof rep) return;
    memcpy(rep + rl, b, n); rl += (size_t)n; rep[rl++] = '\n'; rep[rl] = 0;
}

static long ms_now(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec*1000L + ts.tv_nsec/1000000L;
}

// Try to label + own + chmod a file so `shell` can read it.
static void expose_file(const char *path) {
    int xr = setxattr(path, "security.selinux", "u:object_r:shell_data_file:s0", 30, 0);
    int cr = chmod(path, 0666);
    int orr = chown(path, 2000, 2000);
    rlog("[expose] %s setxattr=%d chmod=%d chown=%d errno=%d(%s)",
         path, xr, cr, orr, errno, strerror(errno));
}

static void write_here(const char *dir, const char *name, const void *data, size_t len, int expose) {
    char p[256]; snprintf(p, sizeof p, "%s/%s", dir, name);
    int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd < 0) { rlog("[write] %s open FAIL errno=%d(%s)", p, errno, strerror(errno)); return; }
    ssize_t w = write(fd, data, len); fsync(fd); close(fd);
    rlog("[write] %s wrote %zd/%zu", p, w, len);
    if (expose) expose_file(p);
}

static void worker(void) {
    long t0 = ms_now();
    unsigned char *buf = malloc(MAXBUF); size_t blen = 0;

    // Phase 1: wait for init's own sysfs mount, then read the pstore.
    int got = 0;
    for (int i = 0; i < 600 && !got; i++) {
        int fd = open(PSTORE, O_RDONLY);
        if (fd >= 0) {
            ssize_t r; blen = 0;
            while ((r = read(fd, buf + blen, MAXBUF - blen)) > 0) { blen += (size_t)r; if (blen >= MAXBUF) break; }
            close(fd);
            rlog("[pstore] read %zu bytes at +%ldms", blen, ms_now()-t0);
            got = 1;
            break;
        }
        usleep(500*1000);
    }
    if (!got) { rlog("[pstore] never appeared within 300s"); }

    // Phase 2: wait until setxattr succeeds (policy live).
    char *probe = "/wprobe";
    int pol = 0;
    for (int i = 0; i < 1200; i++) {
        int fd = open(probe, O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd >= 0) {
            close(fd);
            if (setxattr(probe, "security.selinux", "u:object_r:shell_data_file:s0", 30, 0) == 0) { pol = 1; break; }
        }
        usleep(500*1000);
    }
    unlink(probe);
    rlog("[policy] live at +%ldms (pol=%d)", ms_now()-t0, pol);

    // Phase 3: wait for /data/local/tmp (vold mounts /data).
    int tmpok = 0;
    for (int i = 0; i < 1200; i++) {
        struct stat st;
        if (stat("/data/local/tmp", &st) == 0) { tmpok = 1; break; }
        usleep(500*1000);
    }
    rlog("[data] /data/local/tmp ready=%d at +%ldms", tmpok, ms_now()-t0);

    if (tmpok) {
        if (got && blen) write_here("/data/local/tmp", "pmsg_dump.bin", buf, blen, 1);
        // report with how far we got
        char head[512];
        int hl = snprintf(head, sizeof head,
            "ANE initwrap v4 report\nuptime at write: %ldms after fork\npstore bytes: %zu\npolicy live: %d\ndata local/tmp: %d\n",
            ms_now()-t0, blen, pol, tmpok);
        rlog("=== v4 report head written ===");
        int fd = open("/data/local/tmp/pmsg_wrap_report.txt", O_WRONLY | O_CREAT | O_TRUNC, 0666);
        if (fd >= 0) { write(fd, head, hl); write(fd, rep, rl); fsync(fd); close(fd);
            expose_file("/data/local/tmp/pmsg_wrap_report.txt"); }
    }

    // Phase 4: repair earlier runs' files so shell can read them too.
    // /cache (Android resets dir perms at boot, but vold/init ran already; we are later).
    struct stat st;
    if (stat("/cache", &st) == 0) {
        chmod("/cache", 0775);
        rlog("[fix] /cache chmod 0775");
        expose_file("/cache/pmsg_dump.bin");
        expose_file("/cache/pmsg_wrap_report.txt");
    }
    // /vendor /product /system copies (ro partitions; relabel is enough).
    expose_file("/vendor/pmsg_wrap_report.txt");
    expose_file("/vendor/pmsg_dump.bin");
    expose_file("/product/pmsg_wrap_report.txt");
    expose_file("/system/pmsg_wrap_report.txt");
    _exit(0);
}

int main(int argc, char **argv) {
    const char *a0 = argv[0] ? argv[0] : "";
    const char *base = strrchr(a0, '/');
    base = base ? base + 1 : a0;
    if (strcmp(base, "init") != 0 || argc > 1) {
        execv("/init.hw", argv);
        execv("/init.real", argv);
        _exit(127);
    }

    // Inert main path: spawn the worker, then chain to the real init untouched.
    pid_t p = fork();
    if (p == 0) { worker(); _exit(0); }
    // give the child a head start on its buffer, then hand over
    execv("/init.hw", argv);
    execv("/init.real", argv);
    syscall(SYS_reboot, 0xfee1dead, 672274793, 0x01234567, 0);
    for (;;) pause();
    return 0;
}
