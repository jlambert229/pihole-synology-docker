# Pi-hole on Synology NAS with Docker

Network-wide ad blocking and local DNS running on your Synology NAS. No dedicated hardware required — uses Docker with macvlan networking for clean IP separation.

> **Companion repo for:** [Running Pi-hole on Synology NAS with Docker](https://foggyclouds.io/post/pihole-synology-docker)

## Why This Setup

- **macvlan networking** — Pi-hole gets its own LAN IP (e.g., `192.168.1.53`), avoiding port conflicts with DSM
- **macvlan shim** — Solves the host ↔ macvlan isolation problem so your NAS can reach Pi-hole
- **Automated deployment** — Push-button deploy from your workstation over SSH
- **Configuration as code** — Curated blocklists, whitelist, custom DNS — all version-controlled
- **Automated backups** — Daily exports (Teleporter + volume snapshots) with 14-day retention

## Quick Start

**Prerequisites:**
- Synology NAS with DSM 7+ and Container Manager installed
- SSH key-based auth to your NAS
- An unused IP on your LAN for Pi-hole

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
PIHOLE_PASSWORD=your-secure-password

# Timezone — https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
TZ=America/New_York
```

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

**Essential lists:**
- StevenBlack unified (~130k domains)
- OISD Big (~1.5M domains, excellent maintenance)
- HaGeZi Multi Pro (ads/tracking/malware)

**Recommended lists:**
- Firebog curated (AdGuard, EasyList, EasyPrivacy)
- Malware/phishing protection

**Aggressive lists (disabled by default):**
- HaGeZi Ultimate (will break things)
- OISD NSFW (adult content filter)

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
- **RAM:** ~150MB
- **Storage:** ~500MB (container + config)

**Query response times:**
- Cached: <1ms
- Blocked: <1ms
- Forwarded upstream: 10-20ms

## Why These Choices

### macvlan vs Host Networking

**macvlan pros:**
- Clean IP separation
- No port conflict with DSM
- Pi-hole appears as a distinct device

**macvlan cons:**
- Host can't talk to container (solved by shim)
- Slightly more complex setup

**Why macvlan?** DSM may want port 53 for its own services. macvlan is cleaner long-term.

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

- [Pi-hole](https://pi-hole.net/) — The network-wide ad blocker
- [StevenBlack hosts](https://github.com/StevenBlack/hosts) — Unified hosts blocklist
- [OISD](https://oisd.nl/) — Comprehensive blocklist
- [HaGeZi DNS Blocklists](https://github.com/hagezi/dns-blocklists) — Multi-tier protection
- Synology community for DSM Docker quirks
- Reddit's r/pihole for troubleshooting patterns

---

**Questions or issues?** Open an issue or check the [blog post](https://foggyclouds.io/post/pihole-synology-docker) for detailed explanations.
