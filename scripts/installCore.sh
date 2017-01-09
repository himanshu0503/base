readonly CORE_COMPONENTS="postgresql \
  vault \
  gitlab \
  swarm \
  rabbitmq"

###########################################################
export CORE_COMPONENTS_LIST=""
export CORE_MACHINES_LIST=""
export SKIP_STEP=false

_update_install_status() {
  local update=$(cat $STATE_FILE | jq '.installStatus.'"$1"'='true'')
  _update_state "$update"
}

_check_component_status() {
  local status=$(cat $STATE_FILE | jq '.installStatus.'"$1"'')
  if [ "$status" == true ]; then
    SKIP_STEP=true;
  fi
}

ensure_updated_packages() {
  if [ "$UPDATED_APT_PACKAGES" == false ]; then
    __process_msg "Installing core components on machines"
    local machines_list=$(cat $STATE_FILE | jq '[ .machines[] ]')
    local machines_count=$(echo $machines_list | jq '. | length')
    for i in $(seq 1 $machine_count); do
      local machine=$(echo $machines_list | jq '.['"$i-1"']')
      local host=$(echo $machine | jq '.ip')
      _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/installBase.sh" "$SCRIPT_DIR_REMOTE"
      _exec_remote_cmd "$host" "$SCRIPT_DIR_REMOTE/installBase.sh"
    done
    UPDATED_APT_PACKAGES=true
  fi
}

configure_swarm_master() {
  __process_msg "Configuring swarm master"
  source "$SCRIPTS_DIR/_manageDockerMaster.sh"
}

configure_swarm_workers() {
  __process_msg "Configuring swarm workers"
  source "$SCRIPTS_DIR/_manageDockerWorkers.sh"
}

install_docker_local() {
  SKIP_STEP=false
  _check_component_status "dockerInstalled"
  if [ "$SKIP_STEP" == false ]; then
    __process_msg "Checking Docker on localhost"
    source "$REMOTE_SCRIPTS_DIR/installDocker.sh" "$INSTALL_MODE"

    _update_install_status "dockerInstalled"
    _update_install_status "dockerInitialized"
  else
    __process_msg "Docker already installed, skipping"
    __process_msg "Docker already initialized, skipping"
  fi
}

initialize_docker_local() {
  __process_msg "Updating docker credentials to pull shippable images"

  local credentials_template="$REMOTE_SCRIPTS_DIR/credentials.template"
  local credentials_file="$REMOTE_SCRIPTS_DIR/credentials"

  __process_msg "Updating : installerAccessKey"
  local aws_access_key=$(cat $STATE_FILE | jq -r '.systemSettings.installerAccessKey')
  if [ -z "$aws_access_key" ]; then
    __process_msg "Please update 'systemSettings.installerAccessKey' in state.json and run installer again"
    exit 1
  fi

  sed "s#{{aws_access_key}}#$aws_access_key#g" $credentials_template > $credentials_file

  __process_msg "Updating : installerSecretKey"
  local aws_secret_key=$(cat $STATE_FILE | jq -r '.systemSettings.installerSecretKey')
  if [ -z "$aws_secret_key" ]; then
    __process_msg "Please update 'systemSettings.installerSecretKey' in state.json and run installer again"
    exit 1
  fi
  sed -i "s#{{aws_secret_key}}#$aws_secret_key#g" $credentials_file

  mkdir -p ~/.aws
  cp -v $credentials_file $HOME/.aws/
  echo "aws ecr --region us-east-1 get-login" | sudo tee /tmp/docker_login.sh
  sudo chmod +x /tmp/docker_login.sh
  local docker_login_cmd=$(eval "/tmp/docker_login.sh")
  __process_msg "Docker login generated, logging into ecr "
  eval "$docker_login_cmd"
}

install_compose(){
  SKIP_STEP=false
  _check_component_status "composeInstalled"
  if [ "$SKIP_STEP" == false ]; then
    if ! type "docker-compose" > /dev/null; then
      echo "Downloading docker compose"
      local download_compose_exc=$(wget https://github.com/docker/compose/releases/download/1.8.1/docker-compose-`uname -s`-`uname -m` -O /tmp/docker-compose)
      echo "$download_compose_exc"

      sudo chmod +x /tmp/docker-compose
      local extract_compose_exc=$(sudo mv /tmp/docker-compose /usr/local/bin/)
      echo "$extract_compose_exc"

      sudo docker-compose --version
    fi
    _update_install_status "composeInstalled"
  else
    __process_msg "Docker compose already, installed, skipping"
    sudo docker-compose --version
  fi
}

install_database() {
  SKIP_STEP=false
  _check_component_status "databaseInstalled"
  if [ "$SKIP_STEP" = false ]; then
    ensure_updated_packages
    __process_msg "Installing Database"
    local db_host=$(cat $STATE_FILE | jq '.machines[] | select (.group=="core" and .name=="db")')
    local host=$(echo $db_host | jq '.ip')
    ##TODO:
    # - prommt user for db username and password
    # - copy the installation script to remote machine
    # - run sed command to replace username/password with user input
    # - once complete, save the values in satefile
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/installPostgresql.sh" "$SCRIPT_DIR_REMOTE"
    _exec_remote_cmd "$host" "$SCRIPT_DIR_REMOTE/installPostgresql.sh"
    __process_msg "Waiting 30s for postgres to boot"
    sleep 30s
    _update_install_status "databaseInstalled"
  else
    __process_msg "Database already installed, skipping"
    __process_msg "Database already initialized, skipping"
  fi
}

install_database_local() {
  SKIP_STEP=false
  _check_component_status "databaseInstalled"

  if [ "$SKIP_STEP" = false ]; then
    __process_msg "Installing Database"

    sudo docker-compose -f $LOCAL_SCRIPTS_DIR/services.yml up -d postgres
    __process_msg "Waiting 30s for postgres to boot"
    sleep 30s

    _update_install_status "databaseInstalled"
  else
    __process_msg "Database already installed, skipping"
  fi
}

save_db_credentials_in_statefile() {
  SKIP_STEP=false
  _check_component_status "databaseInitialized"

  if [ "$SKIP_STEP" = false ]; then
    __process_msg "Saving database credentials in state file"
    local db_host=$(cat $STATE_FILE | jq '.machines[] | select (.group=="core" and .name=="db")')
    local db_ip=$(echo $db_host | jq -r '.ip')
    local db_port=5432
    local db_address=$db_ip":"$db_port

    db_name="shipdb"
    db_username="apiuser"
    db_password="testing1234"
    db_dialect="postgres"

    result=$(cat $STATE_FILE | jq '.systemSettings.dbHost = "'$db_ip'"')
    update=$(echo $result | jq '.' | tee $STATE_FILE)

    result=$(cat $STATE_FILE | jq '.systemSettings.dbDialect = "'$db_dialect'"')
    update=$(echo $result | jq '.' | tee $STATE_FILE)

    result=$(cat $STATE_FILE | jq '.systemSettings.dbPort = "'$db_port'"')
    update=$(echo $result | jq '.' | tee $STATE_FILE)

    result=$(cat $STATE_FILE | jq '.systemSettings.dbname = "'$db_name'"')
    update=$(echo $result | jq '.' | tee $STATE_FILE)

    result=$(cat $STATE_FILE | jq '.systemSettings.dbUsername = "'$db_username'"')
    update=$(echo $result | jq '.' | tee $STATE_FILE)

    result=$(cat $STATE_FILE | jq '.systemSettings.dbPassword = "'$db_password'"')
    update=$(echo $result | jq '.' | tee $STATE_FILE)

    result=$(cat $STATE_FILE | jq '.systemSettings.dbUrl = "'$db_address'"')
    update=$(echo $result | jq '.' | tee $STATE_FILE)

    _update_install_status "databaseInitialized"
  else
    __process_msg "Database already initialized, skipping"
  fi
}

save_db_credentials_in_statefile_local() {
  __process_msg "Saving database credentials in state file local"
  local db_ip=172.17.42.1
  local db_port=5432
  local db_address=$db_ip":"$db_port

  db_name="shipdb"
  db_username="apiuser"
  db_password="testing1234"
  db_dialect="postgres"

  result=$(cat $STATE_FILE | jq '.systemSettings.dbHost = "'$db_ip'"')
  update=$(echo $result | jq '.' | tee $STATE_FILE)

  result=$(cat $STATE_FILE | jq '.systemSettings.dbDialect = "'$db_dialect'"')
  update=$(echo $result | jq '.' | tee $STATE_FILE)

  result=$(cat $STATE_FILE | jq '.systemSettings.dbPort = "'$db_port'"')
  update=$(echo $result | jq '.' | tee $STATE_FILE)

  result=$(cat $STATE_FILE | jq '.systemSettings.dbname = "'$db_name'"')
  update=$(echo $result | jq '.' | tee $STATE_FILE)

  result=$(cat $STATE_FILE | jq '.systemSettings.dbUsername = "'$db_username'"')
  update=$(echo $result | jq '.' | tee $STATE_FILE)

  result=$(cat $STATE_FILE | jq '.systemSettings.dbPassword = "'$db_password'"')
  update=$(echo $result | jq '.' | tee $STATE_FILE)

  result=$(cat $STATE_FILE | jq '.systemSettings.dbUrl = "'$db_address'"')
  update=$(echo $result | jq '.' | tee $STATE_FILE)

}

initialize_database_local() {
  SKIP_STEP=false
  _check_component_status "databaseInitialized"

  if [ "$SKIP_STEP" = false ]; then
    __process_msg "Initializing Database"
    local db_ip=172.17.42.1
    local db_port=5432
    local db_username=$(cat $STATE_FILE | jq -r '.systemSettings.dbUsername')
    local db_name=$(cat $STATE_FILE | jq -r '.systemSettings.dbname')

    local vault_migrations_file="$REMOTE_SCRIPTS_DIR/vault_kv_store.sql"
    local db_mount_dir="$LOCAL_SCRIPTS_DIR/data"

    sudo cp -vr $vault_migrations_file $db_mount_dir
    sudo docker exec local_postgres_1 psql -U $db_username -d $db_name -f /tmp/data/vault_kv_store.sql

    _update_install_status "databaseInitialized"
  else
    __process_msg "Database already initialized, skipping"
  fi
}

save_db_credentials() {
  __process_msg "Saving database credentials"
  local db_host=$(cat $STATE_FILE | jq '.machines[] | select (.group=="core" and .name=="db")')
  local host=$(echo $db_host | jq '.ip')
  local db_ip=$(echo $db_host | jq '.ip')
  local db_port=5432
  local db_username=$(cat $STATE_FILE | jq -r '.systemSettings.dbUsername')
  local db_password=$(cat $STATE_FILE | jq -r '.systemSettings.dbPassword')
  local db_address=$db_ip:$db_port

  #TODO: fetch db_name from state.json
  # make substitutions locally and then push
  local db_name="shipdb"

  _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/.pgpass" "/root/"
  _exec_remote_cmd $host "sed -i \"s/{{address}}/$db_address/g\" /root/.pgpass"
  _exec_remote_cmd $host "sed -i \"s/{{database}}/$db_name/g\" /root/.pgpass"
  _exec_remote_cmd $host "sed -i \"s/{{username}}/$db_username/g\" /root/.pgpass"
  _exec_remote_cmd $host "sed -i \"s/{{password}}/$db_password/g\" /root/.pgpass"
  _exec_remote_cmd $host "chmod 0600 /root/.pgpass"
}

install_vault() {
  local vault_host=$(cat $STATE_FILE | jq '.machines[] | select (.group=="core" and .name=="db")')
  local host=$(echo $vault_host | jq '.ip')

  SKIP_STEP=false
  _check_component_status "vaultInstalled"
  if [ "$SKIP_STEP" = false ]; then
    ensure_updated_packages
    __process_msg "Installing Vault"
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/installVault.sh" "$SCRIPT_DIR_REMOTE"
    _exec_remote_cmd "$host" "$SCRIPT_DIR_REMOTE/installVault.sh"
    _update_install_status "vaultInstalled"
  else
    __process_msg "Vault already installed, skipping"
  fi
}

initialize_vault() {
  local vault_host=$(cat $STATE_FILE | jq '.machines[] | select (.group=="core" and .name=="db")')
  local host=$(echo $vault_host | jq '.ip')

  SKIP_STEP=false
  _check_component_status "vaultInitialized"
  if [ "$SKIP_STEP" = false ]; then
    local vault_url=$host

    local db_host=$(cat $STATE_FILE | jq '.machines[] | select (.group=="core" and .name=="db")')
    local db_ip=$(echo $db_host | jq '.ip')
    local db_port=5432
    local db_username=$(cat $STATE_FILE | jq '.systemSettings.dbUsername')
    local db_address=$db_ip:$db_port

    local db_name="shipdb"
    local VAULT_JSON_FILE="/etc/vault.d/vaultConfig.json"

    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/vault.hcl" "/etc/vault.d/"
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/policy.hcl" "/etc/vault.d/"
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/vault_kv_store.sql" "/etc/vault.d/"
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/vault.conf" "/etc/init/"
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/vaultConfig.json" "/etc/vault.d/"

    _exec_remote_cmd $host "sed -i \"s/{{DB_USERNAME}}/$db_username/g\" /etc/vault.d/vault.hcl"
    _exec_remote_cmd $host "sed -i \"s/{{DB_PASSWORD}}/$db_password/g\" /etc/vault.d/vault.hcl"
    _exec_remote_cmd $host "sed -i \"s/{{DB_ADDRESS}}/$db_address/g\" /etc/vault.d/vault.hcl"

    _exec_remote_cmd $host "psql -U $db_username -h $db_ip -d $db_name -w -f /etc/vault.d/vault_kv_store.sql"

    _exec_remote_cmd $host "service vault start || true"

    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/bootstrapVault.sh" "$SCRIPT_DIR_REMOTE"
    _exec_remote_cmd_proxyless "$host" "$SCRIPT_DIR_REMOTE/bootstrapVault.sh $db_username $db_name $db_ip $vault_url"

    __process_msg "Saving vault credentials in state.json"
    local VAULT_FILE="/tmp/shippable/vaultConfig.json"
    local VAULT_JSON_FILE="/etc/vault.d/vaultConfig.json"

    local vault_host=$(cat $STATE_FILE | jq '.machines[] | select (.group=="core" and .name=="db")')
    local host=$(echo $vault_host | jq -r '.ip')
    local vault_url="http://$host:8200"
    result=$(cat $STATE_FILE | jq -r '.systemSettings.vaultUrl = "'$vault_url'"')
    update=$(echo $result | jq '.' | tee $STATE_FILE)

    _copy_script_local $host $VAULT_JSON_FILE

    local vault_token=$(cat $VAULT_FILE | jq -r '.vaultToken')
    result=$(cat $STATE_FILE | jq -r '.systemSettings.vaultToken = "'$vault_token'"')
    update=$(echo $result | jq '.' | tee $STATE_FILE)
    __process_msg "Vault credentials successfully saved to state.json"
    _update_install_status "vaultInitialized"
  else
    __process_msg "Vault already initialized, skipping"
  fi
}

install_vault_local() {
  SKIP_STEP=false
  _check_component_status "vaultInstalled"
  if [ "$SKIP_STEP" = false ]; then
    __process_msg "Installing Vault"

    sudo docker-compose -f $LOCAL_SCRIPTS_DIR/services.yml up -d vault

    __process_msg "Waiting 10s for vault to boot"
    sleep 10s

    _update_install_status "vaultInstalled"
  else
    __process_msg "Vault already installed, skipping"
  fi
}

initialize_vault_local() {
  SKIP_STEP=false
  _check_component_status "vaultInitialized"
  if [ "$SKIP_STEP" = false ]; then
    __process_msg "Initializing Vault"
    docker exec -it local_vault_1 sh -c '/vault/config/scripts/bootstrap.sh'
    local vault_config_dir="$LOCAL_SCRIPTS_DIR/vault"
    local vault_token_file="$vault_config_dir/scripts/vaultToken.json"
    local vault_token=$(cat "$vault_token_file" | jq -r '.vaultToken')
    __process_msg "Generated vault token $vault_token"


    result=$(cat $STATE_FILE | jq -r '.systemSettings.vaultToken = "'$vault_token'"')
    update=$(echo $result | jq '.' | tee $STATE_FILE)

    local vault_url="http://172.17.42.1:8200"
    result=$(cat $STATE_FILE | jq -r '.systemSettings.vaultUrl = "'$vault_url'"')
    update=$(echo $result | jq '.' | tee $STATE_FILE)

    _update_install_status "vaultInitialized"
  else
    __process_msg "Vault already initialized, skipping"
  fi
}

install_rabbitmq() {
  local db_host=$(cat $STATE_FILE \
    | jq '.machines[] | select (.group=="core" and .name=="db")')
  local host=$(echo $db_host \
    | jq -r '.ip')

  SKIP_STEP=false
  _check_component_status "rabbitmqInstalled"
  if [ "$SKIP_STEP" = false ]; then
    ensure_updated_packages
    __process_msg "Installing RabbitMQ"
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/installRabbit.sh" "$SCRIPT_DIR_REMOTE"
    _exec_remote_cmd "$host" "$SCRIPT_DIR_REMOTE/installRabbit.sh"

    _update_install_status "rabbitmqInstalled"
  else
    __process_msg "RabbitMQ already installed, skipping"
  fi

  _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/rabbitmqadmin" "$SCRIPT_DIR_REMOTE"

  SKIP_STEP=false
  _check_component_status "rabbitmqInitialized"
  if [ "$SKIP_STEP" = false ]; then
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/bootstrapRabbit.sh" "$SCRIPT_DIR_REMOTE"
    _exec_remote_cmd "$host" "$SCRIPT_DIR_REMOTE/bootstrapRabbit.sh"

    local amqp_host=$host
    local amqp_url=$(cat $STATE_FILE \
      | jq -r '.systemSettings.amqpUrl')
    local amqp_url_admin=$(cat $STATE_FILE \
      | jq -r '.systemSettings.amqpUrlAdmin')
    local amqp_host_state=$(python -c "from urlparse import urlparse; print urlparse('$amqp_url').hostname")
    local amqp_port=$(python -c "from urlparse import urlparse; print urlparse('$amqp_url').port")
    local amqp_user=$(python -c "from urlparse import urlparse; print urlparse('$amqp_url').username")
    local amqp_pass=$(python -c "from urlparse import urlparse; print urlparse('$amqp_url').password")
    local amqp_protocol=$(python -c "from urlparse import urlparse; print urlparse('$amqp_url').scheme")
    local amqp_admin_protocol=$(python -c "from urlparse import urlparse; print urlparse('$amqp_url_admin').scheme")
    local amqp_admin_port=$(python -c "from urlparse import urlparse; print urlparse('$amqp_url_admin').port")

    __process_msg "AMQP HOST in state file: $amqp_host_state"
    __process_msg "AMQP PORT in state file: $amqp_port"
    __process_msg "AMQP PROTOCOL in state file: $amqp_protocol"

    if [ -z "$amqp_port" ] || [ "$amqp_port" == "None" ]; then
      # hostname provided as a fqdn
      # this can only happen when user has manually updated it,
      # use the host from statefile

      amqp_host=$amqp_host_state
      local amqp_url_updated="$amqp_protocol://$amqp_user:$amqp_pass@$amqp_host/shippable"
      __process_msg "Amqp url: $amqp_url"
      local update=$(cat $STATE_FILE \
        | jq '.systemSettings.amqpUrl = "'$amqp_url_updated'"')
      update=$(echo $update | jq '.' | tee $STATE_FILE)

      local amqp_url_root="$amqp_protocol://$amqp_user:$amqp_pass@$amqp_host/shippableRoot"
      __process_msg "Amqp root url: $amqp_url_root"
      update=$(cat $STATE_FILE \
        | jq '.systemSettings.amqpUrlRoot = "'$amqp_url_root'"')
      update=$(echo $update | jq '.' | tee $STATE_FILE)

      local amqp_url_admin="$amqp_admin_protocol://$amqp_user:$amqp_pass@$amqp_host:$amqp_admin_port"
      __process_msg "Amqp admin url: $amqp_url_admin"
      update=$(cat $STATE_FILE \
        | jq '.systemSettings.amqpUrlAdmin = "'$amqp_url_admin'"')
      update=$(echo $update | jq '.' | tee $STATE_FILE)

    else
      # hostname provided as ip:port pair
      # use the ip of install box

      local amqp_url_updated="$amqp_protocol://$amqp_user:$amqp_pass@$amqp_host:$amqp_port/shippable"
      __process_msg "Amqp url: $amqp_url"
      local update=$(cat $STATE_FILE \
        | jq '.systemSettings.amqpUrl = "'$amqp_url_updated'"')
      update=$(echo $update | jq '.' | tee $STATE_FILE)

      local amqp_url_root="$amqp_protocol://$amqp_user:$amqp_pass@$amqp_host:$amqp_port/shippableRoot"
      __process_msg "Amqp root url: $amqp_url_root"
      update=$(cat $STATE_FILE \
        | jq '.systemSettings.amqpUrlRoot = "'$amqp_url_root'"')
      update=$(echo $update | jq '.' | tee $STATE_FILE)

      local amqp_url_admin="$amqp_admin_protocol://$amqp_user:$amqp_pass@$amqp_host:$amqp_admin_port"
      __process_msg "Amqp admin url: $amqp_url_admin"
      update=$(cat $STATE_FILE \
        | jq '.systemSettings.amqpUrlAdmin = "'$amqp_url_admin'"')
      update=$(echo $update | jq '.' | tee $STATE_FILE)
    fi

    _update_install_status "rabbitmqInitialized"
  else
    __process_msg "RabbitMQ already initialized, skipping"
  fi
}

install_rabbitmq_local() {
  SKIP_STEP=false
  _check_component_status "rabbitmqInstalled"
  if [ "$SKIP_STEP" = false ]; then
    __process_msg "Installing rabbitmq"

    sudo docker-compose -f $LOCAL_SCRIPTS_DIR/services.yml up -d message

    __process_msg "rabbitmq successfully installed"
    __process_msg "Waiting 10s for rabbitmq to boot"
    sleep 10s
    _update_install_status "rabbitmqInstalled"
  else
    __process_msg "rabbitmq already installed, skipping"
  fi
}

initialize_rabbitmq_local() {
  SKIP_STEP=false
  _check_component_status "rabbitmqInitialized"
  if [ "$SKIP_STEP" = false ]; then

    source "$LOCAL_SCRIPTS_DIR/bootstrapRabbit.sh"
    __process_msg "rabbitmq successfully initialized"

    _update_install_status "rabbitmqInitialized"
  else
    __process_msg "RabbitMQ already initialized, skipping"
  fi
}

install_gitlab() {
  SKIP_STEP=false
  _check_component_status "gitlabInitialized"
  if [ "$SKIP_STEP" = false ]; then
    ensure_updated_packages
    __process_msg "Installing Gitlab"
    local gitlab_host=$(cat $STATE_FILE | jq '.machines[] | select (.group=="core" and .name=="swarm")')
    local host=$(echo $gitlab_host | jq -r '.ip')
    local gitlab_system_int=$(cat $STATE_FILE | jq '.systemIntegrations[] | select (.name=="gitlab")')

    local gitlab_root_password=$(echo $gitlab_system_int | jq -r '.formJSONValues[]| select (.label=="password")|.value')
    local gitlab_external_url=$(echo $gitlab_system_int | jq -r '.formJSONValues[]| select (.label=="url")|.value')

    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/installGitlab.sh" "$SCRIPT_DIR_REMOTE"
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/gitlab.rb" "/etc/gitlab/"

    _exec_remote_cmd $host "sed -i \"s/{{gitlab_machine_url}}/$host/g\" /etc/gitlab/gitlab.rb"
    _exec_remote_cmd $host "sed -i \"s/{{gitlab_password}}/$gitlab_root_password/g\" /etc/gitlab/gitlab.rb"
    _exec_remote_cmd "$host" "$SCRIPT_DIR_REMOTE/installGitlab.sh"
    _update_install_status "gitlabInstalled"
    _update_install_status "gitlabInitialized"
  else
    __process_msg "Gitlab already installed, skipping"
    __process_msg "Gitlab already initialized, skipping"
  fi
}

install_gitlab_local() {
  SKIP_STEP=false
  _check_component_status "gitlabInstalled"
  if [ "$SKIP_STEP" = false ]; then
    __process_msg "Installing Gitlab"

    sudo docker-compose -f $LOCAL_SCRIPTS_DIR/services.yml up -d gitlab

    _update_install_status "gitlabInstalled"
  else
    __process_msg "Gitlab already installed, skipping"
  fi
}

install_ecr() {
  SKIP_STEP=false
  _check_component_status "ecrInitialized"
  if [ "$SKIP_STEP" = false ]; then
    ensure_updated_packages
    __process_msg "Installing Docker on management machine"
    local gitlab_host=$(cat $STATE_FILE | jq '.machines[] | select (.group=="core" and .name=="swarm")')
    local host=$(echo $gitlab_host | jq '.ip')
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/installEcr.sh" "$SCRIPT_DIR_REMOTE"
    _exec_remote_cmd "$host" "$SCRIPT_DIR_REMOTE/installEcr.sh"
    _update_install_status "ecrInstalled"
    _update_install_status "ecrInitialized"
  else
    __process_msg "ECR already installed, skipping"
    __process_msg "ECR already initialized, skipping"
  fi
}

install_ecr_local() {
  SKIP_STEP=false
  _check_component_status "ecrInitialized"
  if [ "$SKIP_STEP" = false ]; then
    __process_msg "Installing ECR on local machine"

    sudo apt-get -y install python-pip
    sudo pip install awscli==1.10.63

    _update_install_status "ecrInstalled"
    _update_install_status "ecrInitialized"
  else
    __process_msg "ECR already installed, skipping"
    __process_msg "ECR already initialized, skipping"
  fi
}


install_redis() {
  SKIP_STEP=false
  _check_component_status "redisInitialized"
  local redis_host=$(cat $STATE_FILE | jq '.machines[] | select (.group=="core" and .name=="db")')
  local host=$(echo $redis_host | jq '.ip')

  if [ "$SKIP_STEP" = false ]; then
    ensure_updated_packages
    __process_msg "Installing Redis"
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/redis.conf" "/etc/redis"
    _copy_script_remote $host "$REMOTE_SCRIPTS_DIR/installRedis.sh" "$SCRIPT_DIR_REMOTE"
    _exec_remote_cmd "$host" "$SCRIPT_DIR_REMOTE/installRedis.sh"
    _update_install_status "redisInstalled"
    _update_install_status "redisInitialized"
  else
    __process_msg "Redis already installed, skipping"
    __process_msg "Redis already initialized, skipping"
  fi

  local ip=$(echo $redis_host | jq -r '.ip')
  local redis_url="$ip:6379"
  #TODO : Fetch the redis port from the redis.conf
  result=$(cat $STATE_FILE | jq -r '.systemSettings.redisUrl = "'$redis_url'"')
  update=$(echo $result | jq '.' | tee $STATE_FILE)
}

install_redis_local() {
  SKIP_STEP=false
  _check_component_status "redisInstalled"

  if [ "$SKIP_STEP" = false ]; then
    __process_msg "Installing Redis"

    sudo docker-compose -f $LOCAL_SCRIPTS_DIR/services.yml up -d redis

    local redis_url="172.17.42.1:6379"
    result=$(cat $STATE_FILE | jq -r '.systemSettings.redisUrl = "'$redis_url'"')
    update=$(echo $result | jq '.' | tee $STATE_FILE)

    __process_msg "Redis successfully intalled"
    _update_install_status "redisInstalled"
    _update_install_status "redisInitialized"
  else
    __process_msg "Redis already installed, skipping"
  fi
}

main() {
  __process_marker "Installing core"
  if [ "$INSTALL_MODE" == "production" ]; then
    configure_swarm_master
    configure_swarm_workers
    install_database
    save_db_credentials_in_statefile
    save_db_credentials
    install_vault
    initialize_vault
    install_rabbitmq
    install_gitlab
    install_ecr
    install_redis
  else
    install_docker_local
    initialize_docker_local
    install_compose
    install_database_local
    save_db_credentials_in_statefile_local
    initialize_database_local
    install_vault_local
    initialize_vault_local
    install_rabbitmq_local
    initialize_rabbitmq_local
    install_gitlab_local
    install_ecr_local
    install_redis_local
  fi
}

main
