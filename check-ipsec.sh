#!/bin/sh

# =============================================================
# Sophos XGS IPsec Tunnel Watchdog
# Author: Diyar Abbas (fixes applied)
# Repo: https://github.com/diyarit/sophos-xgs-ipsec-watchdog
# Fixes:
#   - Interval now in SECONDS instead of minutes for faster recovery
#   - Tunnel name parsing fixed to preserve full name including suffix
#   - timeout 30 wrapper added to ipsec reload and ipsec up
#     to prevent blocking when run from background shell
# =============================================================

if [ -z "$1" ]; then
   echo "Welcome to ipsec watchdog by Diyar https://github.com/diyarit/sophos-xgs-ipsec-watchdog"
   echo "usage: $0 [NameofTunnel | auto] [IntervalInSeconds]"
   echo ""
   echo "information: if you use the 2nd parameter, an endless loop will be started."
   echo ""
   echo "configured tunnels on the system:"
   ipsec status > /tmp/ipsec-status.txt
   tunnel_array=$(awk 'NR>1 {print $1}' /tmp/ipsec-status.txt | tr -d '!"$%&/()=?.*[]:{}' | sort -u)
   for tunnel in $tunnel_array; do
       if ipsec status | grep -q "$tunnel.*INSTALLED"; then
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
      ipsec status > /tmp/ipsec-status.txt
      targets=$(awk 'NR>1 {print $1}' /tmp/ipsec-status.txt | tr -d '!"$%&/()=?.*[]:{}' | sort -u)
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

         # Recovery with timeout protection to prevent blocking
         timeout 30 ipsec reload
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
