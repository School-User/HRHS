#!/bin/bash
# CyberPatriot Ubuntu 22.04 Audit Script
# RUN AS: bash cyberpatriot_audit.sh > audit_$(date +%Y%m%d_%H%M%S).txt 2>&1
# This script ONLY READS - makes no changes

set -e
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR=~/cp_audit_${TIMESTAMP}
mkdir -p $OUTDIR

echo "=== CYBERPATRIOT AUDIT START: $(date) ==="
echo "Machine: $(hostname) | Ubuntu: $(lsb_release -ds)"
echo ""

# ===== USERS & GROUPS =====
echo "=== 1. USERS & GROUPS ==="
echo "--- /etc/passwd (non-system, uid >= 1000) ---"
awk -F: '$3 >= 1000 {print}' /etc/passwd

echo ""
echo "--- /etc/group (check adm, sudo, root) ---"
grep -E "^(root|adm|sudo):" /etc/group

echo ""
echo "--- All groups for each home user ---"
for u in $(ls /home 2>/dev/null); do
  echo "$u: $(id $u 2>/dev/null || echo 'NONEXISTENT')"
done

echo ""
echo "--- Password status (NP=no password, P=active, L=locked) ---"
for u in $(awk -F: '$3 >= 1000 {print $1}' /etc/passwd); do
  passwd -S $u 2>/dev/null || true
done

# ===== SERVICES & DAEMONS =====
echo ""
echo "=== 2. SERVICES & DAEMONS ==="
echo "--- Enabled systemd services ---"
systemctl list-unit-files --type=service | grep enabled

echo ""
echo "--- Running services (filter for suspicious) ---"
systemctl list-units --type=service --state=running | grep -iE "(ftp|telnet|xrdp|wireshark|nmap|john|snap|cups|bluetooth|avahi)"

echo ""
echo "--- Network listeners (netstat -tupln) ---"
netstat -tupln 2>/dev/null | grep -v "^Active" | sort -k4 -t: -n

# ===== SOFTWARE PACKAGES =====
echo ""
echo "=== 3. SOFTWARE PACKAGES (Suspicious) ==="
echo "--- Common CyberPatriot 'bad' software ---"
for pkg in telnet ftp xrdp wireshark nmap john ophcrack amule transmission bittorrent vsftpd openssh-server openssh-client cups bluetooth avahi-daemon; do
  dpkg -l | grep "^ii.*$pkg" && echo "  ✗ $pkg INSTALLED" || true
done

echo ""
echo "--- Snap packages ---"
snap list 2>/dev/null || echo "snapd not installed"

# ===== CRON JOBS =====
echo ""
echo "=== 4. CRON JOBS ==="
echo "--- /etc/cron* files ---"
ls -laR /etc/cron* 2>/dev/null | head -50

echo ""
echo "--- User crontabs ---"
for u in $(ls /home 2>/dev/null); do
  crontab -u $u -l 2>/dev/null && echo "  [crontab for $u found]" || true
done
crontab -u root -l 2>/dev/null && echo "  [crontab for root found]" || true

# ===== FIREWALL =====
echo ""
echo "=== 5. FIREWALL (UFW) ==="
ufw status verbose 2>/dev/null || echo "UFW not installed or disabled"

echo ""
echo "--- iptables rules ---"
iptables -L -n -v 2>/dev/null | head -30

# ===== SSH CONFIG =====
echo ""
echo "=== 6. SSH CONFIGURATION ==="
echo "--- Current sshd settings ---"
sshd -T 2>/dev/null | sort

# ===== PASSWORD POLICIES =====
echo ""
echo "=== 7. PASSWORD POLICIES ==="
echo "--- /etc/login.defs (key lines) ---"
grep -iE "PASS_|ENCRYPT_METHOD|LOGIN_" /etc/login.defs | grep -v "^#"

echo ""
echo "--- /etc/security/pwquality.conf ---"
grep -v "^#" /etc/security/pwquality.conf | grep -v "^$"

echo ""
echo "--- PAM files (common-password, common-auth) ---"
echo "common-password:"
head -20 /etc/pam.d/common-password
echo ""
echo "common-auth:"
head -20 /etc/pam.d/common-auth

# ===== FILE PERMISSIONS =====
echo ""
echo "=== 8. FILE PERMISSIONS (Red Flags) ==="
echo "--- SUID/SGID in /home ---"
find /home -perm /6000 2>/dev/null

echo ""
echo "--- World-writable files in /home ---"
find /home -perm -002 2>/dev/null | head -20

echo ""
echo "--- World-writable /tmp, /var/tmp ---"
ls -ld /tmp /var/tmp 2>/dev/null

# ===== KERNEL SETTINGS (sysctl) =====
echo ""
echo "=== 9. KERNEL / SYSCTL SETTINGS ==="
echo "--- Critical kernel params ---"
sysctl -a 2>/dev/null | grep -E "(net.ipv4|kernel.panic|kernel.randomize|kernel.dmesg)" | sort

# ===== SUSPICIOUS PROCESSES =====
echo ""
echo "=== 10. RUNNING PROCESSES (Suspicious) ==="
ps -ef | grep -iE "(python3?|perl|ruby|php|nc|ncat|/bin/sh|bash -i)" | grep -v grep

# ===== LOG FILES =====
echo ""
echo "=== 11. RECENT LOG ACTIVITY ==="
echo "--- Last auth failures (last 20 lines) ---"
tail -20 /var/log/auth.log 2>/dev/null | grep -i "fail\|invalid\|refused" || echo "No recent failures or log unreadable"

echo ""
echo "--- Last system changes (var/log recent) ---"
ls -ltr /var/log | tail -15

# ===== SUMMARY =====
echo ""
echo "=== AUDIT COMPLETE: $(date) ==="
echo "Review output above and compare to READ ME requirements"
echo "NO CHANGES MADE - this was read-only"
