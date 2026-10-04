// ane_initwrap3b.c — v3b: minimal surface.  Hardcoded partitions (measured
// from the live mount table: cache=/dev/mmcblk0p42, userdata=/dev/mmcblk0p56),
// NO /proc or /sys mounts, NO uevent scan.  Only devtmpfs (and only if the
// device node is missing), then cache write + labels, then exec /init.hw.
// Pass-through preserved for ueventd/watchdogd re-exec (argv[0] != "init").
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

#define PSTORE "/sys/fs/pstore/pmsg-ramoops-0"
#define CACHE_DEV "/dev/mmcblk0p42"
#define DATA_DEV  "/dev/mmcblk0p56"
#define MAXBUF (8*1024*1024)

static char rep[16384]; static size_t rl = 0;
static unsigned char *dump; static size_t dlen = 0;
static int rep_fd = -1;

static void rlog(const char *f, ...) {
    char b[512]; va_list ap; va_start(ap, f);
    int n = vsnprintf(b, sizeof b, f, ap); va_end(ap);
    if (n < 0) return;
    if ((size_t)n >= sizeof b) n = sizeof b - 1;
    if (rl + (size_t)n + 2 >= sizeof rep) n = (int)(sizeof rep - rl - 2);
    if (n <= 0) return;
    memcpy(rep + rl, b, n); rl += (size_t)n; rep[rl++] = '\n'; rep[rl] = 0;
    if (rep_fd >= 0) { write(rep_fd, b, (size_t)n); write(rep_fd, "\n", 1); fsync(rep_fd); }
}

static void read_pstore(void) {
    int fd = open(PSTORE, O_RDONLY);
    rlog("[pstore] open fd=%d errno=%d(%s)", fd, errno, strerror(errno));
    if (fd < 0) return;
    dump = malloc(MAXBUF);
    if (!dump) { rlog("[pstore] malloc failed"); close(fd); return; }
    ssize_t r;
    while ((r = read(fd, dump + dlen, MAXBUF - dlen)) > 0) { dlen += (size_t)r; if (dlen >= MAXBUF) break; }
    rlog("[pstore] read %zu bytes", dlen);
    close(fd);
}

static void fix_file(const char *path, const char *label) {
    if (access(path, F_OK)) { rlog("[fix] %s absent (errno=%d)", path, errno); return; }
    int cr = chmod(path, 0644);
    int xr = setxattr(path, "security.selinux", label, strlen(label) + 1, 0);
    rlog("[fix] %s chmod=%d setxattr=%d(%s)", path, cr, xr, strerror(errno));
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

    rlog("[v3b] pid=%d uid=%d", getpid(), getuid());

    // /sys: needed for the pstore read; mount only if absent.
    if (access(PSTORE, F_OK)) {
        mkdir("/sys", 0755);
        int mr = mount("sysfs", "/sys", "sysfs", 0, NULL);
        rlog("[sys] sysfs mount rc=%d (%s)", mr, strerror(errno));
    } else {
        rlog("[sys] pstore path already visible");
    }

    // /dev: kernel usually auto-mounts devtmpfs; mount only if the node is missing.
    if (access(CACHE_DEV, F_OK)) {
        mkdir("/dev", 0755);
        int mr = mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
        rlog("[dev] devtmpfs mount rc=%d (%s)", mr, strerror(errno));
    } else {
        rlog("[dev] %s already present (devtmpfs pre-mounted)", CACHE_DEV);
    }

    mkdir("/mnt", 0755);
    int rc = mount(CACHE_DEV, "/mnt", "ext4", 0, NULL);
    rlog("[cache] mount %s rc=%d (%s)", CACHE_DEV, rc, strerror(errno));
    if (rc == 0) {
        rep_fd = open("/mnt/pmsg_wrap_report.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
        rlog("[cache] report fd=%d", rep_fd);
        read_pstore();
        if (dump && dlen > 0) {
            int fd = open("/mnt/pmsg_dump.bin", O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (fd >= 0) { ssize_t w = write(fd, dump, dlen); fsync(fd); close(fd); rlog("[cache] dump wrote %zd", w); }
            else rlog("[cache] dump open failed: %s", strerror(errno));
        } else {
            rlog("[cache] dump skipped (dlen=%zu)", dlen);
        }
        fix_file("/mnt/pmsg_dump.bin", "u:object_r:cache_file:s0");
        fix_file("/mnt/pmsg_wrap_report.txt", "u:object_r:cache_file:s0");
        int dr = chmod("/mnt", 0775);
        rlog("[cache] chmod root 0775 rc=%d", dr);
        rlog("[cache] umount=%d (%s)", umount("/mnt"), strerror(errno));
    }
    if (rep_fd >= 0) { close(rep_fd); rep_fd = -1; }

    // /data (f2fs): best effort.
    rc = mount(DATA_DEV, "/mnt", "f2fs", 0, NULL);
    rlog("[data] mount f2fs rc=%d (%s)", rc, strerror(errno));
    if (rc) { rc = mount(DATA_DEV, "/mnt", "ext4", 0, NULL); rlog("[data] ext4 rc=%d (%s)", rc, strerror(errno)); }
    if (rc == 0) {
        mkdir("/mnt/local", 0755); mkdir("/mnt/local/tmp", 0777); chmod("/mnt/local/tmp", 0777);
        if (dump && dlen > 0) {
            int fd = open("/mnt/local/tmp/pmsg_dump.bin", O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (fd >= 0) { write(fd, dump, dlen); close(fd); chmod("/mnt/local/tmp/pmsg_dump.bin", 0644); rlog("[data] dump written"); }
            else rlog("[data] open failed: %s", strerror(errno));
        }
        int fd = open("/mnt/local/tmp/pmsg_wrap_report.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) { write(fd, rep, rl); close(fd); chmod("/mnt/local/tmp/pmsg_wrap_report.txt", 0644); }
        rlog("[data] umount=%d (%s)", umount("/mnt"), strerror(errno));
    }

    sync();
    rlog("[v3b] exec /init.hw");
    execv("/init.hw", argv);
    execv("/init.real", argv);
    syscall(SYS_reboot, 0xfee1dead, 672274793, 0x01234567, 0);
    for (;;) pause();
    return 0;
}
