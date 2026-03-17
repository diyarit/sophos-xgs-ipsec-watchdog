# sophos-xgs-ipsec-watchdog

Monitors IPsec tunnels on Sophos XGS firewalls and automatically restarts them with debug logging when they go down.

> **Tested on:** Sophos XGS136 — SFOS 21.5.1 MR-1-Build261

---

## Overview

`check-ipsec.sh` is a shell script designed for Sophos XGS firewalls running SFOS. It monitors one or all configured IPsec tunnels and when a tunnel is found to be down, it collects diagnostic information and attempts an automatic recovery.

### Features

- Dynamically detects tunnel names from `/tmp/ipsec/connections/` config files — **works even when ALL tunnels are completely down**, no hardcoding required
- Monitors a specific tunnel or all tunnels automatically
- Auto-restarts tunnels that are not in `INSTALLED` state using `ipsec reload` + `ipsec up`
- Runs `ipsec down` first to clear stale duplicate Child SAs before attempting recovery
- `timeout 30` wrapper on all `ipsec` commands to prevent blocking when run from a background shell with no TTY
- Collects debug information on failure (logs, DB snapshots, config files)
- Configurable check interval in **seconds** for fast recovery
- Busybox compatible — no `xargs` dependency
- Survives PuTTY session close — runs fully in background
- Auto-starts on reboot via startup hook

---

## Usage

```sh
check-ipsec.sh [TunnelName | auto] [IntervalInSeconds]
```

| Argument | Description |
| --- | --- |
| `TunnelName` | Name of a specific tunnel to monitor |
| `auto` | Automatically detect and monitor all configured tunnels |
| `IntervalInSeconds` | Optional. If provided, the script runs in a continuous loop at this interval |

### Examples

```sh
# List all tunnels and their current status
check-ipsec.sh

# Monitor a specific tunnel once
check-ipsec.sh MyTunnel

# Monitor all tunnels once
check-ipsec.sh auto

# Monitor all tunnels every 30 seconds (recommended)
check-ipsec.sh auto 30 &

# Monitor a specific tunnel every 60 seconds
check-ipsec.sh MyTunnel 60 &
```

---

## Installation

Connect via SSH and navigate to **Menu 5 > Option 3** (Advanced Shell), then run:

```sh
mount -no remount,rw /
curl https://raw.githubusercontent.com/diyarit/sophos-xgs-ipsec-watchdog/refs/heads/main/check-ipsec.sh > /bin/check-ipsec.sh
chmod +x /bin/check-ipsec.sh
mount -no remount,ro /
```

> **Note:** On SFOS 21.5.x you may see `mount: mounting none on / failed: Device or resource busy` — this is normal. Write operations still succeed, ignore the error.

---

## Autorun on Startup

To have the script start automatically on every reboot:

**1. Remount the filesystem as writable:**
```sh
mount -no remount,rw /
```

**2. Add `check-ipsec.sh` to the startup hook:**
```sh
cat > /scripts/system/clientpref/customization_application_startup.sh << 'EOF'
#!/bin/sh
/bin/check-ipsec.sh auto 30 &
exit 0;
EOF
```

> ⚠️ The `exit 0;` line **must** come after the watchdog launch line. If it appears first, the watchdog will never start on reboot.

**3. Verify the file looks correct:**
```sh
cat /scripts/system/clientpref/customization_application_startup.sh
```

Expected output:
```
#!/bin/sh
/bin/check-ipsec.sh auto 30 &
exit 0;
```

**4. Remount the filesystem as read-only:**
```sh
mount -no remount,ro /
```

**5. Start the script immediately without rebooting:**
```sh
/bin/check-ipsec.sh auto 30 &
```

**6. Confirm it is running:**
```sh
ps | grep check-ipsec
```

Expected output (PID will differ):
```
ash   12345  ...  ash /bin/check-ipsec.sh
grep  12346  ...  grep check-ipsec
```

---

## Day-to-Day Commands

```sh
# Check if watchdog is running
ps | grep check-ipsec

# Check tunnel status
ipsec status

# View tunnel failure log
cat /tmp/ipsec-status.log

# Stop the watchdog
kill -9 $(ps | grep check-ipsec | grep -v grep | awk '{print $1}') 2>/dev/null

# Restart the watchdog
kill -9 $(ps | grep check-ipsec | grep -v grep | awk '{print $1}') 2>/dev/null
/bin/check-ipsec.sh auto 30 &

# Manually bounce both tunnels
ipsec down MyTunnel
sleep 5
ipsec up MyTunnel

# View debug logs from last failure
ls /tmp/ipsec_debug/
cat /tmp/ipsec_debug/statusall.log
```

---

## After a Firmware Upgrade

> ⚠️ Sophos XGS firmware upgrades may wipe custom scripts and startup hooks. After any firmware upgrade, run the following to restore the watchdog:

```sh
mount -no remount,rw /
curl https://raw.githubusercontent.com/diyarit/sophos-xgs-ipsec-watchdog/refs/heads/main/check-ipsec.sh > /bin/check-ipsec.sh
chmod +x /bin/check-ipsec.sh
cat > /scripts/system/clientpref/customization_application_startup.sh << 'EOF'
#!/bin/sh
/bin/check-ipsec.sh auto 30 &
exit 0;
EOF
mount -no remount,ro /
/bin/check-ipsec.sh auto 30 &
ps | grep check-ipsec
```

---

## Uninstall

To completely remove the watchdog and restore the firewall to its original state:

```sh
# Kill the running watchdog
kill -9 $(ps | grep check-ipsec | grep -v grep | awk '{print $1}') 2>/dev/null

# Remount writable
mount -no remount,rw /

# Delete the script
rm -f /bin/check-ipsec.sh

# Restore startup hook to original
cat > /scripts/system/clientpref/customization_application_startup.sh << 'EOF'
#!/bin/sh
exit 0;
EOF

# Lock filesystem
mount -no remount,ro /
```

---

## Debug Output

When a tunnel goes down, the script writes diagnostic data to `/tmp/ipsec_debug/`:

| File | Contents |
| --- | --- |
| `charon.log` | IPsec daemon log |
| `statusall.log` | Full `ipsec statusall` output |
| `cfg/` | Tunnel connection config files |
| `tblvpnconnection.db` | VPN connection table dump |
| `tblvpnpolicy.db` | VPN policy table dump |

Failure events are also logged to `/tmp/ipsec-status.log` with timestamps.

---

## How It Works

```
Every 30 seconds:
    ↓
Read tunnel names from /tmp/ipsec/connections/*.conf
    ↓
For each tunnel:
    ipsec status | grep INSTALLED?
        ↓ YES → log "ok", continue
        ↓ NO  → log "is down"
                collect debug info
                timeout 30 ipsec down  ← clear stale SAs
                sleep 5
                timeout 30 ipsec reload
                sleep 5
                timeout 30 ipsec up    ← re-establish tunnel
```

---

## Compatibility

| Item | Detail |
| --- | --- |
| Tested firmware | SFOS 21.5.1 MR-1-Build261 |
| Tested hardware | Sophos XGS136 |
| Shell | `/bin/sh` (busybox ash) |
| Dependencies | None — no `xargs`, no `cron`, no external tools |

---

## Changelog

| Version | Changes |
| --- | --- |
| 1.0 | Initial release |
| 2.0 | Interval changed from minutes to seconds. `timeout 30` added to `ipsec reload` and `ipsec up` to prevent blocking in background shell |
| 3.0 | Tunnel names hardcoded to fix empty target list when all tunnels are down |
| 4.0 | Added `ipsec down` before `reload/up` to clear stale duplicate Child SAs |
| 5.0 | Dynamic tunnel detection from `/tmp/ipsec/connections/*.conf` — no hardcoding required |
| 5.1 | Replaced `xargs` with `sed` for busybox compatibility |
