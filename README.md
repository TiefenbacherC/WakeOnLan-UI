# WakeOnLan-UI

Eine kleine Weboberfläche (ASP.NET Core) für den Raspberry Pi: pro Gerät ein „Aufwecken“-Knopf,
der Pi schickt das Magic Packet ins Heimnetz. Mit eingetragener IP zeigt die Seite auch, ob das
Gerät online ist.

Wozu: Über VPN klappt Wake-on-LAN direkt meist nicht, weil das Magic Packet ein Broadcast ist und
Broadcasts nicht durch den VPN-Tunnel gehen. Über VPN auf diese Seite – und der Pi im selben Netz
weckt den PC auf.

## Einrichtung am Pi

Per SSH am Pi anmelden und ausführen:

```bash
curl -fsSL https://raw.githubusercontent.com/TiefenbacherC/WakeOnLan-UI/main/pi-setup.sh | bash
```

Das Skript [`pi-setup.sh`](pi-setup.sh) installiert Docker und git (falls nötig), klont das Repo
nach `~/WakeOnLan-UI`, legt den Befehl `wol` an, baut das Image und startet die Seite.

Danach die Geräte eintragen:

```bash
wol edit
```

```json
[
  { "name": "Mein PC", "mac": "AA:BB:CC:DD:EE:FF", "ip": "192.168.1.50", "broadcast": "192.168.1.255" }
]
```

- `ip` (optional): zeigt online/offline per Ping an
- `broadcast` (optional): Broadcast-Adresse des Netzes; ohne Angabe `255.255.255.255`

Die Liste wird bei jedem Seitenaufruf neu gelesen, ein Neustart ist nicht nötig.

Die Seite ist dann unter `http://<IP-vom-Pi>:8090` erreichbar. Sie hat kein Passwort – also nur
im Heimnetz bzw. über VPN erreichbar machen, nicht per Portweiterleitung ins Internet.

## Befehle

```bash
wol start     # starten
wol stop      # stoppen
wol status    # läuft sie? welche Version?
wol restart
wol logs
wol edit      # Geräteliste bearbeiten
wol port 80   # Port dauerhaft ändern (ohne Zahl: aktuellen Port anzeigen)
wol update    # neuesten Stand von GitHub holen, neu bauen, neu starten
```

Der Container läuft mit `--network host`, sonst käme der Broadcast nicht im Heimnetz an.

## Lokal starten

```bash
WOL_CONFIG=devices.example.json dotnet run
```
