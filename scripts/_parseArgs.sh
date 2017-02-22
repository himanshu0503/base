#!/bin/bash -e

__validate_args() {
  __process_marker "Validating arguments"
  if [ -z "$SHIPPABLE_VERSION" ]; then
	  __process_error "SHIPPABLE_VERSION not set, exiting"
	  exit 1
	else
    __process_msg "Shippable version: $SHIPPABLE_VERSION"
	fi

  if [ -z "$IS_UPGRADE" ]; then
    __process_error "IS_UPGRADE not set, exiting"
    exit 1
  else
    __process_msg "Running an upgrade: $IS_UPGRADE"
  fi

  if [ $IS_UPGRADE == true ]; then
    # if doing an upgrade, use installMode from state file
    __process_msg "Setting installMode to one in state file"
    local state_install_mode=$(cat $STATE_FILE \
      | jq -r '.installMode')
    if [ $state_install_mode == "" ];then
      __process_msg "No 'installMode' value defined in statefile, exiting"
      exit 1
    else
      INSTALL_MODE=$state_install_mode
      local release=$(cat $STATE_FILE \
        | jq '.release="'"$SHIPPABLE_VERSION"'"')
      _update_state "$release"
      __process_msg "Install mode: $INSTALL_MODE"
    fi
  else
    # fresh install, installMode required
    if [ -z "$INSTALL_MODE" ]; then
      __process_error "INSTALL_MODE not set, exiting"
      exit 1
    else
      __process_msg "Install mode: $INSTALL_MODE"
    fi
  fi


  local migrations_path=$MIGRATIONS_DIR/$SHIPPABLE_VERSION.sql
  if [ ! -f "$migrations_path" ]; then
    __process_error "Migrations file $migrations_path does not exist, exiting"
    exit 1
  else
    __process_msg "Migrations file: $migrations_path"
  fi

  local versions_path=$VERSIONS_DIR/$SHIPPABLE_VERSION.json
  if [ ! -f "$versions_path" ]; then
    __process_error "Versions file $versions_path does not exist, exiting"
    exit 1
  else
    __process_msg "Versions: $versions_path"
  fi

}

__parse_args() {
  if [[ $# -gt 0 ]]; then
    while [[ $# -gt 0 ]]; do
      key="$1"

      case $key in
        -v|--version)
          SHIPPABLE_VERSION="$2"
          shift
          ;;
        -l|--local)
          INSTALL_MODE="local"
          ;;
        -u|--upgrade)
          IS_UPGRADE=true
          ;;
        -s|--status)
          __show_status
          ;;
        -v|--version)
          __show_version
          ;;
        -h|--help)
          __print_help
          ;;
        *)
          echo "Invalid option: $key"
          __print_help
          ;;
      esac
      shift
    done
  else
    __print_help
  fi
}

__print_help() {
  echo "
  usage: $0 options
  This script installs Shippable enterprise
  examples:
    $0 --local                      //Install on localhost with 'master' version
    $0 --local --version v5.2.1     //Install on localhost with 'v5.2.1' version
    $0 --version v5.2.1             //Install on cluster with 'v5.2.1' version
    $0 --upgrade --version v5.2.1   //Update the installation to 'v5.2.1' version
  OPTIONS:
    -s | --status     Print status of current installation
    -l | --local      Run a localhost installation
    -v | --version    Install a particular version
    -h | --help       Print this message
  "
	exit 0
}
