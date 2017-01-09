#!/bin/bash -e

install_docker_workers() {
  local service_machines_list=$(cat $STATE_FILE |
    jq '[ .machines[] | select(.group=="services") ]')
  local service_machines_count=$(echo $service_machines_list | jq '. | length')
  for i in $(seq 1 $service_machines_count); do
    local machine=$(echo $service_machines_list | jq '.['"$i-1"']')
    local name=$(echo $machine | jq -r '.name')
    local worker_docker_installed=$(echo $machine | jq -r '.isDockerInstalled')

    ##TODO: remove once 'installStatus.dockerInitialized' flag is removed
    if [ -z ${worker_docker_installed+x} ]; then
      __process_msg "Setting docker installed status to global docker install status for worker: $name"
      local docker_installed_status=$(cat $STATE_FILE |
        jq -r '.installStatus.dockerInstalled')
      worker_docker_installed=$docker_installed_status
      local swarm_worker=$(cat $STATE_FILE |
        jq '.machines |=
        map (
          if .name=="'$name'" then
            .isDockerInstalled="'$docker_installed_status'"
          else
            .
          end)'
      )
      _update_state "$swarm_worker"
    else
      __process_msg "Using the docker installed status set in machine config for worker: $name"
    fi

    if [ "$worker_docker_installed" == false ]; then
      __process_msg "Docker not installed on worker: $name, installing"
      local host=$(echo $machine | jq '.ip')
      _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/installDocker.sh" "$SCRIPT_DIR_REMOTE"
      _exec_remote_cmd "$host" "$SCRIPT_DIR_REMOTE/installDocker.sh"
      local swarm_worker=$(cat $STATE_FILE |
        jq '.machines |=
        map (
          if .name=="'$name'" then
            .isDockerInstalled=true
          else
            .
          end)'
      )
      _update_state "$swarm_worker"
    else
      __process_msg "Docker already installed on swarm master, skipping"
    fi
  done
}

initialize_docker_workers() {
  __process_msg "Initializing Docker on swarm workers"

  local service_machines_list=$(cat $STATE_FILE |
    jq '[ .machines[] | select(.group=="services") ]')
  local service_machines_count=$(echo $service_machines_list | jq '. | length')
  for i in $(seq 1 $service_machines_count); do
    local machine=$(echo $service_machines_list | jq '.['"$i-1"']')
    local host=$(echo $machine | jq -r '.ip')
    local name=$(echo $machine | jq -r '.name')
    local worker_docker_initialized=$(echo $machine | jq -r '.isDockerInitialized')

    ##TODO: remove once 'installStatus.dockerInitialized' flag is removed
    if [ -z ${worker_docker_initialized+x} ]; then
      __process_msg "Setting docker initialized status to global docker install status for worker: $name"
      local docker_initialized_status=$(cat $STATE_FILE |
        jq -r '.installStatus.dockerInitialized')
      worker_docker_initialized=$docker_initialized_status
      local swarm_worker=$(cat $STATE_FILE |
        jq '.machines |=
        map (
          if .name=="'$name'" then
            .isDockerInitialized="'$docker_initialized_status'"
          else
            .
          end)'
      )
      _update_state "$swarm_worker"
    else
      __process_msg "Using the docker initialized status set in machine config for worker: $name"
    fi

    if [ "$worker_docker_initialized" == false ]; then
      __process_msg "Docker not initialized on worker: $name, initializing"

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

      local swarm_worker=$(cat $STATE_FILE |
        jq '.machines |=
        map (
          if .name=="'$name'" then
            .isDockerInitialized=true
          else
            .
          end)'
      )
      _update_state "$swarm_worker"
      __process_msg "Initialized Docker on swarm worker: $name"
    else
      __process_msg "Docker already initialized on swarm worker: $name, skipping"
    fi
  done
}

initialize_swarm_workers() {
  __process_msg "Initializing swarm workers on service machines"
  local service_machines_list=$(cat $STATE_FILE |
    jq '[ .machines[] | select(.group=="services") ]')
  local service_machines_count=$(echo $service_machines_list | jq '. | length')
  for i in $(seq 1 $service_machines_count); do
    local machine=$(echo $service_machines_list | jq '.['"$i-1"']')
    local host=$(echo $machine | jq -r '.ip')
    local name=$(echo $machine | jq -r '.name')
    local worker_initialized=$(echo $machine | jq -r '.isWorkerInitialized')

    ##TODO: remove once 'installStatus.dockerInitialized' flag is removed
    if [ -z ${worker_initialized+x} ]; then
      __process_msg "Setting worker initialized status to global docker initialized status for worker: $name"
      local worker_initialized_status=$(cat $STATE_FILE |
        jq -r '.installStatus.swarmInitialized')
      worker_initialized=$worker_initialized_status
      local swarm_worker=$(cat $STATE_FILE |
        jq '.machines |=
        map (
          if .name=="'$name'" then
            .isWorkerInitialized="'$worker_initialized_status'"
          else
            .
          end)'
      )
      _update_state "$swarm_worker"
    else
      __process_msg "Using the worker initialized status set in machine config for worker: $name"
    fi

    if [ "$worker_initialized" == false ]; then
      __process_msg "Worker: $name not initialized, initializing"
      local gitlab_host=$(cat $STATE_FILE | jq '.machines[] | select (.group=="core" and .name=="swarm")')
      local gitlab_host_ip=$(echo $gitlab_host | jq -r '.ip')
      local swarm_worker_token=$(cat $STATE_FILE | jq '.systemSettings.swarmWorkerToken')

      _exec_remote_cmd "$host" "docker swarm leave || true"
      _exec_remote_cmd "$host" "docker swarm join --token $swarm_worker_token $gitlab_host_ip"
      local swarm_worker=$(cat $STATE_FILE |
        jq '.machines |=
        map (
          if .name=="'$name'" then
            .isWorkerInitialized=true
          else
            .
          end)'
      )
      _update_state "$swarm_worker"
      __process_msg "Initialized swarm worker: $name"
    else
      __process_msg "Swarm worker: $name already initialized, skipping"
    fi
  done
}

main() {
  install_docker_workers
  initialize_docker_workers
  initialize_swarm_workers
}

main
