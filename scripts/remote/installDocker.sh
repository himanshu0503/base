#!/bin/bash -e

export INSTALL_MODE="$1"
export DOCKER_RESTART=false
export DEBIAN_FRONTEND=noninteractive
readonly DOCKER_VERSION=1.13.1-0~ubuntu-trusty

check_docker_local() {
  {
    type docker &> /dev/null && __process_msg "Docker available"
  } || {
    __process_msg "Please install Docker before running the installer"
    exit 1
  }
}

docker_install() {
  echo "Installing Docker..."
  # Clean up any existing installation
  sudo apt-get purge -y docker-engine
  rm -rf /var/lib/docker || true
  rm -rf /etc/default/docker || true

  sudo apt-get install -y linux-image-extra-$(uname -r) linux-image-extra-virtual
  sudo apt-get install -y -o Dpkg::Options::="--force-confnew" docker-engine=$DOCKER_VERSION
}

check_docker_opts() {
  echo "Checking docker options..."
  SHIPPABLE_DOCKER_OPTS='DOCKER_OPTS="$DOCKER_OPTS -H unix:///var/run/docker.sock -g=/data --storage-driver aufs"'
  opts_exist=$(sh -c "grep '$SHIPPABLE_DOCKER_OPTS' /etc/default/docker || echo ''")
  if [ -z "$opts_exist" ]; then
    echo "Appending DOCKER_OPTS to /etc/default/docker"
    echo "$SHIPPABLE_DOCKER_OPTS" | sudo tee -a /etc/default/docker
    DOCKER_RESTART=true
  else
    echo "Shippable DOCKER_OPTS already present in /etc/default/docker"
  fi

  echo "Disabling Docker TCP listener..."
  sudo sh -c "sed -e s/\"-H tcp:\/\/0.0.0.0:4243\"//g -i /etc/default/docker"
}

restart_docker_service() {
  if [ $DOCKER_RESTART == true ]; then
    echo "Restarting Docker..."
    sudo service docker restart
  fi
}

main() {
  if [ "$INSTALL_MODE" == "local" ]; then
    check_docker_local
  else
    docker_install
    check_docker_opts
    restart_docker_service
  fi
}

main
