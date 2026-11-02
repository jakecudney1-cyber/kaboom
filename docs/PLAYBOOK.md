# Operator Playbook — kaboom red-team suite

A runbook for running an authorized engagement against your own isolated lab.
Pair with `docs/LAB_SETUP.md` (building the lab) and `.claude/agents/README.md`
(the agents).

## 1. Pre-flight

1. **Authorization:** confirm every target is a machine you own on an isolated
   lab network. If not, stop.
2. **Scope file:**
   ```bash
   cp .claude/agents/ENGAGEMENT_SCOPE.example.yaml ENGAGEMENT_SCOPE.yaml
   # set targets.in_scope, out_of_scope, authorization, and rules_of_engagement
   ```
3. **Sanity-check parsing:**
   ```bash
   ./redteam.sh scope
   ```
   This prints the parsed scope and refuses immediately if any in-scope target
   isn't RFC1918/lab.

## 2. Running an engagement

### (a) Agent-driven — via `redteam-lead`
Invoke the `redteam-lead` subagent ("test my lab per ENGAGEMENT_SCOPE.yaml"). It
scope-gates, validates, echoes the scope, waits for your go, then delegates:

| Phase | Agent | kaboom | Gate |
|-------|-------|--------|------|
| Recon | `recon-scout` | `-p i` | `allow_active_scanning` |
| Vuln | `vuln-assessor` | `-p v` | `allow_vuln_assessment` |
| Web exploit | `web-exploiter` | `-p w` | `allow_exploitation` **+** confirmation |
| Creds | `cred-tester` | `-p d` | `allow_credential_testing` **+** confirmation |
| Host exploit | `exploit-operator` | Metasploit | `allow_exploitation` **+** confirmation |
| Report | `report-writer` | `-p r` | — |

Gated phases are skipped (and noted) unless enabled. When enabled on your own
lab they run **for real** — that's how you get the detection/prevention lessons.

### (b) Script-driven — via `./redteam.sh`
`redteam.sh` reads `ENGAGEMENT_SCOPE.yaml`, enforces scope, and for each in-scope
host runs `kaboom/kaboom.sh -t <host> -f <report_dir> -p <letter>` — or **prints
the command** if the tools aren't installed.

| Command | kaboom | What it does | Requires |
|---------|--------|--------------|----------|
| `./redteam.sh recon` | `-p i` | nmap, dirb/gobuster, whatweb, sslscan, enum4linux | `allow_active_scanning: true` |
| `./redteam.sh vuln` | `-p v` | nikto, searchsploit, NSE | `allow_vuln_assessment: true` |
| `./redteam.sh web` | `-p w` | sqlmap, commix, dotdotpwn, nuclei (**active**) | `allow_exploitation: true` **+** `CONFIRM_EXPLOIT=yes` |
| `./redteam.sh creds` | `-p d` | hydra dictionary attacks | `allow_credential_testing: true` |
| `./redteam.sh exploit` | Metasploit | per-host `.rc` you fill in, then `msfconsole -r` | `allow_exploitation: true` **+** `CONFIRM_EXPLOIT=yes` |
| `./redteam.sh report` | `-p r` | HTML report from the SQLite DB | — |
| `./redteam.sh all` | `i`,`v`,`r` | safe phases in sequence (web/creds/exploit excluded) | per-phase gates |
| `./redteam.sh scope` | — | print parsed scope | — |

**Recommended order:** `recon` → `vuln` → (`web`/`creds`/`exploit` as authorized)
→ `report`.

## 3. Reading results

- Per-host working files: `reports/<host>/` (`IG/`, `VA/`, `WEB/EVIDENCE/`, …).
- **Consolidated findings DB:** `reports/kaboom.db` (SQLite) — tables `hosts`,
  `ports`, `vulnerabilities`, `credentials`, `web_findings`. Never overwritten
  across runs.
- kaboom's HTML report (phase `r`), plus the suite's `REPORT.md` / `findings.csv`
  when you escalate to `report-writer` for a narrative write-up.
- Query directly, e.g.:
  `sqlite3 reports/kaboom.db "SELECT host_id,cve,service,severity FROM vulnerabilities;"`

## 4. Gates & safety rails in practice

- **Credential testing** needs `allow_credential_testing: true` + in-session
  confirmation. Start small; tune `HYDRA_THREADS` in `kaboom.conf`.
- **Account-lockout caution:** `rdp`/`smb` against AD can lock accounts — warn
  first, keep parallelism low, stop on signs of lockout
  (`stop_on_service_disruption: true`).
- **Web + host exploitation** need `allow_exploitation: true` **and**
  `CONFIRM_EXPLOIT=yes` (or in-session confirmation via `redteam-lead`). The
  `exploit` phase never auto-selects a module — it writes a `reports/<host>/
  exploit.rc` template you fill from the vuln assessment, and refuses an `.rc`
  with no `use` line. For each hit, capture what a defender would see.
- **Scan-rate → nmap timing:** `max_scan_rate` = `polite`/`normal`/`aggressive`
  → `-T2`/`-T3`/`-T4`.

## 5. Validating the tooling

```bash
./tests/redteam_test.sh    # 13 guardrail checks — must stay green
```
No network or scan tools required. The SessionStart hook runs this plus a
tool-availability report every session.

## 6. Troubleshooting

- **"kaboom/tools missing — run on your lab Kali host"** — you're on a host
  without the tools (e.g. a cloud session). Copy the printed command to your Kali
  box on the lab network.
- **"target '…' is not an RFC1918/lab address — refusing"** — a public/non-lab IP
  is in `in_scope`. Fix the scope file.
- **A phase says "…not true — skipping"** — enable its flag in
  `ENGAGEMENT_SCOPE.yaml` (and confirm, for gated phases).
- **No `ENGAGEMENT_SCOPE.yaml`** — copy the example template and fill it in.
