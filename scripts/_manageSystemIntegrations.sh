#!/bin/bash -e

export ENABLED_MASTER_INTEGRATIONS=""
export ENABLED_SYSTEM_INTEGRATIONS=""
export DB_SYSTEM_INTEGRATIONS=""

get_enabled_masterIntegrations() {
  __process_msg "GET-ing available master integrations from db"
  # TODO: after GET route is fixed, use filters only

  _shippable_get_masterIntegrations

  if [ $response_status_code -gt 299 ]; then
    __process_msg "Error GET-ing master integration list: $response"
    __process_msg "Status code: $response_status_code"
    exit 1
  fi

  local response_length=$(echo $response | jq '. | length')

  if [ $response_length -gt 5 ]; then
    ## NOTE: we're assuming we have at least 5 master integrations in global list

    ENABLED_MASTER_INTEGRATIONS=$(echo $response \
      | jq '[ .[] | select(.isEnabled==true and (.level=="system" or .level=="generic")) ]')
    local enabled_integrations_length=$(echo $ENABLED_MASTER_INTEGRATIONS | jq -r '. | length')
    __process_msg "Successfully fetched master integration list: $enabled_integrations_length"
  else
    local error=$(echo $response | jq '.')
    __process_msg "Error GET-ing master integration list: $error"
  fi
}

get_enabled_systemIntegrations() {
  __process_msg "GET-ing enabled system integrations from db"

  _shippable_get_systemIntegrations

  if [ $response_status_code -gt 299 ]; then
    __process_msg "Error GET-ing system integration list: $response"
    __process_msg "Status code: $response_status_code"
    exit 1
  fi

  DB_SYSTEM_INTEGRATIONS=$(echo $response | jq '.')
  local db_system_integrations_length=$(echo $DB_SYSTEM_INTEGRATIONS | jq -r '. | length')
  __process_msg "Successfully fetched available system integrations from db: $db_system_integrations_length"
}

validate_systemIntegrations() {
  __process_msg "Validating system integrations list in state.json"
  local enabled_master_integrations=$(echo $ENABLED_MASTER_INTEGRATIONS \
    | jq '.')
  local enabled_master_integrations_length=$(echo $enabled_master_integrations \
    | jq -r '. | length')

  if [ $enabled_master_integrations_length -eq 0 ]; then
    __process_msg "Misconfigured state.json. State cannot have zero master integrations, please reconfigure state " \
      " to insert master integrations"
    exit 1
  fi

  local enabled_system_integrations=$(cat $STATE_FILE \
    | jq '.systemIntegrations')
  local enabled_system_integrations_length=$(echo $enabled_system_integrations \
    | jq -r '. | length')

  if [ $enabled_system_integrations_length -eq 0 ]; then
    __process_msg "Please add system integrations and run installer again"
  fi

  for i in $(seq 1 $enabled_system_integrations_length); do
    local enabled_system_integration=$(echo $enabled_system_integrations \
      | jq '.['"$i-1"']')
    local enabled_system_integration_name=$(echo $enabled_system_integration \
      | jq -r '.name')
    local enabled_system_integration_master_name=$(echo $enabled_system_integration \
      | jq -r '.masterName')
    local is_valid_system_integration=false

    for j in $(seq 1 $enabled_master_integrations_length); do
      local enabled_master_integration=$(echo $enabled_master_integrations \
        | jq '.['"$j-1"']')
      local enabled_master_integration_name=$(echo $enabled_master_integration \
        | jq -r '.name')

      if [ "$enabled_system_integration_master_name" == "$enabled_master_integration_name" ]; then
        # found associated master integration
        is_valid_system_integration=true
        break
      fi
    done

    if [ $is_valid_system_integration == false ]; then
      __process_msg "Invalid system integration in state.json: '$enabled_system_integration_master_name'." \
        " Cannot find releated master integration"
      __process_msg "Please add master integration for the provider or remove the system integration " \
        " and run installer again"
      exit 1
    fi

  done
  __process_msg "Successfully validated system integrations"
}

upsert_systemIntegrations() {
  local enabled_system_integrations=$(cat $STATE_FILE \
    | jq '.systemIntegrations')
  local enabled_system_integrations_length=$(echo $enabled_system_integrations \
    | jq -r '. | length')

  local db_system_integrations=$(echo $DB_SYSTEM_INTEGRATIONS \
    | jq '.')
  local db_system_integrations_length=$(echo $db_system_integrations \
    | jq -r '. | length')

  for i in $(seq 1 $enabled_system_integrations_length); do
    local enabled_system_integration=$(echo $enabled_system_integrations \
      | jq '.['"$i-1"']')
    local enabled_system_integration_name=$(echo $enabled_system_integration \
      | jq -r '.name')
    local enabled_system_integration_master_name=$(echo $enabled_system_integration \
      | jq -r '.masterName')

    local is_system_integration_available=false
    local system_integration_to_update=""
    local system_integration_in_db=""

    for j in $(seq 1 $db_system_integrations_length); do
      local db_system_integration=$(echo $db_system_integrations \
        | jq '.['"$j-1"']')
      local db_system_integration_name=$(echo $db_system_integration \
        | jq -r '.name')
      local db_system_integration_master_name=$(echo $db_system_integration \
        | jq -r '.masterName')

      if [ $enabled_system_integration_master_name == $db_system_integration_master_name ] && \
        [ $enabled_system_integration_name == $db_system_integration_name ]; then
        is_system_integration_available=true
        system_integration_to_update=$enabled_system_integration
        system_integration_in_db=$db_system_integration
      fi
    done

    if [ $is_system_integration_available == true ]; then
      # put the system integration with values in state.json
      __process_msg "Updating existing system integration: $enabled_system_integration_name of type: $enabled_system_integration_master_name"
      local db_system_integration_id=$(echo $system_integration_in_db \
        | jq -r '.id')
      local db_system_integration_name=$(echo $system_integration_in_db \
        | jq -r '.name')
      local db_system_integration_master_name=$(echo $system_integration_in_db \
        | jq -r '.masterName')

      enabled_system_integration=$(echo $enabled_system_integration \
        | jq '.id="'$db_system_integration_id'"')
      enabled_system_integration=$(echo $enabled_system_integration \
        | jq '.masterName="'$db_system_integration_master_name'"')
      enabled_system_integration=$(echo $enabled_system_integration \
        | jq '.name="'$db_system_integration_name'"')
      enabled_system_integration=$(echo $enabled_system_integration \
        | jq '.isEnabled=true')

      _shippable_putById_systemIntegrations $db_system_integration_id "$enabled_system_integration"

      if [ $response_status_code -gt 299 ]; then
        __process_msg "Error updating system integration $enabled_system_integration_master_name: $response"
        __process_msg "Status code: $response_status_code"
        exit 1
      else
        __process_msg "Sucessfully updated integration for $enabled_system_integration_master_name"
      fi
    else
      # find the master integration for this system integration
      # post a new system integration
      __process_msg "Adding new system integration: $enabled_system_integration_name of type: $enabled_system_integration_master_name"

      local enabled_master_integration=$(echo $ENABLED_MASTER_INTEGRATIONS \
        | jq '.[] |
          select
            (.name == "'$enabled_system_integration_master_name'")')
      local enabled_master_integration_id=$(echo $enabled_master_integration \
        | jq -r '.id')
      local enabled_master_integration_name=$(echo $enabled_master_integration \
        | jq -r '.name')

      enabled_system_integration=$(echo $enabled_system_integration \
        | jq '.masterIntegrationId="'$enabled_master_integration_id'"')
      enabled_system_integration=$(echo $enabled_system_integration \
        | jq '.masterName="'$enabled_master_integration_name'"')
      enabled_system_integration=$(echo $enabled_system_integration \
        | jq '.isEnabled=true')

      _shippable_post_systemIntegrations "$enabled_system_integration"

      if [ $response_status_code -gt 299 ]; then
        __process_msg "Error adding system integration $enabled_system_integration_master_name: $response"
        __process_msg "Status code: $response_status_code"
        exit 1
      else
        __process_msg "Sucessfully added integration for $enabled_system_integration_master_name"
      fi

    fi
  done
}

delete_systemIntegrations() {
  # for each SI in list
  # if there is no MI, ask user to delete SI from list
  #   and try again
  __process_msg "DELETE-ing removed system integrations from state.json, from db, if any"

  local system_integrations=$(cat $STATE_FILE | jq '.systemIntegrations')

  local db_system_integrations=$(echo $DB_SYSTEM_INTEGRATIONS \
    | jq '.')
  local db_system_integrations_length=$(echo $db_system_integrations \
    | jq -r '. | length')
  for i in $(seq 1 $db_system_integrations_length); do
    local db_system_integration=$(echo $db_system_integrations \
      | jq '.['"$i-1"']')
    local db_system_integration_name=$(echo $db_system_integration \
      | jq -r '.name')
    local db_system_integration_master_name=$(echo $db_system_integration \
      | jq -r '.masterName')
    local system_integration=$(echo $system_integrations \
      | jq -r -c '[ .[] | select (.masterName == "'$db_system_integration_master_name'" and .name == "'$db_system_integration_name'") ]')
    local system_integration_length=$(echo $system_integration \
      | jq -r '. | length')
    if [ $system_integration_length -eq 0 ]; then
      local db_system_integration_id=$(echo $db_system_integration \
        | jq -r '.id')

      _shippable_deleteById_systemIntegrations $db_system_integration_id

      if [ $response_status_code -gt 299 ]; then
        __process_msg "Error deleting system integration $db_system_integration_master_name: $response"
        __process_msg "Status code: $response_status_code"
        exit 1
      else
        __process_msg "Sucessfully deleted integration for $db_system_integration_master_name"
      fi
    fi
  done
}

main() {
  __process_marker "Configuring system integrations"
  get_enabled_masterIntegrations
  get_enabled_systemIntegrations
  validate_systemIntegrations
  upsert_systemIntegrations
  delete_systemIntegrations
}

main
