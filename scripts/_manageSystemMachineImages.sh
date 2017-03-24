#!/bin/bash -e

local EXISTING_SYSTEM_MACHINE_IMAGES=""

get_available_systemMachineImages() {
  __process_msg "GET-ing available system machine images from db"

  _shippable_get_systemMachineImages

  if [ $response_status_code -gt 299 ]; then
    __process_msg "Error GET-ing system machine images list: $response"
    __process_msg "Status code: $response_status_code"
    exit 1
  fi

  EXISTING_SYSTEM_MACHINE_IMAGES=$(echo $response | jq '.')
}

update_exec_runsh_images() {
  __process_msg "Updating exec and runsh image tags in system machine images"

  local release=$(cat $STATE_FILE | jq -r '.release')
  local system_machine_images=$(cat $STATE_FILE | jq -r '.systemMachineImages')
  local system_machine_images_length=$(echo $system_machine_images | jq -r '. | length')

  # TODO: Add field runShRepo in state file and use it from there
  local runSh_image_repo="shipimg/genexec"
  local runSh_image="$runSh_image_repo:$release"
  echo "Updating runShImage to $runSh_image in state file"

  local updated_system_machine_images=$(cat $STATE_FILE | jq '[ .systemMachineImages | .[] | .runShImage="'$runSh_image'" ]')
  local update=$(cat $STATE_FILE | jq '.systemMachineImages = '"$updated_system_machine_images"'')
  _update_state "$update"
}

save_systemMachineImages(){
  __process_msg "Saving available system machine images into db"

  local system_machine_images=$(cat $STATE_FILE | jq -r '.systemMachineImages')
  local system_machine_images_length=$(echo $system_machine_images | jq -r '. | length')

  for i in $(seq 1 $system_machine_images_length); do
    local system_machine_image=$(echo $system_machine_images | jq '.['"$i-1"']')
    local system_machine_image_name=$(echo $system_machine_image | jq '.name')
    local system_machine_image_id=$(echo $EXISTING_SYSTEM_MACHINE_IMAGES | jq -r '.[] | select (.name=='"$system_machine_image_name"') | .id')

    if [ -z "$system_machine_image_id" ]; then
      _shippable_post_systemMachineImages "$system_machine_image"

      if [ $response_status_code -gt 299 ]; then
        __process_msg "Error inserting system machine image $system_machine_image_name: $response"
        __process_msg "Status code: $response_status_code"
        exit 1
      else
        echo "Sucessfully inserted system machine image: $system_machine_image_name"
      fi
    else
      _shippable_putById_systemMachineImages $system_machine_image_id "$system_machine_image"

      if [ $response_status_code -gt 299 ]; then
        __process_msg "Error updating system machine image $system_machine_image_name: $response"
        __process_msg "Status code: $response_status_code"
        exit 1
      else
        __process_msg "Sucessfully updated system machine image: $system_machine_image_name"
      fi
    fi
  done
  __process_msg "Successfully saved system machine images"
}

main() {
  __process_marker "Configuring system machine images"
  get_available_systemMachineImages
  update_exec_runsh_images
  save_systemMachineImages
}

main
