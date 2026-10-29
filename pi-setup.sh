#!/usr/bin/env bash
# Einmalige Einrichtung auf dem Raspberry Pi:
#   curl -fsSL https://raw.githubusercontent.com/TiefenbacherC/WakeOnLan-UI/main/pi-setup.sh | bash
#
# Installiert Docker und git (falls nötig), klont das Repo nach ~/WakeOnLan-UI,
# legt den Befehl "wol" an und startet die Weboberfläche.
set -euo pipefail

REPO="https://github.com/TiefenbacherC/WakeOnLan-UI.git"
DIR="$HOME/WakeOnLan-UI"
USER_NAME="$(id -un)"

echo "==> Pakete prüfen"
if ! command -v git >/dev/null; then
  sudo apt-get update -q
  sudo apt-get install -y -q git
fi
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
fi
sudo usermod -aG docker "$USER_NAME"

echo "==> Repo holen"
if [ -d "$DIR/.git" ]; then
  git -C "$DIR" pull -q --ff-only
else
  git clone -q "$REPO" "$DIR"
fi
chmod +x "$DIR/wol.sh"
[ -f "$DIR/devices.json" ] || cp "$DIR/devices.example.json" "$DIR/devices.json"

echo "==> Befehl 'wol' anlegen"
sudo ln -sf "$DIR/wol.sh" /usr/local/bin/wol

echo "==> Bauen und starten (beim ersten Mal dauert das ein paar Minuten)"
# sg: die frisch hinzugefügte docker-Gruppe gilt in dieser Sitzung sonst noch nicht
sg docker -c "$DIR/wol.sh update"

echo
echo "Fertig! Jetzt mit 'wol edit' die MAC-Adresse deines PCs eintragen."
echo "Befehle: wol start | stop | status | logs | edit | port | update"
