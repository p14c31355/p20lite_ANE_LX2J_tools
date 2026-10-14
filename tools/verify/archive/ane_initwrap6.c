// ane_initwrap6.c — full visibility edition.
// Everything learned so far:
//  - the SD channel works (cards written by pre-init PID1 are readable via
//    /storage after a stock boot);
//  - the exec of /init.hw succeeds; the boot wedges AFTER that;
//  - the pstore path was ENOENT (sysfs handling needs diagnosis).
// v6 therefore:
//  - mounts the SD FIRST and writes EVERY marker to it (M0 onward);
//  - records /dev listing, sysfs mount attempts (incl. alternate mountpoint),
//    and the pstore directory listing;
//  - reads every pstore file and copies them to the SD;
//  - forks a child that AFTER exec runs (post-boot, stuck or not):
//      t+20s: dump /dev/kmsg to SD (kernel + init logs!)
//      t+50s: mount proc, list all processes to SD
//      t+90s: second kmsg dump (delta)
//    then exits.  This child survives the exec and can work even when the
//    init chain is wedged.
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

static void dump_file_to_sd(const char *src, const char *dstname, size_t maxlen) {
    char dst[256]; snprintf(dst, sizeof dst, "%s/%s", SDDIR, dstname);
    int in = open(src, O_RDONLY);
    if (in < 0) { M("read %s open fail errno=%d(%s)", src, errno, strerror(errno)); return; }
    int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (out < 0) { close(in); M("sd %s open fail errno=%d(%s)", dst, errno, strerror(errno)); return; }
    char *buf = malloc(262144);
    size_t tot = 0; ssize_t r;
    while (buf && tot < maxlen && (r = read(in, buf, 262144)) > 0) {
        write(out, buf, (size_t)r); tot += (size_t)r;
    }
    free(buf); close(in); fsync(out); close(out);
    M("copied %s -> %s (%zu bytes)", src, dstname, tot);
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
    // The pstore device may only appear after the kernel module loads during
    // init (v5 saw ENOENT pre-init).  Try both mountpoints at each checkpoint.
    const char *paths[] = {"/sys/fs/pstore/pmsg-ramoops-0", "/mntsys/fs/pstore/pmsg-ramoops-0", NULL};
    char dst[128];
    for (int i = 0; paths[i]; i++) {
        if (access(paths[i], F_OK) == 0) {
            snprintf(dst, sizeof dst, "pmsg_t%s.bin", tag);
            dump_file_to_sd(paths[i], dst, MAXBUF);
            return;
        }
    }
    M("[child] pstore not visible at t+%ss", tag);
}

static void child_after_exec(void) {
    // Survives the exec; runs post-boot even if the init chain is wedged.
    for (int i = 0; i < 20; i++) usleep(1000*1000);          // t+20s
    dump_file_to_sd("/dev/kmsg", "kmsg_t20.txt", 4*1024*1024);
    try_pstore_at("20");
    for (int i = 0; i < 30; i++) usleep(1000*1000);          // t+50s
    mkdir("/mntproc", 0755);
    int pr = mount("proc", "/mntproc", "proc", 0, NULL);
    M("[child] proc mount rc=%d errno=%s", pr, strerror(errno));
    if (pr == 0) list_dir_to_sd("/mntproc", "proc_t50.txt");
    try_pstore_at("50");
    for (int i = 0; i < 40; i++) usleep(1000*1000);          // t+90s
    dump_file_to_sd("/dev/kmsg", "kmsg_t90.txt", 4*1024*1024);
    list_dir_to_sd("/dev", "dev_t90.txt");
    try_pstore_at("90");
    dump_file_to_sd("/sys/fs/pstore/console-ramoops-0", "console_t90.txt", MAXBUF);
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

    // ---- Step 1: SD first, so ALL markers survive. ----
    if (access("/dev/mmcblk1", F_OK)) {
        mkdir("/dev", 0755);
        mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
    }
    mkdir("/mnts", 0755);
    const char *types[] = {"vfat", "exfat", "msdos", NULL};
    const char *sd_dev = access("/dev/mmcblk1p1", F_OK) ? "/dev/mmcblk1" : "/dev/mmcblk1p1";
    int rc = -1;
    for (int i = 0; types[i]; i++) {
        rc = mount(sd_dev, "/mnts", types[i], 0, NULL);
        if (rc == 0) break;
    }
    mkdir(SDDIR, 0755);
    rep_fd = open(SDDIR "/report.txt", O_WRONLY | O_CREAT | O_TRUNC, 0666);

    M("M0 v6 start pid=%d sd_dev=%s mount rc=%d errno=%s", getpid(), sd_dev, rc, strerror(errno));
    list_dir_to_sd("/dev", "dev_t0.txt");

    // ---- Step 2: sysfs + pstore diagnosis ----
    M("M1 access /sys=%d /sys/fs=%d /sys/fs/pstore=%d",
      access("/sys", F_OK), access("/sys/fs", F_OK), access("/sys/fs/pstore", F_OK));
    int sr = mount("sysfs", "/sys", "sysfs", 0, NULL);
    M("M2 mount sysfs /sys rc=%d errno=%s", sr, strerror(errno));
    if (access("/sys/fs/pstore", F_OK)) {
        mkdir("/mntsys", 0755);
        int sr2 = mount("sysfs", "/mntsys", "sysfs", 0, NULL);
        M("M3 mount sysfs /mntsys rc=%d errno=%s", sr2, strerror(errno));
        M("M3b access /mntsys/fs/pstore=%d", access("/mntsys/fs/pstore", F_OK));
    } else {
        M("M3 /sys/fs/pstore visible already");
    }

    const char *pdirs[] = {"/sys/fs/pstore", "/mntsys/fs/pstore", NULL};
    for (int i = 0; pdirs[i]; i++) {
        if (!access(pdirs[i], F_OK)) {
            list_dir_to_sd(pdirs[i], "pstore_ls.txt");
            char p[256];
            snprintf(p, sizeof p, "%s/pmsg-ramoops-0", pdirs[i]);
            dump_file_to_sd(p, "pmsg-ramoops-0.bin", MAXBUF);
            snprintf(p, sizeof p, "%s/console-ramoops-0", pdirs[i]);
            dump_file_to_sd(p, "console-ramoops-0.txt", MAXBUF);
            char dst[256];
            for (int k = 0; k < 8; k++) {
                snprintf(p, sizeof p, "%s/dmesg-ramoops-%d", pdirs[i], k);
                snprintf(dst, sizeof dst, "dmesg-ramoops-%d.txt", k);
                dump_file_to_sd(p, dst, MAXBUF);
            }
            break;
        }
    }

    // ---- Step 3: fork the after-exec child, then hand over. ----
    pid_t pid = fork();
    if (pid == 0) { child_after_exec(); _exit(0); }
    M("M4 child forked pid=%d; exec /init.hw now", pid);
    execv("/init.hw", argv);
    M("M5 exec returned errno=%d(%s)", errno, strerror(errno));
    sync();
    syscall(SYS_reboot, 0xfee1dead, 672274793, 0x01234567, 0);
    M("M6 reboot returned errno=%d", errno);
    for (;;) pause();
}
