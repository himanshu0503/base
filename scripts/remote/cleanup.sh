#!/bin/bash -e

readonly COMPONENT_REPOSITORY=$1
readonly RELEASE=$2

remove_old_images() {
  local all_images=$(sudo docker images)
  echo "$all_images" | while read -r line; do
    local image_repository=$(echo $line | awk '{print $1}')
    local image_tag=$(echo $line | awk '{print $2}')
    local image_id=$(echo $line | awk '{print $3}')
    if [ "$image_repository" == "$COMPONENT_REPOSITORY" ]; then
      if [ "$image_tag" != "$RELEASE" ]; then
        local stale_image=$image_repository:$image_tag
        echo "Stale image $stale_image found, attempting to remove..."
        sudo docker rmi $image_id || true
      fi
    fi
  done
}

main() {
  if [ -z "$RELEASE" ]; then
    echo "RELEASE env required to remove stale images"
    exit 1
  fi

  if [ -z "$COMPONENT_REPOSITORY" ]; then
    echo "COMPONENT_REPOSITORY env required to remove stale images"
    exit 1
  fi

  remove_old_images
}

main
