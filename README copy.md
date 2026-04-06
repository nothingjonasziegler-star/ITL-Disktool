**DSGVO-Hinweis:**
Dieses Tool speichert und überträgt ausschließlich technische Statusdaten (Device, Typ, Status, Fortschritt, Größe, SMART-Status). Es werden keine personenbezogenen Daten oder Seriennummern verarbeitet oder angezeigt. Die Weboberfläche zeigt nur anonyme Statusinformationen aller erkannten Datenträger.
# DiskToolITL 1.0

Automatisiertes System zum sicheren Löschen von Festplatten (HDD/SSD) mit Hot-Swap-Erkennung, SMART-Diagnostik und Web-Oberfläche.

---

## 🧠 Übersicht

DiskToolITL ist eine minimalistische, Debian-basierte Lösung zur automatischen Erkennung, Analyse und sicheren Löschung von Datenträgern.

Das System ist für den Einsatz in:

* IT-Recycling
* Forensik / Datenschutz
* Rechenzentren
* Werkstätten / Labore

entwickelt und ermöglicht die parallele Verarbeitung mehrerer Datenträger ohne manuelles Eingreifen.

---

## 🐧 Systemvoraussetzungen

* Debian 11 (Bullseye) oder Debian 12 (Bookworm)
* Root-Zugriff
* Python 3.9 oder neuer
* Internetzugang für die Paketinstallation (einmalig)

---

## 📦 Installation auf Debian

### 1. Systempakete installieren

```bash
sudo apt update
sudo apt install -y \
    smartmontools \
    util-linux \
    python3 \
    python3-pip \
    udev \
    isc-dhcp-client \
    net-tools \
    curl
```

### 2. Python-Abhängigkeiten installieren

```bash
pip3 install flask requests
```

### 3. Tool einrichten

```bash
# Repository klonen oder Dateien kopieren
sudo mkdir -p /opt/DiskToolITL
sudo cp -r ./* /opt/DiskToolITL/
sudo chmod +x /opt/DiskToolITL/DiskToolITL.py
```

### 4. Verzeichnisse erstellen

```bash
sudo mkdir -p /tmp/wipe_db
sudo mkdir -p /var/log/DiskToolITL
```

---

## 🔁 Autostart via systemd

### Service-Datei anlegen

```bash
sudo nano /etc/systemd/system/DiskToolITL.service
```

Inhalt:

```ini
[Unit]
Description=DiskToolITL - Automatisches Disk-Wipe-System
After=network.target udev.service
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/DiskToolITL/DiskToolITL.py
WorkingDirectory=/opt/DiskToolITL
Restart=always
RestartSec=5
User=root
StandardOutput=append:/var/log/DiskToolITL/DiskToolITL.log
StandardError=append:/var/log/DiskToolITL/DiskToolITL.log

[Install]
WantedBy=multi-user.target
```

### Service aktivieren und starten

```bash
sudo systemctl daemon-reload
sudo systemctl enable DiskToolITL
sudo systemctl start DiskToolITL
```

### Status prüfen

```bash
sudo systemctl status DiskToolITL
```

### Logs anzeigen

```bash
sudo journalctl -u DiskToolITL -f
# oder direkt:
sudo tail -f /var/log/DiskToolITL/DiskToolITL.log
```

---

## 🌐 Web-GUI aufrufen

Nach dem Start ist die Oberfläche im lokalen Netzwerk erreichbar:

```
http://<IP-des-Systems>:8080
```

Die aktuelle IP-Adresse wird beim Systemstart auf der Konsole angezeigt.

---

## ⚙️ Konfiguration

Die Server-URL für den SMART-Daten-Upload kann direkt in der Web-GUI unter **Einstellungen** gesetzt werden oder manuell in:

```
/tmp/wipe_db/config.json
```

Beispiel:

```json
{
  "server_url": "http://192.168.1.100:5000/api/smart"
}
```

---

---

## ⚙️ Kernfunktionen

### 🔌 Hotswap Disk Detection

* Automatische Erkennung neu angeschlossener HDDs und SSDs im laufenden Betrieb
* Polling-Intervall: 5 Sekunden
* Unterstützt SATA, USB und NVMe
* Boot-Disk wird automatisch erkannt und ausgeschlossen
* Mehrere Datenträger werden parallel verarbeitet

---

### 🧪 SMART-Diagnostik

* Automatisches Auslesen der SMART-Daten vor dem Löschvorgang
* Gesundheitsstatus (PASSED / FAILED) wird erkannt
* Speicherung aller SMART-Daten im JSON-Format lokal
* Unterscheidung zwischen HDD und SSD

---

### 🔥 Sicheres Löschen (Zero-Fill)

* Vollständiges Überschreiben des Datenträgers mit Nullen
* Fortschrittsanzeige in Prozent
* Parallelverarbeitung mehrerer Disks
* Automatische Verifikation nach dem Wipe
* Fehlerstatus bei fehlgeschlagener Prüfung

---

### ☁️ SMART-Upload

* SMART-Daten können automatisch an einen Server gesendet werden
* JSON-Format mit:

  * Gerät
  * Modell
  * Seriennummer
  * Größe
  * Zeitstempel
  * vollständige SMART-Daten
* Konfigurierbar über Web-Oberfläche
* Fallback auf lokale Speicherung bei Fehlern

---

### 🌐 Web-GUI (Port 8080)

* Zugriff über Browser im Netzwerk
* Live-Übersicht aller Datenträger
* Einstellungen können dort getätigt werden

**Anzeige beinhaltet:**

* Device (z. B. /dev/sdb)
* Typ (HDD / SSD)
* Modell & Seriennummer
* Größe
* Status:

  * SMART
  * WIPING
  * DONE
  * ERROR
* Fortschritt in Prozent

**Weitere Features:**

* Live-Log (letzte 80 Einträge)
* Anzeige aktiver und abgeschlossener Prozesse
* Konfiguration der Server-URL
* Automatische Aktualisierung
* Dark Mode Oberfläche

---

### 🌐 Netzwerk (Auto-Konfiguration)

* Automatische Initialisierung aller Netzwerkinterfaces
* DHCP auf allen Ports
* Fallback-IP: 192.168.1.200
* Anzeige der aktuellen IP beim Systemstart
* Zugriff auf Web-GUI über:
  http://<IP-Adresse>:8080

---

### 🖥️ Branding & System

* Hostname: DiskToolITL
* Eigene OS-Version: DiskToolITL 1.0
* Anzeige von Systeminformationen beim Boot:

  * IP-Adresse
  * Web-GUI URL
* Optional: Anzeige eines Logos beim Start

---

## 📁 Datenstruktur

Alle Status- und Metadaten werden lokal gespeichert:

* `/tmp/wipe_db/`

  * Disk-Status (JSON pro Gerät)
  * SMART-Daten
  * Upload-Fehler
  * Server-Konfiguration

* `/var/log/`

  * Zentrales Logfile für alle Aktionen

---

## 🔄 Workflow

1. Neue Festplatte wird eingesteckt
2. System erkennt das Gerät automatisch
3. Boot-Disk wird ausgeschlossen
4. SMART-Daten werden ausgelesen
5. Optional: Upload an Server
6. Start des Löschvorgangs
7. Fortschritt wird kontinuierlich aktualisiert
8. Verifikation nach Abschluss
9. Status wird gesetzt:

   * DONE (erfolgreich)
   * ERROR (Fehler erkannt)

---

## ⚠️ Sicherheitshinweise

* Alle erkannten Datenträger werden automatisch gelöscht
* Es erfolgt keine Benutzerabfrage
* Falsche Konfiguration kann zu Datenverlust führen
* System sollte ausschließlich in kontrollierten Umgebungen eingesetzt werden

---

## 🚀 Einsatzszenarien

* Massenerasure von Datenträgern
* Hardware-Recycling
* Datenschutzkonforme Löschung
* Testumgebungen für Storage-Systeme
* Automatisierte Werkstattlösungen

---

## 🔧 Erweiterungsmöglichkeiten

* Integration von LED-Statusanzeigen (z. B. über Mikrocontroller)
* Erweiterte Löschmethoden (DoD, Gutmann)
* Benutzerverwaltung
* API für externe Systeme
* Cluster-Betrieb mit zentralem Dashboard

---

## 📌 Fazit

DiskToolITL ist ein leistungsfähiges, automatisiertes System zur sicheren und parallelen Löschung von Datenträgern mit minimalem Bedienaufwand.

Es kombiniert:

* Automatisierung
* Transparenz
* Sicherheit
* Erweiterbarkeit

in einer kompakten Lösung.

---
