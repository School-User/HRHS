#!/usr/bin/env bash
# show-user-apps-debian.sh
# Lists user-downloaded apps on Debian/Ubuntu as a numbered list
# Usage: ./show-user-apps-debian.sh [--plain]
# Run WITHOUT sudo

set -uo pipefail

PLAIN=false

for arg in "$@"; do
    case "$arg" in
        --plain) PLAIN=true ;;
        --help|-h)
            echo "Usage: $0 [--plain]"
            echo "  --plain   No colors (for piping)"
            exit 0 ;;
    esac
done

if $PLAIN; then
    GREEN=''; YELLOW=''; CYAN=''; BLUE=''; BOLD=''; DIM=''; RESET=''
else
    GREEN='\033[0;32m'; YELLOW='\033[0;33m'
    CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
fi

command -v dpkg &>/dev/null || { echo "Error: dpkg not found."; exit 1; }

if [[ $EUID -eq 0 ]]; then
    echo "Don't run this as root/sudo — run it as your normal user."
    exit 1
fi

# ── Collect packages ──────────────────────────────────────────────────────────

# Get priority:essential and priority:important packages (base system)
BASE_PKGS=$(apt-cache search '' 2>/dev/null | \
    grep -E '^(base-files|base-passwd|bash|coreutils|dash|debconf|debian-archive-keyring|debianutils|diffutils|dpkg|e2fsprogs|findutils|fontconfig-config|gcc-base|gcc-lib|gettext-base|grep|gzip|hostname|init-system-helpers|libacl1|libattr1|libaudit-common|libblkid1|libbrotli1|libbsd|libbz2|libc-bin|libc6|libcap-ng0|libcap2|libcom-err2|libcrypt1|libdb5|libdebian-installer4|libdebconfclient0|libdevmapper1|libdns-export1[0-9]|libdpkg-perl|libext2fs2|libffi[0-9]|libgcc-s1|libgcrypt20|libgdbm|libglib2|libgmp10|libgnutls30|libgomp1|libgpg-error0|libgssapi-krb5|libhogweed|libidn2|libiniparser|libisl|libjson-c|libk5crypto|libkeyutils|libkrb5|libkrb5support|liblz4|liblzma5|libmount1|libmpc|libmpfr|libmspack|libnautilus-extension1a|libnettle|libnewt0.52|libnsl2|libnspr4|libnss|libp11-kit|libpam-modules|libpam-runtime|libpam|libpam0g|libparted|libpcre2|libpcre3|libpopt|libprocps|libpthread-stubs0|libpython|libreadline|libseccomp|libselinux|libsemanage|libsepol|libsmartcols|libsodium|libssl|libstdc|libsystemd0|libtasn1|libtext-charwidth-perl|libtext-iconv-perl|libtext-wrapi18n-perl|libtinfo|libtirpc|libudev|libunistring|libusb-0|libusb-1|libuuid|libwrap|libx11|libxau|libxcb|libxdmcp|libxext|libxrender|libzstd|linux-base|login|logsave|lsb-base|lsb-release-minimal|mawk|media-types|mount|ncurses-base|ncurses-bin|netbase|netcat-openbsd|openssh-client|openssh-server|openssl|os-prober|parted|passwd|perl-base|perl-modules|pinentry|procps|readline-common|sed|sensible-utils|sysvinit-utils|tar|tasksel|tasksel-data|telnet|time|tzdata|ubuntu-keyring|ucf|udev|util-linux|uuid-runtime|vim-common|vim-tiny|wget|whiptail|xdg-user-dirs|xz-utils|zerofree|zlib1g)$' 2>/dev/null | awk '{print $1}' | sort -u)

# Get snap packages
SNAP_PKGS=$(snap list 2>/dev/null | tail -n +2 | awk '{print $1}' | sort -u || true)

# Get all explicitly installed deb packages
ALL_EXPLICIT=$(apt-mark showmanual 2>/dev/null | sort -u || true)

# Get all installed deb packages (for version lookup)
ALL_INSTALLED=$(dpkg -l 2>/dev/null | grep '^ii' | awk '{print $2}' | sort -u || true)

USER_PKGS=()
while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue

    # Skip base/essential packages
    if echo "$BASE_PKGS" | grep -qx "$pkg" 2>/dev/null; then
        continue
    fi

    # Skip lib packages and dev packages (common noise)
    if [[ "$pkg" =~ ^lib[a-z0-9]+ || \
          "$pkg" =~ -dev$          || \
          "$pkg" =~ -doc$          || \
          "$pkg" =~ -dbg$          || \
          "$pkg" =~ ^fonts-       || \
          "$pkg" =~ ^python[0-9]?- ]]; then
        continue
    fi

    USER_PKGS+=("$pkg")
done <<< "$ALL_EXPLICIT"

TOTAL=${#USER_PKGS[@]}

if [[ $TOTAL -eq 0 ]]; then
    echo "No user-downloaded apps found."
    echo "Try running: apt-mark showmanual | head   to verify apt works."
    exit 0
fi

# Count snap packages safely
SNAP_COUNT=0
if [[ -n "$SNAP_PKGS" ]]; then
    SNAP_COUNT=$(comm -12 <(printf '%s\n' "${USER_PKGS[@]}" | sort) <(printf '%s\n' "$SNAP_PKGS") 2>/dev/null | wc -l || echo 0)
fi
DEB_COUNT=$((TOTAL - SNAP_COUNT))

# ── Header ────────────────────────────────────────────────────────────────────

echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║     User-Downloaded Apps — Debian/Ubuntu         ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
printf "${BOLD}  Total: ${GREEN}%d${RESET}  ${BOLD}Deb: ${BLUE}%d${RESET}  ${BOLD}Snap: ${YELLOW}%d${RESET}\n\n" \
    "$TOTAL" "$DEB_COUNT" "$SNAP_COUNT"

# ── Numbered list ─────────────────────────────────────────────────────────────

i=1
for pkg in $(printf '%s\n' "${USER_PKGS[@]}" | sort); do
    is_snap=false
    if [[ -n "$SNAP_PKGS" ]] && echo "$SNAP_PKGS" | grep -qx "$pkg" 2>/dev/null; then
        is_snap=true
        ver=$(snap info "$pkg" 2>/dev/null | grep 'installed:' | awk '{print $2}' || echo "?")
    else
        ver=$(echo "$ALL_INSTALLED" | grep -m1 "^${pkg}\$" >/dev/null 2>&1 && \
              dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || echo "?")
    fi

    if $is_snap; then
        printf "  ${YELLOW}%3d. %-30s${RESET} ${DIM}%-20s${RESET} ${YELLOW}[snap]${RESET}\n" "$i" "$pkg" "$ver"
    else
        printf "  ${GREEN}%3d. %-30s${RESET} ${DIM}%s${RESET}\n" "$i" "$pkg" "$ver"
    fi
    ((i++)) || true
done

echo
echo -e "${DIM}Blue = deb (apt)   Yellow = snap   Run without sudo${RESET}"
