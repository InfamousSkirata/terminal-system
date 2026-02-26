# Roblox + VM Setup Context

## Aktueller Stand (Feb 26, 2026)
Roblox Studio läuft auf dem Haupt-PC, Codex + robloxstudio-mcp laufen auf der VM.
Der Studio-Plugin-Endpunkt nutzt Port `58741`.

### Verbindung (täglich)
1) Auf dem Haupt-PC den SSH-Tunnel starten und offen lassen:
```bash
ssh -N -L 58741:127.0.0.1:58741 tgc@10.0.2.15
```
2) Auf der VM den MCP-Server starten:
```bash
npx -y robloxstudio-mcp@latest
```
3) Verbindungscheck auf der VM:
```bash
curl -m 2 -sS -D - http://localhost:58741/ -o /dev/null
```
Erwartung: HTTP-Header (404 am Root ist ok).

### Codex MCP Config (VM)
```toml
[mcp_servers.robloxstudio]
command = "npx"
args = ["-y", "robloxstudio-mcp@latest"]
```

## Daily Restart Checklist (Feb 26, 2026)
Goal: MCP + Rojo both reachable from Studio on main PC.

### 1) Main PC: SSH tunnel(s) to VM (keep running)
MCP tunnel:
```bash
ssh -N -L 58741:127.0.0.1:58741 tgc@10.0.2.15
```
Rojo tunnel:
```bash
ssh -N -L 34872:127.0.0.1:34872 tgc@10.0.2.15
```

### 2) VM: start MCP server
```bash
npx -y robloxstudio-mcp@latest
```
Leave this terminal open.

### 3) VM: start Rojo server
```bash
/home/tgc/.cargo/bin/rojo serve --address 0.0.0.0 --port 34872
```
Leave this terminal open.

### 4) VM: verify MCP tunnel
```bash
curl -m 2 -sS -D - http://localhost:58741/ -o /dev/null
```
Expected: HTTP headers (404 at root is OK).

### 5) Main PC: Studio plugin endpoints
MCP plugin:
```
http://127.0.0.1:58741/mcp
```
Rojo plugin:
```
127.0.0.1:34872
```

### Notes
- VM IP used: `10.0.2.15` (update if it changes).
- Codex MCP config lives in `~/.codex/config.toml`.

### Häufige Fehler (neu)
- `ERR_INTERNAL_ASSERTION` oder `ERR_MODULE_NOT_FOUND` bei `npx`:
  - Node 20 nutzen.
  - `npx`-Cache leeren:
```bash
rm -rf ~/.npm/_npx
npm cache clean --force
```
  - Dann `npx -y robloxstudio-mcp@latest` erneut starten.

## Legacy Setup (Port 3000, VirtualBox NAT)
## Ziel
Roblox Studio läuft auf dem Haupt-PC.
Rojo + MCP laufen auf der VM.

## Netzwerkmodell (aktueller Stand)
- VM läuft mit NAT + Port Forwarding.
- MCP wird vom Haupt-PC über `127.0.0.1:3000` erreicht.

## Einmalige Einrichtung

### 1) VirtualBox NAT Port Forwarding
VM ausgeschaltet konfigurieren:
- Adapter: NAT
- Port Forward Regel:
  - Name: `mcp3000`
  - Protocol: `TCP`
  - Host IP: `127.0.0.1`
  - Host Port: `3000`
  - Guest IP: `10.0.2.15` (ggf. anpassen, falls VM-IP sich ändert)
  - Guest Port: `3000`

### 2) robloxstudio-mcp installieren (VM)
```bash
sudo npm i -g robloxstudio-mcp@latest
```

### 3) Fix für `EACCES ... mkdir '/build-library'` (VM)
`robloxstudio-mcp` sucht einen `build-library` Ordner. Wenn er fehlt, versucht das Tool fälschlich `/build-library` und crasht.

```bash
sudo mkdir -p /usr/local/lib/node_modules/robloxstudio-mcp/build-library
sudo chown -R "$USER:$USER" /usr/local/lib/node_modules/robloxstudio-mcp/build-library
```

## Start nach jedem PC-Neustart

### A) VM starten
Dann auf der VM im Terminal:
```bash
robloxstudio-mcp
```
Falls command nicht gefunden wird:
```bash
/usr/local/bin/robloxstudio-mcp
```
Terminal offen lassen.

### Schnellstart (empfohlen)
Im Projektordner auf der VM:
```bash
bash scripts/start-vm-dev.sh
```
Mit Rojo zusätzlich:
```bash
bash scripts/start-vm-dev.sh --with-rojo
```
Stoppen:
```bash
bash scripts/stop-vm-dev.sh
```

### B) Roblox Studio auf Haupt-PC starten
- MCP Plugin öffnen
- Endpoint:
```text
http://127.0.0.1:3000/mcp
```

## Verbindungscheck

### Auf Haupt-PC (PowerShell)
```powershell
Test-NetConnection 127.0.0.1 -Port 3000
```
Erwartung: `TcpTestSucceeded : True`

### Auf VM prüfen, ob MCP lauscht
```bash
ss -ltnp | rg 3000
```
Erwartung: `LISTEN` auf `:3000`

## Rojo (separat)
Auf der VM starten:
```bash
rojo serve --address 0.0.0.0 --port 34872
```
In Studio (Rojo Plugin) mit VM-IP + Port verbinden, je nach aktuellem Netzwerksetup.

## Häufige Fehler + Fix

### `retrying` im Plugin
Ursachen:
- MCP Server läuft nicht
- Falsche URL im Plugin
- Port Forwarding/FW fehlt

Fix-Reihenfolge:
1. Auf VM `robloxstudio-mcp` starten
2. Auf VM `ss -ltnp | rg 3000`
3. Auf PC `Test-NetConnection 127.0.0.1 -Port 3000`
4. Plugin URL auf `http://127.0.0.1:3000/mcp`

### `Cannot find module 'unpipe'`
Korruptes `npx`-Temp-Setup. Lösung: global installieren statt `npx`-Start.

### `EACCES` bei global npm Install
Mit `sudo npm i -g ...` ausführen.

## Relevante Codex-Konfiguration
Datei:
- `~/.codex/config.toml`

Eintrag:
```toml
[mcp_servers.robloxstudio]
command = "npx"
args = ["-y", "robloxstudio-mcp@latest"]
```
Hinweis: lokal stabiler war der direkte Start mit `robloxstudio-mcp` nach globaler Installation.
