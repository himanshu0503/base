
# Helper methods ##########################################
###########################################################

__show_status() {
  echo "All services operational"
	#TODO:
	# - print running release version
	# - print services list
	# - print machines list
	exit 0
}

__check_valid_state_json() {
  {
    json_errors=$( { cat $STATE_FILE | jq  . ; } 2>&1 )
  } || {
    message="state.json is invalid JSON, please fix the following "
    message+="error(s) before continuing:"
    __process_error $message $json_errors
    exit 1
  }
}

__check_dependencies() {
  __process_marker "Installing dependencies"

  {
    type jq &> /dev/null && __process_msg "'jq' already installed, skipping"
  } || {
    __process_msg "Installing 'jq'"
    apt-get install -y jq
  }

  {
    type rsync &> /dev/null && __process_msg "'rsync' already installed, skipping"
  } || {
    __process_msg "Installing 'rsync'"
    apt-get install -y rsync
  }

  {
    type ssh &> /dev/null && __process_msg "'ssh' already installed, skipping"
  } || {
    __process_msg "Installing 'ssh'"
    apt-get install -y ssh-client
  }
}
