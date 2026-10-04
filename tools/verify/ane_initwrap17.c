// ane_initwrap15.c — one-second watchdog, timely return.
// v14 proved: BCB write OK (32 bytes), watchdog armed OK (settimeout(10) rc=0
// val=10) — yet no reset ever came.  The kernel's own kicker (the "watchdog
// kick now" kworker) evidently feeds the dog faster than 10 s.  The counter:
// set the timeout to ONE second and pet it ourselves every 400 ms while the
// observation runs; the moment our pets stop, the hardware bites in ~1 s,
// no matter what the kernel kicker does (it cannot be faster than 1 s).
// Observation window: ~20 s (the init's forked child lives its 5 s; markers
// land on the SD).  Then stop petting -> reset -> LK reads BCB -> fastboot.
// Fallback: if we are still alive after the stop, force a reboot syscall.
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
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <sched.h>
#include <signal.h>

#define SDDIR "/mnts/ane"
#define MAXBUF (16*1024*1024)
#define MISC_DEV "/dev/mmcblk0p20"
#define WATCHDOG_DEV "/dev/watchdog"
#define WDIOC_SETTIMEOUT _IOWR('W', 6, int)
#define WDIOC_GETTIMEOUT _IOR('W', 7, int)
static int wd_fd = -1;

static char rep2[8192]; static size_t rl2 = 0;
static void M(const char *fmt, ...) {
    char b[384]; va_list ap; va_start(ap, fmt);
    int n = vsnprintf(b, sizeof b, fmt, ap); va_end(ap);
    if (n < 0) return;
    if ((size_t)n >= sizeof b) n = sizeof b - 1;
    if (rl2 + (size_t)n + 2 < sizeof rep2) { memcpy(rep2+rl2, b, (size_t)n); rl2 += (size_t)n; rep2[rl2++]='\n'; rep2[rl2]=0; }
    int fd = open(SDDIR "/report.txt", O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd >= 0) { write(fd, b, (size_t)n); write(fd, "\n", 1); fsync(fd); close(fd); }
}

static int copy_nb(const char *src, const char *dstname, size_t maxlen) {
    int in = open(src, O_RDONLY | O_NONBLOCK);
    if (in < 0) return -1;
    char dst[256]; snprintf(dst, sizeof dst, "%s/%s", SDDIR, dstname);
    int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (out < 0) { close(in); return -1; }
    char *buf = malloc(262144);
    size_t tot = 0; ssize_t r;
    for (;;) {
        if (!buf || tot >= maxlen) break;
        r = read(in, buf, 262144);
        if (r > 0) { write(out, buf, (size_t)r); tot += (size_t)r; }
        else break;
    }
    free(buf); close(in); fsync(out); close(out);
    return (int)tot;
}

static void pet(void) { if (wd_fd >= 0) { ssize_t r = write(wd_fd, "\0", 1); (void)r; } }

static void fault_handler(int sig, siginfo_t *si, void *uc) {
    (void)uc;
    M("FAULT sig=%d addr=%p code=%d pid=%d", sig, si ? si->si_addr : (void*)0,
      si ? si->si_code : -1, getpid());
    // Write a second copy to a dedicated file (belt and braces).
    int fd = open(SDDIR "/FAULT.txt", O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd >= 0) {
        char b[128];
        int n = snprintf(b, sizeof b, "sig=%d addr=%p code=%d\n", sig,
                         si ? si->si_addr : (void*)0, si ? si->si_code : -1);
        write(fd, b, (size_t)n); fsync(fd); close(fd);
    }
    for (;;) pause();
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

    // ---- SD mount ----
    if (access("/dev/mmcblk1", F_OK)) { mkdir("/dev", 0755); mount("devtmpfs", "/dev", "devtmpfs", 0, NULL); }
    mkdir("/mnts", 0755);
    const char *sd_dev = access("/dev/mmcblk1p1", F_OK) ? "/dev/mmcblk1" : "/dev/mmcblk1p1";
    const char *types[] = {"vfat", "exfat", "msdos", NULL};
    int rc = -1;
    for (int i = 0; types[i]; i++) { rc = mount(sd_dev, "/mnts", types[i], 0, NULL); if (rc == 0) break; }
    mkdir(SDDIR, 0755);

    M("M0 v17 start pid=%d sd rc=%d", getpid(), rc);

    // Fault handlers: if a PID1 fault panics the kernel, the panic message is
    // unreachable (no VT, pstore unregistered).  Handle the fault, log its
    // address, then keep the process alive so the watchdog performs a clean
    // reset instead of a panic.
    {
        struct sigaction sa;
        memset(&sa, 0, sizeof sa);
        sa.sa_sigaction = fault_handler;
        sa.sa_flags = SA_SIGINFO;
        sigaction(SIGSEGV, &sa, NULL);
        sigaction(SIGBUS, &sa, NULL);
        sigaction(SIGILL, &sa, NULL);
        sigaction(SIGFPE, &sa, NULL);
        sigaction(SIGABRT, &sa, NULL);
        M("M-sig: handlers installed");
    }

    // ---- FIRST STRIKE: BCB + 1-second watchdog ----
    {
        int mf = open(MISC_DEV, O_WRONLY);
        if (mf >= 0) { ssize_t mw = pwrite(mf, "bootonce-bootloader\0\0\0\0\0\0\0\0\0\0\0\0", 32, 0); fsync(mf); close(mf); M("M-bcb: written (%zd bytes)", mw); }
        else M("M-bcb: misc open fail errno=%d(%s)", errno, strerror(errno));
        wd_fd = open(WATCHDOG_DEV, O_WRONLY);
        if (wd_fd >= 0) {
            int t = 1;
            int ir = ioctl(wd_fd, WDIOC_SETTIMEOUT, &t);
            int back = 0; ioctl(wd_fd, WDIOC_GETTIMEOUT, &back);
            M("M-wd: armed fd=%d set rc=%d val=%d back=%d", wd_fd, ir, t, back);
            pet();
        } else M("M-wd: open fail errno=%d(%s)", errno, strerror(errno));
    }

    // ---- sysfs/pstore look ----
    if (access("/sys/fs/pstore", F_OK)) { mkdir("/sys", 0755); mount("sysfs", "/sys", "sysfs", 0, NULL); }
    copy_nb("/dev/kmsg", "kmsg_boot.txt", 8*1024*1024);

    // ---- fork the init as a child; then the observation window (petting) ----
    pid_t init_pid = fork();
    if (init_pid == 0) { execv("/init.hw", argv); execv("/init.real", argv); _exit(127); }

    // Dedicated petter/observer child: survives independently of the shepherd.
    pid_t petter = fork();
    if (petter == 0) {
        for (int i = 1; i <= 62; i++) {          // ~25 s
            pet();
            usleep(400*1000);
            M("[petter] alive t+%d.%ds", i*4/10, (i*4)%10);   // every tick
            if (i % 10 == 0) {                   // every ~4 s: kmsg snapshot
                char name[64]; snprintf(name, sizeof name, "kmsg_t%02ds.txt", i*4/10);
                int n = copy_nb("/dev/kmsg", name, 4*1024*1024);
                M("[petter] t+%ds kmsg=%dB", i*4/10, n);
            }
        }
        M("[petter] done at ~25 s, stopping pets");
        _exit(0);
    }
    M("M1 init forked pid=%d; petter pid=%d; both petting", init_pid, petter);
    if (unshare(CLONE_NEWNS) == 0) mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL);

    // ~20 s of observation: pet every 400 ms; snapshot kmsg + pstore every 4 s
    for (int i = 1; i <= 50; i++) {
        pet();
        usleep(400*1000);
        if (i % 10 == 0) {
            char name[64]; snprintf(name, sizeof name, "kmsg_t%02ds.txt", i*4/10);
            int n = copy_nb("/dev/kmsg", name, 4*1024*1024);
            M("t+%ds kmsg=%dB children=%d", i*4/10, n, -1);
            if (i % 20 == 0) {
                char lst[64]; snprintf(lst, sizeof lst, "pstore_ls_t%02ds.txt", i*4/10);
                DIR *d = opendir("/sys/fs/pstore");
                if (d) {
                    char dst[256]; snprintf(dst, sizeof dst, "%s/%s", SDDIR, lst);
                    int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0666);
                    struct dirent *e; int cnt = 0;
                    while ((e = readdir(d))) { if (out >= 0 && e->d_name[0] != '.') { write(out, e->d_name, strlen(e->d_name)); write(out, "\n", 1); cnt++; } }
                    if (out >= 0) { fsync(out); close(out); }
                    closedir(d);
                    M("t+%ds pstore entries=%d", i*4/10, cnt);
                }
            }
        }
    }

    // ---- stop petting: the dog bites within ~1 s ----
    M("M2 observation done; STOP PETTING; reset expected in <=1 s");
    sync();
    for (int i = 0; i < 25; i++) {           // if we survive, force at ~+10 s
        usleep(400*1000);
        if (i == 24) {
            M("M3 still alive; forcing reboot");
            sync();
            syscall(SYS_reboot, 0xfee1dead, 672274793, 0x01234567, 0);
            M("M3 reboot returned errno=%d(%s)", errno, strerror(errno));
        }
    }
    for (;;) { usleep(1000*1000); }
}
