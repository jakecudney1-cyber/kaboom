# CLAUDE.md — kaboom + red-team agent suite

Guidance for Claude Code working in this repo.

## What this repo is

Two layers:

1. **kaboom** (`kaboom.sh`) — the upstream bash pentest automation tool. It drives
   nmap, dirb, nikto, searchsploit, metasploit, and hydra across two phases:
   information gathering and vulnerability assessment. See `README.md`.
2. **A red-team agent suite** built on top of it, for running structured,
   **authorized** tests against a network the operator owns (a home lab / test
   range).

## Authorization — non-negotiable

This tooling is for systems the operator **owns or has written authorization to
test**. Every component gates on `ENGAGEMENT_SCOPE.yaml`:

- Targets must be RFC1918 / loopback / lab addresses. Public or third-party
  addresses are **refused**.
- Exploitation and credential testing are **off by default** and require both a
  scope-file opt-in and explicit operator confirmation.
- No exfiltration, persistence, or lateral movement by default.

If a request would test something outside the scope file, or something the
operator doesn't clearly control, **stop and ask** — don't proceed.

## Layout

```
.claude/agents/            # red-team subagents (see that dir's README)
  redteam-lead.md          #   orchestrator / entry point
  recon-scout.md           #   nmap host+service discovery (read-only)
  web-enum.md              #   dirb + nikto web enumeration
  vuln-assessor.md         #   searchsploit + safe NSE + CVE->MSF mapping
  cred-tester.md           #   hydra weak-cred tests (GATED, off by default)
  report-writer.md         #   compiles REPORT.md + findings.csv
  ENGAGEMENT_SCOPE.example.yaml
.claude/hooks/check-tools.sh   # SessionStart: reports tool + scope availability
.claude/settings.json          # wires the SessionStart hook
redteam.sh                 # phase runner: recon|web|vuln|creds|report|all|scope
tests/redteam_test.sh      # guardrail tests for redteam.sh (runnable anywhere)
ENGAGEMENT_SCOPE.yaml       # operator-created, git-ignored (your targets/authz)
reports/                   # scan output, git-ignored
```

## How to run an engagement

1. Create the scope file:
   ```bash
   cp .claude/agents/ENGAGEMENT_SCOPE.example.yaml ENGAGEMENT_SCOPE.yaml
   # set targets.in_scope to your lab subnet; set authorization; choose rules
   ```
2. Either:
   - **Agent-driven:** invoke `redteam-lead` ("test my lab per
     ENGAGEMENT_SCOPE.yaml"). It validates scope, asks for go-ahead, then
     delegates recon → web → vuln → (creds, if enabled) → report.
   - **Script-driven:** `./redteam.sh all` (or a single phase).
3. Review `reports/REPORT.md` and `reports/findings.csv`.

## Where it actually runs

The scan tools (nmap, dirb, nikto, searchsploit, msfconsole, hydra) must run on a
host **on the lab network** — e.g. a Kali box, reached via a Claude session
running on that machine. In a cloud session the tools are absent and the lab is
unreachable; in that mode **both `redteam.sh` and the agents print the exact
commands to run rather than fabricating output.** Never invent scan results.

The SessionStart hook reports, each session, which tools are present and whether
the scope file exists.

## Validating changes

Before committing changes to `redteam.sh`, run the guardrail tests:

```bash
./tests/redteam_test.sh    # 7 checks: scope parse, RFC1918 refusal, gates, safe NSE
```

They need no network or scan tools and must stay green — they are the guarantee
that the scope/authorization guardrails still hold.

## Conventions

- Keep `ENGAGEMENT_SCOPE.yaml` and `reports/` out of git (already in
  `.gitignore`).
- Treat any credentials found during testing as sensitive; reference that they
  were found, don't spread them around.
- When adding a phase or agent, carry the same gates: scope check first,
  destructive actions opt-in + confirmed, print-don't-fabricate when tools are
  missing, and add a test to `tests/redteam_test.sh`.
