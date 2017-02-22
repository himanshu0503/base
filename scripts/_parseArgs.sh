#!/bin/bash -e

__show_status() {
  echo "All services operational"
	#TODO:
	# - print running release version
	# - print services list
	# - print machines list
	exit 0
}

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
					SHIPPABLE_INSTALL_TYPE="local"
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

__print_help_install() {
  echo "
  usage: ./base.sh --install [local | production]
  This command installs shippable on either localhost or production environment.
  production environment is chosen by default
  "
}

__print_help() {
  echo "
  usage: $0 options
  This script installs Shippable enterprise
  OPTIONS:
    -s | --status     Print status of current installation
    -l | --local      Run a localhost installation
    -v | --version    Install a particular version
    -h | --help       Print this message
  "
	exit 0
}
