#!/usr/bin/env bash
#
# redteam.sh — scope-gated wrapper that drives kaboom (kaboom/kaboom.sh) through
# an authorized red-team workflow against a self-owned lab.
#
# Reads ENGAGEMENT_SCOPE.yaml, enforces scope (RFC1918/lab only), and maps gated
# phases onto kaboom's phase letters (i/v/w/d/r). When a tool is missing it PRINTS
# the command instead of running it, so this is safe to run anywhere.
#
# Phase mapping:
#   recon   -> kaboom -p i   (nmap/dirb/gobuster/whatweb/sslscan/enum4linux)   [allow_active_scanning]
#   vuln    -> kaboom -p v   (nikto/searchsploit/NSE)                          [allow_vuln_assessment]
#   web     -> kaboom -p w   (sqlmap/commix/dotdotpwn/nuclei — ACTIVE exploit) [allow_exploitation + CONFIRM]
#   creds   -> kaboom -p d   (hydra dictionary attacks)                        [allow_credential_testing]
#   exploit -> Metasploit resource script (host exploitation)                  [allow_exploitation + CONFIRM]
#   report  -> kaboom -p r   (consolidated HTML report from the SQLite DB)
#
# Usage:
#   ./redteam.sh scope                 # print parsed scope and exit
#   ./redteam.sh recon|vuln|report     # safe phases
#   ./redteam.sh all                   # recon -> vuln -> report (safe only)
#   CONFIRM_EXPLOIT=yes ./redteam.sh web
#   ./redteam.sh creds                 # needs allow_credential_testing: true
#   CONFIRM_EXPLOIT=yes ./redteam.sh exploit
#
set -euo pipefail

SCOPE_FILE="${SCOPE_FILE:-ENGAGEMENT_SCOPE.yaml}"
EXAMPLE=".claude/agents/ENGAGEMENT_SCOPE.example.yaml"
KABOOM="kaboom/kaboom.sh"

die()  { echo "error: $*" >&2; exit 1; }
info() { echo "[redteam] $*"; }

[ -f "$SCOPE_FILE" ] || die "no $SCOPE_FILE — copy $EXAMPLE and fill it in first."

# --- tiny YAML readers (flat keys + simple list blocks; no yq dependency) ---
yget() {
  sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" "$SCOPE_FILE" | head -1 \
    | sed 's/#.*//; s/[[:space:]]*$//; s/^"//; s/"$//'
}
ylist() {
  awk -v k="$1" '
    $0 ~ "^[[:space:]]*"k":[[:space:]]*$" {inb=1; next}
    inb && /^[[:space:]]*-[[:space:]]*/ {
      s=$0; sub(/^[[:space:]]*-[[:space:]]*/,"",s); sub(/#.*/,"",s);
      gsub(/[[:space:]]+$/,"",s); gsub(/"/,"",s); if (s!="") print s; next
    }
    inb && /^[[:space:]]*[A-Za-z_]+:/ {inb=0}
  ' "$SCOPE_FILE"
}

mapfile -t IN_SCOPE  < <(ylist in_scope)
mapfile -t OUT_SCOPE < <(ylist out_of_scope)
ALLOW_SCAN=$(yget allow_active_scanning)
ALLOW_VULN=$(yget allow_vuln_assessment)
ALLOW_CREDS=$(yget allow_credential_testing)
ALLOW_EXPLOIT=$(yget allow_exploitation)
RATE=$(yget max_scan_rate)
REPORT_DIR=$(yget report_dir); REPORT_DIR="${REPORT_DIR:-./reports}"

[ "${#IN_SCOPE[@]}" -gt 0 ] || die "no in_scope targets in $SCOPE_FILE"

# --- scope enforcement: RFC1918 / loopback / lab only ---
is_private() {
  local ip="${1%%/*}"
  [[ "$ip" =~ ^10\. ]] && return 0
  [[ "$ip" =~ ^192\.168\. ]] && return 0
  [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] && return 0
  [[ "$ip" =~ ^127\. ]] && return 0
  return 1
}
for t in "${IN_SCOPE[@]}"; do
  is_private "$t" || die "target '$t' is not an RFC1918/lab address — refusing. Test only networks you own."
done
in_out_scope() { local t="$1"; for o in "${OUT_SCOPE[@]:-}"; do [ "$t" = "$o" ] && return 0; done; return 1; }

hosts_only() {  # expand in_scope minus out_of_scope, individual hosts (skip CIDRs for phases that need a host)
  for t in "${IN_SCOPE[@]}"; do [[ "$t" == */* ]] && continue; in_out_scope "$t" && continue; echo "$t"; done
}

# run kaboom for one phase letter against each in-scope host, or print the command
kaboom_phase() {  # kaboom_phase <letter> <label>
  local letter="$1" label="$2"
  info "=== $label (kaboom -p $letter) ==="
  mkdir -p "$REPORT_DIR"
  local ran=0
  while read -r host; do
    [ -z "$host" ] && continue
    ran=1
    local cmd="$KABOOM -t $host -f '$REPORT_DIR' -p $letter"
    if [ -x "$KABOOM" ] && command -v nmap >/dev/null 2>&1; then
      info "running: $cmd"; eval "MAX_SCAN_RATE='${RATE:-normal}' $cmd" || info "kaboom exited non-zero for $host (continuing)"
    else
      echo "    [kaboom/tools missing — run on your lab Kali host]: $cmd"
    fi
  done < <(hosts_only)
  [ "$ran" = 1 ] || info "no individual in-scope hosts for this phase (CIDRs are discovered in recon)."
}

phase_recon()  { [ "$ALLOW_SCAN" = "true" ] || { info "allow_active_scanning not true — skipping recon"; return; }; kaboom_phase i "recon / information gathering"; }
phase_vuln()   { [ "$ALLOW_VULN" = "true" ] || { info "allow_vuln_assessment not true — skipping vuln"; return; }; kaboom_phase v "vulnerability assessment"; }
phase_report() { kaboom_phase r "report (HTML + SQLite findings DB at $REPORT_DIR/kaboom.db)"; }

phase_creds() {
  if [ "$ALLOW_CREDS" != "true" ]; then
    info "allow_credential_testing not true — skipping (edit $SCOPE_FILE to opt in)."; return
  fi
  info "credential testing — low parallelism; stop on lockout (RDP/SMB can lock accounts)"
  kaboom_phase d "dictionary attack"
}

confirm_gate() {  # shared gate for active-exploitation phases
  local what="$1"
  if [ "$ALLOW_EXPLOIT" != "true" ]; then
    info "allow_exploitation not true — skipping $what. Set it in $SCOPE_FILE to enable."; return 1
  fi
  if [ "${CONFIRM_EXPLOIT:-}" != "yes" ]; then
    echo "    $what launches REAL attacks against lab hosts: $(hosts_only | tr '\n' ' ')"
    echo "    These must be machines you own in an isolated lab. To proceed, re-run with:"
    echo "        CONFIRM_EXPLOIT=yes ./redteam.sh ${2:-}"
    return 1
  fi
  return 0
}

phase_web() {
  confirm_gate "web injection/exploitation" web || return 0
  info "web injection/exploitation CONFIRMED (sqlmap/commix/dotdotpwn/nuclei)"
  kaboom_phase w "web injection / exploitation"
}

phase_exploit() {
  confirm_gate "Metasploit host exploitation" exploit || return 0
  info "host exploitation CONFIRMED for: $(hosts_only | tr '\n' ' ')"
  while read -r t; do
    [ -z "$t" ] && continue
    local d="$REPORT_DIR/${t//\//_}"; mkdir -p "$d"
    local rc="$d/exploit.rc"
    if [ ! -f "$rc" ]; then
      cat > "$rc" <<RC
# Metasploit resource script for $t — fill in the module (from the vuln
# assessment / kaboom.db vulnerabilities table), then rerun this phase.
# Example (Metasploitable2 vsftpd backdoor):
#   use exploit/unix/ftp/vsftpd_234_backdoor
#   set RHOSTS $t
#   run
# -- edit below --
# use <exploit/module/path>
# set RHOSTS $t
# set LHOST <your-kali-ip>
# run
# exit -y
RC
      echo "    wrote template $rc — add the module, then rerun this phase."
      continue
    fi
    if ! grep -qE '^[[:space:]]*use[[:space:]]' "$rc"; then
      echo "    $rc has no 'use <module>' line yet — fill it in before running."
      continue
    fi
    if command -v msfconsole >/dev/null 2>&1; then
      info "running msfconsole -q -r $rc"; msfconsole -q -r "$rc" | tee "$d/exploit_output.txt"
    else
      echo "    [msfconsole missing — run on your lab Kali host]: msfconsole -q -r '$rc' | tee '$d/exploit_output.txt'"
    fi
  done < <(hosts_only)
  info "For each hit, capture what a defender would see (logs/alerts) — that's the prevention lesson."
}

print_scope() {
  echo "scope file : $SCOPE_FILE"
  echo "in_scope   : ${IN_SCOPE[*]}"
  echo "out_scope  : ${OUT_SCOPE[*]:-(none)}"
  echo "rate       : ${RATE:-normal}"
  echo "scanning   : ${ALLOW_SCAN:-?}  vuln: ${ALLOW_VULN:-?}  creds: ${ALLOW_CREDS:-?}  exploit: ${ALLOW_EXPLOIT:-?}"
  echo "report_dir : $REPORT_DIR  (findings DB: $REPORT_DIR/kaboom.db)"
  echo "kaboom     : $KABOOM"
}

case "${1:-}" in
  recon)   phase_recon ;;
  vuln)    phase_vuln ;;
  web)     phase_web ;;
  creds)   phase_creds ;;
  exploit) phase_exploit ;;
  report)  phase_report ;;
  scope)   print_scope ;;
  all)     phase_recon; phase_vuln; phase_report ;;   # safe phases only; web/creds/exploit are gated + explicit
  *) echo "usage: $0 {recon|vuln|web|creds|exploit|report|all|scope}"; exit 2 ;;
esac
