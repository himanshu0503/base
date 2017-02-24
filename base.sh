#!/bin/bash -e

###########################################################
#
# Shippable Enterprise Installer
#
# Supported OS: Ubuntu 14.04
# Supported bash: 4.3.11
###########################################################

# Global variables ########################################
###########################################################
readonly IFS=$'\n\t'
readonly ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly VERSIONS_DIR="$ROOT_DIR/versions"
readonly MIGRATIONS_DIR="$ROOT_DIR/migrations"
readonly POST_INSTALL_MIGRATIONS_DIR="$MIGRATIONS_DIR/post_install"
readonly SCRIPTS_DIR="$ROOT_DIR/scripts"
readonly USR_DIR="$ROOT_DIR/usr"
readonly LOGS_DIR="$USR_DIR/logs"
readonly TIMESTAMP="$(date +%Y_%m_%d_%H_%M_%S)"
readonly LOG_FILE="$LOGS_DIR/${TIMESTAMP}_logs.txt"
readonly MAX_DEFAULT_LOG_COUNT=6
readonly REMOTE_SCRIPTS_DIR="$ROOT_DIR/scripts/remote"
readonly LOCAL_SCRIPTS_DIR="$ROOT_DIR/scripts/local"
readonly STATE_FILE="$USR_DIR/state.json"
readonly STATE_FILE_BACKUP="$USR_DIR/state.json.backup"
readonly STATE_FILE_ARCHIVE_DIR="$USR_DIR/states"
readonly MAX_DEFAULT_STATE_COUNT=6
readonly SSH_USER="root"
readonly SSH_PRIVATE_KEY=$USR_DIR/machinekey
readonly SSH_PUBLIC_KEY=$USR_DIR/machinekey.pub
readonly LOCAL_BRIDGE_IP=172.17.42.1
readonly API_TIMEOUT=600
export LC_ALL=C
export UPDATED_APT_PACKAGES=false

# Installation default values #############################
###########################################################
export INSTALL_MODE="production"
export SHIPPABLE_VERSION="master"
export RELEASE_VERSION=""
export IS_UPGRADE=false
###########################################################

source "$SCRIPTS_DIR/logger.sh"
source "$SCRIPTS_DIR/_helpers.sh"
source "$SCRIPTS_DIR/_parseArgs.sh"
source "$SCRIPTS_DIR/_execScriptRemote.sh"
source "$SCRIPTS_DIR/_copyScriptRemote.sh"
source "$SCRIPTS_DIR/_copyScriptLocal.sh"
source "$SCRIPTS_DIR/_manageState.sh"
source "$SCRIPTS_DIR/_manageState.sh"

main() {
  __check_logsdir
  __check_dependencies
  __parse_args "$@"
  __initialize_state
  __validate_args
  export RELEASE_VERSION=$SHIPPABLE_VERSION
  readonly SCRIPT_DIR_REMOTE="/tmp/shippable/$SHIPPABLE_VERSION"
  source "$SCRIPTS_DIR/getConfigs.sh"
  {
    source "$SCRIPTS_DIR/bootstrapMachines.sh"
    source "$SCRIPTS_DIR/installCore.sh"
    source "$SCRIPTS_DIR/bootstrapApp.sh"
    source "$SCRIPTS_DIR/provisionServices.sh"
    source "$SCRIPTS_DIR/cleanup.sh"
  } 2>&1 | tee $LOG_FILE ; ( exit ${PIPESTATUS[0]} )

  __cleanup_logfiles
  __archive_state_file
  __process_msg "Installation successfully completed !!!"
}

main "$@"
