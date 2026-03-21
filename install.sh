#!/bin/bash
set -e

sudo apt update
sudo apt install -y python3 python3-pip jq smartmontools util-linux isc-dhcp-client net-tools curl

python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt

sudo mkdir -p /opt/disktoolitl
sudo cp -r . /opt/disktoolitl/
sudo chmod +x /opt/disktoolitl/*.sh

sudo mkdir -p /var/log/disktoolitl
sudo mkdir -p /tmp/wipe_db

sudo cp disktoolitl.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable disktoolitl

printf '\nInstallation abgeschlossen!\nStarte mit:\n  sudo systemctl start disktoolitl\nOder zum Testen:\n  sudo bash /opt/disktoolitl/disktoolitl.sh\n'