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

    M("M0 v21 start pid=%d sd rc=%d", getpid(), rc);

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

    // ---- MISC dump: BCB command + any sticky eRecovery override bytes ----
    // The Honor 9 Lite (same Kirin 659 generation) documents an "eRecovery
    // override persisted in misc" that forces eRecovery regardless of what the
    // BCB says.  Dump the raw head so the actual flag bytes can be identified
    // instead of guessed.
    {
        int mf = open("/dev/mmcblk0p20", O_RDONLY);
        if (mf >= 0) {
            unsigned char mb[2048];
            ssize_t rn = read(mf, mb, sizeof mb);
            close(mf);
            if (rn > 0) {
                char dst[256]; snprintf(dst, sizeof dst, "%s/misc_head.bin", SDDIR);
                int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0666);
                if (out >= 0) { ssize_t wn = write(out, mb, (size_t)rn); fsync(out); close(out); (void)wn; }
                char hex[3*64+1]; int hp = 0;
                for (int i = 0; i < 64 && i < rn; i++) hp += snprintf(hex+hp, sizeof hex - (size_t)hp, "%02x ", mb[i]);
                if (hp > 0) hex[hp] = 0;
                M("M-misc: read %zd bytes; head: %s", rn, hex);
            } else M("M-misc: read rc=%zd errno=%d", rn, errno);
        } else M("M-misc: open fail errno=%d", errno);
    }

    // ---- RDR boot-fail neutralization (eRecovery prevention) ----
    // The Huawei BFM counts consecutive unexpected reboots in a file and in the
    // bbox reserved-RAM marker; once the count exceeds unexpected-max-reboot-times
    // (DTB), the kernel restarts into erecovery by itself.  Reset the counter
    // file the same way rdr_reset_reboot_times() does (single 0 byte), and clear
    // the sticky /cache erecovery reason, on every experiment boot.
    {
        mkdir("/cache", 0755);
        int crc = mount("/dev/mmcblk0p42", "/cache", "ext4", 0, NULL);
        M("M-rdr: cache mount rc=%d errno=%d", crc, errno);
        if (crc == 0) {
            int rf = open("/cache/recovery/last_erecovery_entry", O_RDONLY);
            if (rf >= 0) {
                char rb[256]; int rn = (int)read(rf, rb, sizeof rb - 1);
                if (rn > 0) { rb[rn] = 0; M("M-rdr: reason file: %.120s", rb); }
                close(rf);
                int ul = unlink("/cache/recovery/last_erecovery_entry");
                M("M-rdr: reason unlink rc=%d errno=%d", ul, errno);
            } else M("M-rdr: no reason file errno=%d", errno);
            DIR *d = opendir("/cache/recovery");
            if (d) {
                char dst[256]; snprintf(dst, sizeof dst, "%s/cache_recovery_ls.txt", SDDIR);
                int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0666);
                struct dirent *e;
                while ((e = readdir(d))) {
                    if (out >= 0 && e->d_name[0] != '.') { write(out, e->d_name, strlen(e->d_name)); write(out, "\n", 1); }
                }
                if (out >= 0) { fsync(out); close(out); }
                closedir(d);
            }
            umount2("/cache", MNT_DETACH);
        }
        mkdir("/data", 0755);
        int drc = mount("/dev/mmcblk0p56", "/data", "f2fs", MS_RDONLY, NULL);
        M("M-rdr: data ro mount rc=%d errno=%d", drc, errno);
        if (drc == 0) {
            const char *cands[] = {
                "/data/log/reboot_times.log",
                "/data/hisi_logs/reboot_times.log",
                "/data/log/hisi_logs/reboot_times.log",
                "/data/reboot_times.log",
                NULL
            };
            const char *found = NULL;
            for (int i = 0; cands[i]; i++) {
                if (access(cands[i], F_OK) == 0) { found = cands[i]; break; }
            }
            if (found) {
                int f = open(found, O_RDONLY);
                if (f >= 0) {
                    unsigned char b = 0xFF; int rn = (int)read(f, &b, 1); close(f);
                    M("M-rdr: counter %s rn=%d val=0x%02x", found, rn, b);
                }
                int rr = mount(NULL, "/data", NULL, MS_REMOUNT, NULL);
                M("M-rdr: remount rw rc=%d errno=%d", rr, errno);
                if (rr == 0) {
                    int f2 = open(found, O_RDWR);
                    if (f2 >= 0) {
                        unsigned char z = 0; lseek(f2, 0, SEEK_SET);
                        ssize_t wn = write(f2, &z, 1); fsync(f2); close(f2);
                        M("M-rdr: counter reset wn=%zd", wn);
                    } else M("M-rdr: counter open rw fail errno=%d", errno);
                }
            } else {
                M("M-rdr: counter not found; dumping dirs");
                const char *dirs[] = {"/data/log", "/data/hisi_logs", NULL};
                for (int i = 0; dirs[i]; i++) {
                    DIR *dd = opendir(dirs[i]);
                    if (!dd) { M("M-rdr: ls %s fail errno=%d", dirs[i], errno); continue; }
                    char dst[256]; snprintf(dst, sizeof dst, "%s/data_ls_%d.txt", SDDIR, i);
                    int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0666);
                    struct dirent *e;
                    while ((e = readdir(dd))) {
                        if (out >= 0 && e->d_name[0] != '.') { write(out, e->d_name, strlen(e->d_name)); write(out, "\n", 1); }
                    }
                    if (out >= 0) { fsync(out); close(out); }
                    closedir(dd);
                    M("M-rdr: ls %s dumped", dirs[i]);
                }
            }
            umount2("/data", MNT_DETACH);
        }
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

    // ---- CLEAN RETURN: petter + clean restart with reason "bootloader". ----
    // A watchdog death is recorded as AP_S_AWDT ("unexpected") and feeds the
    // LK's fail counter toward eRecovery.  A clean restart with the reason
    // "bootloader" is exactly what `adb reboot bootloader` does: the reason is
    // stored in the PMU (set_reboot_reason -> PMU_RESET_REG) and the LK opens
    // fastboot honoring the BCB bootonce command, without counting a failure.
    // The petter keeps the 1 s watchdog fed through the reboot window; if the
    // reboot path hangs, petting stops after ~8 s and the dog still bites.
    {
        pid_t rb = fork();
        if (rb == 0) {
            for (int i = 1; i <= 20; i++) { pet(); usleep(400*1000); }
            _exit(0);
        }
        sync();
        M("M-rb: clean restart2 'bootloader' (petter pid=%d)", rb);
        syscall(SYS_reboot, 0xfee1dead, 672274793, 0xa1b2c3d4, "bootloader");
        M("M-rb: restart2 returned errno=%d; plain restart", errno);
        sync();
        syscall(SYS_reboot, 0xfee1dead, 672274793, 0x01234567, 0);
        M("M-rb: plain returned errno=%d; falling back to watchdog path", errno);
    }

    // ---- sysfs/pstore look ----
    if (access("/sys/fs/pstore", F_OK)) { mkdir("/sys", 0755); mount("sysfs", "/sys", "sysfs", 0, NULL); }
    copy_nb("/dev/kmsg", "kmsg_boot.txt", 8*1024*1024);

    // ---- petter/observer child first: it must survive our pid-1 exec. ----
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
    M("M1 petter pid=%d; execing init.hw as pid 1 next", petter);
    if (unshare(CLONE_NEWNS) == 0) mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL);

    // Magisk-style handoff: replace pid 1 (ourselves) with the stock init so it
    // runs as pid 1 exactly as the kernel intended.  The petter is a separate
    // process and survives this exec; its fd to the watchdog stays valid.
    M("M1a exec init.hw (pid 1 handoff)");
    execv("/init.hw", argv);
    execv("/init.real", argv);
    M("M1b exec FAILED errno=%d(%s); continuing observation", errno, strerror(errno));

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
