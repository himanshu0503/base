#!/bin/bash -e

install_docker_master() {
  __process_msg "Installing Docker on swarm master"
  local swarm_master_host=$(cat $STATE_FILE |
    jq '.machines[] | select (.group=="core" and .name=="swarm")')
  local master_docker_installed=$(echo $swarm_master_host |
    jq -r '.isDockerInstalled')

  ##TODO: remove once 'installStatus.dockerInstalled' flag is removed
  if [ -z ${master_docker_installed+x} ]; then
    __process_msg "Setting swarm master docker install status to global docker install status"
    local docker_install_status=$(cat $STATE_FILE |
      jq -r '.installStatus.dockerInstalled')
    master_docker_installed=$docker_install_status
    local swarm_master=$(cat $STATE_FILE |
      jq '.machines |=
      map (
        if .name=="swarm" then
          .isDockerInstalled="'$docker_install_status'"
        else
          .
        end)'
    )
    _update_state "$swarm_master"
  else
    __process_msg "Using the docker install status set in swarm master config"
  fi

  if [ "$master_docker_installed" == false ]; then
    __process_msg "Docker not installed on swarm master, installing"
    local host=$(echo $swarm_master_host | jq '.ip')
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/installDocker.sh" "$SCRIPT_DIR_REMOTE"
    _exec_remote_cmd "$host" "$SCRIPT_DIR_REMOTE/installDocker.sh"
    local swarm_master=$(cat $STATE_FILE |
      jq '.machines |=
      map (
        if .name=="swarm" then
          .isDockerInstalled=true
        else
          .
        end)'
    )
    _update_state "$swarm_master"
  else
    __process_msg "Docker already installed on swarm master, skipping"
  fi
}

initialize_docker_master() {
  __process_msg "Initializing Docker on swarm master"
  local swarm_master_host=$(cat $STATE_FILE |
    jq '.machines[] | select (.group=="core" and .name=="swarm")')
  local host=$(echo $swarm_master_host \
    | jq '.ip')

  ## Alaways initialize because ecr credentials expire afer 12 hours
  __process_msg "Initializing docker on swarm master $host"

  local credentials_template="$REMOTE_SCRIPTS_DIR/credentials.template"
  local credentials_file="$USR_DIR/credentials"

  __process_msg "Loading: installerAccessKey"
  local aws_access_key=$(cat $STATE_FILE | jq -r '.systemSettings.installerAccessKey')
  if [ -z "$aws_access_key" ]; then
    __process_msg "Please update 'systemSettings.installerAccessKey' in state.json and run installer again"
    exit 1
  fi
  sed "s#{{aws_access_key}}#$aws_access_key#g" $credentials_template > $credentials_file

  __process_msg "Loading: installerSecretKey"
  local aws_secret_key=$(cat $STATE_FILE | jq -r '.systemSettings.installerSecretKey')
  if [ -z "$aws_secret_key" ]; then
    __process_msg "Please update 'systemSettings.installerSecretKey' in state.json and run installer again"
    exit 1
  fi
  sed -i "s#{{aws_secret_key}}#$aws_secret_key#g" $credentials_file

  _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/docker-credential-ecr-login" "/usr/bin/"
  _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/config.json" "/root/.docker/"
  _copy_script_remote $host "$USR_DIR/credentials" "/root/.aws/"

  local swarm_master=$(cat $STATE_FILE |
    jq '.machines |=
    map (
      if .name=="swarm" then
        .isDockerInitialized=true
      else
        .
      end)'
  )
  _update_state "$swarm_master"
  __process_msg "Initialized Docker on swarm master"
}

initialize_swarm_master() {
  ensure_updated_packages
  __process_msg "Initializing Swarm on master"

  local swarm_master_host=$(cat $STATE_FILE |
    jq '.machines[] | select (.group=="core" and .name=="swarm")')
  local host=$(echo $swarm_master_host \
    | jq '.ip')
  local master_swarm_initialized=$(echo $swarm_master_host |
    jq -r '.isMasterInitialized')

  ##TODO: remove once 'installStatus.dockerInitialized' flag is removed
  if [ -z ${master_swarm_initialized+x} ]; then
    __process_msg "Setting master swarm initialized status to global docker install status"
    local master_initialized_status=$(cat $STATE_FILE |
      jq -r '.installStatus.swarmInstalled')
    master_swarm_initialized=$docker_initialized_status
    local swarm_master=$(cat $STATE_FILE |
      jq '.machines |=
      map (
        if .name=="swarm" then
          .isMasterInitialized="'$master_initialized_status'"
        else
          .
        end)'
    )
    _update_state "$swarm_master"
  else
    __process_msg "Using the master initialized status set in swarm master config"
  fi

  if [ "$master_swarm_initialized" == false ]; then
    __process_msg "Docker not initialized on master, initializing"
    local gitlab_host=$(cat $STATE_FILE \
      | jq '.machines[] | select (.group=="core" and .name=="swarm")')
    local host=$(echo $gitlab_host \
      | jq '.ip')

    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/installSwarm.sh" "$SCRIPT_DIR_REMOTE"
    _exec_remote_cmd "$host" "$SCRIPT_DIR_REMOTE/installSwarm.sh"

    __process_msg "Initializing docker swarm master"
    _exec_remote_cmd "$host" "docker swarm leave --force || true"
    local swarm_init_cmd="docker swarm init --advertise-addr $host"
    _exec_remote_cmd "$host" "$swarm_init_cmd"

    local swarm_worker_token="swarm_worker_token.txt"
    local swarm_worker_token_remote="$SCRIPT_DIR_REMOTE/$swarm_worker_token"
    _exec_remote_cmd "$host" "'docker swarm join-token -q worker > $swarm_worker_token_remote'"
    _copy_script_local $host "$swarm_worker_token_remote"

    local script_dir_local="/tmp/shippable"
    local swarm_worker_token_local="$script_dir_local/$swarm_worker_token"
    local swarm_worker_token=$(cat $swarm_worker_token_local)

    local swarm_worker_token_update=$(cat $STATE_FILE | jq '
      .systemSettings.swarmWorkerToken = "'$swarm_worker_token'"')
    update=$(echo $swarm_worker_token_update | jq '.' | tee $STATE_FILE)

    __process_msg "Running Swarm in drain mode"
    local swarm_master_host_name="swarm_master_host_name.txt"
    local swarm_master_host_name_remote="$SCRIPT_DIR_REMOTE/$swarm_master_host_name"
    _exec_remote_cmd "$host" "'docker node inspect self | jq -r '.[0].Description.Hostname' > $swarm_master_host_name_remote'"
    _copy_script_local $host "$swarm_master_host_name_remote"

    local swarm_master_host_name_remote="$script_dir_local/$swarm_master_host_name"
    local swarm_master_host_name=$(cat $swarm_master_host_name_remote)
    _exec_remote_cmd "$host" "docker node update  --availability drain $swarm_master_host_name"

    local swarm_master=$(cat $STATE_FILE |
      jq '.machines |=
      map (
        if .name=="swarm" then
          .isMasterInitialized=true
        else
          .
        end)'
    )
    _update_state "$swarm_master"

  else
    __process_msg "Swarm master already initialized, skipping"
  fi
}

main() {
  install_docker_master
  initialize_docker_master
  initialize_swarm_master
}

main
