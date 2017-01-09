#!/bin/bash -e
readonly MACHINES_CONFIG="$USR_DIR/machines.json"
###########################################################
export MACHINES_LIST=""

validate_machines_config() {
  __process_msg "validating machines config"
  MACHINES_LIST=$(cat $MACHINES_CONFIG | jq '.')
  local machine_count=$(echo $MACHINES_LIST | jq -r '. | length')

  local is_upgrade=$(cat $STATE_FILE \
    | jq -r '.isUpgrade')

  if [ $is_upgrade == false ]; then
    __process_msg "Cleaning up machines array in state.json"
    local update=$(cat $STATE_FILE \
      | jq '.machines=[]')
    _update_state "$update"
  else
    __process_msg "Installer running in upgrade mode, not clearing machines list"
  fi

  local machines_list_state=$(cat $STATE_FILE \
    | jq '.machines')
  local machine_count_state=$(echo $machines_list_state \
    | jq -r '. | length')

  for i in $(seq 1 $machine_count); do
    local machine=$(echo $MACHINES_LIST \
      | jq '.['"$i-1"']')
    local machine_name=$(echo $machine \
      | jq -r '.name')
    local is_machine_available=false

    for j in $(seq 1 $machine_count_state); do
      local machine_state=$(echo $machines_list_state \
        | jq '.['"$j-1"']')
      local machine_state_name=$(echo $machine_state \
        | jq -r '.name')
      if [ "$machine_name" == "$machine_state_name" ]; then
        is_machine_available=true
        __process_msg "Machine: $machine_name already present in state file"
      fi
    done

    if [ "$is_machine_available" == false ]; then
      __process_msg "Adding machine: $machine_name to state file"
      local host=$(echo $machine | jq '.ip')
      local name=$(echo $machine | jq '.name')
      local group=$(echo $machine | jq '.group')

      local machines_state=$(cat $STATE_FILE | jq '
        .machines |= . + [{
          "name": '"$name"',
          "group": '"$group"',
          "ip": '"$host"',
          "sshSuccessful": "false",
          "isBootstrapped": "false"
        }]')

      local update=$(echo $machines_state \
        | jq '.')
      _update_state "$update"
    fi
  done

  __process_msg "Validated machines config"

  local swarm_master_status=$(cat $STATE_FILE |
    jq '.machines[] | select (.name=="swarm") |
    .isMasterInitialized')

  if [ $swarm_master_status == null ] || 
    [ "$swarm_master_status" == false ]; then
    __process_msg "Initializing default values for swarm master"
    local swarm_master=$(cat $STATE_FILE |
      jq '.machines |=
      map (
        if .name=="swarm" then
          . + {
                "isDockerInstalled": false,
                "isDockerInitialized": false,
                "isMasterInitialized" : false
              }
        else
          .
        end)'
    )
    _update_state "$swarm_master"
  else
    __process_msg "Swarm master already initialized, skipping"
  fi

  local service_machines_list=$(cat $STATE_FILE |
    jq '[ .machines[] | select(.group=="services") ]')
  local service_machines_count=$(echo $service_machines_list | jq '. | length')
  for i in $(seq 1 $service_machines_count); do
    local machine=$(echo $service_machines_list | jq '.['"$i-1"']')
    local name=$(echo $machine | jq -r '.name')
    local worker_status=$(echo $machine | jq -r '.isWorkerInitialized')

    if [ $worker_status == null ] || 
      [ "$worker_status" == false ]; then
      __process_msg "Initializing default values for worker: $name"
      local swarm_worker=$(cat $STATE_FILE |
        jq '.machines |=
        map (
          if .name=="'$name'" then
            . + {
                  "isDockerInstalled": false,
                  "isDockerInitialized": false,
                  "isWorkerInitialized" : false
                }
          else
            .
          end)'
      )
      _update_state "$swarm_worker"
    else
      __process_msg "Worker $name already initialized, skipping"
    fi
  done

  __process_msg "Successfully validated machines config"
}

create_ssh_keys() {
  __process_msg "Creating SSH keys"
  if [ -f "$SSH_PRIVATE_KEY" ] && [ -f $SSH_PUBLIC_KEY ]; then
    __process_msg "SSH keys already present, skipping"
  else
    __process_msg "SSH keys not available, generating"
    local keygen_exec=$(ssh-keygen -t rsa -P "" -f $SSH_PRIVATE_KEY)
    __process_msg "SSH keys successfully generated"
  fi
}

update_ssh_key() {
  ##TODO: ask user to update ssh keys in machines
  __process_msg "Please run the following command on all the machines (including this one), type (y) when done"
  echo ""
  echo "echo `cat $SSH_PUBLIC_KEY` | sudo tee -a /root/.ssh/authorized_keys"
  echo ""

  __process_msg "Done? (y/n)"
  read response
  if [[ "$response" =~ "y" ]]; then
    __process_msg "Proceeding with steps to set up the machines"
  else
    __process_msg "SSH keys are required to bootstrap the machines"
    update_ssh_key
  fi
}

check_connection() {
  __process_msg "Checking machine connection"
  local machine_count=$(echo $MACHINES_LIST | jq '. | length')
  for i in $(seq 1 $machine_count); do
    local machine=$(echo $MACHINES_LIST | jq '.['"$i-1"']')
    local host=$(echo $machine | jq -r '.ip')
    _exec_remote_cmd "$host" "ls"

    local machine_state=$(cat $STATE_FILE |
      jq '.machines |=
        map (
          if .ip="'$host'" then
            .sshSuccessful=true
          else
            .
          end
        )'
      )
    _update_state "$machine_state"
  done

  local update=$(cat $STATE_FILE |
    jq '.installStatus.machinesSSHSuccessful='true'')
  _update_state "$update"
  __process_msg "All hosts reachable"
}

check_requirements() {
  # TODO: check machine config: memory, cpu disk, arch os type
  __process_msg "Validating machine requirements"
  local machine_count=$(echo $MACHINES_LIST | jq '. | length')
  for i in $(seq 1 $machine_count); do
    local machine=$(echo $MACHINES_LIST | jq '.['"$i-1"']')
    local host=$(echo $machine | jq '.ip')
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/checkRequirements.sh" "$SCRIPT_DIR_REMOTE"
    _exec_remote_cmd "$host" "$SCRIPT_DIR_REMOTE/checkRequirements.sh"
  done
}

export_language() {
  __process_msg "Exporting Language Preferences"
  local machine_count=$(echo $MACHINES_LIST | jq '. | length')
  for i in $(seq 1 $machine_count); do
    local machine=$(echo $MACHINES_LIST | jq '.['"$i-1"']')
    local host=$(echo $machine | jq '.ip')
    _exec_remote_cmd "$host" "export LC_ALL=C"
  done
}

setup_node() {
  __process_msg "Configuring ulimits on machines"
  local machine_count=$(echo $MACHINES_LIST | jq '. | length')
  for i in $(seq 1 $machine_count); do
    local machine=$(echo $MACHINES_LIST | jq '.['"$i-1"']')
    local host=$(echo $machine | jq '.ip')
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/setupNode.sh" "$SCRIPT_DIR_REMOTE"
    _exec_remote_cmd "$host" "$SCRIPT_DIR_REMOTE/setupNode.sh"
  done
}

bootstrap() {
  __process_msg "Installing core components on machines"
  local machine_count=$(echo $MACHINES_LIST | jq '. | length')
  for i in $(seq 1 $machine_count); do
    local machine=$(echo $MACHINES_LIST | jq '.['"$i-1"']')
    local host=$(echo $machine | jq '.ip')
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/installBase.sh" "$SCRIPT_DIR_REMOTE"
    _exec_remote_cmd "$host" "$SCRIPT_DIR_REMOTE/installBase.sh $INSTALL_MODE"
  done
  UPDATED_APT_PACKAGES=true
}

install_ntp() {
  __process_msg "Installing ntp"
  local machine_count=$(echo $MACHINES_LIST | jq '. | length')
  for i in $(seq 1 $machine_count); do
    local machine=$(echo $MACHINES_LIST | jq '.['"$i-1"']')
    local host=$(echo $machine | jq '.ip')
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/installNTP.sh" "$SCRIPT_DIR_REMOTE"
    _exec_remote_cmd "$host" "$SCRIPT_DIR_REMOTE/installNTP.sh $INSTALL_MODE"
  done
}

bootstrap_local() {
  __process_msg "Installing core components on machines"
  source "$REMOTE_SCRIPTS_DIR/installBase.sh" "$INSTALL_MODE"
  sudo rm -rf "$LOCAL_SCRIPTS_DIR/gitlab" || true
}

main() {
  __process_marker "Bootstrapping machines"

  if [ "$INSTALL_MODE" == "production" ]; then
    __process_msg "Bootstrapping machines in production mode"
    validate_machines_config
    create_ssh_keys

    local machines_list=$(cat $STATE_FILE \
      | jq '.machines')
    local machine_count=$(echo $machines_list \
      | jq -r '. | length')

    for i in $(seq 1 $machine_count); do
      local machine=$(echo $machines_list \
        | jq '.['"$i-1"']')
      local machine_name=$(echo $machine \
        | jq -r '.name')
      local machine_bootstrapped=$(echo $machine \
        | jq -r '.isBootstrapped')

      if [ -z ${machine_bootstrapped+x} ]; then
        __process_msg "Setting machine bootstrap status from global setting"
        local bootstrapped_status=$(cat $STATE_FILE |
          jq -r '.installStatus.machinesBootstrapped')
        machine_bootstrapped=$bootstrapped_status
        local machine_update=$(cat $STATE_FILE |
          jq '.machines |=
          map (
            if .name=="'$machine_name'" then
              .isBootstrapped="'$bootstrapped_status'"
            else
              .
            end)'
        )
        _update_state "$machine_update"
      fi

      if [ $machine_bootstrapped == false ]; then
        __process_msg "Machine: $name not bootstrapped, processing"
        update_ssh_key
        check_connection
        check_requirements
        export_language
        setup_node
        bootstrap
        install_ntp
        local machine_update=$(cat $STATE_FILE |
          jq '.machines |=
          map (
            if .name=="'$machine_name'" then
              .isBootstrapped=true
            else
              .
            end)'
        )
        _update_state "$machine_update"
      else
        __process_msg "Machine: $name already bootstrapped, skipping"
      fi
    done
  else
    __process_msg "Bootstrapping machines in local mode"
    local machines_list=$(cat $STATE_FILE \
      | jq '.machines')
    local machine_count=$(echo $machines_list \
      | jq -r '. | length')

    if [ $machine_count -eq 0 ]; then
      __process_msg "Adding a dummy  machine in state file for localhost"
      local update=$(cat $STATE_FILE \
        | jq '.machines=[{
          "name": "localhost",
          "group": "core",
          "ip": "127.0.0.1",
          "sshSuccessful": "true",
          "isBootstrapped": "false"
        }]'
        )
      _update_state "$update"
    else
      __process_msg "localhost already present in state file, skipping"
    fi

    local machine=$(cat $STATE_FILE \
      | jq '.machines[0]')
    local machine_name=$(echo $machine \
      | jq -r '.name')
    local machine_bootstrapped=$(echo $machine \
      | jq -r '.isBootstrapped')

    if [ $machine_bootstrapped == false ]; then
      bootstrap_local
      local machine_update=$(cat $STATE_FILE |
        jq '.machines |=
        map (
          if .name=="'$machine_name'" then
            .isBootstrapped=true
          else
            .
          end)'
      )
      _update_state "$machine_update"
    else
      __process_msg "machine $machine_name already bootstrapped, skipping"
    fi
  fi
}

main
