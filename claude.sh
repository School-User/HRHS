#!/bin/bash

# Aeacus Ubuntu 22.04 Vulnerability Reconnaissance Script
# Systematically checks all common scoring vectors

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

log_issue() {
    echo -e "${RED}[!] $1${NC}"
}

log_ok() {
    echo -e "${GREEN}[✓] $1${NC}"
}

log_info() {
    echo -e "${YELLOW}[*] $1${NC}"
}

# ============================================================================
# 1. USER ACCOUNTS & PERMISSIONS
# ============================================================================
log_section "USER ACCOUNTS & PERMISSIONS"

echo "Current users:"
cat /etc/passwd | cut -d: -f1,3,5 | column -t -s:

echo -e "\n${YELLOW}Checking for suspicious users:${NC}"
# Users with UID 0 (root equivalent)
if [ "$(awk -F: '$3 == 0 {print $1}' /etc/passwd | wc -l)" -gt 1 ]; then
    log_issue "Multiple UID 0 users found:"
    awk -F: '$3 == 0 {print "  - " $1}' /etc/passwd
else
    log_ok "Only root has UID 0"
fi

# Users without home directories
echo -e "\n${YELLOW}Users without home directories:${NC}"
awk -F: '$6 == "/nonexistent" || $6 == "/nologin" {print "  " $1 " -> " $6}' /etc/passwd

# Sudo group members
echo -e "\n${YELLOW}Sudo group members:${NC}"
getent group sudo | cut -d: -f4 | tr ',' '\n' | sed 's/^/  /'

# ============================================================================
# 2. SSH CONFIGURATION
# ============================================================================
log_section "SSH CONFIGURATION"

echo "Key SSH settings:"
sudo sshd -T 2>/dev/null | grep -E "^(permitrootlogin|passwordauthentication|permitemptypasswords|x11forwarding|x11uselocalhost|maxauthtries|protocol|pubkeyauthentication|permituserenvironment|compression)" | sed 's/^/  /'

echo -e "\n${YELLOW}SSH config file checks:${NC}"
if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
    log_issue "PermitRootLogin set to yes"
fi

if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
    log_issue "PasswordAuthentication enabled"
fi

if grep -q "^PermitEmptyPasswords yes" /etc/ssh/sshd_config 2>/dev/null; then
    log_issue "PermitEmptyPasswords enabled"
fi

if grep -q "^X11Forwarding yes" /etc/ssh/sshd_config 2>/dev/null; then
    log_issue "X11Forwarding enabled"
fi

# ============================================================================
# 3. SERVICES & DAEMONS
# ============================================================================
log_section "SERVICES & DAEMONS"

echo "Running services:"
systemctl list-units --type=service --state=running --no-pager 2>/dev/null | grep -E "\.service" | awk '{print "  " $1}' | head -20

echo -e "\n${YELLOW}Suspicious services (telnet, ftp, vsftpd, etc):${NC}"
systemctl is-active telnetd 2>/dev/null && log_issue "telnetd is running" || log_ok "telnetd not running"
systemctl is-active vsftpd 2>/dev/null && log_issue "vsftpd is running" || log_ok "vsftpd not running"
systemctl is-active snmpd 2>/dev/null && log_issue "snmpd is running" || log_ok "snmpd not running"

# ============================================================================
# 4. INSTALLED PACKAGES (Hacking tools, media, etc)
# ============================================================================
log_section "INSTALLED PACKAGES"

echo -e "${YELLOW}Scanning for prohibited tools:${NC}"
PROHIBITED="nmap john hashcat netcat nc-openbsd hydra nikto sqlmap aircrack airmon kismet ettercap wireshark tcpdump"

for tool in $PROHIBITED; do
    if dpkg -l 2>/dev/null | grep -q "^ii.*$tool"; then
        log_issue "Prohibited tool installed: $tool"
    fi
done

log_ok "Scan complete"

# ============================================================================
# 5. PROHIBITED FILES (Media, documents, scripts)
# ============================================================================
log_section "PROHIBITED FILES"

echo -e "${YELLOW}Scanning for media files (mp3, wav, flac, m4a):${NC}"
find / -type f \( -name "*.mp3" -o -name "*.wav" -o -name "*.flac" -o -name "*.m4a" \) 2>/dev/null | sed 's/^/  /'

echo -e "\n${YELLOW}Scanning for suspicious scripts in home directories:${NC}"
find /home /root -type f \( -name "*.sh" -o -name "*.py" -o -name "*.pl" \) 2>/dev/null | sed 's/^/  /'

echo -e "\n${YELLOW}Scanning for common exploit/crack locations:${NC}"
for dir in "/opt/crack" "/opt/exploit" "/opt/hacking" "/tmp/tools" "/var/tmp/tools"; do
    if [ -d "$dir" ]; then
        log_issue "Suspicious directory exists: $dir"
        ls -la "$dir" 2>/dev/null | sed 's/^/  /'
    fi
done

# ============================================================================
# 6. FILE PERMISSIONS & OWNERSHIP
# ============================================================================
log_section "FILE PERMISSIONS & OWNERSHIP"

echo -e "${YELLOW}SUID/SGID binaries (should be minimal):${NC}"
find / -perm /4000 -o -perm /2000 2>/dev/null | grep -v "^/sys\|^/proc\|^/dev" | head -30 | sed 's/^/  /'

echo -e "\n${YELLOW}World-writable files/directories:${NC}"
find / -perm -002 -type f 2>/dev/null | grep -v "^/sys\|^/proc\|^/dev\|^/tmp\|^/var/tmp" | head -20 | sed 's/^/  /'

echo -e "\n${YELLOW}Checking /etc/sudoers permissions:${NC}"
ls -la /etc/sudoers 2>/dev/null | sed 's/^/  /'

# ============================================================================
# 7. PASSWORD POLICY & ACCOUNTS
# ============================================================================
log_section "PASSWORD POLICY & ACCOUNTS"

echo -e "${YELLOW}Password policy (/etc/login.defs):${NC}"
grep -E "^(PASS_MAX_DAYS|PASS_MIN_DAYS|PASS_WARN_AGE|PASS_MIN_LEN)" /etc/login.defs 2>/dev/null | sed 's/^/  /'

echo -e "\n${YELLOW}Accounts with empty passwords:${NC}"
awk -F: '($2 == "" || $2 == "!" || $2 == "*") {print "  " $1}' /etc/shadow 2>/dev/null || echo "  Cannot read /etc/shadow (need root)"

echo -e "\n${YELLOW}Locked/disabled accounts:${NC}"
awk -F: '($2 ~ /^\!/) {print "  " $1}' /etc/shadow 2>/dev/null || echo "  Cannot read /etc/shadow (need root)"

# ============================================================================
# 8. CRON JOBS
# ============================================================================
log_section "CRON JOBS"

echo -e "${YELLOW}System cron jobs:${NC}"
for user in root www-data; do
    if crontab -u $user -l 2>/dev/null; then
        echo "  User: $user"
        crontab -u $user -l 2>/dev/null | sed 's/^/    /'
    fi
done

# ============================================================================
# 9. NETWORK CONFIGURATION
# ============================================================================
log_section "NETWORK CONFIGURATION"

echo -e "${YELLOW}/etc/hosts:${NC}"
cat /etc/hosts | sed 's/^/  /'

echo -e "\n${YELLOW}Firewall status (UFW):${NC}"
sudo ufw status 2>/dev/null | sed 's/^/  /' || echo "  UFW not installed or not active"

echo -e "\n${YELLOW}Open ports (netstat/ss):${NC}"
ss -tlnp 2>/dev/null | grep LISTEN | awk '{print "  " $4}' || netstat -tlnp 2>/dev/null | grep LISTEN

# ============================================================================
# 10. SYSTEM PACKAGES & UPDATES
# ============================================================================
log_section "SYSTEM PACKAGES & UPDATES"

echo -e "${YELLOW}Unattended-upgrades status:${NC}"
systemctl is-enabled unattended-upgrades 2>/dev/null && log_ok "unattended-upgrades enabled" || log_issue "unattended-upgrades not enabled"

echo -e "\n${YELLOW}Available updates:${NC}"
apt list --upgradable 2>/dev/null | wc -l | xargs echo "  Packages with updates:"

# ============================================================================
# 11. BOOTLOADER & GRUB
# ============================================================================
log_section "BOOTLOADER & GRUB"

echo -e "${YELLOW}GRUB password protection:${NC}"
if grep -q "^set superusers" /boot/grub/grub.cfg 2>/dev/null; then
    log_ok "GRUB superuser set"
else
    log_issue "GRUB not password protected"
fi

# ============================================================================
# 12. AUDIT & LOGGING
# ============================================================================
log_section "AUDIT & LOGGING"

echo -e "${YELLOW}auditd status:${NC}"
systemctl is-active auditd 2>/dev/null && log_ok "auditd running" || log_issue "auditd not running"

echo -e "\n${YELLOW}rsyslog status:${NC}"
systemctl is-active rsyslog 2>/dev/null && log_ok "rsyslog running" || log_issue "rsyslog not running"

# ============================================================================
# 13. DESKTOP ENVIRONMENT (if applicable)
# ============================================================================
log_section "DESKTOP ENVIRONMENT"

if command -v gnome-shell &> /dev/null; then
    echo "GNOME detected"
    systemctl is-active gdm 2>/dev/null && log_ok "GDM running" || log_issue "GDM not running"
fi

echo -e "\n${BLUE}=== RECONNAISSANCE COMPLETE ===${NC}"
echo "Review the above output to identify unfixed vulnerabilities."
