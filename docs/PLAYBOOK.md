# Operator Playbook — kaboom red-team suite

A quickstart runbook for running an **authorized** engagement against a lab
network you own, using `redteam.sh` and the red-team agent suite.

> **Authorization is non-negotiable.** This tooling is only for systems you own
> or have written authorization to test. Every target must be an RFC1918 /
> loopback / lab address — public or third-party addresses are refused. See
> [`CLAUDE.md`](../CLAUDE.md) for the full authorization policy.

---

## 1. Pre-flight

1. **Confirm authorization.** You must own, or hold written authorization for,
   every host you list in scope. If you cannot clearly establish control of a
   target, do not add it.

2. **Create the scope file** from the template:

   ```bash
   cp .claude/agents/ENGAGEMENT_SCOPE.example.yaml ENGAGEMENT_SCOPE.yaml
   ```

   `ENGAGEMENT_SCOPE.yaml` is git-ignored — it holds your targets and
   authorization details and is never committed.

3. **Fill it in.** Edit the copy and set:
   - `engagement.owner` / `authorization` / `authorized_by` — your ownership /
     authorization line.
   - `targets.in_scope` — your lab subnet(s) and host(s), RFC1918 only (e.g.
     `192.168.56.0/24`, `192.168.56.101`).
   - `targets.out_of_scope` — hosts to leave untouched (e.g. the gateway
     `192.168.56.1`).
   - `rules_of_engagement` — the gates (`allow_active_scanning`,
     `allow_vuln_assessment`, `allow_credential_testing`, `allow_exploitation`)
     and `max_scan_rate` (`polite | normal | aggressive`).
   - `output.report_dir` — defaults to `./reports`.

4. **Sanity-check parsing** before any active work:

   ```bash
   ./redteam.sh scope
   ```

   This prints the parsed `in_scope`, `out_scope`, rate (with the mapped nmap
   timing), the four gate states, and `report_dir`. If a target is not an
   RFC1918/lab address the runner **refuses and exits** here — fix the scope
   file before continuing.

---

## 2. Running an engagement

### (a) Agent-driven — via the `redteam-lead` subagent

Invoke the **`redteam-lead`** agent (e.g. "test my lab per
ENGAGEMENT_SCOPE.yaml"). It is the orchestrator and entry point. It will:

1. Read `ENGAGEMENT_SCOPE.yaml` and **stop** if it is missing.
2. Validate scope (RFC1918/lab only; stop and ask on any public address).
3. Echo the scope, authorization line, and rules of engagement, and wait for
   your explicit **"go"**.
4. Delegate per-host, in order, to the specialist subagents:

   | Phase | Subagent | Role / tools | Gate |
   |-------|----------|--------------|------|
   | Recon | `recon-scout` | host + service discovery, nmap (read-only) | `allow_active_scanning` |
   | Web | `web-enum` | dirb + nikto on web services | `allow_active_scanning` |
   | Vuln | `vuln-assessor` | searchsploit + safe NSE + CVE→MSF mapping (analysis only) | `allow_vuln_assessment` |
   | Creds | `cred-tester` | hydra weak-credential tests | `allow_credential_testing` **+** in-session confirmation |
   | Report | `report-writer` | compiles `REPORT.md` + `findings.csv` | — |

   Credential testing is skipped (and noted) unless enabled. Exploitation is
   never auto-run — even with `allow_exploitation: true`, `redteam-lead`
   coordinates it manually with your in-session confirmation.

### (b) Script-driven — via `./redteam.sh`

`redteam.sh` is a thin phase runner. It reads `ENGAGEMENT_SCOPE.yaml`, enforces
scope, and either runs each tool (if installed) or **prints the exact command**
(if the tool is missing) so it is safe to run anywhere.

Subcommands:

| Command | Tool(s) driven | What it does | Requires |
|---------|----------------|--------------|----------|
| `./redteam.sh recon` | nmap | `-sn` host discovery for CIDRs; `-sV -O --top-ports 1000` service scan per host → `recon_nmap.*` | `allow_active_scanning: true` |
| `./redteam.sh web` | dirb, nikto | dirb directory enum + nikto scan per host (skips CIDRs) → `dirb_80.txt`, `nikto_80.txt` | `allow_active_scanning: true` |
| `./redteam.sh vuln` | nmap NSE, searchsploit | `--script 'default,safe,vuln'` NSE (no exploit scripts) → `nse.*`; prints searchsploit next-steps | `allow_vuln_assessment: true` |
| `./redteam.sh creds` | hydra | weak-cred check, **ssh only by default**, `-t 4 -f` → `hydra_ssh.txt` | `allow_credential_testing: true` |
| `./redteam.sh report` | — | writes `REPORT.md` skeleton + `findings.csv` header, lists artifacts | — |
| `./redteam.sh all` | all above | runs recon → web → vuln → creds → report in sequence | per-phase gates |
| `./redteam.sh scope` | — | prints parsed scope and exits | — |

**Recommended order:** `recon` → `web` → `vuln` → `creds` → `report` (which is
exactly what `all` does). Out-of-scope hosts and CIDRs (for web/vuln/creds) are
skipped automatically. Each phase whose gate is not `true` prints a "skipping"
notice and does nothing.

> The scan tools must run on a host **on the lab network** (e.g. a Kali box). In
> a cloud session they are absent and the lab is unreachable, so both the runner
> and the agents print commands rather than fabricating output.

---

## 3. Reading results

Output lands under `output.report_dir` (default `./reports/`, git-ignored),
one directory per host (slashes in CIDRs become underscores):

```
reports/
  192.168.56.101/
    recon_nmap.{nmap,gnmap,xml}   # recon
    dirb_80.txt  nikto_80.txt     # web
    nse.{nmap,gnmap,xml}          # vuln (NSE)
    hydra_ssh.txt                 # creds (if enabled)
  REPORT.md                       # summary (from `report`)
  findings.csv                    # host,port,service,severity,cve,summary
```

- **`REPORT.md`** (from `./redteam.sh report`) is a skeleton: engagement name,
  authorization line, date, in-scope list, gate states, and a list of all
  artifact files. Fill in severity ranking from the per-host artifacts.
- **`findings.csv`** starts as just the header row — populate it from the
  artifacts for easy sorting.

**For a narrative report**, hand a host's artifact set to the **`report-writer`**
agent. It reads the per-host files, then produces a richer `REPORT.md`
(executive summary, methodology, findings ranked by severity with evidence /
CVE / MSF module / remediation, appendix) and a filled `findings.csv`. It
synthesizes only — it does not scan, does not invent findings (a missing
artifact means that phase didn't run), and treats any found credentials as
sensitive.

---

## 4. Gates & safety rails in practice

- **Credential testing** is off by default. To enable it: set
  `allow_credential_testing: true` in the scope file **and** confirm in-session
  (the `cred-tester` agent double-gates on both; the script gate is the YAML
  flag). Start with small dictionaries and `ssh` only; the runner defaults to
  ssh — add `pop3`/`imap`/`rdp`/`smb` deliberately.
- **Exploitation is never auto-run.** Even with `allow_exploitation: true`, the
  runner never launches exploits (it only prints a note), and agents only
  *map* CVEs to Metasploit modules. Launching anything is manual and requires
  explicit in-session operator confirmation coordinated by `redteam-lead`.
- **Account-lockout caution:** testing `rdp`/`smb` against AD can lock out
  accounts. Warn first, keep parallelism low (`-t 4` or lower), and stop
  immediately on signs of lockout or service disruption
  (`stop_on_service_disruption: true`).
- **Scan-rate → nmap timing:** `max_scan_rate` maps to nmap `-T`:

  | `max_scan_rate` | nmap timing |
  |-----------------|-------------|
  | `polite`        | `-T2`       |
  | `normal` (default / unset) | `-T3` |
  | `aggressive`    | `-T4`       |

---

## 5. Validating the tooling

- **Guardrail tests** must stay green before committing changes to `redteam.sh`:

  ```bash
  ./tests/redteam_test.sh
  ```

  These 7 checks (public-IP refusal, scope + timing parse, recon commands,
  out-of-scope skip, creds gate off/on, safe-NSE-only) need no network or scan
  tools — missing tools make the runner print commands, so the tests run
  anywhere. They are the guarantee the scope/authorization guardrails hold.

- **SessionStart hook** (`.claude/hooks/check-tools.sh`) reports, each session,
  which of `nmap dirb nikto searchsploit msfconsole hydra` are present vs.
  missing, runs the guardrail self-test, and reminds you whether
  `ENGAGEMENT_SCOPE.yaml` exists (it never prints the file's contents).

---

## 6. Troubleshooting

- **"[tool missing — run on your lab Kali host]" / tools reported MISSING** —
  you are on a host without the scan tools (e.g. a cloud session). Run the
  printed commands on a Kali-style host on the lab network, or install the
  tools there (`apt install <tool>`). Output is never fabricated.
- **`target '…' is not an RFC1918/lab address — refusing`** — the target is not
  private (10/8, 172.16–31, 192.168/16, 127/8). Only test networks you own;
  remove or correct the target in the scope file.
- **`skip out-of-scope …`** — the host is listed under `targets.out_of_scope`;
  remove it there if it should be tested.
- **`no ENGAGEMENT_SCOPE.yaml — copy … and fill it in first`** — you haven't
  created the scope file. See [Pre-flight](#1-pre-flight).
- **A phase does nothing / "not true — skipping"** — the relevant gate
  (`allow_active_scanning`, `allow_vuln_assessment`, `allow_credential_testing`)
  is not `true` in the scope file.
