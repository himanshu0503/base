#!/bin/bash -e

###########################################################
validate_machines() {
  __process_msg "validating version"
  if [ "$INSTALL_MODE" == "production" ]; then
    if [ ! -f "$USR_DIR/machines.json" ]; then
      echo "Cannot find machines.json, exiting..."
      exit 1
    else
      __process_msg "Found machines.json"
    fi
  fi
}

validate_state() {
  __process_msg "validating state.json"
  # parse from jq
  local release_version=$(cat $STATE_FILE \
    | jq -r '.release')
  if [ -z "$release_version" ]; then
    __process_msg "Invalid statefile, no release version specified"
    __process_msg "Please fix the statefile or delete it and try again"
    exit 1
  fi
  # check if version exists
  # check if installer array exists
  # check if systemconfig object exists
  # check if masterIntegration exist
  # check if providers exit
  # check if systemIntegrations exist
  # check if systemImages exist
  # check if systemMachineImages exist
  # check if services exist
  __process_msg "state.json valid, proceeding with installation"
}

main() {
  __process_marker "Configuring installer"
  validate_machines
  validate_state
}

main
