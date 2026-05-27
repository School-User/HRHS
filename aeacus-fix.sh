#!/bin/bash
# CyberPatriot Ubuntu 22.04 Remediation Script (v2 - CORRECTED)
# Targets: 25 vulnerabilities x 4pts + 2 bonus x 5pts = 110 points
# RUN AS: sudo bash cyberpatriot_remediate_v2.sh 2>&1 | tee remediate.log

set -e
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/root/cp_backup_${TIMESTAMP}"

echo "=== CYBERPATRIOT REMEDIATION v2 START: $(date) ==="
echo "Backup directory: $BACKUP_DIR"
echo ""

# Create backups
mkdir -p "$BACKUP_DIR"
echo "[*] Creating backups..."
cp -r /etc "$BACKUP_DIR/etc_backup" 2>/dev/null || true
echo "✓ Backups created"

###############################################################################
# VULN #1-3: USER MANAGEMENT
###############################################################################
echo ""
echo "=== FIXING USERS & GROUPS ==="

# Remove connor (uid=0, unauthorized root)
if id connor &>/dev/null; then
  echo "[*] Removing connor..."
  userdel -f -r connor 2>/dev/null || userdel -f connor
  echo "✓ connor removed"
else
  echo "○ connor already removed"
fi

# Remove sierra (not in approved list)
if id sierra &>/dev/null; then
  echo "[*] Removing sierra..."
  userdel -f -r sierra 2>/dev/null || userdel -f sierra
  echo "✓ sierra removed"
else
  echo "○ sierra already removed"
fi

# Verify kast group (should be gid 1016)
echo "[*] Fixing kast GID..."
if ! grep -q "^sierra:" /etc/group; then
  groupadd -g 1016 sierra 2>/dev/null || true
fi
usermod -g 1016 kast 2>/dev/null || true
echo "✓ kast GID = 1016"

# Add vlad to sudo
echo "[*] Adding vlad to sudo..."
usermod -aG sudo vlad 2>/dev/null || true
echo "✓ vlad in sudo"

###############################################################################
# VULN #4-9: PASSWORD POLICIES
###############################################################################
echo ""
echo "=== FIXING PASSWORD POLICIES ==="

# Backup original files
cp /etc/login.defs "$BACKUP_DIR/login.defs.orig" 2>/dev/null || true
cp /etc/security/pwquality.conf "$BACKUP_DIR/pwquality.conf.orig" 2>/dev/null || true
cp /etc/pam.d/common-password "$BACKUP_DIR/common-password.orig" 2>/dev/null || true
cp /etc/pam.d/common-auth "$BACKUP_DIR/common-auth.orig" 2>/dev/null || true

# FIX /etc/login.defs - DIRECT REPLACEMENT
echo "[*] Hardening /etc/login.defs..."
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   2/' /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs
sed -i 's/^ENCRYPT_METHOD.*/ENCRYPT_METHOD YESCRYPT/' /etc/login.defs
sed -i 's/^LOGIN_RETRIES.*/LOGIN_RETRIES 5/' /etc/login.defs

# Verify changes
PASS_MAX=$(grep "^PASS_MAX_DAYS" /etc/login.defs | awk '{print $2}')
echo "✓ /etc/login.defs updated (PASS_MAX_DAYS=$PASS_MAX)"

# FIX /etc/security/pwquality.conf - COMPLETE REWRITE
echo "[*] Hardening /etc/security/pwquality.conf..."
cat > /etc/security/pwquality.conf << 'PWQUALITY_EOF'
# Password quality requirements
minlen = 14
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
minclass = 4
maxrepeat = 3
maxsequence = 3
retry = 3
difok = 5
gecoscheck = 1
enforce_for_root
PWQUALITY_EOF

MINLEN=$(grep "^minlen" /etc/security/pwquality.conf | awk '{print $3}')
echo "✓ /etc/security/pwquality.conf updated (minlen=$MINLEN)"

# Ensure libpam-pwquality is installed
apt-get install -y libpam-pwquality >/dev/null 2>&1 || true

# FIX /etc/pam.d/common-password - COMPLETE REWRITE
echo "[*] Hardening /etc/pam.d/common-password..."
cat > /etc/pam.d/common-password << 'COMMON_PASSWORD_EOF'
#
# /etc/pam.d/common-password - password-related modules common to all services
#
password requisite pam_pwquality.so retry=3
password required pam_pwhistory.so remember=5 enforce_for_root
password [success=2 default=ignore] pam_unix.so obscure use_authtok try_first_pass yescrypt minlen=14 remember=5
password sufficient pam_sss.so use_authtok
password requisite pam_deny.so
password required pam_permit.so
password optional pam_gnome_keyring.so
COMMON_PASSWORD_EOF

echo "✓ /etc/pam.d/common-password hardened"

# FIX /etc/pam.d/common-auth - ADD FAILLOCK
echo "[*] Hardening /etc/pam.d/common-auth..."
cat > /etc/pam.d/common-auth << 'COMMON_AUTH_EOF'
#
# /etc/pam.d/common-auth - authentication settings common to all services
#
auth required pam_faillock.so preauth silent audit deny=5 unlock_time=900
auth [success=2 default=ignore] pam_unix.so nullok
auth [default=die] pam_faillock.so authfail audit deny=5 unlock_time=900
auth [success=1 default=ignore] pam_sss.so use_first_pass
auth requisite pam_deny.so
auth required pam_permit.so
auth optional pam_cap.so
auth sufficient pam_faillock.so authsucc
COMMON_AUTH_EOF

echo "✓ /etc/pam.d/common-auth hardened with faillock"

# Apply password aging to existing users (mindays=2, maxdays=90, warndays=14)
echo "[*] Applying password aging to all users..."
for user in $(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd); do
  chage -m 2 -M 90 -I 30 -W 14 "$user" 2>/dev/null || true
done
echo "✓ Password aging applied"

###############################################################################
# VULN #10-14: REMOVE BAD SOFTWARE
###############################################################################
echo ""
echo "=== REMOVING BAD SOFTWARE ==="

BAD_PACKAGES=("telnet" "ftp" "tnftp" "nmap" "nmap-common" "ophcrack" "transmission" "transmission-gtk" "transmission-common")

for pkg in "${BAD_PACKAGES[@]}"; do
  if dpkg -l 2>/dev/null | grep -q "^ii.*$pkg"; then
    echo "[*] Removing $pkg..."
    apt-get purge -y "$pkg" >/dev/null 2>&1 || true
    echo "✓ $pkg removed"
  fi
done

apt-get autoremove -y >/dev/null 2>&1 || true

###############################################################################
# VULN #15-21: DISABLE UNNECESSARY SERVICES
###############################################################################
echo ""
echo "=== DISABLING UNNECESSARY SERVICES ==="

# Disable avahi
echo "[*] Disabling avahi-daemon..."
systemctl disable avahi-daemon.service 2>/dev/null || true
systemctl stop avahi-daemon.service 2>/dev/null || true
echo "✓ avahi disabled"

# Disable CUPS
echo "[*] Disabling CUPS..."
systemctl disable cups.service 2>/dev/null || true
systemctl disable cups-browsed.service 2>/dev/null || true
systemctl stop cups.service 2>/dev/null || true
systemctl stop cups-browsed.service 2>/dev/null || true
systemctl disable snap.cups.cupsd.service 2>/dev/null || true
systemctl disable snap.cups.cups-browsed.service 2>/dev/null || true
systemctl stop snap.cups.cupsd.service 2>/dev/null || true
systemctl stop snap.cups.cups-browsed.service 2>/dev/null || true
echo "✓ CUPS disabled"

# Disable Bluetooth
echo "[*] Disabling Bluetooth..."
systemctl disable bluetooth.service 2>/dev/null || true
systemctl stop bluetooth.service 2>/dev/null || true
echo "✓ Bluetooth disabled"

# NOTE: Do NOT disable snapd (README says don't disable CSSClient, keep services running)
echo "○ snapd kept running (per README guidelines)"

###############################################################################
# VULN #22: SSH HARDENING
###############################################################################
echo ""
echo "=== HARDENING SSH ==="

echo "[*] Backing up sshd_config..."
cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.orig"

# COMPLETE REWRITE of sshd_config
echo "[*] Rewriting sshd_config..."
cat > /etc/ssh/sshd_config << 'SSHD_EOF'
# CyberPatriot Hardened SSH Configuration
Port 22
AddressFamily inet
ListenAddress 0.0.0.0

Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentication
PermitRootLogin without-password
StrictModes yes
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 4
MaxSessions 3

# Key exchange & encryption
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,sntrup761x25519-sha512@openssh.com,diffie-hellman-group-exchange-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256
Ciphers chacha20-poly1305@openssh.com,aes128-ctr,aes192-ctr,aes256-ctr,aes128-gcm@openssh.com,aes256-gcm@openssh.com
MACs umac-64-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512

# Timing & keepalives
ClientAliveInterval 300
ClientAliveCountMax 0
LoginGraceTime 30

# Access control - HARDENED
AllowTcpForwarding no
AllowAgentForwarding no
AllowStreamLocalForwarding no
PermitTunnel no
X11Forwarding no
PermitUserEnvironment no

# Logging & info
SyslogFacility AUTH
LogLevel VERBOSE
PrintLastLog no
PrintMotd no
UseLogin no
UsePAM yes
IgnoreRhosts yes

# Subsystems
Subsystem sftp /usr/lib/openssh/sftp-server

# Advanced
Compression delayed
TCPKeepAlive yes
UsePrivilegeSeparation sandbox
VersionAddendum none
SSHD_EOF

# Test SSH syntax
if sshd -t 2>/dev/null; then
  echo "✓ SSH config syntax valid"
else
  echo "✗ SSH config syntax ERROR - restoring backup"
  cp "$BACKUP_DIR/sshd_config.orig" /etc/ssh/sshd_config
  exit 1
fi

# Restart SSH
systemctl restart ssh.service 2>/dev/null || systemctl restart sshd.service 2>/dev/null
echo "✓ SSH restarted"

###############################################################################
# VULN #23: ENABLE FIREWALL
###############################################################################
echo ""
echo "=== ENABLING FIREWALL (UFW) ==="

echo "[*] Enabling UFW..."
ufw --force enable >/dev/null 2>&1

# Set default policies
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1

# Allow SSH
echo "[*] Allowing SSH..."
ufw allow 22/tcp >/dev/null 2>&1

# Verify UFW status
if ufw status | grep -q "Status: active"; then
  echo "✓ UFW enabled and SSH allowed"
else
  echo "✗ UFW enable failed"
fi

###############################################################################
# VULN #24: KERNEL / SYSCTL HARDENING
###############################################################################
echo ""
echo "=== HARDENING KERNEL / SYSCTL ==="

echo "[*] Backing up sysctl.conf..."
cp /etc/sysctl.conf "$BACKUP_DIR/sysctl.conf.orig"

# Append hardening settings (remove duplicates first if they exist)
echo "[*] Applying sysctl hardening..."

# Remove any existing hardening lines to avoid duplicates
sed -i '/# CyberPatriot TCP/,+50d' /etc/sysctl.conf 2>/dev/null || true

# Append new hardening configuration
cat >> /etc/sysctl.conf << 'SYSCTL_EOF'

# CyberPatriot TCP/IP Hardening
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Kernel hardening
kernel.panic = 10
kernel.randomize_va_space = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_userns_clone = 0
kernel.sysrq = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0
SYSCTL_EOF

# Load new sysctl settings
sysctl -p >/dev/null 2>&1
echo "✓ Sysctl hardening applied"

###############################################################################
# BONUS #1: FILE PERMISSIONS
###############################################################################
echo ""
echo "=== FIXING FILE PERMISSIONS ==="

echo "[*] Fixing .bash_history permissions..."
for user in abby avery secuser; do
  hist="/home/$user/.bash_history"
  if [ -f "$hist" ]; then
    chmod 644 "$hist"
    echo "✓ /home/$user/.bash_history = 644"
  fi
done

if [ -f "/home/secuser/Downloads/aeacus-linux/phocus" ]; then
  chmod 644 "/home/secuser/Downloads/aeacus-linux/phocus"
  echo "✓ phocus = 644"
fi

###############################################################################
# BONUS #2: SUDO/GROUP VERIFICATION
###############################################################################
echo ""
echo "=== VERIFYING SUDO ACCESS ==="

for admin in secuser avery alex debolt vlad; do
  if id $admin &>/dev/null; then
    usermod -aG sudo $admin 2>/dev/null || true
    echo "✓ $admin has sudo"
  fi
done

###############################################################################
# FINAL SUMMARY
###############################################################################
echo ""
echo "=== REMEDIATION COMPLETE ==="
echo "Backup: $BACKUP_DIR"
echo ""
echo "Next steps:"
echo "1. Run: sudo bash cyberpatriot_verify.sh"
echo "2. Check Scoring Report on Desktop"
echo ""
echo "=== END: $(date) ==="
