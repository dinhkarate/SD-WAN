#!/bin/bash
# File Watcher - Auto-reload IP list when changed
# Uses inotify for efficient file monitoring

set -e

source /etc/sdwan/config.env

IP_LIST_FILE="${SPECIAL_IP_LIST:-/etc/sdwan/special-ips.json}"
WATCH_INTERVAL="${FILE_WATCH_INTERVAL:-5}"
LAST_HASH=""

echo "[$(date)] Starting file watcher for $IP_LIST_FILE..."

# Function to compute file hash
get_hash() {
    md5sum "$1" 2>/dev/null | cut -d' ' -f1
}

# Function to reload IPs
reload_ips() {
    echo "[$(date)] Detected change in IP list, reloading..."
    /etc/sdwan/scripts/load-special-ips.sh
    LAST_HASH=$(get_hash "$IP_LIST_FILE")
}

# Check if inotifywait is available
if command -v inotifywait &> /dev/null; then
    echo "[$(date)] Using inotify for file watching..."
    
    while true; do
        inotifywait -q -e modify,move_self,close_write "$IP_LIST_FILE" 2>/dev/null
        sleep 1  # Debounce
        reload_ips
    done
else
    echo "[$(date)] inotifywait not found, using polling (interval: ${WATCH_INTERVAL}s)..."
    
    LAST_HASH=$(get_hash "$IP_LIST_FILE")
    
    while true; do
        sleep "$WATCH_INTERVAL"
        
        CURRENT_HASH=$(get_hash "$IP_LIST_FILE")
        if [ "$CURRENT_HASH" != "$LAST_HASH" ]; then
            reload_ips
        fi
    done
fi
