// ane_initwrap5.c — SD-card channel edition (user's idea).
// Writes progress markers + the pstore dump to the microSD card, then chains
// to the real init.  The SD is free of SELinux labels and Android's permission
// resets, and it is physically removable — so the data survives even if the
// boot wedges after this point.  Markers M0..M9 pin down exactly how far the
// chain gets (M8 = exec returned!).
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdarg.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/reboot.h>
#include <sys/syscall.h>

#define PSTORE "/sys/fs/pstore/pmsg-ramoops-0"
#define MAXBUF (8*1024*1024)

static int rep_fd = -1;
static void M(const char *fmt, ...) {
    char b[384]; va_list ap; va_start(ap, fmt);
    int n = vsnprintf(b, sizeof b, fmt, ap); va_end(ap);
    if (n < 0) return;
    if ((size_t)n >= sizeof b) n = sizeof b - 1;
    if (rep_fd >= 0) { write(rep_fd, b, n); write(rep_fd, "\n", 1); fsync(rep_fd); }
    write(2, b, n); write(2, "\n", 1);
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

    M("M0 wrapper start pid=%d", getpid());

    if (access("/dev/mmcblk1", F_OK)) {
        mkdir("/dev", 0755);
        int mr = mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
        M("M1 devtmpfs mount rc=%d errno=%s", mr, strerror(errno));
    } else {
        M("M1 /dev/mmcblk1 present (no mount needed)");
    }

    if (access(PSTORE, F_OK)) {
        mkdir("/sys", 0755);
        int sr = mount("sysfs", "/sys", "sysfs", 0, NULL);
        M("M2 sysfs mount rc=%d errno=%s", sr, strerror(errno));
    } else {
        M("M2 pstore visible (no mount needed)");
    }

    char *sd_dev = "/dev/mmcblk1p1";
    if (access(sd_dev, F_OK)) {
        if (!access("/dev/mmcblk1", F_OK)) { sd_dev = "/dev/mmcblk1"; }
        else { M("M3 no SD block device found"); sd_dev = NULL; }
    }

    if (sd_dev) {
        mkdir("/mnts", 0755);
        const char *types[] = {"vfat", "exfat", "msdos", NULL};
        int rc = -1; const char *used = NULL;
        for (int i = 0; types[i]; i++) {
            rc = mount(sd_dev, "/mnts", types[i], 0, NULL);
            if (rc == 0) { used = types[i]; break; }
        }
        M("M3 mount %s rc=%d fs=%s errno=%s", sd_dev, rc, used ? used : "none", strerror(errno));
        if (rc == 0) {
            mkdir("/mnts/ane", 0755);
            rep_fd = open("/mnts/ane/report.txt", O_WRONLY | O_CREAT | O_TRUNC, 0666);
            M("M4 SD ready, report fd=%d", rep_fd);

            int fd = open(PSTORE, O_RDONLY);
            if (fd >= 0) {
                unsigned char *buf = malloc(MAXBUF); size_t blen = 0;
                ssize_t r;
                while (buf && (r = read(fd, buf + blen, MAXBUF - blen)) > 0) { blen += (size_t)r; if (blen >= MAXBUF) break; }
                close(fd);
                M("M5 pstore read %zu bytes", blen);
                if (buf && blen > 0) {
                    int df = open("/mnts/ane/pmsg_dump.bin", O_WRONLY | O_CREAT | O_TRUNC, 0666);
                    if (df >= 0) {
                        ssize_t w = write(df, buf, blen); fsync(df); close(df);
                        M("M6 dump written %zd bytes", w);
                    } else M("M6 dump open fail errno=%s", strerror(errno));
                }
            } else {
                M("M5 pstore open fail errno=%s", strerror(errno));
            }
            sync();
        }
    }

    M("M7 exec /init.hw now");
    execv("/init.hw", argv);
    M("M8 exec returned errno=%d(%s) — init chain broken", errno, strerror(errno));
    sync();
    syscall(SYS_reboot, 0xfee1dead, 672274793, 0x01234567, 0);
    M("M9 reboot syscall returned errno=%d", errno);
    for (;;) pause();
}
