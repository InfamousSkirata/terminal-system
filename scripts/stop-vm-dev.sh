#!/usr/bin/env bash
set -euo pipefail

pkill -f "robloxstudio-mcp" >/dev/null 2>&1 || true
pkill -f "rojo serve" >/dev/null 2>&1 || true

echo "Stopped robloxstudio-mcp and rojo (if running)."
