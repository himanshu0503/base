#!/bin/bash -e

install_ntp() {
  apt-get install -y ntp
}

start_ntp() {
  service ntp restart
}

main() {
  {
    check_ntp=$(service --status-all 2>&1 | grep ntp)
  } || {
    true
  }
  if [ ! -z "$check_ntp" ]; then
    echo "NTP already installed, skipping."
    return
  fi

  pushd /tmp
  install_ntp
  start_ntp
  popd
}

main
