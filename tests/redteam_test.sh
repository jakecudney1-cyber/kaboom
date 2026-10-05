#!/usr/bin/env bash
# Guardrail tests for redteam.sh — runnable anywhere (no scan tools needed,
# since missing tools make the runner print commands instead of executing).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT/redteam.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()   { echo "  PASS: $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail+1)); }

scope() { cat > "$TMP/$1"; echo "$TMP/$1"; }

LAB="$(scope lab.yaml <<'EOF'
targets:
  in_scope:
    - "192.168.56.0/24"
    - "192.168.56.101"
  out_of_scope:
    - "192.168.56.1"
rules_of_engagement:
  allow_active_scanning: true
  allow_vuln_assessment: true
  allow_credential_testing: false
  allow_exploitation: false
  max_scan_rate: "polite"
output:
  report_dir: "REPORTS_PLACEHOLDER"
EOF
)"
# redirect report_dir into TMP so tests never write into the repo
sed -i "s#REPORTS_PLACEHOLDER#$TMP/reports#" "$LAB"

PUBLIC="$(scope public.yaml <<'EOF'
targets:
  in_scope:
    - "8.8.8.8"
rules_of_engagement:
  allow_active_scanning: true
output:
  report_dir: "REPORTS_PLACEHOLDER"
EOF
)"
sed -i "s#REPORTS_PLACEHOLDER#$TMP/reports#" "$PUBLIC"

run() { SCOPE_FILE="$1" bash "$RUNNER" "${@:2}" 2>&1; }

echo "== test: public IP is refused =="
out="$(run "$PUBLIC" recon)"; rc=$?
if [ $rc -ne 0 ] && grep -q "not an RFC1918/lab address" <<<"$out"; then ok "public target refused"; else bad "public target not refused (rc=$rc): $out"; fi

echo "== test: scope parses cleanly =="
out="$(run "$LAB" scope)"
grep -q "192.168.56.101" <<<"$out" && grep -q "polite (-T2)" <<<"$out" && ok "scope + timing parsed" || bad "scope parse: $out"

echo "== test: recon emits nmap for host and discovery for CIDR =="
out="$(run "$LAB" recon)"
grep -q "recon_nmap' 192.168.56.101" <<<"$out" && grep -q "sn -T2 192.168.56.0/24" <<<"$out" && ok "recon commands correct" || bad "recon: $out"

echo "== test: out-of-scope host is skipped in recon =="
out="$(run "$LAB" recon)"
grep -q "skip out-of-scope 192.168.56.1" <<<"$out" || ! grep -q "recon_nmap' 192.168.56.1\b" <<<"$out" && ok "out-of-scope skipped" || bad "out-of-scope touched: $out"

echo "== test: creds gate OFF by default =="
out="$(run "$LAB" creds)"
grep -q "not true — skipping" <<<"$out" && ok "creds skipped when disabled" || bad "creds ran while disabled: $out"

echo "== test: creds gate ON when enabled =="
CREDS="$TMP/creds.yaml"; sed 's/allow_credential_testing: false/allow_credential_testing: true/' "$LAB" > "$CREDS"
out="$(run "$CREDS" creds)"
grep -q "hydra -L user_wordlist_short.txt" <<<"$out" && ok "hydra emitted when enabled" || bad "hydra missing when enabled: $out"

echo "== test: vuln uses only safe NSE categories (no exploit scripts) =="
out="$(run "$LAB" vuln)"
grep -q "script 'default,safe,vuln'" <<<"$out" && ! grep -q "script exploit" <<<"$out" && ok "vuln NSE is non-intrusive" || bad "vuln NSE wrong: $out"

echo "== test: exploit gate OFF when allow_exploitation is false =="
out="$(run "$LAB" exploit)"
grep -q "allow_exploitation is not true" <<<"$out" && ok "exploit skipped when disabled" || bad "exploit ran while disabled: $out"

echo "== test: exploit needs confirmation even when enabled =="
EXP="$TMP/exploit.yaml"; sed 's/allow_exploitation: false/allow_exploitation: true/' "$LAB" > "$EXP"
out="$(run "$EXP" exploit)"
grep -q "CONFIRM_EXPLOIT=yes" <<<"$out" && ! grep -q "exploitation CONFIRMED" <<<"$out" && ok "exploit requires confirmation" || bad "exploit ran without confirmation: $out"

echo "== test: confirmed exploit writes a template rc (no module => no launch) =="
out="$(SCOPE_FILE="$EXP" CONFIRM_EXPLOIT=yes bash "$RUNNER" exploit 2>&1)"
grep -q "wrote template" <<<"$out" && ok "confirmed exploit emits template, no auto-module" || bad "confirmed exploit behavior wrong: $out"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
