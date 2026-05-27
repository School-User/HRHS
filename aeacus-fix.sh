#!/bin/bash
# CyberPatriot Ubuntu 22.04 Remediation Script (CLEAN - NO PASSWORD POLICIES)
# RUN AS: sudo bash cyberpatriot_remediate_clean.sh 2>&1 | tee remediate.log

set -e
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/root/cp_backup_${TIMESTAMP}"

echo "=== CYBERPATRIOT REMEDIATION START: $(date) ==="
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

echo "○ snapd kept running (per README guidelines)"

###############################################################################
# VULN #22: SSH HARDENING
###############################################################################
echo ""
echo "=== HARDENING SSH ==="

echo "[*] Backing up sshd_config..."
cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.orig"

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
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow 22/tcp >/dev/null 2>&1

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

echo "[*] Applying sysctl hardening..."
sed -i '/# CyberPatriot TCP/,+50d' /etc/sysctl.conf 2>/dev/null || true

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

sysctl -p >/dev/null 2>&1
echo "✓ Sysctl hardening applied"

###############################################################################
# FILE PERMISSIONS
###############################################################################
echo ""
echo "=== FIXING FILE PERMISSIONS ==="

for user in abby avery secuser; do
  hist="/home/$user/.bash_history"
  if [ -f "$hist" ]; then
    chmod 644 "$hist"
    echo "✓ /home/$user/.bash_history = 644"
  fi
done

###############################################################################
# FINAL SUMMARY
###############################################################################
echo ""
echo "=== REMEDIATION COMPLETE ==="
echo "Backup: $BACKUP_DIR"
echo ""
echo "=== END: $(date) ==="
