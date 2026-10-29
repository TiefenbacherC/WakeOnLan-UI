#!/usr/bin/env bash
# Steuerung der Wake-on-LAN-Weboberfläche auf dem Pi.
#   ./wol.sh start    – starten (baut das Image, falls nötig)
#   ./wol.sh stop     – stoppen
#   ./wol.sh restart  – neu starten
#   ./wol.sh status   – läuft sie? welche Version?
#   ./wol.sh logs     – Logs anzeigen
#   ./wol.sh port 80  – Port dauerhaft ändern (ohne Zahl: aktuellen Port anzeigen)
#   ./wol.sh edit     – Geräteliste bearbeiten
#   ./wol.sh update   – neuesten Stand von GitHub holen, neu bauen und starten
#   ./wol.sh dns      – DNS im WireGuard-VPN einrichten, damit http://wol/ funktioniert
#                       (optional: ./wol.sh dns <name> <wireguard-interface>)
set -euo pipefail

NAME="wakeonlan-ui"
IMAGE="wakeonlan-ui:latest"
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# Geräteliste und Port liegen nicht in git, bleiben also bei Updates erhalten
DEVICES="$DIR/devices.json"
PORT_FILE="$DIR/.port"
PORT="${PORT:-$(cat "$PORT_FILE" 2>/dev/null || echo 8090)}"

g() {
  git -c safe.directory="$DIR" -C "$DIR" "$@"
}

version() {
  g describe --tags --always 2>/dev/null || echo dev
}

build() {
  docker build -q --build-arg VERSION="$(version)" -t "$IMAGE" "$DIR" >/dev/null
  docker image prune -f >/dev/null
}

run() {
  [ -f "$DEVICES" ] || cp "$DIR/devices.example.json" "$DEVICES"
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  # Host-Netz: nur so erreicht der Broadcast das Heimnetz
  docker run -d --name "$NAME" --restart unless-stopped --network host \
    -e PORT="$PORT" -v "$DEVICES:/config/devices.json:ro" "$IMAGE" >/dev/null
  echo "Läuft auf http://$(hostname -I 2>/dev/null | awk '{print $1}'):$PORT ($(version))"
}

# dnsmasq auf dem WireGuard-Interface: <name> zeigt auf die VPN-IP des Pi,
# alle anderen Anfragen gehen weiter an den Router
dns() {
  local name="$1" iface="$2" vpn_ip router
  vpn_ip="$(ip -4 -o addr show "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
  if [ -z "$vpn_ip" ]; then
    echo "Interface $iface hat keine IPv4-Adresse – läuft WireGuard? (Name prüfen mit: ip -br addr)" >&2
    exit 1
  fi
  router="$(ip route | awk '/^default/ {print $3; exit}')"

  command -v dnsmasq >/dev/null || { sudo apt-get update -q && sudo apt-get install -y -q dnsmasq; }
  sudo tee /etc/dnsmasq.d/wakeonlan-ui.conf >/dev/null <<EOF
# angelegt von wol.sh dns
interface=$iface
bind-dynamic
no-resolv
server=$router
address=/$name/$vpn_ip
EOF
  sudo systemctl enable -q dnsmasq
  sudo systemctl restart dnsmasq

  echo "DNS läuft: $name → $vpn_ip (andere Anfragen → $router)"
  echo "Jetzt im WireGuard-Client unter DNS eintragen: $vpn_ip"
  [ "$PORT" = 80 ] || echo "Tipp: 'wol port 80', dann reicht http://$name/ ohne :$PORT"
}

running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" = "true" ]
}

main() {
  case "${1:-}" in
    start)
      docker image inspect "$IMAGE" >/dev/null 2>&1 || build
      run
      ;;
    stop)
      docker rm -f "$NAME" >/dev/null 2>&1 && echo "Gestoppt." || echo "Lief nicht."
      ;;
    restart)
      main stop
      main start
      ;;
    update)
      g pull -q --ff-only
      build
      run
      ;;
    status)
      if running; then
        echo "Läuft (Port $PORT), Version $(version)."
      else
        echo "Gestoppt (Version $(version))."
      fi
      ;;
    logs)
      docker logs -f "$NAME"
      ;;
    edit)
      [ -f "$DEVICES" ] || cp "$DIR/devices.example.json" "$DEVICES"
      "${EDITOR:-nano}" "$DEVICES"
      echo "Gespeichert – die Seite liest die Liste bei jedem Aufruf neu."
      ;;
    port)
      local new="${2:-}"
      if [ -z "$new" ]; then
        echo "Port: $PORT"
        exit 0
      fi
      if ! [[ "$new" =~ ^[0-9]+$ ]] || [ "$new" -lt 1 ] || [ "$new" -gt 65535 ]; then
        echo "Ungültiger Port: $new (erlaubt: 1–65535)" >&2
        exit 1
      fi
      echo "$new" > "$PORT_FILE"
      PORT="$new"
      echo "Port auf $PORT gesetzt."
      if running; then
        run
      fi
      ;;
    dns)
      dns "${2:-wol}" "${3:-wg0}"
      ;;
    *)
      echo "Verwendung: $0 {start|stop|restart|status|logs|edit|port [nummer]|update|dns [name] [interface]}"
      exit 1
      ;;
  esac
}

# Direkt nach der Einrichtung kennt die laufende Sitzung die docker-Gruppe noch nicht
if ! docker info >/dev/null 2>&1 && id -nG "$(id -un)" | grep -qw docker && [ -z "${WOL_SG:-}" ]; then
  exec env WOL_SG=1 sg docker -c "$(printf "%q " "$DIR/wol.sh" "$@")"
fi

# erst die ganze Datei einlesen, dann ausführen – so stört ein git-Update dieses Skripts nicht
main "$@"
exit
