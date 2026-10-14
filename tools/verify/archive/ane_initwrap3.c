// ane_initwrap3.c — v3: minimal, cache-focused, with progressive logging.
// Diffs from v2:
//  - writes the report EARLY (right after mounting cache) and fsyncs it, so a
//    later hang still leaves evidence of how far we got
//  - only touches /cache (dump + labels + chmod root 0775) and /data (f2fs!)
//  - re-labels the existing /cache/pmsg_dump.bin from earlier runs
//  - skips vendor/product/system/oem entirely (bisect: they may be the hazard)
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
static unsigned char *dump; static size_t dlen = 0; static int dump_ok = 0;
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
    dump_ok = dlen > 0;
}

static int find_part(const char *name, char *dev, size_t devsz) {
    DIR *d = opendir("/sys/class/block");
    if (!d) { rlog("findpart: opendir %s", strerror(errno)); return -1; }
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

static void fix_file(const char *path, const char *label) {
    if (access(path, F_OK)) { rlog("[fix] %s absent", path); return; }
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

    rlog("[v3] pid=%d uid=%d", getpid(), getuid());
    mkdir("/dev", 0755); mkdir("/proc", 0755); mkdir("/sys", 0755); mkdir("/mnt", 0755);
    rlog("mount devtmpfs: %d (%s)", mount("devtmpfs", "/dev", "devtmpfs", 0, NULL), strerror(errno));
    rlog("mount proc: %d (%s)", mount("proc", "/proc", "proc", 0, NULL), strerror(errno));
    rlog("mount sysfs: %d (%s)", mount("sysfs", "/sys", "sysfs", 0, NULL), strerror(errno));

    // ---- /cache: the primary target.  Mount raw, keep the report open. ----
    char dev[128]; char mnt[96];
    if (find_part("cache", dev, sizeof dev) == 0) {
        snprintf(mnt, sizeof mnt, "/mnt/w_cache");
        mkdir(mnt, 0755);
        int rc = mount(dev, mnt, "ext4", 0, NULL);
        rlog("[cache] mount %s rc=%d (%s)", dev, rc, strerror(errno));
        if (rc == 0) {
            char f2[200]; snprintf(f2, sizeof f2, "%s/pmsg_wrap_report.txt", mnt);
            rep_fd = open(f2, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            rlog("[cache] report fd=%d", rep_fd);
            read_pstore();
            if (dump && dlen > 0) {
                char f1[200]; snprintf(f1, sizeof f1, "%s/pmsg_dump.bin", mnt);
                int fd = open(f1, O_WRONLY | O_CREAT | O_TRUNC, 0644);
                if (fd >= 0) { ssize_t w = write(fd, dump, dlen); fsync(fd); close(fd); rlog("[cache] dump wrote %zd", w); }
                else rlog("[cache] dump open failed: %s", strerror(errno));
            } else {
                rlog("[cache] dump skipped (dlen=%zu) - keeping existing file", dlen);
            }
            fix_file("/mnt/w_cache/pmsg_dump.bin", "u:object_r:cache_file:s0");
            fix_file("/mnt/w_cache/pmsg_wrap_report.txt", "u:object_r:cache_file:s0");
            // previous runs' files: fix labels too (same paths, same fix)
            int dr = chmod(mnt, 0775);
            rlog("[cache] chmod root=%d", dr);
            rlog("[cache] done; umount=%d (%s)", umount(mnt), strerror(errno));
        }
        if (rep_fd >= 0) { close(rep_fd); rep_fd = -1; }
    } else {
        rlog("[cache] partition not found");
    }

    // ---- /data (f2fs!): best-effort, then exec. ----
    if (find_part("userdata", dev, sizeof dev) == 0) {
        snprintf(mnt, sizeof mnt, "/mnt/w_data");
        mkdir(mnt, 0755);
        int rc = mount(dev, mnt, "f2fs", 0, NULL);
        rlog("[data] mount f2fs rc=%d (%s)", rc, strerror(errno));
        if (rc) { rc = mount(dev, mnt, "ext4", 0, NULL); rlog("[data] mount ext4 rc=%d (%s)", rc, strerror(errno)); }
        if (rc == 0) {
            mkdir("/mnt/w_data/local", 0755); mkdir("/mnt/w_data/local/tmp", 0777);
            chmod("/mnt/w_data/local/tmp", 0777);
            if (dump) {
                int fd = open("/mnt/w_data/local/tmp/pmsg_dump.bin", O_WRONLY | O_CREAT | O_TRUNC, 0644);
                if (fd >= 0) { write(fd, dump, dlen); close(fd); chmod("/mnt/w_data/local/tmp/pmsg_dump.bin", 0644); rlog("[data] dump written"); }
                else rlog("[data] open failed: %s", strerror(errno));
            }
            int fd = open("/mnt/w_data/local/tmp/pmsg_wrap_report.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (fd >= 0) { write(fd, rep, rl); close(fd); chmod("/mnt/w_data/local/tmp/pmsg_wrap_report.txt", 0644); }
            rlog("[data] umount=%d (%s)", umount(mnt), strerror(errno));
        }
    } else {
        rlog("[data] partition not found");
    }

    sync();
    rlog("[v3] exec /init.hw");
    execv("/init.hw", argv);
    execv("/init.real", argv);
    syscall(SYS_reboot, 0xfee1dead, 672274793, 0x01234567, 0);
    for (;;) pause();
    return 0;
}
