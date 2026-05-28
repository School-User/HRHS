#!/bin/bash
# Cyber Security Audit Script

echo "--- Starting Security Audit ---"

# 1. Find world-writable files (Excluding /proc and /sys)
echo "[+] Checking for world-writable files..."
find / -path /proc -prune -o -path /sys -prune -o -type f -perm -0002 -ls 2>/dev/null

# 2. Find SUID/SGID files (Often used for privilege escalation)
echo "[+] Checking for SUID/SGID files..."
find / -path /proc -prune -o -path /sys -prune -o -type f \( -perm -4000 -o -perm -2000 \) -ls 2>/dev/null

# 3. List all enabled services
echo "[+] Listing enabled systemd services..."
systemctl list-unit-files --state=enabled --no-pager

# 4. Check for .ssh folders in home directories (potential unauthorized access)
echo "[+] Checking for user .ssh directories..."
ls -ld /home/*/.ssh 2>/dev/null

# 5. Check for files with no owner (often indicator of malicious file deletion)
echo "[+] Checking for orphaned files..."
find / -nouser -o -nogroup 2>/dev/null

echo "--- Audit Complete ---"
