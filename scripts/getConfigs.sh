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

initialize_state() {
  __process_msg "Initializing state file"
  __process_msg "Install mode: $INSTALL_MODE"
  if [ ! -f "$USR_DIR/state.json" ]; then
    if [ -f "$USR_DIR/state.json.backup" ]; then
      __process_msg "A state.json.backup file exists, do you want to use the backup? (yes/no)"
      read response
      if [[ "$response" == "yes" ]]; then
        cp -vr $USR_DIR/state.json.backup $USR_DIR/state.json
        rm $USR_DIR/state.json.backup || true
      else
        __process_msg "Dicarding backup, creating a new state.json from state.json.example"
        rm $USR_DIR/state.json.backup || true
        cp -vr $USR_DIR/state.json.example $USR_DIR/state.json
        local update=$(cat $STATE_FILE \
          | jq '.installMode="'$INSTALL_MODE'"')
        update=$(echo $update | jq '.' | tee $STATE_FILE)
      fi
    else
      __process_msg "No state.json exists, creating a new state.json from state.json.example."
      cp -vr $USR_DIR/state.json.example $STATE_FILE
      rm $USR_DIR/state.json.backup || true
      local update=$(cat $STATE_FILE \
        | jq '.installMode="'$INSTALL_MODE'"')
      update=$(echo $update | jq '.' | tee $STATE_FILE)
    fi
  else
			# if a state file exists, use it
    __process_msg "using existing state.json"
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
  initialize_state
  validate_state
}

main
