#!/bin/bash -e

ntp_install() {
  echo "Installing and Starting NTP"

  apt-get install -y ntp
  /etc/init.d/ntp restart
}

main() {
  ntp_install
}

main
