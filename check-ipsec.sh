#!/bin/sh

# =============================================================
# Sophos XGS IPsec Tunnel Watchdog
# Author: Diyar Abbas
# Repo: https://github.com/diyarit/sophos-xgs-ipsec-watchdog
# Version: 5.1
#
# Features:
#   - Dynamically detects tunnel names from config files in
#     /tmp/ipsec/connections/ — works even when ALL tunnels
#     are down, no hardcoding required
#   - Interval in SECONDS for fast recovery
#   - ipsec down before reload/up to clear stale duplicate SAs
#   - timeout 30 wrapper on all ipsec commands to prevent
#     blocking when run from background shell with no TTY
#   - Debug logging to /tmp/ipsec_debug/ on every failure
#   - Busybox compatible — no xargs, uses sed instead
#
# Usage:
#   check-ipsec.sh                        List all tunnels and status
#   check-ipsec.sh auto                   Check all tunnels once
#   check-ipsec.sh auto 30               Check all tunnels every 30 seconds
#   check-ipsec.sh MyTunnel 30           Check specific tunnel every 30 seconds
# =============================================================

CONNECTIONS_DIR="/tmp/ipsec/connections"

get_tunnels() {
   ls "$CONNECTIONS_DIR"/*.conf 2>/dev/null | sed 's|.*/||; s|\.conf$||'
}

if [ -z "$1" ]; then
   echo "Welcome to ipsec watchdog by Diyar https://github.com/diyarit/sophos-xgs-ipsec-watchdog"
   echo "usage: $0 [NameofTunnel | auto] [IntervalInSeconds]"
   echo ""
   echo "information: if you use the 2nd parameter, an endless loop will be started."
   echo ""
   echo "configured tunnels on the system:"
   for tunnel in $(get_tunnels); do
       if ipsec status | grep "$tunnel" | grep -q 'INSTALLED'; then
         echo "  [OK] $tunnel"
      else
         echo "  [DOWN] $tunnel"
      fi
   done
   exit 0
fi

INTERVAL_SEC=$2

while :
do
   NOW=$(date '+%F_%H:%M:%S')

   if [ "$1" = "auto" ]; then
      targets=$(get_tunnels)
   else
      targets="$1"
   fi

   for current_tunnel in $targets; do
      [ -z "$current_tunnel" ] && continue

      if ipsec status | grep "$current_tunnel" | grep -q 'INSTALLED'; then
         echo "$current_tunnel ok $NOW"
      else
         echo "$current_tunnel is down $NOW"
         echo "$current_tunnel is down $NOW" >> /tmp/ipsec-status.log

         # Collect debug information
         mkdir -p /tmp/ipsec_debug/cfg && cp /log/charon.log /tmp/ipsec_debug/
         ipsec statusall > /tmp/ipsec_debug/statusall.log
         [ -d /tmp/ipsec/connections ] && cp /tmp/ipsec/connections/* /tmp/ipsec_debug/cfg/

         psql corporate nobody -x -c "select * from tblvpnconnection" > /tmp/ipsec_debug/tblvpnconnection.db
         psql corporate nobody -x -c "select * from tblvpnpolicy" > /tmp/ipsec_debug/tblvpnpolicy.db

         # Recovery — down first to clear stale SAs, then reload and up
         timeout 30 ipsec down "$current_tunnel"
         sleep 5
         timeout 30 ipsec reload
         sleep 5
         timeout 30 ipsec up "$current_tunnel"
         echo "$current_tunnel restart initiated $NOW"
      fi
   done

   if [ -z "$2" ]; then
      break
   else
      echo "waiting $INTERVAL_SEC seconds for next check ..."
      sleep "$INTERVAL_SEC"
   fi
done
