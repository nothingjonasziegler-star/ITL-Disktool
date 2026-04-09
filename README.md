# DiskTool
System zum automatischen Erkennen, Prüfen und sicheren Löschen von Datenträgern mit Hot-Swap-Unterstützung.

---

## Übersicht

DiskToolITL erkennt automatisch neu angeschlossene Datenträger, liest SMART-Daten aus, löscht die Disk mit der für den Typ optimalen Methode und erstellt ein Löschzertifikat mit SHA256-Prüfsumme.

Einsatzgebiete:
- IT-Recycling
- Sichere Datenlöschung
- Rechenzentren
- Werkstätten / Labore

---

## Systemvoraussetzungen

- Debian 11+ / Ubuntu 20.04+
- Root-Zugriff
- Internetzugang für Paketinstallation (einmalig)

---

## Installation

```bash
git clone https://github.com/nothingjonasziegler-star/ITL-Disktool.git
cd ITL-Disktool
sudo bash install.sh
```

Das Installationsskript:
- Installiert alle Abhängigkeiten (nwipe, hdparm, nvme-cli, smartmontools, cifs-utils, etc.)
- Kopiert das Tool nach `/opt/disktoolitl/`
- Erstellt `.env` aus `.env.example` (falls nicht vorhanden)
- Richtet den systemd-Service ein

### Starten

```bash
# Als Service
sudo systemctl start disktoolitl

# Oder direkt zum Testen
sudo bash /opt/disktoolitl/disktoolitl.sh
```

### Status prüfen

```bash
sudo systemctl status disktoolitl
sudo journalctl -u disktoolitl -f
```

---

## Konfiguration (.env)

Die Konfiguration erfolgt über `/opt/disktoolitl/.env`:

| Variable | Beschreibung | Beispiel |
|---|---|---|
| `SHARE_IP` | IP des Windows-Servers für Zertifikate | `10.10.20.32` |
| `SHARE_NAME` | Name der Windows-Freigabe | `Zertifikate` |
| `SHARE_PATH` | Unterordner auf der Freigabe | `Loeschzertifikate` |
| `SHARE_USER` | Windows-Benutzername (leer = Gastzugriff) | |
| `SHARE_PASS` | Windows-Passwort | |
| `FALLBACK_IP` | Statische IP falls kein DHCP | `192.168.1.200` |
| `FALLBACK_PREFIX` | Subnetzmaske als Prefix | `24` |

### Netzwerk-Share einrichten (Windows-Server)

1. Ordner erstellen (z.B. `D:\Zertifikate`)
2. Rechtsklick → Freigeben → Freigabename: `Zertifikate`
3. Berechtigungen: Lese-/Schreibzugriff
4. In `.env` die IP und den Freigabenamen eintragen

Zertifikate werden nach `\\SHARE_IP\SHARE_NAME\SHARE_PATH\` kopiert.
Falls der Share nicht erreichbar ist, bleiben die Zertifikate lokal gespeichert.

---

## Unterstützte Datenträger & Löschmethoden

| Typ | Methode | Fallback |
|---|---|---|
| **HDD** | nwipe DOD 5220.22-M (3-Pass) | shred (3-Pass + Zero) |
| **SSD (SATA)** | blkdiscard + ATA Secure Erase (hdparm) | shred (3-Pass) |
| **NVMe** | NVMe Sanitize (Block Erase) | NVMe Format (Secure Erase) |
| **USB** | blkdiscard + shred (3-Pass + Zero) | shred |

Jede Löschung wird mit 20 Prüfpunkten verifiziert.

---

## Workflow

```
Festplatte anstecken
        │
        ▼
 Automatische Erkennung (udevadm / Polling)
        │
        ▼
  Boot-Disk ausschließen
        │
        ▼
  SMART-Daten auslesen (Typ, Modell, Seriennummer, Temperatur)
        │
        ▼
  Löschung starten (typ-spezifische Methode)
        │
        ▼
  Verifikation (20 Prüfpunkte)
        │
        ▼
  Löschzertifikat erstellen (SHA256)
        │
        ▼
  Zertifikat auf Netzwerk-Share kopieren (optional)
        │
        ▼
  Status: DONE ✓
```

---

## Terminal-Oberfläche (TUI)

Nach dem Start zeigt das Tool eine Live-Übersicht im Terminal:

- ITL-Logo
- IP-Adresse, Uhrzeit, Uptime
- Statusübersicht: Gesamt / Aktiv / Fertig / Fehler
- Pro Datenträger: Device, Typ, Modell, Serial, Größe, Temperatur, Fortschritt, Status
- Live-Log (letzte Einträge)

Statusanzeigen:
- `SMART` — SMART-Daten werden gelesen
- `WIPING` — Löschung läuft (mit Fortschrittsbalken)
- `VERIFY` — Verifikation läuft
- `DONE` — Erfolgreich gelöscht
- `ERROR` — Fehler aufgetreten

---

## Dateistruktur

```
/opt/disktoolitl/
├── disktoolitl.sh          # Hauptskript (Einstiegspunkt)
├── disk_monitor.sh         # Disk-Erkennung (udevadm + Polling)
├── smart_check.sh          # SMART-Diagnostik & Typ-Erkennung
├── wipe_disk.sh            # Lösch-Engine (typ-spezifisch)
├── uploader.sh             # Zertifikat auf Netzwerk-Share kopieren
├── network_init.sh         # Netzwerk-Initialisierung (DHCP + Fallback)
├── splash.sh               # Terminal-Oberfläche (TUI)
├── install.sh              # Installationsskript
├── disktoolitl.service     # systemd Unit-Datei
├── .env                    # Konfiguration (nicht in Git)
├── .env.example            # Konfigurations-Vorlage
└── logs/
    ├── disktoolitl.log     # Zentrales Logfile
    └── certificates/       # Löschzertifikate (lokal)
```

Temporäre Laufzeitdaten: `/tmp/wipe_db/` (State-JSON pro Datenträger)

---

## Löschzertifikat

Nach erfolgreicher Löschung wird ein Zertifikat erstellt mit:
- Device, Typ, Modell, Seriennummer
- Kapazität
- Löschmethode
- Start-/Endzeit, Dauer
- Verifikationsergebnis (20 Prüfpunkte)
- SHA256-Prüfsumme

Speicherort: `logs/certificates/` und optional auf dem konfigurierten Netzwerk-Share.

---

## Abhängigkeiten

| Paket | Zweck |
|---|---|
| `nwipe` | HDD-Löschung (DOD 5220.22-M) |
| `coreutils` (shred) | Fallback-Löschung / USB |
| `hdparm` | SSD ATA Secure Erase |
| `nvme-cli` | NVMe Sanitize / Format |
| `smartmontools` | SMART-Daten |
| `util-linux` (lsblk, blkdiscard) | Disk-Erkennung, SSD TRIM |
| `udev` (udevadm) | Hot-Swap Event-Erkennung |
| `jq` | JSON-Verarbeitung |
| `cifs-utils` | SMB-Share Mount |
| `dialog` | TUI-Unterstützung |
| `isc-dhcp-client` | DHCP |
| `net-tools` | Netzwerk-Tools |

---

## Sicherheitshinweise

- Alle neu angeschlossenen Datenträger werden **automatisch gelöscht** — ohne Rückfrage
- Die Boot-Disk wird automatisch erkannt und ausgeschlossen
- Das Tool darf nur in kontrollierten Umgebungen eingesetzt werden
- `.env` enthält Zugangsdaten und ist durch `chmod 600` geschützt
- Bei Disk-Entfernung während des Wipe-Vorgangs wird der Status auf ERROR gesetzt
