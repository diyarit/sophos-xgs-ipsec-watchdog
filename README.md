# sophos-xgs-ipsec-watchdog

Monitors IPsec tunnels on Sophos XGS firewalls and automatically restarts them with debug logging when they go down.

## Overview

`check-ipsec.sh` is a shell script designed for Sophos XGS firewalls. It monitors one or all configured IPsec tunnels, and when a tunnel is found to be down, it collects diagnostic information and attempts an automatic recovery.

### Features

- List all configured IPsec tunnels and their current status
- Monitor a specific tunnel or all tunnels automatically
- Auto-restart tunnels that are not in `INSTALLED` state
- Collect debug information on failure (logs, DB snapshots, config files)
- Configurable check interval for continuous monitoring

## Usage

```bash
check-ipsec.sh [TunnelName | auto] [IntervalInMinutes]
```

| Argument | Description |
|---|---|
| `TunnelName` | Name of a specific tunnel to monitor |
| `auto` | Automatically detect and monitor all configured tunnels |
| `IntervalInMinutes` | Optional. If provided, the script runs in a continuous loop at this interval |

### Examples

```bash
# List all tunnels and their status
check-ipsec.sh

# Monitor a specific tunnel once
check-ipsec.sh MyTunnel

# Monitor all tunnels every 5 minutes
check-ipsec.sh auto 5
```

## Installation

Connect via SSH and navigate to **Menu 5 > Option 3**, then run:

```bash
mount -o remount,rw /
curl https://raw.githubusercontent.com/diyarit/sophos-xgs-ipsec-watchdog/refs/heads/main/check-ipsec.sh > /bin/check-ipsec.sh
chmod +x /bin/check-ipsec.sh
mount -o remount,ro /
```

## Autorun on Startup

To have the script start automatically on boot via the Sophos XGS startup hook:

1. Remount the filesystem as writable:

```bash
mount -no remount,rw /
```

2. Add `check-ipsec.sh` to the startup hook:

```bash
cat > /scripts/system/clientpref/customization_application_startup.sh << 'EOF'
#!/bin/sh
/bin/check-ipsec.sh auto 1 &
exit 0;
EOF
```

3. Verify the file looks correct:

```bash
cat /scripts/system/clientpref/customization_application_startup.sh
```

4. Remount the filesystem as read-only:

```bash
mount -no remount,ro /
```

5. Start the script immediately without rebooting:

```bash
/bin/check-ipsec.sh auto 1 &
```

6. Confirm it is running:

```bash
ps | grep check-ipsec
```

## Firmware Updates

> **Note:** Sophos XGS firmware updates may wipe custom scripts and startup hooks from the filesystem. After any firmware update, follow these steps to restore the watchdog:

1. Remount the filesystem as writable:

```bash
mount -no remount,rw /
```

2. Re-download and reinstall the script:

```bash
curl https://raw.githubusercontent.com/diyarit/sophos-xgs-ipsec-watchdog/refs/heads/main/check-ipsec.sh > /bin/check-ipsec.sh
chmod +x /bin/check-ipsec.sh
```

3. Recreate the startup hook:

```bash
cat > /scripts/system/clientpref/customization_application_startup.sh << 'EOF'
#!/bin/sh
/bin/check-ipsec.sh auto 30 &
exit 0;
EOF
```

4. Remount the filesystem as read-only:

```bash
mount -no remount,ro /
```

5. Start the script immediately without rebooting:

```bash
/bin/check-ipsec.sh auto 1 &
```

## Uninstall

To completely remove the watchdog and restore the firewall to its original state:

1. Kill the running watchdog process:

```bash
kill -9 $(ps | grep check-ipsec | grep -v grep | awk '{print $1}') 2>/dev/null
```

2. Remount the filesystem as writable:

```bash
mount -no remount,rw /
```

3. Delete the script:

```bash
rm -f /bin/check-ipsec.sh
```

4. Restore the startup hook to its original state:

```bash
cat > /scripts/system/clientpref/customization_application_startup.sh << 'EOF'
#!/bin/sh
exit 0;
EOF
```

5. Remount the filesystem as read-only:

```bash
mount -no remount,ro /
```

## Debug Output

When a tunnel goes down, the script writes diagnostic data to `/tmp/ipsec_debug/`:

| File | Contents |
|---|---|
| `charon.log` | IPsec daemon log |
| `statusall.log` | Full `ipsec statusall` output |
| `cfg/` | Tunnel connection config files |
| `tblvpnconnection.db` | VPN connection table dump |
| `tblvpnpolicy.db` | VPN policy table dump |
