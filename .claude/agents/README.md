# Red-team agent suite (for authorized, self-owned lab testing)

A set of Claude Code subagents that drive **kaboom** and its underlying tools
(nmap, dirb, nikto, searchsploit, metasploit, hydra) through a structured
red-team workflow against **a network you own** — a home lab or isolated test
range.

> These agents are for testing systems you own or have written authorization to
> test. They gate every action on an `ENGAGEMENT_SCOPE.yaml` file, refuse targets
> outside RFC1918/lab ranges, and keep exploitation and credential testing off by
> default.

## Agents

| Agent | Phase | Does | Default posture |
|-------|-------|------|-----------------|
| `redteam-lead` | orchestration | Confirms scope + authorization, delegates phases, aggregates | entry point |
| `recon-scout` | info gathering | Host discovery, port/service/OS scan (nmap, kaboom -p 1) | read-only |
| `web-enum` | info gathering | Web path enumeration + web vuln scan (dirb, nikto) | scan-only |
| `vuln-assessor` | vuln assessment | CVE research + NSE + CVE→MSF module mapping | analysis-only, no exploit |
| `cred-tester` | vuln assessment | Weak/default credential tests (hydra) | **disabled** unless opted in |
| `report-writer` | reporting | Compiles evidence into REPORT.md + findings.csv | synthesis-only |

## Setup

1. Copy the scope template and fill it in:
   ```bash
   cp .claude/agents/ENGAGEMENT_SCOPE.example.yaml ENGAGEMENT_SCOPE.yaml
   # edit targets.in_scope to your lab net, set authorization, choose rules
   ```
2. Keep `ENGAGEMENT_SCOPE.yaml` out of version control if it has details you
   don't want committed (add it to `.gitignore`).

## Usage

Start with the lead agent and let it delegate:

```
> Use the redteam-lead agent to test my lab per ENGAGEMENT_SCOPE.yaml
```

The lead will validate scope, get your go-ahead, then run recon → web-enum →
vuln-assessor → (cred-tester if enabled) → report-writer.

## Where the tools run

This repo's tools (nmap, hydra, etc.) run on a Kali-style host **on your lab
network**. If you invoke these agents from a cloud session where the tools aren't
installed, they will emit the exact commands for you to run on your lab host
rather than fabricate output. Run them from a machine that can actually reach the
lab for live results.

## Guardrails (built into every agent)

- Act only on `in_scope` targets; refuse public/third-party addresses.
- No exploitation unless `allow_exploitation: true` **and** you confirm in-session.
- No credential testing unless `allow_credential_testing: true` **and** confirmed.
- Honor `stop_on_service_disruption`; back off on lockout/unresponsiveness.
- No exfiltration, persistence, or lateral movement by default.
