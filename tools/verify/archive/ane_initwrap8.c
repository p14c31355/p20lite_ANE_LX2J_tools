// ane_initwrap8.c — fixed kmsg (O_NONBLOCK), fully instrumented child.
// Lessons folded in:
//  - v7 hung because /dev/kmsg was read without O_NONBLOCK (blocks when the
//    log is momentarily empty).  All kmsg reads here are non-blocking and
//    loop until EAGAIN.  (The wrapper itself is fine: glibc 2.35 on 4.4 only
//    triggers the Huawei "syscall 293" monitor dump, non-fatally.)
//  - pstore is a real filesystem mounted on /sys/fs/pstore in Android; as
//    uid 0 the child can enumerate it and read the ramoops module parameters.
//  - The child survives the exec; its kmsg captures AFTER init started — that
//    is the evidence we need for the wedge.
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

// Non-blocking safe copy: open with O_NONBLOCK, read until EAGAIN/EOF.
static int copy_nb(const char *src, const char *dstname, size_t maxlen) {
    int in = open(src, O_RDONLY | O_NONBLOCK);
    if (in < 0) { M("read %s open fail errno=%d(%s)", src, errno, strerror(errno)); return -1; }
    char dst[256]; snprintf(dst, sizeof dst, "%s/%s", SDDIR, dstname);
    int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (out < 0) { close(in); M("sd %s open fail errno=%d(%s)", dst, errno, strerror(errno)); return -1; }
    char *buf = malloc(262144);
    size_t tot = 0; ssize_t r; int last = 0;
    for (;;) {
        if (!buf || tot >= maxlen) break;
        r = read(in, buf, 262144);
        if (r > 0) { write(out, buf, (size_t)r); tot += (size_t)r; }
        else { last = errno; break; }
    }
    free(buf); close(in); fsync(out); close(out);
    M("copied %s -> %s (%zu bytes, end errno=%d)", src, dstname, tot, last);
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

static void cat_params_to_sd(void) {
    char dst[256]; snprintf(dst, sizeof dst, "%s/ramoops_params.txt", SDDIR);
    const char *names[] = {"ecc","pmsg_size","dump_oops","record_size","mem_address",
                           "ftrace_size","console_size","mem_size","mem_type", NULL};
    int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    for (int i = 0; names[i]; i++) {
        char p[192]; snprintf(p, sizeof p, "/sys/module/ramoops/parameters/%s", names[i]);
        char v[256] = "(unreadable)"; int fd = open(p, O_RDONLY);
        if (fd >= 0) { ssize_t r = read(fd, v, sizeof v - 1); if (r > 0) v[r] = 0; close(fd); }
        if (out >= 0) { char line[320]; int l = snprintf(line, sizeof line, "%s = %s", names[i], v); write(out, line, (size_t)l); }
    }
    if (out >= 0) { fsync(out); close(out); }
    M("ramoops params dumped");
}

static void child_after_exec(void) {
    M("[child] alive pid=%d", getpid());          // scheduling proof, t+0
    for (int i = 1; i <= 480; i++) {              // heartbeat every 5s, 40 min
        usleep(5*1000*1000);
        M("[hb] t+%ds", i*5);
        if (i == 4) {                             // t+20: post-exec kmsg (the prize)
            copy_nb("/dev/kmsg", "kmsg_t20.txt", 4*1024*1024);
            list_dir_to_sd("/sys/fs/pstore", "pstore_ls_t20.txt");
            cat_params_to_sd();
        }
        if (i == 10) {                            // t+50: processes
            mkdir("/mntproc", 0755);
            int pr = mount("proc", "/mntproc", "proc", 0, NULL);
            M("[child] proc mount rc=%d errno=%s", pr, strerror(errno));
            if (pr == 0) list_dir_to_sd("/mntproc", "proc_t50.txt");
        }
        if (i == 18) {                            // t+90: kmsg + dev
            copy_nb("/dev/kmsg", "kmsg_t90.txt", 4*1024*1024);
            list_dir_to_sd("/dev", "dev_t90.txt");
        }
        if (i % 6 == 0) {                         // every 30s: fresh kmsg + pstore
            copy_nb("/dev/kmsg", "kmsg_latest.txt", 4*1024*1024);
            list_dir_to_sd("/sys/fs/pstore", "pstore_ls_latest.txt");
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

    M("M0 v8 start pid=%d sd_dev=%s mount rc=%d errno=%s", getpid(), sd_dev, rc, strerror(errno));
    copy_nb("/dev/kmsg", "kmsg_boot.txt", 8*1024*1024);
    copy_nb("/proc/cmdline", "cmdline.txt", 4096);
    M("M1 kmsg+cmdline copied");

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

    pid_t pid = fork();
    if (pid == 0) { child_after_exec(); _exit(0); }
    M("M4 child forked pid=%d; exec /init.hw now", pid);
    execv("/init.hw", argv);
    M("M5 exec returned errno=%d(%s)", errno, strerror(errno));
    sync();
    syscall(SYS_reboot, 0xfee1dead, 672274793, 0x01234567, 0);
    for (;;) pause();
}
