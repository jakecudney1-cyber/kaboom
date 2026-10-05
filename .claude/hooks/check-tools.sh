#!/usr/bin/env bash
# SessionStart hook: report which kaboom / red-team tools are available on this
# host so the agents know whether they can run live or must emit commands for a
# lab host. Non-blocking — always exits 0.

set -u

# Core tools the kaboom red-team suite drives.
TOOLS=(nmap dirb nikto searchsploit msfconsole hydra)

present=()
missing=()
for t in "${TOOLS[@]}"; do
  if command -v "$t" >/dev/null 2>&1; then
    present+=("$t")
  else
    missing+=("$t")
  fi
done

echo "[kaboom red-team] tool check on $(hostname 2>/dev/null || echo host):"
if [ "${#present[@]}" -gt 0 ]; then
  echo "  available: ${present[*]}"
fi
if [ "${#missing[@]}" -gt 0 ]; then
  echo "  MISSING:   ${missing[*]}"
  echo "  -> This host can't run the missing tools. Run scans from a Kali-style"
  echo "     host on the lab network, or install them (e.g. apt install ${missing[*]})."
  echo "     Agents will emit commands instead of fabricating output."
else
  echo "  all tools present — agents can run live against in-scope lab targets."
fi

# Guardrail self-test (fast, no network/tools needed) — flags a broken gate early.
if [ -x "tests/redteam_test.sh" ]; then
  if tests/redteam_test.sh >/dev/null 2>&1; then
    echo "  guardrails: redteam.sh self-test PASSED."
  else
    echo "  guardrails: WARNING — redteam.sh self-test FAILED. Run ./tests/redteam_test.sh"
  fi
fi

# Scope file reminder (never print its contents — may hold target/auth details).
if [ -f "ENGAGEMENT_SCOPE.yaml" ]; then
  echo "  scope: ENGAGEMENT_SCOPE.yaml found."
else
  echo "  scope: ENGAGEMENT_SCOPE.yaml NOT found — copy"
  echo "         .claude/agents/ENGAGEMENT_SCOPE.example.yaml and fill it in before running."
fi

exit 0
