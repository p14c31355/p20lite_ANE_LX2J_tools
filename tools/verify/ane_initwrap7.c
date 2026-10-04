// ane_initwrap7.c — the direct read: /dev/pmsg0.
// Established facts from v5/v6 runs:
//  - SD channel works; markers land; exec of /init.hw succeeds (no M5);
//  - the sysfs pstore dir is EMPTY before init (ramoops probes later);
//  - /dev/pmsg0 exists already at pre-init (dev_t0.txt line 241) — PID1 root
//    can open it despite mode 0222 (CAP_DAC_OVERRIDE) and SELinux is not yet
//    enforcing.  Reading it yields the pmsg zone (our key-probe trace lives
//    there).
// v7 = v6 + { read /dev/pmsg0 first thing after the SD mount; also grab the
// boot kmsg; child gets a heartbeat from t+0 and keeps retrying pmsg0/pstore }.
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdarg.h>
#include <dirent.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/reboot.h>
#include <sys/syscall.h>

#define SDDIR "/mnts/ane"
#define MAXBUF (16*1024*1024)

static int rep_fd = -1;

static void M(const char *fmt, ...) {
    char b[384]; va_list ap; va_start(ap, fmt);
    int n = vsnprintf(b, sizeof b, fmt, ap); va_end(ap);
    if (n < 0) return;
    if ((size_t)n >= sizeof b) n = sizeof b - 1;
    if (rep_fd >= 0) { write(rep_fd, b, n); write(rep_fd, "\n", 1); fsync(rep_fd); }
}

static int copy_dev_to_sd(const char *src, const char *dstname, size_t maxlen, int nonblock) {
    int flags = O_RDONLY | (nonblock ? O_NONBLOCK : 0);
    int in = open(src, flags);
    if (in < 0) { M("read %s open fail errno=%d(%s)", src, errno, strerror(errno)); return -1; }
    char dst[256]; snprintf(dst, sizeof dst, "%s/%s", SDDIR, dstname);
    int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (out < 0) { close(in); M("sd %s open fail errno=%d(%s)", dst, errno, strerror(errno)); return -1; }
    char *buf = malloc(262144);
    size_t tot = 0; ssize_t r;
    while (buf && tot < maxlen && (r = read(in, buf, 262144)) > 0) {
        write(out, buf, (size_t)r); tot += (size_t)r;
    }
    int rerr = errno;
    free(buf); close(in); fsync(out); close(out);
    M("copied %s -> %s (%zu bytes, last errno=%d)", src, dstname, tot, rerr);
    return (int)tot;
}

static void list_dir_to_sd(const char *path, const char *dstname) {
    char dst[256]; snprintf(dst, sizeof dst, "%s/%s", SDDIR, dstname);
    DIR *d = opendir(path);
    if (!d) { M("ls %s opendir fail errno=%d(%s)", path, errno, strerror(errno)); return; }
    int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    struct dirent *e; int n = 0;
    while ((e = readdir(d))) {
        if (out >= 0) { write(out, e->d_name, strlen(e->d_name)); write(out, "\n", 1); }
        n++;
    }
    if (out >= 0) { fsync(out); close(out); }
    closedir(d);
    M("listed %s (%d entries) -> %s", path, n, dstname);
}

static void try_pstore_at(const char *tag) {
    const char *paths[] = {"/sys/fs/pstore/pmsg-ramoops-0", "/mntsys/fs/pstore/pmsg-ramoops-0", NULL};
    char dst[128];
    for (int i = 0; paths[i]; i++) {
        if (access(paths[i], F_OK) == 0) {
            snprintf(dst, sizeof dst, "pmsg_t%s.bin", tag);
            copy_dev_to_sd(paths[i], dst, MAXBUF, 0);
            return;
        }
    }
    M("[child] pstore sysfs not visible at t+%s", tag);
}

static void child_after_exec(void) {
    M("[child] alive pid=%d", getpid());     // first thing: prove scheduling
    copy_dev_to_sd("/dev/pmsg0", "pmsg_dev_t0.bin", MAXBUF, 1);
    for (int i = 1; i <= 600; i++) {
        usleep(5*1000*1000);                  // heartbeat every 5s (50 min)
        M("[hb] t+%ds", i*5);
        if (i == 4)  { copy_dev_to_sd("/dev/kmsg", "kmsg_t20.txt", 4*1024*1024, 0); }
        if (i == 10) {
            mkdir("/mntproc", 0755);
            int pr = mount("proc", "/mntproc", "proc", 0, NULL);
            M("[child] proc mount rc=%d errno=%s", pr, strerror(errno));
            if (pr == 0) list_dir_to_sd("/mntproc", "proc_t50.txt");
        }
        if (i == 18) { copy_dev_to_sd("/dev/kmsg", "kmsg_t90.txt", 4*1024*1024, 0); list_dir_to_sd("/dev", "dev_t90.txt"); }
        if (i % 6 == 0) {                     // every 30s: pmsg0 + pstore retries
            copy_dev_to_sd("/dev/pmsg0", "pmsg_dev_latest.bin", MAXBUF, 1);
            try_pstore_at("rt");
        }
    }
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

    // ---- SD first: all markers + outputs live here. ----
    if (access("/dev/mmcblk1", F_OK)) {
        mkdir("/dev", 0755);
        mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
    }
    mkdir("/mnts", 0755);
    const char *sd_dev = access("/dev/mmcblk1p1", F_OK) ? "/dev/mmcblk1" : "/dev/mmcblk1p1";
    const char *types[] = {"vfat", "exfat", "msdos", NULL};
    int rc = -1;
    for (int i = 0; types[i]; i++) {
        rc = mount(sd_dev, "/mnts", types[i], 0, NULL);
        if (rc == 0) break;
    }
    mkdir(SDDIR, 0755);
    rep_fd = open(SDDIR "/report.txt", O_WRONLY | O_CREAT | O_TRUNC, 0666);

    M("M0 v7 start pid=%d sd_dev=%s mount rc=%d errno=%s", getpid(), sd_dev, rc, strerror(errno));

    // ---- THE MAIN EVENT: /dev/pmsg0 (the pmsg zone), plus the boot kmsg. ----
    copy_dev_to_sd("/dev/pmsg0", "pmsg_dev.bin", MAXBUF, 1);
    copy_dev_to_sd("/dev/kmsg", "kmsg_boot.txt", 4*1024*1024, 0);
    M("M1 pmsg0+kmsg copied");

    // ---- sysfs + pstore diagnosis (v6 flow) ----
    M("M1b access /sys=%d /sys/fs=%d /sys/fs/pstore=%d",
      access("/sys", F_OK), access("/sys/fs", F_OK), access("/sys/fs/pstore", F_OK));
    int sr = mount("sysfs", "/sys", "sysfs", 0, NULL);
    M("M2 mount sysfs /sys rc=%d errno=%s", sr, strerror(errno));
    if (access("/sys/fs/pstore", F_OK)) {
        mkdir("/mntsys", 0755);
        int sr2 = mount("sysfs", "/mntsys", "sysfs", 0, NULL);
        M("M3 mount sysfs /mntsys rc=%d errno=%s", sr2, strerror(errno));
    } else {
        M("M3 /sys/fs/pstore visible already");
    }
    list_dir_to_sd("/sys/fs/pstore", "pstore_ls.txt");

    // ---- hand over ----
    pid_t pid = fork();
    if (pid == 0) { child_after_exec(); _exit(0); }
    M("M4 child forked pid=%d; exec /init.hw now", pid);
    execv("/init.hw", argv);
    M("M5 exec returned errno=%d(%s)", errno, strerror(errno));
    sync();
    syscall(SYS_reboot, 0xfee1dead, 672274793, 0x01234567, 0);
    for (;;) pause();
}
