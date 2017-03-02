#!/bin/bash -e

cleanup_stale_images() {
  __process_msg "Cleaning up stale images"

  local release=$(cat $STATE_FILE \
    | jq -r '.release')

  local running_services=$(cat $STATE_FILE \
    | jq '.services')
  local running_services_count=$(echo $running_services \
    | jq '. | length')

  local service_machines_list=$(cat $STATE_FILE \
    | jq '[ .machines[] | select(.group=="services") ]')
  local service_machines_count=$(echo $service_machines_list \
    | jq '. | length')
  for i in $(seq 1 $service_machines_count); do
    local machine=$(echo $service_machines_list \
      | jq '.['"$i-1"']')
    local host=$(echo $machine \
      | jq -r '.ip')
    local cleaned_up_service_images="[]"

    __process_msg "Cleaning up stale images on: $host"
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/cleanup.sh" "$SCRIPT_DIR_REMOTE"

    for j in $(seq 1 $running_services_count); do
      local running_service=$(echo $running_services \
        | jq '.['"$j-1"']')
      local running_service_name=$(echo $running_service \
        | jq -r '.name')
      local running_service_image=$(echo $running_service \
        | jq -r '.image')
      running_service_image=$(echo $running_service_image \
        | tr ":" " " \
        | awk '{print $1}')

      local is_service_image_cleaned=$(echo $cleaned_up_service_images | jq -r '.[] | select (.=="'$running_service_image'")')
      if [ -z "$is_service_image_cleaned" ]; then
        cleaned_up_service_images=$(echo $cleaned_up_service_images | jq '. + ["'$running_service_image'"]')
        __process_msg "Cleaning up tags for: $running_service_image"
        _exec_remote_cmd "$host" "$SCRIPT_DIR_REMOTE/cleanup.sh $running_service_image $release"
      fi
    done
  done
}

cleanup_db() {
  __process_msg "Cleaning up DB"

  local db_host=$(cat $STATE_FILE | jq '.machines[] | select (.group=="core" and .name=="db")')
  local db_ip=$(echo $db_host | jq -r '.ip')
  local db_username=$(cat $STATE_FILE | jq -r '.systemSettings.dbUsername')
  local db_name=$(cat $STATE_FILE | jq -r '.systemSettings.dbname')

  local db_cleanup_file_path="$POST_INSTALL_MIGRATIONS_DIR/$RELEASE_VERSION-post_install.sql"
  if [ ! -f $db_cleanup_file_path ]; then
    __process_msg "No cleanup migrations found for this release, skipping"
  else
    local cleanup_file_name=$(basename $db_cleanup_file_path)
    _copy_script_remote $db_ip $db_cleanup_file_path "$SCRIPT_DIR_REMOTE"
    _exec_remote_cmd $db_ip "psql -U $db_username -h $db_ip -d $db_name -v ON_ERROR_STOP=1 -f $SCRIPT_DIR_REMOTE/$cleanup_file_name"
  fi
}

clean_up_db_local() {
  __process_msg "Cleaning up DB"

  local db_username=$(cat $STATE_FILE | jq -r '.systemSettings.dbUsername')
  local db_name=$(cat $STATE_FILE | jq -r '.systemSettings.dbname')

  local db_cleanup_file_path="$POST_INSTALL_MIGRATIONS_DIR/$RELEASE_VERSION-post_install.sql"
  if [ ! -f $db_cleanup_file_path ]; then
    __process_msg "No cleanup migrations found for this release, skipping"
  else
    local db_mount_dir="$LOCAL_SCRIPTS_DIR/data/cleanup.sql"
    sudo cp -vr $db_cleanup_file_path $db_mount_dir
    sudo docker exec local_postgres_1 psql -U $db_username -d $db_name -v ON_ERROR_STOP=1 -f /tmp/data/cleanup.sql
  fi
}

main() {
  __process_marker "Cleaning up"

  if [ "$INSTALL_MODE" == "production" ]; then
    cleanup_db
    cleanup_stale_images
  else
    clean_up_db_local
    __process_msg "Installer running locally, not cleaning up images"
  fi
}

main
