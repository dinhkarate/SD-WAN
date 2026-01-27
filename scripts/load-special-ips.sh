#!/bin/bash
# Load Special IPs from file into ipset
# Supports: plain text (1 IP per line), JSON array, JSON object with ips/routes key

set -e

source /etc/sdwan/config.env

IP_LIST_FILE="${SPECIAL_IP_LIST:-/etc/sdwan/special-ips.json}"
IPSET_NAME="special_ips"

echo "[$(date)] Loading special IPs from $IP_LIST_FILE..."

# Check if file exists
if [ ! -f "$IP_LIST_FILE" ]; then
    echo "[$(date)] ERROR: IP list file not found: $IP_LIST_FILE"
    exit 1
fi

# Create temporary ipset
ipset create ${IPSET_NAME}_tmp hash:net -exist

# Detect file format and parse
FIRST_CHAR=$(head -c1 "$IP_LIST_FILE")

if [[ "$FIRST_CHAR" == "[" || "$FIRST_CHAR" == "{" ]]; then
    # JSON format
    echo "[$(date)] Detected JSON format"
    jq -r '
      if type == "array" then .[]
      elif type == "object" and has("ips") then .ips[]
      elif type == "object" and has("routes") then .routes[]
      else empty
      end
    ' "$IP_LIST_FILE" 2>/dev/null | while read -r ip; do
        [[ -z "$ip" || "$ip" =~ ^# ]] && continue
        [[ "$ip" != *"/"* ]] && ip="${ip}/32"
        ipset add ${IPSET_NAME}_tmp "$ip" -exist 2>/dev/null || true
    done
else
    # Plain text format (1 IP per line)
    echo "[$(date)] Detected plain text format"
    while read -r ip || [[ -n "$ip" ]]; do
        # Skip empty lines and comments
        [[ -z "$ip" || "$ip" =~ ^# ]] && continue
        # Remove whitespace
        ip=$(echo "$ip" | tr -d '[:space:]')
        [[ -z "$ip" ]] && continue
        # Add /32 if no CIDR notation
        [[ "$ip" != *"/"* ]] && ip="${ip}/32"
        ipset add ${IPSET_NAME}_tmp "$ip" -exist 2>/dev/null || true
    done < "$IP_LIST_FILE"
fi

# Atomic swap
ipset swap ${IPSET_NAME}_tmp $IPSET_NAME 2>/dev/null || ipset rename ${IPSET_NAME}_tmp $IPSET_NAME
ipset destroy ${IPSET_NAME}_tmp 2>/dev/null || true

# Count entries
COUNT=$(ipset list $IPSET_NAME | grep -c "^[0-9]" || echo "0")
echo "[$(date)] Loaded $COUNT special IP entries."
