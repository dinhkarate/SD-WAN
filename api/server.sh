#!/bin/bash
# SD-WAN API Server
# Simple REST API for managing routes dynamically
# Uses netcat/socat for minimal dependencies

set -e

source /etc/sdwan/config.env

PORT="${API_PORT:-8080}"
TOKEN="${API_TOKEN:-changeme}"
IP_LIST_FILE="${SPECIAL_IP_LIST:-/etc/sdwan/special-ips.json}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Validate API token
check_auth() {
    local auth_header="$1"
    if [[ "$auth_header" != "Bearer $TOKEN" ]]; then
        return 1
    fi
    return 0
}

# Parse HTTP request
parse_request() {
    local line
    local method=""
    local path=""
    local auth=""
    local content_length=0
    local body=""
    
    # Read request line
    read -r line
    method=$(echo "$line" | cut -d' ' -f1)
    path=$(echo "$line" | cut -d' ' -f2)
    
    # Read headers
    while read -r line; do
        line=$(echo "$line" | tr -d '\r')
        [[ -z "$line" ]] && break
        
        case "$line" in
            Authorization:*) auth="${line#Authorization: }" ;;
            Content-Length:*) content_length="${line#Content-Length: }" ;;
        esac
    done
    
    # Read body if present
    if [[ $content_length -gt 0 ]]; then
        body=$(head -c "$content_length")
    fi
    
    echo "$method|$path|$auth|$body"
}

# Send HTTP response
send_response() {
    local status="$1"
    local content_type="${2:-application/json}"
    local body="$3"
    
    echo -e "HTTP/1.1 $status\r"
    echo -e "Content-Type: $content_type\r"
    echo -e "Content-Length: ${#body}\r"
    echo -e "Connection: close\r"
    echo -e "\r"
    echo -n "$body"
}

# API Handlers
handle_get_ips() {
    if [[ -f "$IP_LIST_FILE" ]]; then
        local content=$(cat "$IP_LIST_FILE")
        send_response "200 OK" "application/json" "$content"
    else
        send_response "404 Not Found" "application/json" '{"error":"IP list not found"}'
    fi
}

handle_add_ip() {
    local ip="$1"
    
    # Validate IP format
    if ! [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
        send_response "400 Bad Request" "application/json" '{"error":"Invalid IP format"}'
        return
    fi
    
    # Add to ipset immediately
    [[ "$ip" != *"/"* ]] && ip="${ip}/32"
    ipset add special_ips "$ip" -exist 2>/dev/null
    
    # Update JSON file
    local tmp_file=$(mktemp)
    if [[ -f "$IP_LIST_FILE" ]]; then
        jq --arg ip "$ip" '. + [$ip] | unique' "$IP_LIST_FILE" > "$tmp_file"
    else
        echo "[\"$ip\"]" > "$tmp_file"
    fi
    mv "$tmp_file" "$IP_LIST_FILE"
    
    log "Added IP: $ip"
    send_response "200 OK" "application/json" "{\"success\":true,\"ip\":\"$ip\"}"
}

handle_remove_ip() {
    local ip="$1"
    
    # Remove from ipset
    [[ "$ip" != *"/"* ]] && ip="${ip}/32"
    ipset del special_ips "$ip" 2>/dev/null || true
    
    # Update JSON file
    if [[ -f "$IP_LIST_FILE" ]]; then
        local tmp_file=$(mktemp)
        jq --arg ip "$ip" 'map(select(. != $ip))' "$IP_LIST_FILE" > "$tmp_file"
        mv "$tmp_file" "$IP_LIST_FILE"
    fi
    
    log "Removed IP: $ip"
    send_response "200 OK" "application/json" "{\"success\":true,\"removed\":\"$ip\"}"
}

handle_reload() {
    /etc/sdwan/scripts/load-special-ips.sh
    local count=$(ipset list special_ips 2>/dev/null | grep -c "^[0-9]" || echo "0")
    send_response "200 OK" "application/json" "{\"success\":true,\"loaded\":$count}"
}

handle_status() {
    local wg0_status=$(wg show wg0 2>/dev/null && echo "up" || echo "down")
    local wg1_status=$(wg show wg1 2>/dev/null && echo "up" || echo "down")
    local ip_count=$(ipset list special_ips 2>/dev/null | grep -c "^[0-9]" || echo "0")
    
    send_response "200 OK" "application/json" "{\"wg0\":\"$wg0_status\",\"wg1\":\"$wg1_status\",\"special_ips\":$ip_count}"
}

# Main request handler
handle_request() {
    local request=$(parse_request)
    local method=$(echo "$request" | cut -d'|' -f1)
    local path=$(echo "$request" | cut -d'|' -f2)
    local auth=$(echo "$request" | cut -d'|' -f3)
    local body=$(echo "$request" | cut -d'|' -f4-)
    
    log "$method $path"
    
    # Public endpoints
    case "$path" in
        /health)
            send_response "200 OK" "application/json" '{"status":"ok"}'
            return
            ;;
    esac
    
    # Protected endpoints - check auth
    if ! check_auth "$auth"; then
        send_response "401 Unauthorized" "application/json" '{"error":"Invalid or missing token"}'
        return
    fi
    
    case "$method|$path" in
        "GET|/api/ips")
            handle_get_ips
            ;;
        "POST|/api/ips")
            local ip=$(echo "$body" | jq -r '.ip // empty')
            handle_add_ip "$ip"
            ;;
        "DELETE|/api/ips"*)
            local ip=$(echo "$path" | sed 's|/api/ips/||')
            handle_remove_ip "$ip"
            ;;
        "POST|/api/reload")
            handle_reload
            ;;
        "GET|/api/status")
            handle_status
            ;;
        *)
            send_response "404 Not Found" "application/json" '{"error":"Not found"}'
            ;;
    esac
}

# Start server
log "Starting SD-WAN API server on port $PORT..."

# Check for socat or use netcat
if command -v socat &> /dev/null; then
    log "Using socat..."
    socat TCP-LISTEN:$PORT,reuseaddr,fork EXEC:"$0 --handle"
elif command -v nc &> /dev/null; then
    log "Using netcat..."
    while true; do
        nc -l -p $PORT -c "$0 --handle"
    done
else
    log "ERROR: Neither socat nor netcat found. Please install one."
    exit 1
fi
