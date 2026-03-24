im making a homelab repo documentation for my proxmox node and my unraid node what are some common scripts to add and give ideas for more
Mar 22
Synthesized homelab documentation strategies for virtualization platforms

Here's a solid breakdown of common and creative scripts to include in your homelab repo:
🖥️ Proxmox Scripts

VM & Container Management

    vm-snapshot.sh — Snapshot all VMs before updates, with auto-cleanup of old snapshots
    ct-create.sh — Templated LXC container provisioner (pass args for hostname, RAM, disk, template)
    vm-backup-verify.sh — Check that PBS/NFS backups completed and aren't corrupt
    bulk-clone.sh — Clone a template VM N times with sequential IPs (great for k8s nodes)

Maintenance

    pve-update.sh — Safe update script that snapshots, updates, and reboots with health checks
    storage-cleanup.sh — Purge old backups, unused disk images, and orphaned snippets
    cert-renew.sh — Auto-renew ACME/Let's Encrypt certs for the web UI

Monitoring

    node-health.sh — Report CPU temp, ZFS pool status, RAM, and disk I/O to a Discord webhook
    vm-status-report.sh — Daily digest of all VM/CT states emailed or pushed to Ntfy

📦 Unraid Scripts

Array & Disk

    parity-check-notify.sh — Wrap parity checks and send results to Discord/Slack
    disk-temp-alert.sh — Poll SMART data, alert if any drive exceeds a threshold
    spindown-report.sh — Log which drives are spinning when they shouldn't be

Docker / Compose

    container-update.sh — Pull latest images and recreate changed containers (like Watchtower but manual)
    compose-backup.sh — Tar up all your /appdata compose stacks before updates
    container-health-check.sh — Curl each service and alert if any return non-200

Backup

    appdata-backup.sh — Rsync /appdata to a backup share, with versioned folders by date
    offsite-sync.sh — Rclone important shares to B2/S3/Wasabi on a schedule

🔧 Cross-Node / General Ideas
Script	Purpose
inventory.sh	Dump both nodes' VM list, containers, and shares into a markdown file
network-scan.sh	Nmap your LAN and diff against a known-good baseline
dns-audit.sh	Check that all your Pi-hole/AdGuard custom records still resolve
ssl-expiry-check.sh	Scan all your self-hosted services and warn on certs expiring < 30 days
wakeonlan.sh	WoL wrapper with a hostname map for lazy node wakeup
tailscale-check.sh	Verify all nodes show as online in Tailscale, alert if any drop
git-config-backup.sh	Pull configs from Proxmox, Unraid, router, etc. and commit to the repo automatically
📁 Suggested Repo Structure

homelab/
├── proxmox/
│   ├── scripts/
│   ├── cloud-init/
│   └── notes.md
├── unraid/
│   ├── scripts/
│   ├── docker-compose/
│   └── notes.md
├── shared/
│   └── scripts/        # cross-node stuff
├── monitoring/
└── README.md

Some underrated additions to consider:

    A bootstrap.sh that sets up a fresh node from scratch (packages, SSH keys, mounts)
    A disaster-recovery.md runbook — not a script but invaluable when things break at 2am
    A .env.example with all your variables documented so future-you knows what's needed

Want me to write out any of these scripts in full?

yes, but also hew can i make my own
Mar 22
Deliberated on timing and pivoted to provide instructional guidance

Let me first figure out which scripts you want written out — then I'll walk you through making your own!

While you pick, here's how to make your own scripts from scratch:
🛠️ How to Write Your Own Homelab Scripts
The Anatomy of a Good Script
bash

#!/usr/bin/env bash
# ============================================================
# script-name.sh — What it does in one line
# Usage: ./script-name.sh [--flag] [arg]
# ============================================================
set -euo pipefail  # exit on error, unset vars, pipe failures

# --- Config (override with env vars) ---
THRESHOLD="${THRESHOLD:-80}"
LOG_FILE="${LOG_FILE:-/var/log/myscript.log}"
WEBHOOK_URL="${WEBHOOK_URL:-}"

# --- Helper functions ---
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
die()  { log "ERROR: $*"; exit 1; }
send() { [[ -n "$WEBHOOK_URL" ]] && curl -sf -X POST "$WEBHOOK_URL" -d "{\"content\":\"$*\"}" || true; }

# --- Checks ---
command -v smartctl &>/dev/null || die "smartctl not installed"

# --- Main logic ---
main() {
    log "Script started"
    # your logic here
    log "Done"
}

main "$@"

Key Principles

set -euo pipefail — Put this at the top of every script. It makes bash stop on errors instead of silently continuing, which prevents cascading failures.

Env-var config — Use ${VAR:-default} so scripts work out of the box but are easy to override via a .env file or cron environment without editing the script itself.

Idempotency — Scripts should be safe to run multiple times. Check before you act:
bash

# Bad
mkdir /mnt/backup

# Good
mkdir -p /mnt/backup

Logging — Always write to a log file AND stdout. Makes debugging cron jobs much easier.

Dry-run mode — Add a --dry-run flag for destructive scripts:
bash

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

delete_file() {
    if $DRY_RUN; then
        echo "[DRY RUN] Would delete: $1"
    else
        rm -f "$1"
    fi
}

Deploying & Scheduling

Make it executable:
bash

chmod +x scripts/my-script.sh

Cron (Proxmox/Unraid both support this):
bash

crontab -e

# Examples:
0 3 * * *  /opt/homelab/scripts/pve-update.sh   # 3am daily
0 * * * *  /opt/homelab/scripts/node-health.sh  # every hour

Unraid User Scripts plugin — GUI-based cron scheduler, great for Unraid-specific stuff without touching crontab manually.
Storing Secrets

Never hardcode passwords or webhook URLs in scripts. Use a .env file:
bash

# .env  (add to .gitignore!)
DISCORD_WEBHOOK=https://discord.com/api/webhooks/...
BACKUP_PASS=supersecret

# Load it in your script:
source "$(dirname "$0")/../.env"

bash

# .gitignore
.env
*.log

Once you pick the scripts above I'll write them out with all of this baked in — notifications wired to whichever platform you chose, .env config, logging, and dry-run where it makes sense.

Q: Which scripts do you want written out in full? (Select all that apply)
A: node-health.sh, pve-update.sh, appdata-backup.sh, container-update.sh, disk-temp-alert.sh, ssl-expiry-check.sh

Q: Where do you want alerts/notifications sent?
A: Email
Mar 22
Architected six bash scripts with integrated email notifications

Let me write all 6 scripts out as files with email notifications, shared .env config, and a helper library they all import.
Orchestrated file generation strategy for multiple scripts

Here's everything — 9 files total, ready to drop into your repo.
What's in the package

shared/lib.sh — The backbone. Every script sources this. It handles logging, the email trap (fires on exit automatically, subject changes to ❌ FAILED if anything went wrong), dry-run mode, and the run() wrapper. You only configure email once in .env.

.env.example — Single config file for everything. Copy to .env, fill it in, add .env to your .gitignore.
Per-script highlights

    node-health.sh — Auto-detects ZFS pools, falls back to /sys/class/thermal if lm-sensors isn't installed, checks VM/CT counts via qm/pct
    pve-update.sh — Snapshots all running VMs and CTs before touching anything, prunes old pre-update snapshots down to SNAP_KEEP, supports --reboot for hands-off scheduled updates
    appdata-backup.sh — Defaults to rsync (fast, incremental), add --compress for tarballs. Has a PAUSE_CONTAINERS variable in .env for databases that need to be stopped cleanly before backup
    container-update.sh — Walks your entire COMPOSE_DIR finding stacks, pulls images, recreates changed containers, does a 10-second post-start health check
    disk-temp-alert.sh — Auto-detects all block devices if you don't specify them, checks temp + reallocated sectors + pending sectors + uncorrectable errors
    ssl-expiry-check.sh — Works for public domains (live TLS grab) and local self-signed certs (file path), handles both Linux and macOS date formats

First steps
bash

cp .env.example .env && nano .env
find . -name "*.sh" -exec chmod +x {} \;

# Test a script safely before scheduling it
./proxmox/scripts/node-health.sh --dry-run

Readme
Document · MD 
Lib
SH 
.env
EXAMPLE 
Node health
SH 
Pve update
SH 
Appdata backup
SH 
Container update
SH 
Disk temp alert
SH 
Ssl expiry check
SH 

show file structure
Mar 22
Orchestrated visual file tree representation

V
Connecting to visualize...

Click any node to ask about it. The color coding is:

    Purple — repo root
    Teal — Proxmox-specific scripts
    Coral — Unraid-specific scripts
    Amber — shared scripts that run on both nodes (lib.sh, disk-temp-alert.sh, ssl-expiry-check.sh)

The key design decision is that shared/lib.sh is the foundation — all 6 scripts source it, so email notifications, logging, and dry-run mode are defined once and inherited everywhere.

walk through how to set this up, file structure is done now what
Mar 22
Architected interactive step-by-step setup guide with commands

V
Connecting to visualize...

Walk through each step in order and check things off as you go. A few things worth calling out:

Step 3 (email) is the most likely to trip you up. On Proxmox, msmtp is the cleanest option — configure it with an app password from your email provider (Fastmail, Gmail, etc.), not your main account password. On Unraid, the built-in notification system under Settings > Notifications can handle email without any extra packages if you'd rather not touch the terminal.

Step 4's dry-run is important. If a script fails dry-run, it almost always means a missing command (smartctl, qm, docker, etc.) or a path in .env that doesn't exist yet. Fix those before scheduling — you don't want cron silently failing at 3am.

Unraid User Scripts (Community Apps) is worth installing over editing crontab raw — it gives you a GUI, per-script enable/disable toggles, and a run log right in the Unraid UI. Makes it much easier to manage without SSH.

Once you're through all 6 steps and getting emails, the setup is done. After that you can start extending — let me know if you want to add anything like a parity-check-notify.sh or a git-config-backup.sh that auto-commits your config files.

root@pve:~# git clone https://github.com/you/homelab.git /opt/homelab
cd /opt/homelab
-bash: git: command not found
-bash: cd: /opt/homelab: No such file or directory
root@pve:~#
Mar 22
Diagnosed missing Git installation on Proxmox node

Git isn't installed on Proxmox by default. Quick fix:
bash

apt update && apt install -y git

Then retry the clone:
bash

git clone https://github.com/you/homelab.git /opt/homelab
cd /opt/homelab

If you haven't pushed the repo to GitHub yet and the files are just local on your machine, use scp instead:
bash

# Run this from your local machine, not the Proxmox node
scp -r ./homelab root@<proxmox-ip>:/opt/homelab

Or if you want to set up the repo directly on the node without GitHub at all:
bash

apt update && apt install -y git
mkdir -p /opt/homelab
cd /opt/homelab
git init

Then copy the files over and do your first commit there. What's your situation — do you have the files on a local machine, or do you want to push to GitHub first?

can i just update the repo on the nodes later?
Mar 22
Recognized straightforward query requiring concise response

Yes, once the remote is set up it's just:
bash

cd /opt/homelab
git pull

Run that on each node whenever you push changes. If you want to make it even easier, you can add a quick alias to your .bashrc:
bash

echo "alias hl-update='cd /opt/homelab && git pull'" >> ~/.bashrc
source ~/.bashrc

Then just type hl-update from anywhere.

You could also automate it entirely by adding a cron job that pulls nightly — though be careful with that approach since a bad push would auto-deploy to both nodes. Manual pulls are safer until the repo is stable.

erations.
fatal: Authentication failed for 'https://github.com/you/homelab.git/'
root@pve:~# git clone https://github.com/you/homelab.git /opt/homelab
Cloning into '/opt/homelab'...
Username for 'https://github.com': aidanjp8
Password for 'https://aidanjp8@github.com': 
remote: Invalid username or token. Password authentication is not supported for Git operations.
fatal: Authentication failed for 'https://github.com/you/homelab.git/'
root@pve:~#
Mar 22
Diagnosed authentication method incompatibility with GitHub requirements

GitHub disabled password auth in 2021. You have two options:

Option 1 — SSH key (recommended, easiest long term)
bash

# Generate a key on the Proxmox node
ssh-keygen -t ed25519 -C "proxmox" -f ~/.ssh/id_ed25519 -N ""

# Print the public key
cat ~/.ssh/id_ed25519.pub

Copy that output, then go to github.com → Settings → SSH and GPG keys → New SSH key, paste it in and save.

Then clone using SSH instead of HTTPS:
bash

git clone git@github.com:aidanjp8/homelab.git /opt/homelab

Option 2 — Personal Access Token (quicker one-off)

Go to github.com → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token, tick the repo scope, generate it and copy it.

Then use it as your password:
bash

git clone https://github.com/aidanjp8/homelab.git /opt/homelab
# Username: aidanjp8
# Password: <paste the token here>

SSH is the better choice for a homelab node since you won't need to re-enter credentials. Also notice your clone URL still says you/homelab — make sure it's aidanjp8/homelab.

ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAIn/pqholuovoNJdLGO5KPGDkOnXT414Q6fpnhMYLOh proxmox
Mar 22
Identified SSH key and next GitHub integration step

Perfect, now add that to GitHub:

    Go to github.com → Settings → SSH and GPG keys → New SSH key
    Give it a name like proxmox
    Paste the whole line and hit Add SSH key

Then come back here and run:
bash

# Test the connection first
ssh -T git@github.com

You should see Hi aidanjp8! You've successfully authenticated... — then clone:
bash

git clone git@github.com:aidanjp8/homelab.git /opt/homelab

oot@pve:~# cat ~/.ssh/id_ed25519.pub
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAIn/pqholuovoNJdLGO5KPGDkOnXT414Q6fpnhMYLOh proxmox
root@pve:~# git clone git@github.com:aidanjp8/homelab.git /opt/homelab
Cloning into '/opt/homelab'...
The authenticity of host 'github.com (140.82.112.4)' can't be established.
ED25519 key fingerprint is SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU.
This key is not known by any other names.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added 'github.com' (ED25519) to the list of known hosts.
ERROR: Repository not found.
fatal: Could not read from remote repository.
Please make sure you have the correct access rights
and the repository exists.
root@pve:~#
Mar 22
Diagnosed repository accessibility issue and pinpointed root cause

The SSH auth is working (it got past the fingerprint stage) — the repo just doesn't exist on GitHub yet. You need to create it first:

    Go to github.com → New repository (the + in the top right)
    Name it homelab, set it to Private, don't initialize it with a README
    Hit Create repository

Then back on the node:
bash

git clone git@github.com:aidanjp8/homelab.git /opt/homelab

If the files are currently sitting on your local machine rather than already in a git repo, do this on your local machine instead:
bash

cd /path/to/homelab
git init
git add .
git commit -m "init"
git remote add origin git@github.com:aidanjp8/homelab.git
git push -u origin main

Then clone on the Proxmox node as above. Have you pushed anything to GitHub yet or are the files still local?

i have a preexisiting public github for this
Mar 22
Identified existing repository and determined URL requirement

Just use your actual repo URL then. What's the repo name — is it already called homelab or something else? Once you tell me I can give you the exact clone command, e.g.:
bash

git clone git@github.com:aidanjp8/your-repo-name.git /opt/homelab

git@github.com:aidanjp8/Home-Lab.git
Mar 22
Thought for 0s
bash

git clone git@github.com:aidanjp8/Home-Lab.git /opt/homelab

both now have the repo
Mar 22
Recognized readiness to advance configuration setup

Nice, back to the setup guide then. Next step is configuring .env on each node:
bash

cd /opt/homelab
cp .env.example .env
nano .env

Do that on both Proxmox and Unraid. The minimum fields to fill in first are EMAIL_TO, EMAIL_FROM, PVE_STORAGE (on Proxmox), and UNRAID_APPDATA (on Unraid). Run this to check what storage IDs Proxmox sees:
bash

pvesm status

show the env
Mar 22
View .env.example

Here's what to change on each node:

On Proxmox — the only fields that matter right now:
bash

EMAIL_FROM="homelab@yourdomain.com"   # whatever you want as the sender
EMAIL_TO="you@yourdomain.com"         # where you want alerts sent
PVE_NODE="pve"                        # your proxmox hostname (probably already 'pve')
PVE_STORAGE="local-zfs"              # confirm with: pvesm status
DISK_DEVICES="/dev/sda /dev/sdb"     # confirm with: lsblk
SSL_DOMAINS="pve.yourdomain.com"     # whatever domains you want checked

On Unraid — swap out the Proxmox fields for:
bash

EMAIL_FROM="homelab@yourdomain.com"
EMAIL_TO="you@yourdomain.com"
UNRAID_APPDATA="/mnt/user/appdata"        # default unless you changed it
UNRAID_BACKUP_DEST="/mnt/user/backups/appdata"
DOCKER_COMPOSE_DIR="/mnt/user/appdata"
DISK_DEVICES="/dev/sdb /dev/sdc /dev/sdd /dev/sde"  # your array drives

Everything else can stay as the default for now — you can tune thresholds later once the scripts are running. What email setup are you using, do you have an SMTP relay or are you going to use Gmail/Fastmail?

url for pve https://192.168.0.238:8006/ root@pve:/opt/homelab# pvesm status
Name             Type     Status           Total            Used       Available        %
local             dir     active        98497780        12545316        80902916   12.74%
local-lvm     lvmthin     active       366133248        37052684       329080563   10.12%
root@pve:/opt/homelab# lsblk
NAME                         MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sda                            8:0    0 931.5G  0 disk 
└─sda1                         8:1    0 931.5G  0 part /mnt/external1
sdb                            8:16   0   3.6T  0 disk 
└─sdb1                         8:17   0   3.6T  0 part /mnt/external2
nvme0n1                      259:0    0 476.9G  0 disk 
├─nvme0n1p1                  259:1    0  1007K  0 part 
├─nvme0n1p2                  259:2    0     1G  0 part /boot/efi
└─nvme0n1p3                  259:3    0 475.9G  0 part 
  ├─pve-swap                 252:0    0   7.6G  0 lvm  [SWAP]
  ├─pve-root                 252:1    0    96G  0 lvm  /
  ├─pve-data_tmeta           252:2    0   3.6G  0 lvm  
  │ └─pve-data-tpool         252:4    0 349.2G  0 lvm  
  │   ├─pve-data             252:5    0 349.2G  1 lvm  
  │   ├─pve-vm--101--disk--0 252:7    0    18G  0 lvm  
  │   ├─pve-vm--105--disk--0 252:8    0    10G  0 lvm  
  │   ├─pve-vm--104--disk--0 252:10   0    93G  0 lvm  
  │   └─pve-vm--106--disk--0 252:11   0     8G  0 lvm  
  └─pve-data_tdata           252:3    0 349.2G  0 lvm  
    └─pve-data-tpool         252:4    0 349.2G  0 lvm  
      ├─pve-data             252:5    0 349.2G  1 lvm  
      ├─pve-vm--101--disk--0 252:7    0    18G  0 lvm  
      ├─pve-vm--105--disk--0 252:8    0    10G  0 lvm  
      ├─pve-vm--104--disk--0 252:10   0    93G  0 lvm  
      └─pve-vm--106--disk--0 252:11   0     8G  0 lvm  
root@pve:/opt/homelab#
Mar 22
Analyzed storage configuration and disk topology comprehensively

Here's exactly what your .env should look like on Proxmox:
bash

EMAIL_FROM="homelab@gmail.com"
EMAIL_TO="your@email.com"
EMAIL_SUBJECT_PREFIX="[Homelab]"

# Proxmox
PVE_NODE="pve"
PVE_BACKUP_DIR="/var/lib/vz/dump"
PVE_SNAPSHOT_NAME="pre-update"
PVE_STORAGE="local-lvm"          # this is where your VM disks live

# Disk Monitoring
DISK_TEMP_THRESHOLD=45
DISK_DEVICES="/dev/sda /dev/sdb /dev/nvme0n1"   # both externals + the NVMe

# SSL — you're IP-based so leave this blank for now
SSL_DOMAINS=""

# Logging
LOG_DIR="/var/log/homelab"

A few things worth noting from your output:

    No ZFS — you're on LVM, so the ZFS section in node-health.sh will just skip itself, that's fine
    local-lvm is the right storage for snapshots, not local (that's just a directory for ISOs/backups)
    sda and sdb are your external drives, nvme0n1 is your boot/OS drive — monitoring all three makes sense
    SSL check — since you're accessing Proxmox via IP (192.168.0.238) rather than a domain, there's nothing to check there unless you set up a local DNS name later

Go ahead and run:
bash

nano /opt/homelab/.env

Paste that in with your actual email addresses, save it, then we can move on to installing mailutils and testing the email.

root@UnRaidNode:~# lsblk
NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
loop0    7:0    0 651.8M  1 loop /usr
loop1    7:1    0 173.4M  1 loop /lib
loop2    7:2    0    80G  0 loop /var/lib/docker
sda      8:0    1  28.9G  0 disk 
└─sda1   8:1    1  28.9G  0 part /boot
sdb      8:16   0 223.6G  0 disk 
├─sdb1   8:17   0   529M  0 part 
├─sdb2   8:18   0   100M  0 part 
├─sdb3   8:19   0    16M  0 part 
└─sdb4   8:20   0 222.9G  0 part 
md1p1    9:1    0 222.9G  0 md   /mnt/disk1
zram0  252:0    0     0B  0 disk 
root@UnRaidNode:~#
Mar 22
Identified single array disk and configured monitoring parameters

Here's your Unraid .env:
bash

EMAIL_FROM="homelab@gmail.com"
EMAIL_TO="your@email.com"
EMAIL_SUBJECT_PREFIX="[Homelab]"

# Unraid
UNRAID_APPDATA="/mnt/user/appdata"
UNRAID_BACKUP_DEST="/mnt/user/backups/appdata"
UNRAID_BACKUP_KEEP=7

# Docker
DOCKER_COMPOSE_DIR="/mnt/user/appdata"
CONTAINER_UPDATE_PRUNE=true

# Disk Monitoring
DISK_TEMP_THRESHOLD=45
DISK_DEVICES="/dev/sdb"          # your one array disk

# SSL
SSL_DOMAINS=""

# Logging
LOG_DIR="/var/log/homelab"

A few things from your output:

    sda is your USB boot drive — skip monitoring it, not useful
    sdb is your single array disk mounted at /mnt/disk1 — that's the one to watch
    Only one data disk — no parity drive visible, so appdata-backup.sh is especially important since there's no redundancy on that array
    Docker is running (loop2 is the Docker image) — container-update.sh will work fine

Same email addresses as your Proxmox .env. Once both are saved we can move on to setting up msmtp for email on both nodes — what email provider are you using?

proton mail
Mar 22
Weighed Proton Mail SMTP limitations and alternative relay solutions

Proton Mail doesn't support standard SMTP directly — their Bridge app that enables it only runs on desktop, not headless servers.

Easiest solution is to use a free Gmail account just for sending while keeping your Proton as the receiving address. Your .env would be:
bash

EMAIL_FROM="homelabnode@gmail.com"    # a gmail you create just for this
EMAIL_TO="you@proton.me"              # your real inbox

Setup on both nodes:
bash

apt install -y mailutils msmtp msmtp-mta

Then create /etc/msmtprc:
bash

nano /etc/msmtprc
```
```
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           smtp.gmail.com
port           587
from           homelabnode@gmail.com
user           homelabnode@gmail.com
password       YOUR_APP_PASSWORD

bash

chmod 600 /etc/msmtprc

For the app password — Gmail won't let you use your normal password:

    Go to myaccount.google.com → Security → 2-Step Verification (must be enabled)
    Then myaccount.google.com/apppasswords
    Create one called homelab, copy the 16-character password
    Paste it into msmtprc as the password

Then test it:
bash

echo "test from proxmox" | mail -s "homelab test" you@proton.me

Do you have a spare Gmail you can use for this, or do you need to create one?

root@UnRaidNode:/opt/homelab# nano .env
root@UnRaidNode:/opt/homelab# apt install -y mailutils msmtp msmtp-mta
bash: apt: command not found
root@UnRaidNode:/opt/homelab# cd
root@UnRaidNode:~# install -y mailutils msmtp msmtp-mta
install: invalid option -- 'y'
Try 'install --help' for more information.
root@UnRaidNode:~#
Mar 22
Identified Unraid's non-standard package manager requirement

Unraid isn't Debian-based so apt doesn't exist. It uses Slackware under the hood. Easiest way to get msmtp is through the Unraid GUI:

    Go to Community Apps (the Apps tab in Unraid UI at 192.168.0.x)
    Search for Nerd Tools
    Install it, then open it from Settings → Nerd Tools
    Find msmtp in the list and enable it

Then configure it the same way:
bash

nano /etc/msmtprc
```
```
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           smtp.gmail.com
port           587
from           homelabnode@gmail.com
user           homelabnode@gmail.com
password       YOUR_APP_PASSWORD

bash

chmod 600 /etc/msmtprc

One thing to know about Unraid — packages don't survive a reboot since the OS runs in RAM. Nerd Tools reinstalls them automatically on boot, but your /etc/msmtprc config will also be wiped. To persist it, save the config somewhere on the array and symlink it, or add it to your go file:
bash

# Add to /boot/config/go so it runs on every boot
echo "cp /boot/config/msmtprc /etc/msmtprc" >> /boot/config/go
cp /etc/msmtprc /boot/config/msmtprc

Do you have Community Apps installed on Unraid?

my email sender is homelaberrors@gmail and the recive is pwetta@proton.me give the msmtprc
Mar 22

defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           smtp.gmail.com
port           587
from           homelaberrors@gmail.com
user           homelaberrors@gmail.com
password       YOUR_APP_PASSWORD

Replace YOUR_APP_PASSWORD with the 16-character app password from Google. Paste this into /etc/msmtprc on both nodes, then:
bash

chmod 600 /etc/msmtprc

And update both .env files:
bash

EMAIL_FROM="homelaberrors@gmail.com"
EMAIL_TO="pwetta@proton.me"

Once you have the app password from Google let me know and we can test it.

done on proxmox skip unraid for now
Mar 22
Pivoted testing strategy toward Proxmox platform

Test it on Proxmox:
bash

echo "test from proxmox" | mail -s "homelab test" pwetta@proton.me

Check your Proton inbox — if it arrives we're good to move on to making the scripts executable. If it lands in spam just mark it as not spam once and it should be fine after that.

root@pve:/opt/homelab# echo "test from proxmox" | mail -s "homelab test" pwetta@proton.me
sendmail: authentication failed (method PLAIN)
sendmail: server message: 535-5.7.8 Username and Password not accepted. For more information, go to
sendmail: server message: 535 5.7.8  https://support.google.com/mail/?p=BadCredentials 5614622812f47-467e7d4b19csm5741472b6e.5 - gsmtp
sendmail: could not send mail (account default from /etc/msmtprc)
sendmail: cannot log to /var/log/msmtp.log: cannot open: Permission denied
sendmail: log info was: host=smtp.gmail.com tls=on auth=on user=homelaberrors@gmail.com from=homelaberrors@gmail.com recipients=pwetta@proton.me smtpstatus=535 smtpmsg='535-5.7.8 Username and Password not accepted. For more information, go to\n535 5.7.8  https://support.google.com/mail/?p=BadCredentials 5614622812f47-467e7d4b19csm5741472b6e.5 - gsmtp' errormsg='authentication failed (method PLAIN)' exitcode=EX_NOPERM
Can't send mail: sendmail process failed with error code 77
root@pve:/opt/homelab#
Mar 22

Two issues — wrong app password, and a log file permission error. Fix both:
bash

# Fix the log permission first
touch /var/log/msmtp.log
chmod 666 /var/log/msmtp.log

For the password, the app password needs to be generated correctly — make sure you've done exactly this:

    Go to myaccount.google.com/security
    Make sure 2-Step Verification is ON (app passwords won't appear without it)
    Go to myaccount.google.com/apppasswords
    Name it homelab → click Create
    Copy the 16-character code it shows (no spaces)

Then update /etc/msmtprc:
bash

nano /etc/msmtprc
```

Replace the password line with the exact 16 characters, no spaces:
```
password       abcdabcdabcdabcd

Then retry:
bash

echo "test from proxmox" | mail -s "homelab test" pwetta@proton.me

The BadCredentials error almost always means either 2FA isn't enabled on the Gmail account, the app password wasn't generated properly, or there are spaces in the password. Which step are you on with the Google account?

root@pve:~# echo "test from proxmox" | mail -s "homelab test" pwetta@proton.me
sendmail: cannot log to /var/log/msmtp.log: cannot open: Permission denied
sendmail: log info was: host=smtp.gmail.com tls=on auth=on user=homelaberrors@gmail.com from=homelaberrors@gmail.com recipients=pwetta@proton.me mailsize=279 smtpstatus=250 smtpmsg='250 2.0.0 OK  1774369284 46e09a7af769-7d7eadcb11csm12777980a34.13 - gsmtp' exitcode=EX_OK
root@pve:~#
10:21 AM
Thought for 1s

Email sent successfully (smtpstatus=250). Just fix the log permission and you're done:
bash

touch /var/log/msmtp.log
chmod 666 /var/log/msmtp.log

Check your Proton inbox — once you confirm it arrived we can move on to making the scripts executable and doing a dry run.

it worked
10:23 AM
Thought for 1s

On to the next step — make everything executable and create the log directory:
bash

cd /opt/homelab
find . -name "*.sh" -exec chmod +x {} \;
mkdir -p /var/log/homelab

Then do a dry run of the first script:
bash

./proxmox/scripts/node-health.sh --dry-run

i dont have the .sh files
10:23 AM
Thought for 3s

Right — you cloned your existing Home-Lab repo which doesn't have the scripts yet. You need to push the files we created into it. On your local machine:
bash

# Copy the scripts into your existing repo
cp -r /path/to/downloaded/homelab/* /path/to/Home-Lab/

# Then push to GitHub
cd /path/to/Home-Lab
git add .
git commit -m "add homelab automation scripts"
git push

Then on Proxmox:
bash

cd /opt/homelab
git pull

The files we created are in the download above — shared/lib.sh, proxmox/scripts/node-health.sh, proxmox/scripts/pve-update.sh, unraid/scripts/appdata-backup.sh, unraid/scripts/container-update.sh, shared/disk-temp-alert.sh, shared/ssl-expiry-check.sh, .env.example.

Where are the downloaded files sitting on your local machine right now?

can you give me all the files again
10:25 AM
Assembled and prepared files for redelivery

All 9 files are there. Download them and place them into your Home-Lab repo maintaining the folder structure:

Home-Lab/
├── .env.example
├── README.md
├── shared/
│   ├── lib.sh
│   ├── disk-temp-alert.sh
│   └── ssl-expiry-check.sh
├── proxmox/
│   └── scripts/
│       ├── node-health.sh
│       └── pve-update.sh
└── unraid/
    └── scripts/
        ├── appdata-backup.sh
        └── container-update.sh

Then push and pull on both nodes:
bash

# Local machine
cd /path/to/Home-Lab
git add .
git commit -m "add homelab automation scripts"
git push

# On Proxmox
cd /opt/homelab && git pull

Lib
SH 
.env
EXAMPLE 
Node health
SH 
Pve update
SH 
Appdata backup
SH 
Container update
SH 
Disk temp alert
SH 
Ssl expiry check
SH 
Readme
Document · MD 


Claude is AI and can make mistakes. Please double-check responses.
Node health · SH
#!/usr/bin/env bash
# ============================================================
# node-health.sh — Proxmox node health report
# Reports: CPU temp, RAM, ZFS pool status, disk usage, load
# Usage: ./node-health.sh [--dry-run]
# Schedule: crontab — 0 * * * * (hourly) or as needed
# ============================================================
set -euo pipefail
source "$(dirname "$0")/../../shared/lib.sh"
init_script "node-health" "$@"
 
# --- Config ---
CPU_TEMP_WARN="${CPU_TEMP_WARN:-75}"    # °C — warn threshold
CPU_TEMP_CRIT="${CPU_TEMP_CRIT:-90}"   # °C — critical threshold
DISK_USAGE_WARN="${DISK_USAGE_WARN:-85}" # % full — warn threshold
 
require_cmds pvesh df free uptime
 
# ============================================================
# CPU Temperature
# ============================================================
check_cpu_temp() {
    log_section "CPU Temperature"
 
    if command -v sensors &>/dev/null; then
        local temp_raw
        temp_raw=$(sensors 2>/dev/null | awk '/^Core|^Package/{print $0}' | head -20)
        log "$temp_raw"
 
        # Extract highest reported temp
        local max_temp
        max_temp=$(sensors 2>/dev/null \
            | grep -oP '(?<=\+)\d+\.\d+(?=°C)' \
            | sort -n | tail -1 | cut -d. -f1)
 
        if (( max_temp >= CPU_TEMP_CRIT )); then
            warn "CPU temp CRITICAL: ${max_temp}°C (threshold: ${CPU_TEMP_CRIT}°C)"
        elif (( max_temp >= CPU_TEMP_WARN )); then
            warn "CPU temp elevated: ${max_temp}°C (threshold: ${CPU_TEMP_WARN}°C)"
        else
            log "CPU temp OK: ${max_temp}°C"
        fi
    else
        # Fallback: read from thermal zone
        local zone temp_mc temp_c
        for zone in /sys/class/thermal/thermal_zone*/temp; do
            temp_mc=$(cat "$zone")
            temp_c=$(( temp_mc / 1000 ))
            log "Thermal zone $(basename "$(dirname "$zone")"): ${temp_c}°C"
        done
        log "Tip: install lm-sensors for detailed CPU core temps"
    fi
}
 
# ============================================================
# Memory
# ============================================================
check_memory() {
    log_section "Memory"
    local mem_total mem_used mem_free mem_pct
    read -r mem_total mem_used mem_free < <(free -m | awk '/^Mem:/{print $2, $3, $4}')
    mem_pct=$(( (mem_used * 100) / mem_total ))
    log "RAM: ${mem_used}MB used / ${mem_total}MB total (${mem_pct}%)"
 
    local swap_total swap_used
    read -r swap_total swap_used < <(free -m | awk '/^Swap:/{print $2, $3}')
    if (( swap_total > 0 )); then
        local swap_pct=$(( (swap_used * 100) / swap_total ))
        log "Swap: ${swap_used}MB used / ${swap_total}MB total (${swap_pct}%)"
        (( swap_pct > 20 )) && warn "Swap usage is ${swap_pct}% — system may be under memory pressure"
    else
        log "Swap: not configured"
    fi
}
 
# ============================================================
# CPU Load
# ============================================================
check_load() {
    log_section "System Load"
    local cpu_count load1 load5 load15
    cpu_count=$(nproc)
    read -r load1 load5 load15 _ < /proc/loadavg
    log "Load average: ${load1} ${load5} ${load15} (${cpu_count} CPUs)"
 
    local load_int
    load_int=$(echo "$load1" | cut -d. -f1)
    if (( load_int > cpu_count * 2 )); then
        warn "Load average is very high: ${load1} on ${cpu_count} CPUs"
    fi
 
    local uptime_str
    uptime_str=$(uptime -p)
    log "Uptime: $uptime_str"
}
 
# ============================================================
# ZFS Pool Status
# ============================================================
check_zfs() {
    log_section "ZFS Pools"
    if ! command -v zpool &>/dev/null; then
        log "ZFS not present — skipping"
        return
    fi
 
    local pool_count
    pool_count=$(zpool list -H 2>/dev/null | wc -l)
 
    if (( pool_count == 0 )); then
        log "No ZFS pools found"
        return
    fi
 
    while IFS=$'\t' read -r name size alloc free cap health; do
        log "Pool: ${name} | ${health} | ${alloc}/${size} used (${cap})"
        if [[ "$health" != "ONLINE" ]]; then
            warn "ZFS pool '${name}' is ${health}!"
        fi
    done < <(zpool list -H -o name,size,alloc,free,cap,health 2>/dev/null)
 
    # Check for recent errors
    local errors
    errors=$(zpool status 2>/dev/null | grep -c "errors:" | grep -v "No known data errors" || true)
    (( errors > 0 )) && warn "ZFS errors detected — run 'zpool status' for details"
 
    # Scrub status
    local last_scrub
    last_scrub=$(zpool status 2>/dev/null | awk '/scan:/{print $0}' | head -1)
    [[ -n "$last_scrub" ]] && log "Scrub: $last_scrub"
}
 
# ============================================================
# Disk Usage
# ============================================================
check_disk_usage() {
    log_section "Disk Usage"
    while read -r fs size used avail pct mp; do
        local pct_num="${pct//%/}"
        log "  ${mp}: ${used}/${size} (${pct})"
        if (( pct_num >= DISK_USAGE_WARN )); then
            warn "Disk usage on ${mp} is ${pct} — above ${DISK_USAGE_WARN}% threshold"
        fi
    done < <(df -h --output=source,size,used,avail,pcent,target \
        -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | tail -n +2)
}
 
# ============================================================
# Proxmox VM/CT Summary
# ============================================================
check_pve_vms() {
    log_section "VMs & Containers"
    if ! command -v qm &>/dev/null; then
        log "Not a Proxmox node — skipping VM check"
        return
    fi
 
    local running stopped
    running=$(qm list 2>/dev/null | grep -c " running" || echo 0)
    stopped=$(qm list 2>/dev/null | grep -c " stopped" || echo 0)
    log "VMs — Running: ${running}, Stopped: ${stopped}"
 
    local ct_running ct_stopped
    ct_running=$(pct list 2>/dev/null | grep -c " running" || echo 0)
    ct_stopped=$(pct list 2>/dev/null | grep -c " stopped" || echo 0)
    log "Containers — Running: ${ct_running}, Stopped: ${ct_stopped}"
}
 
# ============================================================
# Main
# ============================================================
main() {
    check_cpu_temp
    check_memory
    check_load
    check_zfs
    check_disk_usage
    check_pve_vms
    log ""
    log "Health check complete."
}
 
main "$@"
 

