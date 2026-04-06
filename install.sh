#!/bin/bash
set -e

sudo apt update
sudo apt install -y jq smartmontools util-linux isc-dhcp-client net-tools dialog hdparm nvme-cli nwipe udev coreutils cifs-utils
sudo mkdir -p /opt/disktoolitl
sudo cp -r . /opt/disktoolitl/
sudo chmod +x /opt/disktoolitl/*.sh

if [ ! -f /opt/disktoolitl/.env ]; then
    sudo cp .env.example /opt/disktoolitl/.env
    sudo chmod 600 /opt/disktoolitl/.env
fi

sudo mkdir -p /opt/disktoolitl/logs
sudo mkdir -p /opt/disktoolitl/logs/certificates
sudo mkdir -p /tmp/wipe_db

sudo cp disktoolitl.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable disktoolitl

printf '\nInstallation abgeschlossen!\nStarte mit:\n  sudo systemctl start disktoolitl\nOder zum Testen:\n  sudo bash /opt/disktoolitl/disktoolitl.sh\n'