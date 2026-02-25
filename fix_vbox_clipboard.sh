#!/usr/bin/env bash
set -euo pipefail

log() { echo "[fix-vbox] $*"; }
warn() { echo "[fix-vbox][WARN] $*"; }
err() { echo "[fix-vbox][ERR] $*"; }

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  err "Bitte als root ausfuehren: sudo bash $0"
  exit 1
fi

TARGET_USER="${SUDO_USER:-${USER:-}}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
  warn "SUDO_USER ist leer. User-Autostart wird uebersprungen."
fi

log "Systeminfo"
source /etc/os-release || true
echo "OS=${PRETTY_NAME:-unknown}"
echo "Kernel=$(uname -r)"

log "Virtualisierung erkennen"
if command -v systemd-detect-virt >/dev/null 2>&1; then
  VIRT=$(systemd-detect-virt || true)
  echo "virt=${VIRT}"
fi

log "Pakete pruefen/installieren"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y virtualbox-guest-utils virtualbox-guest-x11

log "Module laden"
modprobe vboxguest || true
modprobe vboxsf || true
modprobe vboxvideo || true

log "udev trigger fuer /dev/vboxguest und /dev/vboxuser"
udevadm control --reload-rules || true
udevadm trigger || true
sleep 1

if [[ ! -e /dev/vboxguest ]]; then
  warn "/dev/vboxguest fehlt weiterhin. Das ist oft ein Host/Guest-Additions-Mismatch."
  warn "Nimm im VirtualBox-Menue: Devices -> Insert Guest Additions CD Image und fuehre Installer im Gast aus."
fi

log "GDM auf Xorg umstellen (Wayland deaktivieren)"
if [[ -f /etc/gdm3/custom.conf ]]; then
  if rg -q '^#?WaylandEnable=' /etc/gdm3/custom.conf 2>/dev/null; then
    sed -i 's/^#\?WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/custom.conf
  else
    printf '\nWaylandEnable=false\n' >> /etc/gdm3/custom.conf
  fi
else
  warn "/etc/gdm3/custom.conf nicht gefunden. Ueberspringe Wayland-Konfig."
fi

log "VBoxService neu starten"
systemctl restart vboxadd-service.service 2>/dev/null || true
systemctl restart virtualbox-guest-utils.service 2>/dev/null || true
systemctl restart vboxservice.service 2>/dev/null || true

if [[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]]; then
  USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
  if [[ -n "$USER_HOME" && -d "$USER_HOME" ]]; then
    log "User-Autostart fuer VBoxClient anlegen: $TARGET_USER"
    install -d -m 755 -o "$TARGET_USER" -g "$TARGET_USER" "$USER_HOME/.config/autostart"

    cat > "$USER_HOME/.config/autostart/vbox-clipboard.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=VirtualBox Clipboard Integration
Exec=/usr/bin/VBoxClient --clipboard
X-GNOME-Autostart-enabled=true
NoDisplay=false
StartupNotify=false
Terminal=false
DESKTOP

    cat > "$USER_HOME/.config/autostart/vbox-draganddrop.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=VirtualBox Drag and Drop Integration
Exec=/usr/bin/VBoxClient --draganddrop
X-GNOME-Autostart-enabled=true
NoDisplay=false
StartupNotify=false
Terminal=false
DESKTOP

    chown "$TARGET_USER:$TARGET_USER" \
      "$USER_HOME/.config/autostart/vbox-clipboard.desktop" \
      "$USER_HOME/.config/autostart/vbox-draganddrop.desktop"
  fi
fi

log "Statusreport"
lsmod | rg -i 'vboxguest|vboxsf|vboxvideo' || true
ls -l /dev/vboxguest /dev/vboxuser 2>/dev/null || true
systemctl is-active vboxservice.service 2>/dev/null || true

log "Fertig. Bitte einmal komplett neu starten."
log "Danach im Login-Screen sicherstellen: 'Ubuntu on Xorg'."
