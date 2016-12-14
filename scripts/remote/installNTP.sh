#!/bin/bash -e

ntp_install() {
  echo "Installing and Starting NTP"

  sudo apt-get install -y ntp
  sudo /etc/init.d/ntp restart
}

main() {
  ntp_install
}

main
