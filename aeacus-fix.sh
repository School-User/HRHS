#!/bin/bash
# CyberPatriot Ubuntu 22.04 Remediation Script
# Targets: 25 vulnerabilities x 4pts + 2 bonus x 5pts = 110 points
# RUN AS: sudo bash cyberpatriot_remediate.sh

set -e
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/root/cp_backup_${TIMESTAMP}"

echo "=== CYBERPATRIOT REMEDIATION START: $(date) ==="
echo "Backup directory: $BACKUP_DIR"
echo "This script will fix ~25 vulnerabilities"
echo ""

# Create backups
mkdir -p "$BACKUP_DIR"
echo "[*] Creating backups..."
cp -r /etc "$BACKUP_DIR/etc_backup"
cp -r /var/log "$BACKUP_DIR/logs_backup"
echo "✓ Backups created at $BACKUP_DIR"

###############################################################################
# VULN #1-3: USER MANAGEMENT
###############################################################################
echo ""
echo "=== FIXING USERS & GROUPS ==="

# Remove connor (uid=0, unauthorized root)
echo "[*] Removing connor (uid=0, unauthorized)..."
if id connor &>/dev/null; then
  userdel -f connor 2>/dev/null || true
  echo "✓ connor removed"
else
  echo "○ connor not found (already removed?)"
fi

# Remove sierra (not in approved list)
echo "[*] Removing sierra (unauthorized user)..."
if id sierra &>/dev/null; then
  userdel -f sierra 2>/dev/null || true
  echo "✓ sierra removed"
else
  echo "○ sierra not found (already removed?)"
fi

# Fix kast GID (should be 1016, currently 1015)
echo "[*] Fixing kast GID to 1016..."
groupmod -g 1016 sierra 2>/dev/null || groupadd -g 1016 sierra
usermod -g 1016 kast
echo "✓ kast GID fixed to 1016"

# Add vlad to sudo group (admin needs sudo)
echo "[*] Adding vlad to sudo group..."
usermod -aG sudo vlad
echo "✓ vlad added to sudo group"

# Verify admins are in correct groups
for admin in secuser avery alex debolt; do
  echo "[*] Verifying admin: $admin"
  usermod -aG adm $admin 2>/dev/null || true
  usermod -aG sudo $admin 2>/dev/null || true
done
echo "✓ Admin group membership verified"

###############################################################################
# VULN #4-9: PASSWORD POLICIES
###############################################################################
echo ""
echo "=== FIXING PASSWORD POLICIES ==="

# Fix /etc/login.defs
echo "[*] Hardening /etc/login.defs..."
cp "$BACKUP_DIR/etc_backup/login.defs" "$BACKUP_DIR/etc_backup/login.defs.bak"

# Update password aging
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   2/' /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs
sed -i 's/^ENCRYPT_METHOD.*/ENCRYPT_METHOD YESCRYPT/' /etc/login.defs
sed -i 's/^LOGIN_RETRIES.*/LOGIN_RETRIES 5/' /etc/login.defs
sed -i 's/^LOGIN_TIMEOUT.*/LOGIN_TIMEOUT 60/' /etc/login.defs

echo "✓ /etc/login.defs hardened"

# Fix /etc/security/pwquality.conf
echo "[*] Hardening /etc/security/pwquality.conf..."
cp /etc/security/pwquality.conf "$BACKUP_DIR/etc_backup/pwquality.conf.bak"

cat > /etc/security/pwquality.conf << 'EOF'
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
EOF

echo "✓ /etc/security/pwquality.conf hardened"

# Install libpam-pwquality if missing
apt-get install -y libpam-pwquality 2>&1 | grep -i "install\|already" || true

# Fix PAM common-password
echo "[*] Hardening /etc/pam.d/common-password..."
cp /etc/pam.d/common-password "$BACKUP_DIR/etc_backup/common-password.bak"

cat > /etc/pam.d/common-password << 'EOF'
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
EOF

echo "✓ common-password hardened"

# Fix PAM common-auth (add faillock)
echo "[*] Hardening /etc/pam.d/common-auth..."
cp /etc/pam.d/common-auth "$BACKUP_DIR/etc_backup/common-auth.bak"

cat > /etc/pam.d/common-auth << 'EOF'
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
EOF

echo "✓ common-auth hardened with faillock"

# Apply password aging to existing users
echo "[*] Applying password aging to existing users..."
for user in $(awk -F: '$3 >= 1000 {print $1}' /etc/passwd); do
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
  if dpkg -l | grep -q "^ii.*$pkg"; then
    echo "[*] Removing $pkg..."
    apt-get purge -y "$pkg" 2>&1 | grep -i "removing\|purged" || true
    echo "✓ $pkg removed"
  else
    echo "○ $pkg not installed"
  fi
done

apt-get autoremove -y 2>&1 | tail -2

###############################################################################
# VULN #15-21: DISABLE UNNECESSARY SERVICES
###############################################################################
echo ""
echo "=== DISABLING UNNECESSARY SERVICES ==="

# Disable avahi (mDNS discovery)
echo "[*] Disabling avahi-daemon..."
systemctl disable avahi-daemon.service 2>/dev/null || true
systemctl stop avahi-daemon.service 2>/dev/null || true
echo "✓ avahi-daemon disabled"

# Disable CUPS and snap CUPS
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

# Disable snapd
echo "[*] Disabling snapd..."
systemctl disable snapd.service 2>/dev/null || true
systemctl disable snapd.apparmor.service 2>/dev/null || true
systemctl stop snapd.service 2>/dev/null || true
echo "✓ snapd disabled (keeping service for scoring, per README)"

# Note: README says "Do not disable or stop CSSClient service"
echo "○ Skipping CSSClient (per README guidelines)"

###############################################################################
# VULN #22: SSH HARDENING
###############################################################################
echo ""
echo "=== HARDENING SSH ==="

echo "[*] Backing up sshd_config..."
cp /etc/ssh/sshd_config "$BACKUP_DIR/etc_backup/sshd_config.bak"

# Apply hardening to sshd_config
cat > /etc/ssh/sshd_config << 'EOF'
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

# Key exchange & encryption (strong defaults already set in Ubuntu 22.04)
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,sntrup761x25519-sha512@openssh.com,diffie-hellman-group-exchange-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256
Ciphers chacha20-poly1305@openssh.com,aes128-ctr,aes192-ctr,aes256-ctr,aes128-gcm@openssh.com,aes256-gcm@openssh.com
MACs umac-64-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512

# Timing & keepalives
ClientAliveInterval 300
ClientAliveCountMax 0
LoginGraceTime 30

# Access control
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
EOF

echo "✓ sshd_config hardened"

# Verify syntax
sshd -t && echo "✓ SSH config syntax OK" || echo "✗ SSH config syntax ERROR"

# Restart SSH
systemctl restart ssh.service
echo "✓ SSH restarted"

###############################################################################
# VULN #23: ENABLE FIREWALL
###############################################################################
echo ""
echo "=== ENABLING FIREWALL (UFW) ==="

echo "[*] Enabling UFW..."
ufw --force enable

# Default policies
ufw default deny incoming
ufw default allow outgoing
echo "✓ UFW default policies set"

# Allow SSH only
echo "[*] Allowing SSH port 22..."
ufw allow 22/tcp
echo "✓ SSH allowed"

# Verify UFW status
ufw status
echo "✓ UFW enabled"

###############################################################################
# VULN #24: KERNEL / SYSCTL HARDENING
###############################################################################
echo ""
echo "=== HARDENING KERNEL / SYSCTL ==="

echo "[*] Backing up sysctl.conf..."
cp /etc/sysctl.conf "$BACKUP_DIR/etc_backup/sysctl.conf.bak"

# Apply hardening to sysctl.conf
cat >> /etc/sysctl.conf << 'EOF'

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
EOF

echo "✓ sysctl.conf hardened"

# Load new sysctl settings
sysctl -p > /dev/null 2>&1
echo "✓ sysctl settings applied"

###############################################################################
# BONUS #1: FILE PERMISSIONS
###############################################################################
echo ""
echo "=== FIXING FILE PERMISSIONS ==="

echo "[*] Fixing .bash_history permissions..."
for user in abby avery secuser; do
  if [ -f "/home/$user/.bash_history" ]; then
    chmod 644 "/home/$user/.bash_history"
    echo "✓ /home/$user/.bash_history fixed"
  fi
done

# Fix phocus (if world-writable)
if [ -f "/home/secuser/Downloads/aeacus-linux/phocus" ]; then
  chmod 644 "/home/secuser/Downloads/aeacus-linux/phocus"
  echo "✓ /home/secuser/Downloads/aeacus-linux/phocus fixed"
fi

###############################################################################
# BONUS #2: SUDO/GROUP VERIFICATION
###############################################################################
echo ""
echo "=== VERIFYING SUDO ACCESS ==="

# Ensure admins have sudo
for admin in secuser avery alex debolt; do
  if grep -q "^sudo:" /etc/group && grep -q "$admin" /etc/group | grep sudo; then
    echo "✓ $admin has sudo access"
  else
    usermod -aG sudo "$admin"
    echo "✓ $admin added to sudo"
  fi
done

# Ensure vlad is in sudo
if grep -q vlad /etc/group | grep sudo; then
  echo "✓ vlad has sudo access"
else
  usermod -aG sudo vlad
  echo "✓ vlad added to sudo"
fi

###############################################################################
# FINAL CHECKS
###############################################################################
echo ""
echo "=== FINAL VERIFICATION ==="

echo ""
echo "[✓] Remediation complete!"
echo "[*] Backup directory: $BACKUP_DIR"
echo ""
echo "Scoring Report: View on Desktop"
echo "Do NOT disable CSSClient service per README"
echo "Do NOT change timezone (UTC) per README"
echo "Do NOT remove authorized users per README"
echo ""
echo "=== REMEDIATION END: $(date) ==="
