# Pi-hole on Synology NAS with Docker

![pre-commit](https://github.com/jlambert229/pihole-synology-docker/actions/workflows/pre-commit.yml/badge.svg)
![GitHub last commit](https://img.shields.io/github/last-commit/jlambert229/pihole-synology-docker)

Network-wide ad blocking and local DNS running on your Synology NAS. No dedicated hardware required — uses Docker with macvlan networking for clean IP separation.

> **Companion repo for:** [Running Pi-hole on Synology NAS with Docker](https://foggyclouds.io/post/pihole-synology-docker)

## 🚨 Pi-hole v6 Note

This repo uses **Pi-hole v6** (released February 2025). Key changes from v5:

- **Alpine-based image** — Significantly smaller (~150MB vs ~300MB)
- **`FTLCONF_` environment variables** — All old variables replaced (see [Environment Variables](#2-environment-variables-env) section)
- **Embedded web server** — No more lighttpd/PHP dependency
- **Native HTTPS support** — Built-in TLS with custom or auto-generated certificates
- **`/etc/dnsmasq.d/` disabled by default** — Must enable explicitly (see [Custom DNS](#custom-dns-config99-customconf) section)
- **Environment variables are read-only** — Settings via env vars cannot be changed through web UI

**Upgrading from v5?** See [Pi-hole's upgrade guide](https://docs.pi-hole.net/docker/upgrading/v5-v6/). Configuration files migrate automatically, but **environment variables must be updated manually**.

## Why This Setup

- **macvlan networking** — Pi-hole gets its own LAN IP (e.g., `192.168.1.53`), avoiding port conflicts with DSM
- **macvlan shim** — Solves the host ↔ macvlan isolation problem so your NAS can reach Pi-hole
- **Automated deployment** — Push-button deploy from your workstation over SSH
- **Configuration as code** — Curated blocklists, whitelist, custom DNS — all version-controlled
- **Automated backups** — Daily exports (Teleporter + volume snapshots) with 14-day retention

## Quick Start

**Prerequisites:**
- Synology NAS with DSM 7.2+ and Container Manager 24.0.2+ installed
- SSH key-based auth to your NAS
- An unused IP on your LAN for Pi-hole
- Basic familiarity with `docker-compose` (DSM 7.2+ requires YAML-based container management)

**Deploy in 5 minutes:**

```bash
# 1. Clone this repo
git clone https://github.com/YOUR-USERNAME/pihole-synology-docker.git
cd pihole-synology-docker

# 2. Edit configuration (see Configuration section)
vi docker-compose.yml   # Set your IPs and network interface
vi .env.example         # Review defaults

# 3. Edit deploy.sh to set your NAS connection details
vi deploy.sh            # Set NAS_USER, NAS_IP

# 4. Deploy
./deploy.sh

# 5. Verify
./verify.sh
```

## Architecture

```
┌─────────────────────────────────────────┐
│  Your Router (192.168.1.1)             │
│  DHCP: Hands out Pi-hole as DNS        │
└─────────────────┬───────────────────────┘
                  │
         ┌────────┴────────┐
         │                 │
    ┌────▼────┐      ┌─────▼──────┐
    │ Clients │      │ Synology   │
    │         │      │ 192.168.1.2│
    └─────────┘      └─────┬──────┘
                           │
                      ┌────▼────────────┐
                      │ macvlan-shim    │
                      │ 192.168.1.200   │  ← Bridges host ↔ Pi-hole
                      └────┬────────────┘
                           │
                      ┌────▼────────────┐
                      │ Pi-hole         │
                      │ 192.168.1.53    │  ← Own IP via macvlan
                      └─────────────────┘
```

**The macvlan Problem:**
- macvlan gives Pi-hole a clean dedicated IP
- By design, the host (Synology) **cannot** talk to macvlan containers
- This breaks DSM DNS resolution and other containers

**The Solution:**
- `macvlan-shim.sh` creates a bridge interface on the host
- Now Synology can reach Pi-hole at its macvlan IP
- Automatically persists across reboots via DSM's `rc.d`

## DSM 7.2+ Container Manager Notes

**Important workflow change:** As of DSM 7.2 (Container Manager 24.0.2+), container settings **cannot be modified after creation**. To change ports, volumes, environment variables, or links:

1. Use `docker-compose` projects (YAML-based approach) — **Required for this setup**
2. Or duplicate the container via GUI and recreate with new settings

This repo uses `docker-compose.yml` exclusively, so you can modify settings and redeploy with:

```bash
./deploy.sh
```

**Other DSM 7.2+ changes:**
- Docker daemon updated to 24.0.2
- Native `docker compose` command support (new syntax without hyphen)
- Customizable subnet settings for Container Manager networks
- Immutable container configurations enforced by GUI

## Configuration

### 1. Docker Compose (`docker-compose.yml`)

Edit these values to match your network:

```yaml
networks:
  pihole_net:
    driver_opts:
      parent: eth0                     # Your NAS's primary interface (check with: ip addr)
    ipam:
      config:
        - subnet: 192.168.1.0/24       # Your LAN subnet
          gateway: 192.168.1.1         # Your router IP
          ip_range: 192.168.1.53/32    # Pi-hole's IP (pick an unused one)
```

**Key settings:**
- `PIHOLE_IP` (in services → networks) — The dedicated IP for Pi-hole
- `parent: ethX` — Your NAS's network interface (run `ip addr` on NAS to confirm)
- `subnet`, `gateway` — Match your LAN configuration
- `ip_range: X.X.X.X/32` — Restricts Docker to exactly one IP (prevents conflicts)

### 2. Environment Variables (`.env`)

Copy `.env.example` to `.env` and customize:

```bash
cp .env.example .env
vi .env
```

```bash
# Web interface password (leave empty for no password — not recommended)
# Pi-hole v6 uses FTLCONF_ prefix for all settings
PIHOLE_PASSWORD=your-secure-password

# Timezone — https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
TZ=America/New_York
```

**Pi-hole v6 Variable Changes:**

All environment variables now use the `FTLCONF_` prefix. Common variables:

| Setting | Environment Variable | Default |
|---------|---------------------|---------|
| Web password | `FTLCONF_webserver_api_password` | (none) |
| Upstream DNS | `FTLCONF_dns_upstreams` | `8.8.8.8;8.8.4.4` |
| DNS cache size | `FTLCONF_dns_cache_size` | `10000` |
| Listening mode | `FTLCONF_dns_listeningMode` | `all` |
| DNSSEC | `FTLCONF_dns_dnssec` | `false` |
| Web UI port | `FTLCONF_webserver_port` | `80` (or `8080` if conflict) |

**Important:** Environment variables in Pi-hole v6 are **read-only** — values set via env vars cannot be changed through the web UI or CLI. The env var always overrides other settings.

### 3. Deployment Script (`deploy.sh`)

Edit connection details at the top of `deploy.sh`:

```bash
NAS_USER="your-username"        # Your SSH username on the NAS
NAS_IP="192.168.1.2"            # Your NAS's IP address
NAS_DIR="/volume1/docker/pihole" # Where to deploy on NAS (adjust if needed)
PIHOLE_IP="192.168.1.53"        # Pi-hole's IP (must match docker-compose.yml)
```

### 4. macvlan Shim (`macvlan-shim.sh`)

Edit network configuration to match your setup:

```bash
PARENT_IF="eth0"                # Your NAS's primary interface
SHIM_IF="macvlan-shim"
SHIM_IP="192.168.1.200"         # Pick an UNUSED IP for the shim (not Pi-hole's IP!)
PIHOLE_IP="192.168.1.53"        # Pi-hole's IP (must match docker-compose.yml)
```

### 5. Verification Script (`verify.sh`)

Update connection details:

```bash
NAS_USER="your-username"
NAS_IP="192.168.1.2"
PIHOLE_IP="192.168.1.53"
```

## Usage

### Automated Deployment (Recommended)

Deploy everything from your workstation:

```bash
./deploy.sh
```

**What it does:**
1. Preflight checks (SSH, Container Manager)
2. Creates data directories on NAS
3. Prompts for password/timezone (if `.env` doesn't exist)
4. Copies files to NAS
5. Pulls Pi-hole image and starts container
6. Activates macvlan shim
7. Persists shim across reboots

**Output:**
```
╔══════════════════════════════════════╗
║   Pi-hole → Synology DS               ║
╚══════════════════════════════════════╝

[1/7] Preflight checks
  ✓ SSH connection
  ✓ Container Manager is running
  ✓ docker-compose available

...

════════════════════════════════════════
  Deployment complete!

  Web UI:   http://192.168.1.53/admin
  Test DNS: dig @192.168.1.53 google.com

  Next step: ./verify.sh
════════════════════════════════════════
```

### Verification

Comprehensive health checks:

```bash
./verify.sh
```

**Checks:**
- Container running without restart loops
- DNS resolution working
- Ad domains blocked
- Web UI reachable
- macvlan shim active
- Boot persistence configured

### Apply Configuration

Push curated blocklists, whitelist, regex patterns, and custom DNS:

```bash
./apply-config.sh              # Apply everything
./apply-config.sh --adlists    # Only update blocklists
./apply-config.sh --whitelist  # Only update whitelist
./apply-config.sh --regex      # Only update regex blacklist
./apply-config.sh --dnsmasq    # Only update DNS config
./apply-config.sh --dry-run    # Preview changes
```

**Configuration files:**
- `config/adlists.csv` — Blocklist subscriptions (Essential/Recommended/Aggressive tiers)
- `config/whitelist.txt` — Pre-emptive false positive fixes
- `config/regex-blacklist.txt` — Pattern-based blocking
- `config/99-custom.conf` — Local DNS records + conditional forwarding

### Router Integration

Example script for EdgeRouter/UniFi/VyOS (adapt for your router):

```bash
./update-edgerouter-dns.sh
```

Shows current DHCP DNS config, updates all scopes to advertise Pi-hole, commits changes, backs up config.

### Backups

Manual backup:

```bash
ssh nas-ip "sudo /volume1/docker/pihole/backup.sh --verbose"
```

**Or setup automated daily backups** via DSM Task Scheduler:

1. DSM → Control Panel → Task Scheduler → Create → Scheduled Task → User-defined script
2. General tab: User = `root`, Enabled = checked
3. Schedule tab: Daily, 3:00 AM
4. Task Settings → Run command:

```bash
/volume1/docker/pihole/backup.sh 2>&1 | logger -t pihole-backup
```

**What gets backed up:**
1. **Teleporter export** (`.zip`) — Pi-hole's built-in backup (settings, lists, DNS records)
2. **Volume snapshot** (`.tar.gz`) — Raw `/etc/pihole` + `/etc/dnsmasq.d` data

Backups stored in `/volume1/docker/pihole/backups/` with 14-day retention.

**Restore options:**

```bash
# Option 1: Teleporter (preferred) — via Web UI
# Settings → Teleporter → Import → select backup .zip

# Option 2: Volume snapshot (nuclear option)
ssh nas-ip
cd /volume1/docker/pihole
sudo docker-compose down
sudo tar xzf backups/YYYY-MM-DD_HHMM/pihole-volumes.tar.gz -C /volume1/docker/pihole/
sudo docker-compose up -d
```

## Configuration Files Explained

### Blocklists (`config/adlists.csv`)

Three-tier approach:

| Tier | Purpose | Default |
|------|---------|---------|
| **Essential** | High-quality, well-maintained, minimal false positives | Enabled |
| **Recommended** | Broader coverage, occasional false positive | Enabled |
| **Aggressive** | Maximum blocking, expect breakage | Disabled |

**Essential lists (2026 recommendations):**
- **HaGeZi Multi Pro** — Considered the best blocklist as of 2026; precision targeting of ads, tracking, malware, telemetry
- **OISD Big** (~1.5M domains) — Excellent stability and wide compatibility, the "safe daily driver" option
- **StevenBlack unified** (~130k domains) — Classic community favorite, Pi-hole default

**Philosophy differences:**
- **HaGeZi**: Aggressive precision blocking; deeper silence but occasional breakage requiring manual fixes
- **OISD**: Prioritizes stability and compatibility; avoids gray areas that might break apps

**Recommended lists:**
- Firebog curated (AdGuard, EasyList, EasyPrivacy)
- Malware/phishing protection (DandelionSprout, DigitalSide Threat Intel, Phishing Army)

**Aggressive lists (disabled by default):**
- **HaGeZi Ultimate** — Maximum security for technical users; expect significant breakage
- **OISD NSFW** — Adult content filter (useful for family networks)
- **StevenBlack fakenews + gambling** — Blocks misinformation and gambling sites

### Whitelist (`config/whitelist.txt`)

~100 domains that aggressive blocklists commonly break:
- Microsoft (login, updates, services)
- Apple (updates, captive portal)
- Google (Safe Browsing, fonts, APIs)
- Amazon/Alexa
- Streaming (Netflix, Spotify, YouTube)
- Gaming (Steam, PlayStation, Xbox)
- Samsung Smart TV services

**Why pre-emptive whitelisting?**  
Community-tested false positives. These domains get blocked by overzealous lists and break functionality. Easier to whitelist upfront than debug later.

### Regex Blacklist (`config/regex-blacklist.txt`)

Pattern-based blocking for domains that rotate subdomains:
- Ad server naming patterns (`ad*.`, `adserver.`, `adtech.`)
- Tracking pixels and beacons
- Telemetry (Samsung TV, Roku, Xiaomi)
- Content farms (Taboola, Outbrain, Revcontent)

### Custom DNS (`config/99-custom.conf`)

**⚠️ Pi-hole v6 Change:** By default, Pi-hole v6 **does not read** `/etc/dnsmasq.d/` configuration files. To enable custom dnsmasq configs:

1. **Option A (Recommended):** Mount the config directory and enable in `docker-compose.yml`:
   ```yaml
   environment:
     FTLCONF_misc_etc_dnsmasq_d: 'true'
   ```

2. **Option B:** Use inline configuration via environment variable:
   ```yaml
   environment:
     FTLCONF_misc_dnsmasq_lines: 'host-record=nas.lan,192.168.1.2;host-record=pihole.lan,192.168.1.53'
   ```

**Local DNS records:**
```bash
# Your homelab devices
host-record=nas.lan,192.168.1.2
host-record=pihole.lan,192.168.1.53
host-record=router.lan,192.168.1.1

# Wildcard for services
address=/.homelab.lan/192.168.1.100
```

**Conditional forwarding:**
```bash
# Reverse DNS lookups go to your router
server=/1.168.192.in-addr.arpa/192.168.1.1
```

**Performance tuning:**
- `domain-needed` — Don't forward plain names (no dots)
- `bogus-priv` — Don't forward private IP reverse lookups upstream

## Troubleshooting

### Container Won't Start

**Check port 53 conflict:**

```bash
ssh nas-ip "sudo netstat -tlnp | grep :53"
```

If DSM's DNS Server is running, stop it:
- Package Center → DNS Server → Stop → Disable

### Devices Not Using Pi-hole

**Check what DNS the device is using:**

```bash
nslookup google.com
# Look at the "Server:" line
```

**Common issues:**
- Router DHCP still advertising old DNS
- Device has static DNS configured
- Some devices (Chromecast) hardcode Google DNS (8.8.8.8)

**Force DHCP renewal:**

```bash
# Linux
sudo dhclient -r && sudo dhclient

# macOS
sudo ipconfig set en0 DHCP

# Windows
ipconfig /release && ipconfig /renew
```

### Legitimate Site Broken

**Temporary disable Pi-hole:**
- Web UI → Settings → Disable → 5 minutes

If site works now, it's Pi-hole. Check Query Log to find what was blocked.

**Whitelist the domain:**

```bash
# Add to config/whitelist.txt, then:
./apply-config.sh --whitelist
```

**Common false positives:**
- `s.youtube.com` — Breaks YouTube
- `guce.advertising.com` — Breaks Yahoo login  
- `app-measurement.com` — Breaks some mobile apps

### macvlan Shim Not Working

**Check if shim exists:**

```bash
ssh nas-ip "ip link show macvlan-shim"
```

If missing, recreate:

```bash
ssh nas-ip "sudo /volume1/docker/pihole/macvlan-shim.sh start"
```

**Check if persisted for reboot:**

```bash
ssh nas-ip "ls -la /usr/local/etc/rc.d/macvlan-shim.sh"
```

If missing, copy it:

```bash
ssh nas-ip "sudo cp /volume1/docker/pihole/macvlan-shim.sh /usr/local/etc/rc.d/ && \
            sudo chmod 755 /usr/local/etc/rc.d/macvlan-shim.sh"
```

### DNS Slow After DSM Update

DSM updates sometimes reset network settings. Verify:

1. Container still running: `ssh nas-ip "sudo docker ps"`
2. DSM DNS points to localhost: DSM → Network → General
3. Router DHCP still advertising Pi-hole

### Pi-hole v6 Specific Issues

**Custom dnsmasq configs not loading:**

Pi-hole v6 disables `/etc/dnsmasq.d/` by default. Add to `docker-compose.yml`:

```yaml
environment:
  FTLCONF_misc_etc_dnsmasq_d: 'true'
```

Then restart: `ssh nas-ip "cd /volume1/docker/pihole && sudo docker-compose restart"`

**Environment variables not taking effect:**

- Verify `FTLCONF_` prefix (not old `WEBPASSWORD`, `PIHOLE_DNS_`, etc.)
- Array values (like upstream DNS) must use semicolons: `'1.1.1.1;1.0.0.1'`
- Settings via env vars are **read-only** — cannot be changed via web UI

**Web UI on wrong port:**

If port 80/443 are taken, Pi-hole v6 falls back to port 8080. Check:

```bash
ssh nas-ip "sudo docker logs pihole | grep -i port"
```

Force a specific port:

```yaml
environment:
  FTLCONF_webserver_port: '8080'
```

**Upgrading from v5 to v6:**

Migration runs automatically, but:
1. **Backup volumes first** (irreversible config changes)
2. Update `docker-compose.yml` to use `FTLCONF_` variables
3. Remove old env vars (see [upgrade guide](https://docs.pi-hole.net/docker/upgrading/v5-v6/))

## File Reference

```
.
├── README.md                    # This file
├── docker-compose.yml           # Pi-hole container with macvlan networking
├── .env.example                 # Environment template (copy to .env)
├── .gitignore                   # Ignore .env and backups
│
├── deploy.sh                    # Automated deployment from workstation
├── verify.sh                    # Comprehensive health checks
├── macvlan-shim.sh              # Solves host ↔ macvlan isolation
├── apply-config.sh              # Push config changes to running instance
├── backup.sh                    # Automated backup (cron-ready)
├── update-edgerouter-dns.sh     # Router DHCP automation (example)
│
└── config/
    ├── adlists.csv              # Curated blocklists (Essential/Recommended/Aggressive)
    ├── whitelist.txt            # Pre-emptive false positive fixes
    ├── regex-blacklist.txt      # Pattern-based blocking
    └── 99-custom.conf           # Local DNS records + conditional forwarding
```

## Resource Usage

Tested on a 4-bay Synology NAS (Celeron J-series, 8GB RAM):

- **CPU:** <1% idle, <5% during blocklist updates
- **RAM:** ~100-150MB (Pi-hole v6 is more efficient than v5)
- **Storage:** ~150MB (Pi-hole v6 Alpine image) + ~350MB config = ~500MB total
- **Image size:** v6 Alpine (~150MB) vs v5 Debian (~300MB) — 50% reduction

**Query response times:**
- Cached: <1ms
- Blocked: <1ms
- Forwarded upstream: 10-20ms

**Pi-hole v6 performance improvements:**
- Embedded web server replaces lighttpd/PHP stack
- Reduced memory footprint
- Faster web UI response with server-side pagination

## Why These Choices

### Pi-hole v6 vs v5

**Pi-hole v6 advantages:**
- **Smaller footprint:** Alpine-based image (~150MB vs ~300MB Debian)
- **Embedded web server:** No lighttpd/PHP dependencies; simpler, faster
- **Native HTTPS:** Built-in TLS support without reverse proxy
- **Consolidated config:** Single `/etc/pihole/pihole.toml` file replaces scattered configs
- **Improved API:** RESTful API with server-side pagination

**Trade-offs:**
- **Breaking changes:** Environment variables require migration to `FTLCONF_` syntax
- **Read-only env vars:** Settings via environment cannot be changed through web UI (by design for container immutability)
- **dnsmasq.d disabled:** Custom dnsmasq configs require explicit opt-in

**Why upgrade?** Better performance, reduced resource usage, and modern architecture. The breaking changes are one-time migration effort.

### macvlan vs Host Networking

**macvlan pros:**
- Clean IP separation
- No port conflict with DSM
- Pi-hole appears as a distinct device

**macvlan cons:**
- Host can't talk to container (solved by shim)
- Slightly more complex setup

**Why macvlan?** DSM may want port 53 for its own services. macvlan is cleaner long-term.

### Network Planning Best Practices (2026)

When configuring macvlan on Synology:

**CIDR Alignment:**
- Plan IP ranges in CIDR-sized subnets to avoid conflicts
- Align DHCP ranges, static assignments, and container IPs within proper CIDR boundaries
- Example: Use `192.168.1.0/24` with DHCP in `192.168.1.100-200`, static devices in `192.168.1.2-50`, containers in `192.168.1.51-99`

**IP Range Restriction:**
- Use `/32` notation in `docker-compose.yml` to restrict Docker to exactly one IP
- Example: `ip_range: 192.168.1.53/32` ensures only this IP is used
- Prevents Docker from grabbing multiple IPs from your pool

**Host Communication:**
- The macvlan shim creates a bridge interface on the Synology host
- This solves the inherent macvlan isolation problem (host ↔ container)
- Without the shim, your NAS cannot reach Pi-hole (breaks DSM DNS resolution)

### Teleporter + Volume Backups

**Teleporter:**
- Pi-hole's native export format
- Settings, lists, DNS records
- Import via web UI — easy

**Volume snapshot:**
- Everything on disk (gravity.db, pihole.toml, etc.)
- Nuclear restore option
- Use when Teleporter fails

**Both together:** Belt and suspenders. Teleporter for normal restores, volume for disasters.

### Conservative Blocklists by Default

Aggressive lists break things. Starting conservative means:
- Your family won't complain that "the internet is broken"
- You can add more lists gradually
- You build a whitelist based on actual usage, not guesses

Start with Essential + Recommended. Add Aggressive lists only if you need them.

## Contributing

Found a better blocklist? Have a false positive fix? PRs welcome!

**Please include:**
- What you changed and why
- Testing you did (which sites/services)
- Any trade-offs or known issues

## License

MIT License — see [LICENSE](LICENSE)

## Acknowledgments

- [Pi-hole v6](https://pi-hole.net/) — The network-wide ad blocker (February 2025 release)
- [HaGeZi DNS Blocklists](https://github.com/hagezi/dns-blocklists) — Best-in-class 2026 blocklists with multi-tier protection
- [OISD](https://oisd.nl/) — Stability-focused comprehensive blocklist
- [StevenBlack hosts](https://github.com/StevenBlack/hosts) — Classic unified hosts blocklist
- Synology community for DSM 7.2+ Container Manager insights
- Reddit's r/pihole for troubleshooting patterns and v6 migration help
- Pi-hole community for comprehensive v6 documentation

---

**Questions or issues?** Open an issue or check the [blog post](https://foggyclouds.io/post/pihole-synology-docker) for detailed explanations.
