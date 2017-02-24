
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
  {
    type jq &> /dev/null && true
  } || {
    __process_msg "Installing 'jq'"
    apt-get install -y jq
  }

  {
    type rsync &> /dev/null && true
  } || {
    __process_msg "Installing 'rsync'"
    apt-get install -y rsync
  }

  {
    type ssh &> /dev/null && true
  } || {
    __process_msg "Installing 'ssh'"
    apt-get install -y ssh-client
  }
}

__archive_state_file() {
  __process_msg "Archiving state.json in $STATE_FILE_ARCHIVE_DIR"

  mkdir -p $STATE_FILE_ARCHIVE_DIR

  local archive_state_path="$STATE_FILE_ARCHIVE_DIR/$TIMESTAMP.state.json"
  cp -vr $STATE_FILE $archive_state_path

  local file_count=$(ls -l $STATE_FILE_ARCHIVE_DIR | wc -l)

  if [ "$file_count" -gt "$MAX_DEFAULT_STATE_COUNT" ]; then
    ls -t $STATE_FILE_ARCHIVE_DIR \
      | tail -n +"$MAX_DEFAULT_STATE_COUNT" \
      | xargs rm --
  fi

  __process_msg "Successfully archived state.json"

}
