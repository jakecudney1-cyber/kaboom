#!/usr/bin/env bash
# SessionStart hook: report which kaboom / red-team tools are available, run the
# guardrail self-test, and remind about the scope file. Non-blocking (exits 0).

set -u

# Tools kaboom's phases drive (i/v/w/d/r).
TOOLS=(nmap dirb gobuster whatweb sslscan enum4linux nikto searchsploit msfconsole hydra sqlmap commix dotdotpwn nuclei sqlite3 xmllint)

present=(); missing=()
for t in "${TOOLS[@]}"; do
  if command -v "$t" >/dev/null 2>&1; then present+=("$t"); else missing+=("$t"); fi
done

echo "[kaboom red-team] tool check on $(hostname 2>/dev/null || echo host):"
[ "${#present[@]}" -gt 0 ] && echo "  available: ${present[*]}"
if [ "${#missing[@]}" -gt 0 ]; then
  echo "  MISSING:   ${missing[*]}"
  echo "  -> This host can't run the missing tools. Run from a Kali-style host on"
  echo "     the lab network (or install them). redteam.sh/agents will emit"
  echo "     commands instead of fabricating output."
else
  echo "  all tools present — agents can run live against in-scope lab targets."
fi

# Guardrail self-test (fast, no network/tools needed).
if [ -x "tests/redteam_test.sh" ]; then
  if tests/redteam_test.sh >/dev/null 2>&1; then
    echo "  guardrails: redteam.sh self-test PASSED."
  else
    echo "  guardrails: WARNING — redteam.sh self-test FAILED. Run ./tests/redteam_test.sh"
  fi
fi

# Scope file reminder (never print its contents).
if [ -f "ENGAGEMENT_SCOPE.yaml" ]; then
  echo "  scope: ENGAGEMENT_SCOPE.yaml found."
else
  echo "  scope: ENGAGEMENT_SCOPE.yaml NOT found — copy"
  echo "         .claude/agents/ENGAGEMENT_SCOPE.example.yaml and fill it in before running."
fi

exit 0
