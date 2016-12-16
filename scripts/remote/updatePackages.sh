#!/bin/bash -e

update_packages() {
  echo "Updating packages"
  apt-get update
}

main() {
  update_packages
}

main
