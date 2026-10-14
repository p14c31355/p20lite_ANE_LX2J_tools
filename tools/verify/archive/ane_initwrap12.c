// ane_initwrap9.c — the shepherd design.
// Key facts earned the hard way:
//  - the wrapper's exec of /init.hw succeeds; the init then kills the forked
//    child within ~5 s (v8: "[child] alive" written, no heartbeat at t+5) and
//    the boot wedges after that window;
//  - PID 1 cannot be killed (kill(-1) exempts init/pid1), so PID 1 is the one
//    process that can watch the init's whole life from outside;
//  - /dev/kmsg is readable with O_NONBLOCK; the pstore filesystem at
//    /sys/fs/pstore may receive files once ramoops registers.
// v9: PID 1 stays alive as a shepherd; the init runs as a forked child.
// The shepherd captures, every 2 s for the first 90 s and every 30 s after:
//   kmsg, pstore listing + files (copied before anything else can consume
//   them), process table, and every child exit (waitpid) — so the init's
//   death, if it dies, is recorded with its exit status.
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
#include <sched.h>

#define SDDIR "/mnts/ane"
#define MAXBUF (16*1024*1024)

static int rep_fd = -1;
static int sd_ready = 0;

// Re-open-safe write: if the path vanished because the init switched roots or
// consumed the initramfs, re-create the mount and try again.
static int remount_sd(void);

static void M(const char *fmt, ...) {
    char b[384]; va_list ap; va_start(ap, fmt);
    int n = vsnprintf(b, sizeof b, fmt, ap); va_end(ap);
    if (n < 0) return;
    if ((size_t)n >= sizeof b) n = sizeof b - 1;
    for (int attempt = 0; attempt < 2; attempt++) {
        int fd = open(SDDIR "/report.txt", O_WRONLY | O_CREAT | O_APPEND, 0666);
        if (fd >= 0) {
            write(fd, b, n); write(fd, "\n", 1); fsync(fd); close(fd);
            return;
        }
        remount_sd();
    }
    (void)rep_fd;
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

static void list_dir_to_sd(const char *path, const char *dstname) {
    char dst[256]; snprintf(dst, sizeof dst, "%s/%s", SDDIR, dstname);
    DIR *d = opendir(path);
    if (!d) return;
    int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    struct dirent *e; int n = 0;
    while ((e = readdir(d))) {
        if (out >= 0) { write(out, e->d_name, strlen(e->d_name)); write(out, "\n", 1); }
        n++;
    }
    if (out >= 0) { fsync(out); close(out); }
    closedir(d);
}

// Copy every regular file in /sys/fs/pstore (they may be consumed by their
// readers, so the shepherd's copy is the durable one). Returns count copied.
static int harvest_pstore(const char *tag) {
    DIR *d = opendir("/sys/fs/pstore");
    if (!d) return 0;
    struct dirent *e; int n = 0;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        char src[256]; snprintf(src, sizeof src, "/sys/fs/pstore/%s", e->d_name);
        struct stat st;
        if (stat(src, &st) != 0 || !S_ISREG(st.st_mode)) continue;
        char dst[256]; snprintf(dst, sizeof dst, "PSTORE_%s_%s", tag, e->d_name);
        int r = copy_nb(src, dst, MAXBUF);
        M("[pstore] %s (%ld bytes) -> %s (%d bytes)", src, (long)st.st_size, dst, r);
        n++;
    }
    closedir(d);
    return n;
}

static void ps_to_sd(const char *dstname) {
    char dst[256]; snprintf(dst, sizeof dst, "%s/%s", SDDIR, dstname);
    DIR *d = opendir("/mntproc");
    if (!d) return;
    int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (out < 0) { closedir(d); return; }
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] < '0' || e->d_name[0] > '9') continue;
        char p[256]; snprintf(p, sizeof p, "/mntproc/%s/cmdline", e->d_name);
        char buf[512] = ""; int fd = open(p, O_RDONLY);
        if (fd >= 0) { ssize_t r = read(fd, buf, sizeof buf - 1); if (r > 0) { buf[r] = 0; for (int i = 0; i < r-1; i++) if (!buf[i]) buf[i] = ' '; } close(fd); }
        char line[600]; int l = snprintf(line, sizeof line, "pid %s: %s\n", e->d_name, buf);
        write(out, line, (size_t)l);
    }
    fsync(out); close(out); closedir(d);
}

static int remount_sd(void) {
    if (access("/dev/mmcblk1p1", F_OK)) {
        if (access("/dev/mmcblk1", F_OK)) {
            mkdir("/dev", 0755);
            mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
        }
    }
    mkdir("/mnts", 0755);
    const char *sd_dev = access("/dev/mmcblk1p1", F_OK) ? "/dev/mmcblk1" : "/dev/mmcblk1p1";
    const char *types[] = {"vfat", "exfat", "msdos", NULL};
    for (int i = 0; types[i]; i++) {
        if (mount(sd_dev, "/mnts", types[i], 0, NULL) == 0) { sd_ready = 1; break; }
    }
    mkdir(SDDIR, 0755);
    return sd_ready;
}

int main(int argc, char **argv) {
    const char *a0 = argv[0] ? argv[0] : "";
    const char *base = strrchr(a0, '/');
    base = base ? base + 1 : a0;
    if (strcmp(base, "init") != 0 || argc > 1) {
        execv("/init.hw", argv);      // ueventd/watchdogd/selinux_setup/second_stage pass-through
        execv("/init.real", argv);
        _exit(127);
    }

    // ---- SD + report first ----
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

    M("M0 v12 shepherd start pid=%d sd rc=%d errno=%s", getpid(), rc, strerror(errno));
    copy_nb("/dev/kmsg", "kmsg_boot.txt", 8*1024*1024);
    if (access("/sys/fs/pstore", F_OK)) {
        mkdir("/sys", 0755);
        mount("sysfs", "/sys", "sysfs", 0, NULL);
    }
    list_dir_to_sd("/sys/fs/pstore", "pstore_ls.txt");

    // ---- fork the init as a child; PID 1 stays as the shepherd ----
    pid_t init_pid = fork();
    if (init_pid == 0) {
        execv("/init.hw", argv);
        execv("/init.real", argv);
        _exit(127);
    }
    // The init will rearrange mounts in ITS namespace; isolate ours so our SD
    // mount cannot be unmounted/moved out from under us.
    if (unshare(CLONE_NEWNS) == 0) {
        mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL);
        M("M1b shepherd namespace privatized");
    } else {
        M("M1b unshare failed errno=%d(%s)", errno, strerror(errno));
    }
    M("M1 init forked as pid=%d - shepherd watching", init_pid);
    // world snapshot for diagnostics
    list_dir_to_sd("/", "root_ls_t0.txt");
    list_dir_to_sd("/mnts", "mnts_ls_t0.txt");

    // ---- shepherd loop ----
    mkdir("/mntproc", 0755);
    int procmounted = 0;
    M("M-loop-enter");
    for (int t = 1; t <= 1800; t++) {          // up to ~90 min at 3s/tick
        if (t <= 5) M("M-t%d pre-sleep", t);
        usleep(3*1000*1000);
        if (t <= 5) M("M-t%d slept", t);
        if (t <= 40) {                          // first 2 min: dense capture
            char name[64]; snprintf(name, sizeof name, "kmsg_t%03d.txt", t*3);
            if (t <= 5) M("M-t%d kmsg-copy-start", t);
            int rr = copy_nb("/dev/kmsg", name, 4*1024*1024);
            if (t <= 5) M("M-t%d kmsg-copy-done rc=%d", t, rr);
        } else if (t % 10 == 0) {               // after: every 30 s
            copy_nb("/dev/kmsg", "kmsg_latest.txt", 4*1024*1024);
        }
        {   // heartbeat: reopen-safe liveness proof for the shepherd itself
            int hf = open(SDDIR "/hb.txt", O_WRONLY | O_CREAT | O_APPEND, 0666);
            if (hf >= 0) { char h[32]; int hl = snprintf(h, sizeof h, "hb t=%d\n", t*3); write(hf, h, hl); fsync(hf); close(hf); }
            else remount_sd();
            if (t <= 5) M("M-t%d hb-done", t);
        }
        if (!procmounted) {
            int pr = mount("proc", "/mntproc", "proc", 0, NULL);
            if (pr == 0) { procmounted = 1; list_dir_to_sd("/mntproc", "proc_ls.txt"); }
        }
        if (procmounted && t % 2 == 0) {   // init process state (alive/zombie?)
            char sp[64]; snprintf(sp, sizeof sp, "/mntproc/%d/stat", init_pid);
            copy_nb(sp, "init_stat.txt", 4096);
            snprintf(sp, sizeof sp, "/mntproc/%d/status", init_pid);
            copy_nb(sp, "init_status.txt", 16384);
        }
        if (procmounted && t <= 40 && t % 5 == 0) ps_to_sd("ps_latest.txt");
        int hp = harvest_pstore(t <= 40 ? "e" : "l");   // early/late tag spam control
        (void)hp;
        int st = 0;
        pid_t w = waitpid(-1, &st, WNOHANG);
        if (w > 0) {
            if (WIFEXITED(st))   M("[reap] pid=%d exited code=%d", w, WEXITSTATUS(st));
            else if (WIFSIGNALED(st)) M("[reap] pid=%d killed by signal %d", w, WTERMSIG(st));
            else M("[reap] pid=%d status=0x%x", w, st);
        }
    }
    M("M2 shepherd done (90 min)");
    for (;;) pause();
}
