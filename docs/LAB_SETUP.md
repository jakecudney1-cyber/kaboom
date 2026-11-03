# Lab Setup — standing up an isolated, self-owned practice range

A guide to building a home lab you can legally and safely attack with this repo's
tooling. Everything here assumes **machines you own, on a network you control,
isolated from production and the internet.**

## 1. Safety and ethics first

- Only test systems you own or have **written** authorization to test.
- Keep the lab **isolated**: use a host-only / internal hypervisor network so lab
  traffic can't route to your real LAN or the internet. This isolation plus the
  `ENGAGEMENT_SCOPE.yaml` scope file are two layers of the same guarantee.
- Keep the host/gateway (e.g. `192.168.56.1`) in `out_of_scope`.
- Snapshot targets so you can reset to a known-vulnerable baseline.

## 2. Hypervisor + an isolated network

Example network: **`192.168.56.0/24`**, host at `.1` (out of scope).

**VirtualBox (host-only):**
```bash
VBoxManage hostonlyif create                      # creates vboxnet0
VBoxManage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0
VBoxManage dhcpserver modify --ifname vboxnet0 --disable   # static IPs recommended
```
Attach each VM's adapter to "Host-only Adapter → vboxnet0".

**VMware (Workstation/Fusion):** Virtual Network Editor → add a **host-only**
network, subnet `192.168.56.0/24`, DHCP off. Set each VM's NIC to that network.

**libvirt/KVM (isolated, no forwarding):**
```xml
<network>
  <name>lab-isolated</name>
  <bridge name='virbr-lab'/>
  <ip address='192.168.56.1' netmask='255.255.255.0'/>
  <!-- no <forward> element => fully isolated -->
</network>
```
`virsh net-define lab.xml && virsh net-start lab-isolated && virsh net-autostart lab-isolated`

**Verify isolation:** from a target VM, `ping 8.8.8.8` should fail and you should
not be able to reach your real LAN.

## 3. The attacker box — Kali Linux

Put a **Kali** VM on the isolated network (e.g. `192.168.56.10`). This is where
kaboom and the tools run. The SessionStart hook checks for:
`nmap dirb gobuster whatweb sslscan enum4linux nikto searchsploit msfconsole hydra sqlmap commix dotdotpwn nuclei sqlite3 xmllint`.
Install any missing ones:
```bash
sudo apt update && sudo apt install -y nmap dirb gobuster whatweb sslscan \
  enum4linux nikto exploitdb metasploit-framework hydra sqlmap commix \
  dotdotpwn sqlite3 libxml2-utils
# nuclei: install from its project (Go) if not packaged
```
Clone this repo onto the Kali box and run everything from there.

## 4. Target VMs — intentionally vulnerable, legal to attack

| Target | Good for | Suggested IP |
|--------|----------|--------------|
| Metasploitable 2 | services, host exploits (vsftpd, Samba, etc.) | 192.168.56.20 |
| Metasploitable 3 | modern Windows/Linux host exploitation | 192.168.56.21 |
| OWASP DVWA | web injection (SQLi, XSS, command injection) | 192.168.56.30 |
| OWASP WebGoat / bWAPP | guided web vulns | 192.168.56.31 |
| VulnHub images | mixed boot-to-root practice | 192.168.56.40-41 |

(`.1` host/gateway stays out of scope; `.10` is Kali.)

## 5. The resulting `ENGAGEMENT_SCOPE.yaml` in_scope block

```yaml
targets:
  in_scope:
    - "192.168.56.0/24"      # or list individual target IPs
  out_of_scope:
    - "192.168.56.1"         # host / gateway
    - "192.168.56.10"        # your Kali attacker box
rules_of_engagement:
  allow_active_scanning: true
  allow_vuln_assessment: true
  allow_credential_testing: false   # flip to true to practice hydra
  allow_exploitation: false         # flip to true (+ CONFIRM_EXPLOIT=yes) to exploit
```

## 6. Running the suite from the Kali box

```bash
cp .claude/agents/ENGAGEMENT_SCOPE.example.yaml ENGAGEMENT_SCOPE.yaml   # edit it
./redteam.sh all                              # recon + vuln + report (safe)
CONFIRM_EXPLOIT=yes ./redteam.sh web          # active web injection (sqlmap/…)
./redteam.sh creds                            # needs allow_credential_testing: true
CONFIRM_EXPLOIT=yes ./redteam.sh exploit      # Metasploit host exploitation
```
Or invoke the `redteam-lead` agent and let it orchestrate. In a cloud session
without the tools, the runner prints commands to paste on this Kali box.

## 7. Snapshots and teardown

- Snapshot each target at its clean vulnerable baseline
  (`VBoxManage snapshot <vm> take baseline`) and restore between exercises.
- Power down when idle; delete the isolated network when finished.
- Remember `reports/` and `kaboom.db` are git-ignored — they stay on the Kali box.
