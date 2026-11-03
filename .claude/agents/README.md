# Red-team agent suite (for authorized, self-owned lab testing)

Claude Code subagents that drive **kaboom** (`kaboom/kaboom.sh`) through a
structured red-team workflow against **a network you own** — a home lab / test
range. The suite adds the scope/authorization layer that the raw kaboom script
does not have.

> For systems you own or have written authorization to test. Every component
> gates on `ENGAGEMENT_SCOPE.yaml`, refuses targets outside RFC1918/lab ranges,
> and keeps active exploitation and credential testing off by default.

## Agents → kaboom phase

| Agent | kaboom phase | Does | Default posture |
|-------|--------------|------|-----------------|
| `redteam-lead` | — | Confirms scope + authorization, delegates, aggregates | entry point |
| `recon-scout` | `i` | nmap, dirb/gobuster, whatweb, sslscan, enum4linux | read-only |
| `vuln-assessor` | `v` | nikto, searchsploit, NSE, CVE→MSF mapping | analysis-only |
| `web-exploiter` | `w` | sqlmap, commix, dotdotpwn, nuclei (active) | **disabled** unless opted in + confirmed |
| `cred-tester` | `d` | hydra dictionary attacks | **disabled** unless opted in |
| `exploit-operator` | — | Metasploit host exploitation | **disabled** unless opted in + confirmed |
| `report-writer` | `r` | HTML report + reads the SQLite findings DB | synthesis-only |

All findings persist to a shared SQLite DB at `<report_dir>/kaboom.db`.

## Setup

```bash
cp .claude/agents/ENGAGEMENT_SCOPE.example.yaml ENGAGEMENT_SCOPE.yaml
# edit targets.in_scope to your lab subnet; set authorization; choose rules
```

Keep `ENGAGEMENT_SCOPE.yaml` and `reports/` out of git (already in `.gitignore`).

## Usage

- **Agent-driven:** invoke `redteam-lead` — it validates scope, gets your go,
  then runs recon → vuln → (web/creds/exploit if enabled) → report.
- **Script-driven:** `./redteam.sh all` (safe phases), or a single phase.

## Where it runs

kaboom's tools run on a host **on the lab network** (a Kali box). In a cloud
session the tools are absent and the lab unreachable; there, `redteam.sh` and the
agents **print the exact commands** instead of fabricating output.

## Guardrails (in every agent + redteam.sh, verified by `tests/redteam_test.sh`)

- Act only on `in_scope`; refuse public/third-party addresses.
- No credential testing unless `allow_credential_testing: true` **and** confirmed.
- No web/host exploitation unless `allow_exploitation: true` **and** you confirm
  (runner also requires `CONFIRM_EXPLOIT=yes`). Then it runs for real against your
  own lab — capture the detection/prevention lessons from each hit.
- Honor `stop_on_service_disruption`; no exfiltration/persistence/pivoting by
  default.
