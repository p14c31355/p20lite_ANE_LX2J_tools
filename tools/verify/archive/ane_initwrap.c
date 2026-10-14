// ane_initwrap.c — ANE-LX2J (EMUI8) PID1 wrapper.
// Goal: dump /sys/fs/pstore/pmsg-ramoops-0 to shell-visible partitions,
// then chainload the real init (/init.hw) so Android boots normally.
// Static aarch64. Runs pre-SELinux (no policy loaded yet).
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <sys/reboot.h>
#include <sys/syscall.h>
#include <dirent.h>

#define PSTORE "/sys/fs/pstore/pmsg-ramoops-0"
#define MAXBUF (8*1024*1024)

static char rep[16384]; static size_t rl = 0;
static unsigned char *dump; static size_t dlen = 0;
static int dump_ok = 0;

static void rlog(const char *f, ...) {
    char b[512]; va_list ap; va_start(ap, f);
    int n = vsnprintf(b, sizeof b, f, ap); va_end(ap);
    if (n < 0) return;
    if ((size_t)n >= sizeof b) n = sizeof b - 1;
    if (rl + (size_t)n + 2 >= sizeof rep) n = (int)(sizeof rep - rl - 2);
    if (n <= 0) return;
    memcpy(rep + rl, b, n); rl += (size_t)n; rep[rl++] = '\n'; rep[rl] = 0;
}

static void read_pstore(void) {
    int fd = open(PSTORE, O_RDONLY);
    rlog("pstore open fd=%d errno=%d(%s)", fd, errno, strerror(errno));
    if (fd < 0) return;
    dump = malloc(MAXBUF);
    if (!dump) { rlog("malloc failed"); close(fd); return; }
    ssize_t r;
    while ((r = read(fd, dump + dlen, MAXBUF - dlen)) > 0) {
        dlen += (size_t)r;
        if (dlen >= MAXBUF) break;
    }
    rlog("pstore read %zu bytes (%s)", dlen, r < 0 ? strerror(errno) : "eof");
    close(fd);
    dump_ok = (dlen > 0);
}

static int find_part(const char *name, char *dev, size_t devsz) {
    DIR *d = opendir("/sys/class/block");
    if (!d) { rlog("opendir /sys/class/block: %s", strerror(errno)); return -1; }
    struct dirent *e; int found = -1;
    char pat[64]; snprintf(pat, sizeof pat, "PARTNAME=%s\n", name);
    while ((e = readdir(d))) {
        if (strncmp(e->d_name, "mmcblk0p", 8)) continue;
        char p[256]; snprintf(p, sizeof p, "/sys/class/block/%s/uevent", e->d_name);
        int fd = open(p, O_RDONLY); if (fd < 0) continue;
        char buf[512]; ssize_t n = read(fd, buf, sizeof buf - 1); close(fd);
        if (n <= 0) continue; buf[n] = 0;
        if (strstr(buf, pat)) { snprintf(dev, devsz, "/dev/%s", e->d_name); found = 0; break; }
    }
    closedir(d);
    return found;
}

static void write_out(const char *mnt, const char *sub) {
    char dir[160]; snprintf(dir, sizeof dir, "%s%s", mnt, sub);
    if (sub[0]) { mkdir(dir, 0755); chmod(dir, 0755); }
    char f1[200], f2[200];
    snprintf(f1, sizeof f1, "%s/pmsg_dump.bin", dir);
    snprintf(f2, sizeof f2, "%s/pmsg_wrap_report.txt", dir);
    if (dump) {
        int fd = open(f1, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) {
            ssize_t w = write(fd, dump, dlen); close(fd); chmod(f1, 0644);
            rlog("wrote %s (%zd bytes)", f1, w);
        } else rlog("open %s failed: %s", f1, strerror(errno));
    }
    int fd = open(f2, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) { write(fd, rep, rl); close(fd); chmod(f2, 0644); } 
}

static void try_target(const char *part, const char *sub, const char *label) {
    char dev[128];
    if (find_part(part, dev, sizeof dev)) { rlog("[%s] partition not found", part); return; }
    mkdir("/mnt", 0755);
    char mnt[96]; snprintf(mnt, sizeof mnt, "/mnt/w_%s", part);
    mkdir(mnt, 0755);
    int rc = mount(dev, mnt, "ext4", 0, NULL);
    rlog("[%s] mount %s at %s rc=%d (%s)", part, dev, mnt, rc, strerror(errno));
    if (rc) return;
    write_out(mnt, sub);
    if (label && dump_ok) {
        char f1[200]; snprintf(f1, sizeof f1, "%s%s/pmsg_dump.bin", mnt, sub);
        int xr = setxattr(f1, "security.selinux", label, strlen(label) + 1, 0);
        rlog("[%s] setxattr %s = %d (%s)", part, label, xr, strerror(errno));
    }
    int ur = umount(mnt);
    rlog("[%s] umount rc=%d (%s)", part, ur, strerror(errno));
}

int main(int argc, char **argv) {
    // Android spawns ueventd/watchdogd by re-execing /init (via /sbin/ueventd etc.
    // symlinks).  Only the real first-stage init invocation (argv[0] basename
    // "init", no extra args) may do the dump; everything else must pass through
    // to the real init unchanged so those modes keep working.
    const char *a0 = argv[0] ? argv[0] : "";
    const char *base = strrchr(a0, '/');
    base = base ? base + 1 : a0;
    if (strcmp(base, "init") != 0 || argc > 1) {
        execv("/init.hw", argv);
        execv("/init.real", argv);
        _exit(127);
    }

    rlog("ane_initwrap pid=%d uid=%d", getpid(), getuid());
    mkdir("/dev", 0755); mkdir("/proc", 0755); mkdir("/sys", 0755); mkdir("/mnt", 0755);
    if (mount("devtmpfs", "/dev", "devtmpfs", 0, NULL))
        rlog("mount devtmpfs: %s", strerror(errno));
    else rlog("devtmpfs ok");
    if (mount("proc", "/proc", "proc", 0, NULL))
        rlog("mount proc: %s", strerror(errno));
    else rlog("proc ok");
    if (mount("sysfs", "/sys", "sysfs", 0, NULL))
        rlog("mount sysfs: %s", strerror(errno));
    else rlog("sysfs ok");

    chmod("/sys/fs/pstore", 0755);
    chmod(PSTORE, 0644);
    rlog("pstore chmod attempted");

    read_pstore();

    int m = open("/dev/mem", O_RDONLY);
    rlog("/dev/mem fd=%d (%s)", m, strerror(errno));
    if (m >= 0) close(m);

    try_target("cache",   "",        "u:object_r:cache_file:s0");
    try_target("vendor",  "",        "u:object_r:vendor_file:s0");
    try_target("product", "",        "u:object_r:system_file:s0");
    try_target("oem",     "",        "u:object_r:system_file:s0");
    try_target("system",  "",        "u:object_r:system_file:s0");
    try_target("userdata","/local/tmp","u:object_r:shell_data_file:s0");

    sync();
    rlog("exec /init.hw ...");
    execv("/init.hw", (char *const[]){(char *)"/init.hw", NULL});
    rlog("exec /init.hw failed: %s", strerror(errno));
    execv("/init.real", (char *const[]){(char *)"/init.real", NULL});
    rlog("exec /init.real failed: %s; rebooting", strerror(errno));
    sync();
    syscall(SYS_reboot, 0xfee1dead, 672274793, 0x01234567, 0);
    for (;;) pause();
    return 0;
}
