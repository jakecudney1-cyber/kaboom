# CLAUDE.md — kaboom + red-team agent suite

Guidance for Claude Code working in this repo.

## What this repo is

Two layers:

1. **kaboom** (`kaboom/kaboom.sh`) — an expanded bash pentest automation tool. It
   drives nmap, dirb/gobuster, whatweb, sslscan, enum4linux, nikto, searchsploit,
   hydra, sqlmap, commix, dotdotpwn, nuclei and Metasploit across five phases,
   persists everything to a SQLite findings DB, and renders an HTML report.
   Phases (via `kaboom/kaboom.sh -t <ip> -f <report_path> -p <letters>`):
   - `i` — information gathering
   - `v` — vulnerability assessment
   - `w` — web injection/exploitation (SQLi, OS-command injection, traversal, RCE/CVE)
   - `d` — dictionary attack against open services
   - `r` — consolidated HTML report
   Findings persist to `<report_path>/kaboom.db` (never overwritten). Config via
   `kaboom/kaboom.conf` (see `kaboom.conf.example`).
2. **A red-team agent suite** on top of it, adding the scope/authorization layer
   kaboom lacks, for **authorized** tests against a network the operator owns.

## Authorization — non-negotiable

For systems the operator **owns or has written authorization to test**. Every
component in the suite gates on `ENGAGEMENT_SCOPE.yaml`:

- Targets must be RFC1918 / loopback / lab addresses. Public or third-party
  addresses are **refused**.
- Credential testing (phase `d`) and exploitation (phase `w` + Metasploit) are
  **off by default** and need both a scope-file opt-in and explicit operator
  confirmation (`CONFIRM_EXPLOIT=yes` for the runner). When enabled against an
  isolated lab the operator owns, they run **for real** — that's the point, and
  the real results teach detection and prevention.
- No exfiltration, persistence, or lateral movement by default.

If a request would test something outside the scope file, or something the
operator doesn't clearly control, **stop and ask**.

## Layout

```
kaboom/                     # the kaboom tool + wordlists + config example
  kaboom.sh
  kaboom.conf.example
.claude/agents/             # red-team subagents (see that dir's README)
  redteam-lead.md           #   orchestrator / entry point
  recon-scout.md            #   phase i  (read-only)
  vuln-assessor.md          #   phase v  (analysis only)
  web-exploiter.md          #   phase w  (GATED HARD)
  cred-tester.md            #   phase d  (GATED)
  exploit-operator.md       #   Metasploit host exploitation (GATED HARD)
  report-writer.md          #   phase r  + reads kaboom.db
  ENGAGEMENT_SCOPE.example.yaml
.claude/hooks/check-tools.sh   # SessionStart: tool + guardrail + scope check
.claude/settings.json          # wires the SessionStart hook
redteam.sh                 # scope-gated runner: recon|vuln|web|creds|exploit|report|all|scope
tests/redteam_test.sh      # guardrail tests (runnable anywhere)
ENGAGEMENT_SCOPE.yaml       # operator-created, git-ignored (your targets/authz)
reports/                   # scan output + kaboom.db, git-ignored
docs/                      # LAB_SETUP.md, PLAYBOOK.md
```

## How to run an engagement

1. `cp .claude/agents/ENGAGEMENT_SCOPE.example.yaml ENGAGEMENT_SCOPE.yaml` and set
   `targets.in_scope` to your lab subnet, authorization, and rules.
2. Either invoke `redteam-lead` (agent-driven), or run `./redteam.sh all` (safe
   phases) / a single phase. Enable gated phases explicitly, e.g.
   `CONFIRM_EXPLOIT=yes ./redteam.sh web`.
3. Review `reports/REPORT.md`, `reports/findings.csv`, kaboom's HTML report, and
   the `reports/kaboom.db` findings DB.

## Where it actually runs

kaboom's tools must run on a host **on the lab network** (a Kali box). In a cloud
session the tools are absent and the lab unreachable; there, `redteam.sh` and the
agents **print the exact commands** rather than fabricating output. Never invent
scan results. The SessionStart hook reports tool availability each session.

## Validating changes

```bash
./tests/redteam_test.sh    # 13 checks: scope parse, RFC1918 refusal, phase
                           # mapping (i/v/w/d/r), gates off/on, confirmation
```

They need no network or scan tools and must stay green — they are the guarantee
that the scope/authorization guardrails hold. The SessionStart hook runs them too.

## Conventions

- Keep `ENGAGEMENT_SCOPE.yaml`, `reports/`, and `*.db` out of git (already in
  `.gitignore`).
- Treat credentials found during testing as sensitive; reference that they were
  found, don't spread them.
- When adding a phase/agent, carry the same gates: scope check first, destructive
  actions opt-in + confirmed, print-don't-fabricate when tools are missing, and
  add a test to `tests/redteam_test.sh`.
