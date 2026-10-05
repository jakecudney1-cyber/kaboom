# Lab Setup — standing up an isolated, self-owned practice range

A practical guide to building a home lab you can safely red-team with this repo's
tooling (kaboom + the red-team agent suite). The example network here is
`192.168.56.0/24`, matching `.claude/agents/ENGAGEMENT_SCOPE.example.yaml`, so
the IP plan below drops straight into your `ENGAGEMENT_SCOPE.yaml`.

## 1. Safety and ethics first — read this

This lab exists so you can practice **only against systems you own**. That is the
entire point of building an isolated range: it removes any ambiguity about
authorization.

- **Own everything you touch.** Every VM in this lab is created and owned by you.
  Never point these tools at a machine, service, or address you do not control.
  Scanning or attacking third-party systems without written authorization is
  illegal in most jurisdictions.
- **Isolate the lab from everything else.** The lab must not be able to reach
  your real LAN, your other devices, or the internet. Use a host-only or internal
  network (below) with no NAT/bridged adapter on the target VMs. Intentionally
  vulnerable VMs are, by design, trivially compromised — never expose them to a
  routable network.
- **Keep the host out of scope.** Your hypervisor host (the gateway, typically
  `192.168.56.1`) is not a target. It is explicitly listed under
  `out_of_scope` in the scope file.
- **The tooling enforces this too.** Every agent and `redteam.sh` gate on
  `ENGAGEMENT_SCOPE.yaml`: targets must be RFC1918/lab addresses, exploitation and
  credential testing are off by default, and anything outside the scope file is
  refused. The lab's isolation and the scope file are two layers of the same
  guarantee — set both up correctly.

## 2. Hypervisor and an isolated network

Pick one hypervisor. Any of these can host an isolated network that never routes
to your real LAN or the internet.

### VirtualBox (host-only network)

A **host-only** network connects the VMs and the host, and nothing else.

```bash
# Create a host-only network on 192.168.56.0/24 with the host at .1
VBoxManage hostonlyif create                       # creates vboxnet0
VBoxManage hostonlyif ipconfig vboxnet0 \
    --ip 192.168.56.1 --netmask 255.255.255.0

# Disable the built-in DHCP server so you can assign static IPs (recommended),
# or leave it on and configure a small static range.
VBoxManage dhcpserver remove --interface=vboxnet0 2>/dev/null || true
```

Then for each VM: Settings → Network → Adapter 1 → **Host-only Adapter →
vboxnet0**, and make sure no other adapter is set to NAT or Bridged. For a
range that is also cut off from the host, use an **Internal Network** instead
(`--intnet`), but host-only is usually what you want so the Kali box can reach
the targets while the host provides `.1`.

### VMware Workstation/Fusion (host-only)

Open the **Virtual Network Editor**, add/select a network (e.g. `VMnet1`), set it
to **Host-only**, set the subnet to `192.168.56.0/24`, and **disable "Connect a
host virtual adapter to this network" to internet / disable NAT**. Assign each
VM's network adapter to that `VMnet1` host-only network. Do not attach a NAT or
bridged adapter to the target VMs.

### libvirt / KVM (isolated network)

Define a network with **no forwarding** (no `<forward/>` element = fully
isolated; traffic cannot leave the virtual switch).

```xml
<!-- lab-isolated.xml -->
<network>
  <name>lab-isolated</name>
  <bridge name="virbr-lab"/>
  <ip address="192.168.56.1" netmask="255.255.255.0"/>
  <!-- No <forward> element: isolated, no NAT, no routing to the host LAN. -->
</network>
```

```bash
virsh net-define lab-isolated.xml
virsh net-start   lab-isolated
virsh net-autostart lab-isolated
```

Attach each VM's NIC to `lab-isolated`. The host appears at `192.168.56.1`; there
is no path to the internet or your physical LAN.

> **Verify isolation** once the net is up: from a target VM, confirm
> `ping 8.8.8.8` and a ping to your real LAN both **fail**, while the Kali box can
> reach the targets. If a target can reach the internet, an adapter is
> misconfigured — fix it before continuing.

## 3. The attacker box — Kali Linux

Stand up one **Kali Linux** VM. This is where kaboom and all the underlying
tools run, and where you'll start a Claude Code session to drive the agent suite.

- Attach its NIC to the **same host-only/internal network** (`192.168.56.0/24`).
- Give it a static address, e.g. `192.168.56.10` (see the IP plan below).
- Kali ships with the full toolset. Confirm the pieces this repo uses are present:
  `nmap`, `dirb`, `nikto`, `searchsploit`, `msfconsole`, `hydra`.

This repo's **SessionStart hook** (`.claude/hooks/check-tools.sh`, wired via
`.claude/settings.json`) checks for exactly those six tools and reports which are
present plus whether `ENGAGEMENT_SCOPE.yaml` exists — so when you start a session
on the Kali box you'll immediately see whether you're ready to run live. On a
stock Kali install they'll all be found; if any are missing:

```bash
sudo apt update
sudo apt install -y nmap dirb nikto exploitdb hydra metasploit-framework
```

Clone this repo onto the Kali box and run the suite from there — that's the only
place the tools can actually reach the lab.

## 4. Target VMs — intentionally vulnerable, legal to attack

These are purpose-built, freely available practice targets. Download each, import
it, and attach its NIC to the isolated network. A few well-known ones:

- **Metasploitable2** — a deliberately vulnerable Ubuntu image; the classic
  nmap/Metasploit/hydra practice target (many open services, weak creds).
- **Metasploitable3** — Windows- and Linux-based builds (Vagrant), broader and
  more modern service coverage.
- **OWASP DVWA** (Damn Vulnerable Web Application) — a PHP/MySQL web app with
  tunable difficulty; ideal for the `web-enum` phase (dirb/nikto) and web vulns.
  Often run as a container or dropped onto a small LAMP VM.
- **VulnHub images** — a large catalog of community boot-to-root VMs (e.g.
  Kioptrix, Mr-Robot, the "basic pentesting" series). Pick a few at varying
  difficulty.
- **HackTheBox-style / OWASP WebGoat / bWAPP** — additional local vulnerable-app
  images for web-focused practice.

> Only use images intended for this purpose and downloaded from their official
> sources. Never run them on a routable network.

### Suggested IP plan for `192.168.56.0/24`

| Host | Role | IP |
|------|------|-----|
| Hypervisor host / gateway | **out of scope** | `192.168.56.1` |
| Kali (attacker, runs kaboom) | operator box, not a target | `192.168.56.10` |
| Metasploitable2 | target | `192.168.56.20` |
| Metasploitable3 (Linux) | target | `192.168.56.21` |
| Metasploitable3 (Windows) | target | `192.168.56.22` |
| DVWA / web app VM | target | `192.168.56.30` |
| VulnHub image #1 | target | `192.168.56.40` |
| VulnHub image #2 | target | `192.168.56.41` |

Assign these statically on each VM (or as DHCP reservations). The Kali box
(`.10`) is where you run the tools, so you typically do **not** scan it; the
host (`.1`) stays out of scope.

## 5. The resulting `ENGAGEMENT_SCOPE.yaml` in_scope block

Copy the template (`cp .claude/agents/ENGAGEMENT_SCOPE.example.yaml
ENGAGEMENT_SCOPE.yaml`) and set its `targets` block to match the lab. You can
scope the whole subnet, or list just the target VMs — listing them explicitly is
tidier and keeps the Kali box out of the target set:

```yaml
targets:
  in_scope:
    - "192.168.56.20"    # Metasploitable2
    - "192.168.56.21"    # Metasploitable3 (Linux)
    - "192.168.56.22"    # Metasploitable3 (Windows)
    - "192.168.56.30"    # DVWA / web app VM
    - "192.168.56.40"    # VulnHub image #1
    - "192.168.56.41"    # VulnHub image #2
    # Or scope the whole lab subnet instead of the list above:
    # - "192.168.56.0/24"
  out_of_scope:
    - "192.168.56.1"     # hypervisor host / gateway — never touch
    - "192.168.56.10"    # Kali attacker box — the operator machine
```

Leave the rest of the file as the template has it: `allow_credential_testing` and
`allow_exploitation` stay `false` until you deliberately opt in, and
`stop_on_service_disruption: true` keeps the agents backing off if a VM falls over.

## 6. Running the suite from the Kali box

With the lab up and `ENGAGEMENT_SCOPE.yaml` in place, run everything **from the
Kali box on the lab network** — that's where the tools exist and where the
targets are reachable.

- **Script-driven:** run a single phase or the whole chain:

  ```bash
  ./redteam.sh scope     # sanity-check the scope file parses and resolves
  ./redteam.sh recon     # nmap host + service discovery
  ./redteam.sh all       # recon -> web -> vuln -> (creds if enabled) -> report
  ```

- **Agent-driven:** start a Claude Code session on the Kali box and invoke the
  lead agent:

  ```
  > Use the redteam-lead agent to test my lab per ENGAGEMENT_SCOPE.yaml
  ```

  It validates scope, asks for your go-ahead, then delegates recon → web-enum →
  vuln-assessor → (cred-tester, only if enabled) → report-writer.

Results land in `reports/` (`REPORT.md` + `findings.csv`). Running from a cloud
session where the tools are absent will print the exact commands to run rather
than fabricate output — so always run live from the lab-connected Kali box.

## 7. Snapshots and teardown

Intentionally vulnerable VMs get messy fast once you start exploiting them. Snapshot
so you can reset to a known-good state.

- **Snapshot each target clean, right after import and network config,** before
  any testing. Re-run from the same baseline whenever you want to repeat a scan.

  ```bash
  # VirtualBox
  VBoxManage snapshot "Metasploitable2" take "clean-baseline"
  VBoxManage snapshot "Metasploitable2" restore "clean-baseline"

  # libvirt/KVM
  virsh snapshot-create-as metasploitable2 clean-baseline
  virsh snapshot-revert   metasploitable2 clean-baseline
  ```

  (VMware: use the Snapshot Manager, or `vmrun snapshot <vmx> clean-baseline` /
  `vmrun revertToSnapshot <vmx> clean-baseline`.)

- **Snapshot the Kali box too** after installing/updating tools, so you can roll
  back a broken toolchain.
- **Power down the lab when you're done** — don't leave vulnerable VMs running.
- **Tear down fully** by deleting the VMs and then removing the isolated network
  (`VBoxManage hostonlyif remove vboxnet0`, or `virsh net-destroy lab-isolated &&
  virsh net-undefine lab-isolated`). Because the network never routed anywhere,
  there's nothing to clean up on your real LAN.
- Keep `ENGAGEMENT_SCOPE.yaml` and `reports/` out of git (they already are via
  `.gitignore`); treat any credentials found during practice as sensitive even in
  a lab.
