#!/bin/bash
# ============================================================
# Spider-Verse Linux Assignment — Auto Scoring Script
# Run as root: sudo bash scoring.sh
# ============================================================

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Score Tracking ───────────────────────────────────────────
TOTAL=0
MAX=100
PASS_COUNT=0
FAIL_COUNT=0

# ── Authorized Users (from Readme) ──────────────────────────
ADMIN_USERS=("chowe" "miles" "gwen" "peter")
REGULAR_USERS=("peni" "noir" "ham" "stan" "steve" "miguel" "jefferson" "rio" "may" "jessica" "pavitr" "maryjane")
ALL_AUTHORIZED=("${ADMIN_USERS[@]}" "${REGULAR_USERS[@]}" "auntmay")

declare -A ADMIN_PASSWORDS=(
    ["chowe"]="Cyb3rCont3st"
    ["miles"]="Sup3rHum4n16"
    ["gwen"]="RadioAc7!V65"
    ["peter"]="Dim3Ns!on616"
)

SPIDER_GROUP="spider"
SPIDER_MEMBERS=("may" "peni" "stan" "miguel" "auntmay")

# ── Helpers ──────────────────────────────────────────────────
pass() { echo -e "  ${GREEN}✓${NC}  $1"; }
fail() { echo -e "  ${RED}✗${NC}  $1"; }
info() { echo -e "  ${YELLOW}◈${NC}  $1"; }
hint() { echo -e "      ${DIM}→ $1${NC}"; }

section() {
    echo ""
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  TASK $1: $2  [${3} pts]${NC}"
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"
}

add_score() {
    TOTAL=$((TOTAL + $1))
    PASS_COUNT=$((PASS_COUNT + 1))
}

task_result() {
    local pts=$1
    local passed=$2
    local total=$3
    if [[ "$passed" -eq "$total" ]]; then
        echo -e "  ${GREEN}${BOLD}► TASK PASSED (+${pts} pts)${NC}"
        add_score "$pts"
    elif [[ "$passed" -gt 0 ]]; then
        local partial=$(( pts * passed / total ))
        echo -e "  ${YELLOW}${BOLD}► PARTIAL CREDIT (+${partial} pts) — ${passed}/${total} checks passed${NC}"
        TOTAL=$((TOTAL + partial))
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "  ${RED}${BOLD}► TASK FAILED (+0 pts)${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

is_authorized() {
    local user="$1"
    for u in "${ALL_AUTHORIZED[@]}"; do
        [[ "$user" == "$u" ]] && return 0
    done
    return 1
}

is_system_user() {
    local uid
    uid=$(id -u "$1" 2>/dev/null)
    [[ -z "$uid" ]] && return 1
    [[ "$uid" -lt 1000 ]] && return 0
    return 1
}

# ── ROOT CHECK ───────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}${BOLD}[!] Please run as root: sudo bash scoring.sh${NC}"
    exit 1
fi

# ── BANNER ───────────────────────────────────────────────────
clear
echo -e "${RED}${BOLD}"
cat << 'EOF'
  ███████╗██████╗ ██╗██████╗ ███████╗██████╗
  ██╔════╝██╔══██╗██║██╔══██╗██╔════╝██╔══██╗
  ███████╗██████╔╝██║██║  ██║█████╗  ██████╔╝
  ╚════██║██╔═══╝ ██║██║  ██║██╔══╝  ██╔══██╗
  ███████║██║     ██║██████╔╝███████╗██║  ██║
  ╚══════╝╚═╝     ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═╝
EOF
echo -e "${NC}"
echo -e "${WHITE}${BOLD}       SPIDER-VERSE LINUX SCORING SYSTEM${NC}"
echo -e "${DIM}       User Management Assignment — v1.0${NC}"
echo ""
echo -e "${DIM}  Running checks on: $(hostname) | $(date)${NC}"
echo ""

# ════════════════════════════════════════════════════════════
# TASK 1 — Remove Unauthorized Users (15 pts)
# ════════════════════════════════════════════════════════════
section 1 "Remove Unauthorized Users" 15
T1_PASS=0
T1_TOTAL=0
UNAUTH_FOUND=()

while IFS=: read -r username _ uid _; do
    if [[ "$uid" -ge 1000 && "$uid" -lt 60000 ]]; then
        if ! is_authorized "$username"; then
            UNAUTH_FOUND+=("$username")
        fi
    fi
done < /etc/passwd

T1_TOTAL=1
if [[ "${#UNAUTH_FOUND[@]}" -eq 0 ]]; then
    pass "No unauthorized users found in /etc/passwd"
    T1_PASS=1
else
    fail "Unauthorized users still present: ${UNAUTH_FOUND[*]}"
    hint "Fix: userdel -r <username>"
fi

# Check groups too
UNAUTH_IN_GROUPS=()
while IFS=: read -r groupname _ _ members; do
    if [[ -n "$members" ]]; then
        IFS=',' read -ra member_list <<< "$members"
        for member in "${member_list[@]}"; do
            member=$(echo "$member" | tr -d ' ')
            if [[ -n "$member" ]] && ! is_authorized "$member" && ! is_system_user "$member" 2>/dev/null; then
                # Check if they have UID >= 1000
                uid=$(id -u "$member" 2>/dev/null)
                if [[ -n "$uid" && "$uid" -ge 1000 ]]; then
                    UNAUTH_IN_GROUPS+=("$member@$groupname")
                fi
            fi
        done
    fi
done < /etc/group

T1_TOTAL=$((T1_TOTAL + 1))
if [[ "${#UNAUTH_IN_GROUPS[@]}" -eq 0 ]]; then
    pass "No unauthorized users found in any groups"
    T1_PASS=$((T1_PASS + 1))
else
    fail "Unauthorized users still in groups: ${UNAUTH_IN_GROUPS[*]}"
    hint "Fix: gpasswd -d <user> <group>"
fi

task_result 15 "$T1_PASS" "$T1_TOTAL"

# ════════════════════════════════════════════════════════════
# TASK 2 — Add Missing Authorized Users (15 pts)
# ════════════════════════════════════════════════════════════
section 2 "Add Missing Authorized Users" 15
T2_PASS=0
T2_TOTAL=0
MISSING=()

for user in "${ALL_AUTHORIZED[@]}"; do
    T2_TOTAL=$((T2_TOTAL + 1))
    if id "$user" &>/dev/null; then
        pass "User exists: $user"
        T2_PASS=$((T2_PASS + 1))
    else
        fail "Missing user: $user"
        hint "Fix: useradd -m -s /bin/bash $user"
        MISSING+=("$user")
    fi
done

task_result 15 "$T2_PASS" "$T2_TOTAL"

# ════════════════════════════════════════════════════════════
# TASK 3 — No Users Locked Out (15 pts)
# ════════════════════════════════════════════════════════════
section 3 "No Users Locked Out" 15
T3_PASS=0
T3_TOTAL=0

for user in "${ALL_AUTHORIZED[@]}"; do
    if id "$user" &>/dev/null; then
        T3_TOTAL=$((T3_TOTAL + 1))
        STATUS=$(passwd -S "$user" 2>/dev/null | awk '{print $2}')
        if [[ "$STATUS" == "L" || "$STATUS" == "LK" ]]; then
            fail "$user is LOCKED (status: $STATUS)"
            hint "Fix: passwd -U $user"
        else
            pass "$user is unlocked (status: $STATUS)"
            T3_PASS=$((T3_PASS + 1))
        fi
    fi
done

task_result 15 "$T3_PASS" "$T3_TOTAL"

# ════════════════════════════════════════════════════════════
# TASK 4 — All Users Have Passwords (15 pts)
# ════════════════════════════════════════════════════════════
section 4 "All Users Have Passwords" 15
T4_PASS=0
T4_TOTAL=0

# Check admin passwords match Readme
echo -e "  ${DIM}Checking admin passwords...${NC}"
for admin in "${ADMIN_USERS[@]}"; do
    if id "$admin" &>/dev/null; then
        T4_TOTAL=$((T4_TOTAL + 1))
        # Use PAM/shadow to check if password is set (non-empty)
        SHADOW_ENTRY=$(grep "^$admin:" /etc/shadow 2>/dev/null | cut -d: -f2)
        if [[ -z "$SHADOW_ENTRY" || "$SHADOW_ENTRY" == "!" || "$SHADOW_ENTRY" == "*" || "$SHADOW_ENTRY" == "!!" ]]; then
            fail "$admin has NO password set"
            hint "Fix: echo \"$admin:${ADMIN_PASSWORDS[$admin]}\" | chpasswd"
        else
            pass "$admin has a password set"
            T4_PASS=$((T4_PASS + 1))
        fi
    fi
done

# Check regular users
echo -e "  ${DIM}Checking regular user passwords...${NC}"
for user in "${REGULAR_USERS[@]}" "auntmay"; do
    if id "$user" &>/dev/null; then
        T4_TOTAL=$((T4_TOTAL + 1))
        STATUS=$(passwd -S "$user" 2>/dev/null | awk '{print $2}')
        SHADOW_ENTRY=$(grep "^$user:" /etc/shadow 2>/dev/null | cut -d: -f2)
        if [[ "$STATUS" == "NP" || -z "$SHADOW_ENTRY" || "$SHADOW_ENTRY" == "!" || "$SHADOW_ENTRY" == "*" || "$SHADOW_ENTRY" == "!!" ]]; then
            fail "$user has NO password (status: $STATUS)"
            hint "Fix: echo \"$user:ChangeMe123!\" | chpasswd"
        else
            pass "$user has a password (status: $STATUS)"
            T4_PASS=$((T4_PASS + 1))
        fi
    fi
done

task_result 15 "$T4_PASS" "$T4_TOTAL"

# ════════════════════════════════════════════════════════════
# TASK 5 — Correct Group Memberships (15 pts)
# ════════════════════════════════════════════════════════════
section 5 "Correct Group Memberships" 15
T5_PASS=0
T5_TOTAL=0

# Admins should be in sudo group
echo -e "  ${DIM}Checking sudo group membership...${NC}"
for admin in "${ADMIN_USERS[@]}"; do
    if id "$admin" &>/dev/null; then
        T5_TOTAL=$((T5_TOTAL + 1))
        if id -nG "$admin" 2>/dev/null | grep -qw "sudo"; then
            pass "$admin is in sudo group"
            T5_PASS=$((T5_PASS + 1))
        else
            fail "$admin is NOT in sudo group"
            hint "Fix: usermod -aG sudo $admin"
        fi
    fi
done

# Regular users in 'users' group
echo -e "  ${DIM}Checking users group membership...${NC}"
for user in "${REGULAR_USERS[@]}"; do
    if id "$user" &>/dev/null; then
        T5_TOTAL=$((T5_TOTAL + 1))
        if id -nG "$user" 2>/dev/null | grep -qw "users"; then
            pass "$user is in users group"
            T5_PASS=$((T5_PASS + 1))
        else
            fail "$user is NOT in users group"
            hint "Fix: usermod -aG users $user"
        fi
    fi
done

task_result 15 "$T5_PASS" "$T5_TOTAL"

# ════════════════════════════════════════════════════════════
# TASK 6 — Spider Group + auntmay Account (15 pts)
# ════════════════════════════════════════════════════════════
section 6 "Spider Group + auntmay Account" 15
T6_PASS=0
T6_TOTAL=0

# Check group exists
T6_TOTAL=$((T6_TOTAL + 1))
if getent group "$SPIDER_GROUP" &>/dev/null; then
    pass "Group 'spider' exists"
    T6_PASS=$((T6_PASS + 1))
else
    fail "Group 'spider' does NOT exist"
    hint "Fix: groupadd spider"
fi

# Check auntmay account exists
T6_TOTAL=$((T6_TOTAL + 1))
if id "auntmay" &>/dev/null; then
    pass "Account 'auntmay' exists"
    T6_PASS=$((T6_PASS + 1))
else
    fail "Account 'auntmay' does NOT exist"
    hint "Fix: useradd -m -s /bin/bash -G spider auntmay"
fi

# Check all spider members are in the group
for member in "${SPIDER_MEMBERS[@]}"; do
    T6_TOTAL=$((T6_TOTAL + 1))
    if id "$member" &>/dev/null; then
        if id -nG "$member" 2>/dev/null | grep -qw "$SPIDER_GROUP"; then
            pass "$member is in spider group"
            T6_PASS=$((T6_PASS + 1))
        else
            fail "$member is NOT in spider group"
            hint "Fix: usermod -aG spider $member"
        fi
    else
        fail "$member account doesn't exist (can't check group)"
        hint "Fix: useradd -m -s /bin/bash $member"
    fi
done

task_result 15 "$T6_PASS" "$T6_TOTAL"

# ════════════════════════════════════════════════════════════
# TASK 7 — Files Present for Submission (10 pts)
# ════════════════════════════════════════════════════════════
section 7 "Submit passwd / shadow / group Files" 10
T7_PASS=0
T7_TOTAL=3

# Check if backup copies exist in home or current dir
SEARCH_DIRS=("$HOME" "/root" "/home/$(logname 2>/dev/null)" "$(pwd)")

check_file_exists() {
    local keyword="$1"
    for dir in "${SEARCH_DIRS[@]}"; do
        for f in "$dir"/*"$keyword"* "$dir"/"$keyword"*; do
            [[ -f "$f" ]] && echo "$f" && return 0
        done
    done
    return 1
}

for keyword in "passwd" "shadow" "group"; do
    found=$(check_file_exists "$keyword")
    if [[ -n "$found" ]]; then
        pass "Found $keyword backup: $found"
        T7_PASS=$((T7_PASS + 1))
    else
        fail "No backup copy of $keyword found"
        hint "Fix: cp /etc/$keyword ~/${keyword}_submission"
    fi
done

task_result 10 "$T7_PASS" "$T7_TOTAL"

# ════════════════════════════════════════════════════════════
# FINAL SCORE
# ════════════════════════════════════════════════════════════
echo ""
echo -e "${WHITE}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}${BOLD}  FINAL RESULTS${NC}"
echo -e "${WHITE}${BOLD}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${WHITE}${BOLD}SCORE:   ${BLUE}${TOTAL} / ${MAX} pts${NC}"
echo -e "  ${WHITE}${BOLD}PASSED:  ${GREEN}${PASS_COUNT} tasks${NC}"
echo -e "  ${WHITE}${BOLD}FAILED:  ${RED}${FAIL_COUNT} tasks${NC}"
echo ""

PCT=$(( TOTAL * 100 / MAX ))

# Progress bar
BAR_LEN=40
FILLED=$(( BAR_LEN * TOTAL / MAX ))
EMPTY=$(( BAR_LEN - FILLED ))
BAR=$(printf "%${FILLED}s" | tr ' ' '█')
EMPTY_BAR=$(printf "%${EMPTY}s" | tr ' ' '░')

if   [[ "$TOTAL" -ge 90 ]]; then COLOR="${GREEN}"
elif [[ "$TOTAL" -ge 70 ]]; then COLOR="${BLUE}"
elif [[ "$TOTAL" -ge 60 ]]; then COLOR="${YELLOW}"
else COLOR="${RED}"; fi

echo -e "  ${COLOR}${BAR}${DIM}${EMPTY_BAR}${NC} ${COLOR}${BOLD}${PCT}%${NC}"
echo ""

# Verdict
if   [[ "$TOTAL" -eq 100 ]]; then
    echo -e "  ${GREEN}${BOLD}🕷  PERFECT SCORE — Spider-Verse Certified!${NC}"
elif [[ "$TOTAL" -ge 80 ]]; then
    echo -e "  ${BLUE}${BOLD}★  STRONG WORK — Almost perfect, review failed tasks.${NC}"
elif [[ "$TOTAL" -ge 60 ]]; then
    echo -e "  ${YELLOW}${BOLD}◈  PASSING — But there's room to improve.${NC}"
else
    echo -e "  ${RED}${BOLD}✗  NEEDS WORK — Review the answer key and re-run.${NC}"
fi

echo ""
echo -e "${DIM}══════════════════════════════════════════════════${NC}"

# ── Answer Key ───────────────────────────────────────────────
echo ""
echo -e "${YELLOW}${BOLD}  ANSWER KEY${NC}"
echo -e "${DIM}──────────────────────────────────────────────────${NC}"
echo -e "  ${BLUE}Admins (sudo):${NC}  chowe | miles | gwen | peter"
echo -e "  ${BLUE}Passwords:${NC}"
echo -e "    chowe  → ${YELLOW}Cyb3rCont3st${NC}"
echo -e "    miles  → ${YELLOW}Sup3rHum4n16${NC}"
echo -e "    gwen   → ${YELLOW}RadioAc7!V65${NC}"
echo -e "    peter  → ${YELLOW}Dim3Ns!on616${NC}"
echo ""
echo -e "  ${BLUE}Regular Users (users group):${NC}"
echo -e "    peni noir ham stan steve miguel jefferson"
echo -e "    rio may jessica pavitr maryjane"
echo ""
echo -e "  ${BLUE}Spider Group:${NC}  may peni stan miguel auntmay"
echo -e "  ${BLUE}New account:${NC}   auntmay (create + add to spider)"
echo ""
echo -e "  ${BLUE}Default password for users w/o one:${NC} ${YELLOW}ChangeMe123!${NC}"
echo -e "${DIM}══════════════════════════════════════════════════${NC}"
echo ""
