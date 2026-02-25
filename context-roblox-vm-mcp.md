# Roblox + VM Setup Context

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
