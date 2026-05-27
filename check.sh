#!/bin/bash
# CyberPatriot Post-Remediation Verification
# Run after remediate.sh to verify all fixes

echo "=== CYBERPATRIOT VERIFICATION START: $(date) ==="
echo ""

PASS=0
FAIL=0

check_pass() {
  echo "✓ $1"
  ((PASS++))
}

check_fail() {
  echo "✗ $1"
  ((FAIL++))
}

###############################################################################
# VERIFY USER MANAGEMENT
###############################################################################
echo "=== USERS & GROUPS ==="

# Check connor is removed
if ! id connor &>/dev/null; then
  check_pass "connor removed"
else
  check_fail "connor still exists (uid=0)"
fi

# Check sierra is removed
if ! id sierra &>/dev/null; then
  check_pass "sierra removed"
else
  check_fail "sierra still exists"
fi

# Check kast GID
KAST_GID=$(id -g kast)
if [ "$KAST_GID" -eq 1016 ]; then
  check_pass "kast GID = 1016"
else
  check_fail "kast GID = $KAST_GID (should be 1016)"
fi

# Check vlad in sudo
if grep -q "^sudo:" /etc/group && id vlad | grep -q "27(sudo)"; then
  check_pass "vlad in sudo group"
else
  check_fail "vlad NOT in sudo group"
fi

# Check 4 admins exist
for admin in secuser avery alex debolt; do
  if id "$admin" &>/dev/null; then
    check_pass "Admin $admin exists"
  else
    check_fail "Admin $admin MISSING"
  fi
done

# Check 12 regular users exist
for user in charlie jessica jack abby logan kast elijah connor carter laura vlad may; do
  if id "$user" &>/dev/null 2>&1; then
    :  # User exists (silent)
  else
    if [ "$user" != "connor" ]; then  # connor should be gone
      check_fail "User $user MISSING"
    fi
  fi
done

###############################################################################
# VERIFY PASSWORD POLICIES
###############################################################################
echo ""
echo "=== PASSWORD POLICIES ==="

# Check login.defs
PASS_MAX=$(grep "^PASS_MAX_DAYS" /etc/login.defs | awk '{print $2}')
if [ "$PASS_MAX" -le 90 ]; then
  check_pass "PASS_MAX_DAYS = $PASS_MAX (OK)"
else
  check_fail "PASS_MAX_DAYS = $PASS_MAX (should be ≤90)"
fi

PASS_MIN=$(grep "^PASS_MIN_DAYS" /etc/login.defs | awk '{print $2}')
if [ "$PASS_MIN" -ge 1 ] && [ "$PASS_MIN" -le 10 ]; then
  check_pass "PASS_MIN_DAYS = $PASS_MIN (OK)"
else
  check_fail "PASS_MIN_DAYS = $PASS_MIN (should be 1-10)"
fi

# Check pwquality.conf
if grep -q "minlen = 14" /etc/security/pwquality.conf; then
  check_pass "pwquality: minlen = 14"
else
  check_fail "pwquality: minlen NOT set to 14"
fi

if grep -q "dcredit = -1" /etc/security/pwquality.conf; then
  check_pass "pwquality: dcredit = -1"
else
  check_fail "pwquality: dcredit NOT hardened"
fi

if grep -q "enforce_for_root" /etc/security/pwquality.conf; then
  check_pass "pwquality: enforce_for_root set"
else
  check_fail "pwquality: enforce_for_root NOT set"
fi

# Check PAM faillock
if grep -q "pam_faillock.so" /etc/pam.d/common-auth; then
  check_pass "PAM faillock configured"
else
  check_fail "PAM faillock NOT configured"
fi

# Check PAM password history
if grep -q "pam_pwhistory.so remember=5" /etc/pam.d/common-password; then
  check_pass "PAM password history = 5"
else
  check_fail "PAM password history NOT configured"
fi

###############################################################################
# VERIFY SOFTWARE REMOVED
###############################################################################
echo ""
echo "=== SOFTWARE REMOVAL ==="

BAD_PACKAGES=("telnet" "ftp" "nmap" "ophcrack" "transmission")

for pkg in "${BAD_PACKAGES[@]}"; do
  if ! dpkg -l | grep -q "^ii.*$pkg"; then
    check_pass "$pkg removed"
  else
    check_fail "$pkg STILL INSTALLED"
  fi
done

###############################################################################
# VERIFY SERVICES DISABLED
###############################################################################
echo ""
echo "=== SERVICES STATUS ==="

# Check avahi disabled
if ! systemctl is-enabled avahi-daemon.service &>/dev/null; then
  check_pass "avahi-daemon disabled"
else
  check_fail "avahi-daemon STILL ENABLED"
fi

# Check CUPS disabled
if ! systemctl is-enabled cups.service &>/dev/null; then
  check_pass "cups disabled"
else
  check_fail "cups STILL ENABLED"
fi

# Check Bluetooth disabled
if ! systemctl is-enabled bluetooth.service &>/dev/null; then
  check_pass "bluetooth disabled"
else
  check_fail "bluetooth STILL ENABLED"
fi

# Check SSH enabled
if systemctl is-enabled ssh.service &>/dev/null; then
  check_pass "ssh enabled"
else
  check_fail "ssh DISABLED (should be enabled)"
fi

# Check SSH running
if systemctl is-active --quiet ssh.service; then
  check_pass "ssh running"
else
  check_fail "ssh NOT running"
fi

###############################################################################
# VERIFY SSH HARDENING
###############################################################################
echo ""
echo "=== SSH HARDENING ==="

SSH_CONFIG="/etc/ssh/sshd_config"

if grep -q "^AllowTcpForwarding no" "$SSH_CONFIG"; then
  check_pass "AllowTcpForwarding = no"
else
  check_fail "AllowTcpForwarding NOT hardened"
fi

if grep -q "^X11Forwarding no" "$SSH_CONFIG"; then
  check_pass "X11Forwarding = no"
else
  check_fail "X11Forwarding NOT hardened"
fi

if grep -q "^ClientAliveInterval 300" "$SSH_CONFIG"; then
  check_pass "ClientAliveInterval = 300"
else
  check_fail "ClientAliveInterval NOT set"
fi

if grep -q "^MaxAuthTries 4" "$SSH_CONFIG"; then
  check_pass "MaxAuthTries = 4"
else
  check_fail "MaxAuthTries NOT hardened"
fi

if grep -q "^LoginGraceTime 30" "$SSH_CONFIG"; then
  check_pass "LoginGraceTime = 30"
else
  check_fail "LoginGraceTime NOT hardened"
fi

if sshd -t &>/dev/null; then
  check_pass "SSH syntax valid"
else
  check_fail "SSH syntax ERROR"
fi

###############################################################################
# VERIFY UFW
###############################################################################
echo ""
echo "=== FIREWALL (UFW) ==="

if ufw status | grep -q "Status: active"; then
  check_pass "UFW enabled"
else
  check_fail "UFW DISABLED"
fi

if ufw status | grep -q "22/tcp"; then
  check_pass "SSH port 22 allowed"
else
  check_fail "SSH port 22 NOT allowed"
fi

###############################################################################
# VERIFY SYSCTL HARDENING
###############################################################################
echo ""
echo "=== KERNEL / SYSCTL ==="

# Check a few critical sysctl settings
if sysctl net.ipv4.conf.all.accept_redirects | grep -q "= 0"; then
  check_pass "accept_redirects = 0"
else
  check_fail "accept_redirects NOT hardened"
fi

if sysctl net.ipv4.conf.all.log_martians | grep -q "= 1"; then
  check_pass "log_martians = 1"
else
  check_fail "log_martians NOT set"
fi

if sysctl kernel.panic | grep -q "= 10"; then
  check_pass "kernel.panic = 10"
else
  check_fail "kernel.panic NOT set"
fi

if sysctl kernel.randomize_va_space | grep -q "= 2"; then
  check_pass "kernel.randomize_va_space = 2"
else
  check_fail "kernel.randomize_va_space NOT set"
fi

if sysctl net.ipv4.tcp_syncookies | grep -q "= 1"; then
  check_pass "tcp_syncookies = 1"
else
  check_fail "tcp_syncookies NOT set"
fi

###############################################################################
# VERIFY FILE PERMISSIONS
###############################################################################
echo ""
echo "=== FILE PERMISSIONS ==="

# Check .bash_history not world-writable
for user in abby avery secuser; do
  hist="/home/$user/.bash_history"
  if [ -f "$hist" ]; then
    perms=$(stat -c %a "$hist")
    if [ "$perms" != "666" ]; then
      check_pass "/home/$user/.bash_history = $perms (not 666)"
    else
      check_fail "/home/$user/.bash_history = $perms (still world-writable)"
    fi
  fi
done

###############################################################################
# SUMMARY
###############################################################################
echo ""
echo "=== VERIFICATION SUMMARY ==="
echo "✓ PASSED: $PASS"
echo "✗ FAILED: $FAIL"
echo "Total: $((PASS + FAIL))"
echo ""

if [ $FAIL -eq 0 ]; then
  echo "🎯 ALL CHECKS PASSED - Ready for scoring!"
  exit 0
else
  echo "⚠️  Some checks failed - Review fixes above"
  exit 1
fi
