#!/usr/bin/env bash
# Guardrail tests for redteam.sh — runnable anywhere (missing scan tools make the
# runner print commands instead of executing, so no lab/network is needed).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT/redteam.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
scope() { cat > "$TMP/$1"; echo "$TMP/$1"; }

LAB="$(scope lab.yaml <<EOF
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
  report_dir: "$TMP/reports"
EOF
)"
PUBLIC="$(scope public.yaml <<EOF
targets:
  in_scope:
    - "8.8.8.8"
rules_of_engagement:
  allow_active_scanning: true
output:
  report_dir: "$TMP/reports"
EOF
)"
run() { SCOPE_FILE="$1" bash "$RUNNER" "${@:2}" 2>&1; }

echo "== public IP is refused =="
out="$(run "$PUBLIC" recon)"; rc=$?
{ [ $rc -ne 0 ] && grep -q "not an RFC1918/lab address" <<<"$out"; } && ok "public target refused" || bad "not refused (rc=$rc): $out"

echo "== scope parses =="
out="$(run "$LAB" scope)"
grep -q "192.168.56.101" <<<"$out" && grep -q "findings DB" <<<"$out" && ok "scope parsed" || bad "scope: $out"

echo "== recon maps to kaboom -p i for host, skips out-of-scope =="
out="$(run "$LAB" recon)"
grep -q -- "-t 192.168.56.101 -f '$TMP/reports' -p i" <<<"$out" && ! grep -q -- "-t 192.168.56.1 " <<<"$out" && ok "recon mapping + out-of-scope skip" || bad "recon: $out"

echo "== vuln maps to kaboom -p v =="
out="$(run "$LAB" vuln)"; grep -q -- "-p v" <<<"$out" && ok "vuln -> -p v" || bad "vuln: $out"

echo "== report maps to kaboom -p r =="
out="$(run "$LAB" report)"; grep -q -- "-p r" <<<"$out" && ok "report -> -p r" || bad "report: $out"

echo "== all runs only safe phases (i, v, r — never w/d) =="
out="$(run "$LAB" all)"
{ grep -q -- "-p i" <<<"$out" && grep -q -- "-p v" <<<"$out" && grep -q -- "-p r" <<<"$out" \
  && ! grep -q -- "-p w" <<<"$out" && ! grep -q -- "-p d" <<<"$out"; } && ok "all = i+v+r only" || bad "all: $out"

echo "== creds gate OFF by default =="
out="$(run "$LAB" creds)"; grep -q "allow_credential_testing not true" <<<"$out" && ok "creds skipped" || bad "creds: $out"

echo "== creds ON maps to kaboom -p d when enabled =="
C="$TMP/creds.yaml"; sed 's/allow_credential_testing: false/allow_credential_testing: true/' "$LAB" > "$C"
out="$(run "$C" creds)"; grep -q -- "-p d" <<<"$out" && ok "creds -> -p d" || bad "creds enabled: $out"

echo "== web (injection) gated OFF without allow_exploitation =="
out="$(run "$LAB" web)"; grep -q "allow_exploitation not true" <<<"$out" && ok "web skipped when disabled" || bad "web: $out"

echo "== web needs confirmation even when enabled =="
E="$TMP/exploit.yaml"; sed 's/allow_exploitation: false/allow_exploitation: true/' "$LAB" > "$E"
out="$(run "$E" web)"; grep -q "CONFIRM_EXPLOIT=yes" <<<"$out" && ! grep -q -- "-p w" <<<"$out" && ok "web needs confirmation" || bad "web confirm: $out"

echo "== confirmed web maps to kaboom -p w =="
out="$(SCOPE_FILE="$E" CONFIRM_EXPLOIT=yes bash "$RUNNER" web 2>&1)"
grep -q -- "-p w" <<<"$out" && ok "confirmed web -> -p w" || bad "web confirmed: $out"

echo "== exploit needs confirmation; confirmed writes template (no auto-module) =="
out="$(run "$E" exploit)"; grep -q "CONFIRM_EXPLOIT=yes" <<<"$out" && ok "exploit needs confirmation" || bad "exploit confirm: $out"
out="$(SCOPE_FILE="$E" CONFIRM_EXPLOIT=yes bash "$RUNNER" exploit 2>&1)"
grep -q "wrote template" <<<"$out" && ok "confirmed exploit writes template" || bad "exploit template: $out"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
