#!/bin/bash -e

__bootstrap_state() {
  __process_msg "injecting empty machines array"
  local machines=$(cat $STATE_FILE | \
    jq '.machines=[]')
  _update_state "$machines"

  __process_msg "injecting empty master integrations"
  local master_integrations=$(cat $STATE_FILE | \
    jq '.masterIntegrations=[]')
  _update_state "$master_integrations"

  __process_msg "injecting empty system integrations"
  local system_integrations=$(cat $STATE_FILE | \
    jq '.systemIntegrations=[]')
  _update_state "$system_integrations"

  __process_msg "injecting empty services array"
  local services=$(cat $STATE_FILE | \
    jq '.services=[]')
  _update_state "$services"
}

__validate_args() {
  __process_marker "Validating arguments"

  ################## set IS_UPGRADE #############################
  # Always set IS_UPGRADE from cmd line args

  if [ "$IS_UPGRADE" == "" ]; then
    __process_error "IS_UPGRADE not set, exiting"
    exit 1
  else
    __process_msg "Running an upgrade: $IS_UPGRADE"
  fi

  ################## set SHIPPABLE_VERSION ########################
  # for upgrade, there MUST be a previous release version
  local state_release_version=$(cat $STATE_FILE \
    | jq -r '.release')

  if [ $IS_UPGRADE == true ];then
    ## Running an upgrade, empty release version means error
    if [ "$state_release_version" == "" ]; then
      __process_error "No 'release' value defined in statefile, exiting.
      Run installer from scratch to update release version."
      exit 1
    else
      __process_msg "Release version present for an upgrade, skipping bootstrap"
    fi
  else
    ## Running a fresh install, empty release version means bootstrap statefile
    if [ "$state_release_version" == "" ]; then
      __process_msg "bootstrapping state.json for latest release"
      __bootstrap_state
    else
      __process_msg "Release version present for an install, skipping bootstrap"
    fi
  fi

  local release=$(cat $STATE_FILE \
    | jq '.release="'"$SHIPPABLE_VERSION"'"')
  _update_state "$release"

  __process_msg "Shippable release version: $SHIPPABLE_VERSION"

  ################## set  INSTALL_MODE ##########################
  local state_install_mode=$(cat $STATE_FILE \
    | jq -r '.installMode')

  if [ $IS_UPGRADE == true ]; then
    # if doing an upgrade, use installMode from state file
    __process_msg "Setting installMode from state file"
    if [ "$state_install_mode" == "" ];then
      __process_msg "No 'installMode' value defined in statefile, exiting"
      exit 1
    else
      INSTALL_MODE=$state_install_mode
      __process_msg "Install mode present for an upgrade"
      __process_msg "Install mode: $INSTALL_MODE"
    fi
  else
    if [ "$state_install_mode" == "" ];then
      __process_error "INSTALL_MODE not set, exiting"
      local install_mode=$(cat $STATE_FILE \
        | jq '.installMode="'"$INSTALL_MODE"'"')
      _update_state "$install_mode"
      __process_msg "Install mode: $INSTALL_MODE"
      exit 1
    else
      if [ "$INSTALL_MODE" != "$state_install_mode" ];then
        __process_error "INSTALL_MODE in arguments different from state file,
        either change the arguments or start with fresh state file."
        exit 1
      else
        __process_msg "Install mode: $INSTALL_MODE"
      fi
    fi
  fi


################## check migrations  #############################
  local migrations_path=$MIGRATIONS_DIR/$SHIPPABLE_VERSION.sql
  if [ ! -f "$migrations_path" ]; then
    __process_error "Migrations file $migrations_path does not exist, exiting"
    exit 1
  else
    __process_msg "Migrations file: $migrations_path"
  fi

################## check version #################################
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
    -h | --help       Print this message
  "
	exit 0
}
