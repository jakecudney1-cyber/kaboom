#!/usr/bin/env bash
#
# redteam.sh — thin runner for the kaboom red-team workflow.
#
# Reads ENGAGEMENT_SCOPE.yaml, enforces scope (RFC1918/lab only), and dispatches
# phases. Mirrors the guardrails in .claude/agents/*. When a tool is missing it
# PRINTS the command instead of running it, so this is safe to run anywhere.
#
# Usage:
#   ./redteam.sh recon            # host discovery + port/service scan (nmap)
#   ./redteam.sh web              # dirb + nikto on in-scope hosts
#   ./redteam.sh vuln             # searchsploit + safe NSE
#   ./redteam.sh creds            # hydra (only if allow_credential_testing: true)
#   ./redteam.sh report           # compile REPORT.md + findings.csv
#   ./redteam.sh all              # recon -> web -> vuln -> (creds) -> report
#   ./redteam.sh scope            # print parsed scope and exit
#
set -euo pipefail

SCOPE_FILE="${SCOPE_FILE:-ENGAGEMENT_SCOPE.yaml}"
EXAMPLE=".claude/agents/ENGAGEMENT_SCOPE.example.yaml"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "[redteam] $*"; }

[ -f "$SCOPE_FILE" ] || die "no $SCOPE_FILE — copy $EXAMPLE and fill it in first."

# --- tiny YAML readers (flat keys + simple list blocks; no yq dependency) ---
yget() {  # yget <key>  -> scalar value (strips quotes/comments)
  sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" "$SCOPE_FILE" | head -1 \
    | sed 's/#.*//; s/[[:space:]]*$//; s/^"//; s/"$//'
}
ylist() {  # ylist <block>  -> list items under "<block>:" (indented "- ")
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

# nmap timing from rate
case "$RATE" in
  polite) TIMING="-T2" ;; aggressive) TIMING="-T4" ;; *) TIMING="-T3" ;;
esac

[ "${#IN_SCOPE[@]}" -gt 0 ] || die "no in_scope targets in $SCOPE_FILE"

# --- scope enforcement: RFC1918 / loopback / lab only ---
is_private() {  # accepts IP or CIDR; checks the address part
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

# run a tool if present, else print the command
run_or_print() {  # run_or_print <tool> <full command...>
  local tool="$1"; shift
  mkdir -p "$REPORT_DIR"
  if command -v "$tool" >/dev/null 2>&1; then
    info "running: $*"; eval "$@"
  else
    echo "    [$tool missing — run on your lab Kali host]: $*"
  fi
}

host_dir() { echo "$REPORT_DIR/${1//\//_}"; }

phase_recon() {
  info "=== recon ==="
  [ "$ALLOW_SCAN" = "true" ] || { info "allow_active_scanning is not true — skipping"; return; }
  for t in "${IN_SCOPE[@]}"; do
    in_out_scope "$t" && { info "skip out-of-scope $t"; continue; }
    local d; d="$(host_dir "$t")"; mkdir -p "$d"
    if [[ "$t" == */* ]]; then
      run_or_print nmap "nmap -sn $TIMING $t -oG '$d/discovery.gnmap'"
    else
      run_or_print nmap "nmap -sV -O --top-ports 1000 $TIMING -oA '$d/recon_nmap' $t"
    fi
  done
}

phase_web() {
  info "=== web enum ==="
  [ "$ALLOW_SCAN" = "true" ] || { info "allow_active_scanning is not true — skipping"; return; }
  for t in "${IN_SCOPE[@]}"; do
    [[ "$t" == */* ]] && continue
    in_out_scope "$t" && continue
    local d; d="$(host_dir "$t")"; mkdir -p "$d"
    local ext=""; [ -f custom_extensions_common.txt ] && ext="-X $(paste -sd, custom_extensions_common.txt)"
    local wl="custom_url_wordlist.txt"; [ -f "$wl" ] || wl="/usr/share/dirb/wordlists/common.txt"
    run_or_print dirb  "dirb http://$t/ $wl $ext -o '$d/dirb_80.txt'"
    run_or_print nikto "nikto -h $t -o '$d/nikto_80.txt'"
  done
}

phase_vuln() {
  info "=== vuln assessment ==="
  [ "$ALLOW_VULN" = "true" ] || { info "allow_vuln_assessment is not true — skipping"; return; }
  for t in "${IN_SCOPE[@]}"; do
    [[ "$t" == */* ]] && continue
    in_out_scope "$t" && continue
    local d; d="$(host_dir "$t")"; mkdir -p "$d"
    # safe/default/vuln categories only — no exploit scripts
    run_or_print nmap "nmap -sV --script 'default,safe,vuln' $TIMING -oA '$d/nse' $t"
    echo "    [then: searchsploit <product> <version> for each service found above]"
  done
  [ "$ALLOW_EXPLOIT" = "true" ] && info "NOTE: allow_exploitation is true — exploitation is still manual/operator-confirmed; this runner never launches exploits."
}

phase_creds() {
  info "=== credential testing ==="
  if [ "$ALLOW_CREDS" != "true" ]; then
    info "allow_credential_testing is not true — skipping (edit $SCOPE_FILE to opt in)."; return
  fi
  local ulist="user_wordlist_short.txt" plist="fasttrack.txt"
  for t in "${IN_SCOPE[@]}"; do
    [[ "$t" == */* ]] && continue
    in_out_scope "$t" && continue
    local d; d="$(host_dir "$t")"; mkdir -p "$d"
    info "weak-cred check on $t (low parallelism; stop on lockout)"
    for svc in ssh; do   # default to ssh only; add pop3 imap rdp smb deliberately
      run_or_print hydra "hydra -L $ulist -P $plist -t 4 -f -o '$d/hydra_$svc.txt' $t $svc"
    done
    echo "    [to test pop3/imap/rdp/smb too, add them to the loop — mind account lockout on RDP/SMB]"
  done
}

phase_report() {
  info "=== report ==="
  mkdir -p "$REPORT_DIR"
  local out="$REPORT_DIR/REPORT.md"
  {
    echo "# Red-team report — $(yget name)"
    echo
    echo "- Authorization: $(yget authorization) (owner: $(yget owner))"
    echo "- Date: $(date -u +%Y-%m-%dT%H:%MZ)"
    echo "- In scope: ${IN_SCOPE[*]}"
    echo "- Credential testing: $ALLOW_CREDS | Exploitation: $ALLOW_EXPLOIT"
    echo
    echo "## Artifacts"
    if command -v find >/dev/null; then
      find "$REPORT_DIR" -type f ! -name REPORT.md ! -name findings.csv 2>/dev/null \
        | sed 's/^/- /' || true
    fi
    echo
    echo "> Review per-host nmap/dirb/nikto/NSE output above and rank findings by"
    echo "> severity. For a richer narrative report, hand these artifacts to the"
    echo "> report-writer agent."
  } > "$out"
  echo "host,port,service,severity,cve,summary" > "$REPORT_DIR/findings.csv"
  info "wrote $out and $REPORT_DIR/findings.csv (skeleton — fill from artifacts)"
}

print_scope() {
  echo "scope file : $SCOPE_FILE"
  echo "in_scope   : ${IN_SCOPE[*]}"
  echo "out_scope  : ${OUT_SCOPE[*]:-(none)}"
  echo "rate       : ${RATE:-normal} ($TIMING)"
  echo "scanning   : ${ALLOW_SCAN:-?}  vuln: ${ALLOW_VULN:-?}  creds: ${ALLOW_CREDS:-?}  exploit: ${ALLOW_EXPLOIT:-?}"
  echo "report_dir : $REPORT_DIR"
}

case "${1:-}" in
  recon)  phase_recon ;;
  web)    phase_web ;;
  vuln)   phase_vuln ;;
  creds)  phase_creds ;;
  report) phase_report ;;
  scope)  print_scope ;;
  all)    phase_recon; phase_web; phase_vuln; phase_creds; phase_report ;;
  *) echo "usage: $0 {recon|web|vuln|creds|report|all|scope}"; exit 2 ;;
esac
