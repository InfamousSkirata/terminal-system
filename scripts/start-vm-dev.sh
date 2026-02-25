#!/usr/bin/env bash
set -euo pipefail

# Starts robloxstudio-mcp (required) and optionally Rojo on the VM.
# Usage:
#   bash scripts/start-vm-dev.sh
#   bash scripts/start-vm-dev.sh --with-rojo

WITH_ROJO=0
if [[ "${1:-}" == "--with-rojo" ]]; then
  WITH_ROJO=1
fi

mkdir -p .logs

echo "[1/4] Ensuring robloxstudio-mcp build-library path exists..."
sudo mkdir -p /usr/local/lib/node_modules/robloxstudio-mcp/build-library
sudo chown -R "$USER:$USER" /usr/local/lib/node_modules/robloxstudio-mcp/build-library

echo "[2/4] Starting robloxstudio-mcp on VM..."
pkill -f "robloxstudio-mcp" >/dev/null 2>&1 || true
nohup robloxstudio-mcp > .logs/mcp.log 2>&1 &

sleep 2
if ss -ltnp | grep -q ":3000"; then
  echo "MCP is listening on :3000"
else
  echo "MCP did not start. Check .logs/mcp.log"
  exit 1
fi

if [[ "$WITH_ROJO" -eq 1 ]]; then
  echo "[3/4] Starting Rojo on VM..."
  pkill -f "rojo serve" >/dev/null 2>&1 || true
  nohup rojo serve --address 0.0.0.0 --port 34872 > .logs/rojo.log 2>&1 &
  sleep 1
  if ss -ltnp | grep -q ":34872"; then
    echo "Rojo is listening on :34872"
  else
    echo "Rojo did not start. Check .logs/rojo.log"
    exit 1
  fi
fi

VM_IP="$(hostname -I | awk '{print $1}')"
echo "[4/4] Done."
echo
echo "Studio MCP endpoint (main PC): http://127.0.0.1:3000/mcp"
echo "VM IP for Rojo plugin: ${VM_IP}:34872"
echo "Logs: .logs/mcp.log $( [[ "$WITH_ROJO" -eq 1 ]] && echo '.logs/rojo.log' )"
