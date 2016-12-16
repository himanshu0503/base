#!/bin/bash -e

ntp_install() {
  ntp_status_res=$(service ntp status)
  if [ -z "$ntp_status_res" ]; then
    echo "Installing and Starting NTP"
    apt-get install -y ntp
    service ntp restart
  elif [ -z "$ntp_status_res" | grep "not running" ]; then
    echo "Starting NTP"
    service ntp start
  fi
}

main() {
  ntp_install
}

main
