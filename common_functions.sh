#!/bin/sh

if [[ -f ./consul.env ]]; then
  source ./consul.env
elif [[ -f /usr/local/scripts/consul.env ]]; then
  source /usr/local/scripts/consul.env
elif [[ -f /tmp/consul/scripts/consul.env ]]; then
  source /tmp/consul/scripts/consul.env
fi

function configure_acl() {
  log "Starting server in 'local only' mode. The ACL will be in legacy mode until a leader is elected."
  log_detail "Server will be started in 'local only' mode to not allow node registering while bootstrapping"
  docker-entrypoint.sh agent -server=true -bootstrap-expect=1 -datacenter=${CONSUL_DATACENTER} -bind=127.0.0.1 &
    consul_pid="$!"

  log_detail "waiting for the server to come up"
  ${CONSUL_SCRIPT_DIR}/wait-for-it.sh --timeout=300 --host=127.0.0.1 --port=8500 --strict -- echo "consul found" || (echo "Failed to locate consul" && exit 1)

  log_detail "waiting further 15 seconds to ensure a leader has been elected"
  sleep 15s

  log_detail "continuing the cluster bootstrapping process"
  ${CONSUL_SCRIPT_DIR}/server_acl.sh

  log "Creating Consul cluster backups"
  backup_file="${CONSUL_BOOTSTRAP_DIR}/backup_$(date +%Y-%m-%d-%s).snap"

  log_detail "snapshot will be saved as ${backup_file} "
  ACL_MASTER_TOKEN=`cat ${CONSUL_BOOTSTRAP_DIR}/server_acl_master_token.json | jq -r -M '.acl_master_token'`
  curl --header "X-Consul-Token: ${ACL_MASTER_TOKEN}" http://127.0.0.1:8500/v1/snapshot?dc=docker -o ${backup_file}

  log "Shutting down 'local only' server (pid: ${consul_pid}) and then starting usual server"
  kill ${1}

  log_detail "wait for the 'local only' server to fully shutdown - 10 seconds"
  sleep 10s

  log_detail "Removing 'local only' configuration and updating it with the newly generated configuration"
  rm -f "${CONSUL_CONFIG_DIR}/server_acl.json"
  cp "${CONSUL_BOOTSTRAP_DIR}/generated.json" "${CONSUL_CONFIG_DIR}/generated.json"

  log_detail "all generated output is being copied to ${CONSUL_BACKUP_DIR}"
  cp -r "${CONSUL_BOOTSTRAP_DIR}/" "${CONSUL_BACKUP_DIR}/"
}

function consul_cmd() (
  consul_container="$(docker stack ps -q -f name=${CONSUL_STACK_PROJECT_NAME}_consul ${CONSUL_STACK_PROJECT_NAME})"
  if [ -z CONSUL_HTTP_TOKEN ] || [ CONSUL_HTTP_TOKEN -eq "0" ]; then
    docker exec "${consul_container}" consul "$@"
  else
    docker exec "${consul_container}" -e CONSUL_HTTP_TOKEN consul "$@"
  fi
)

function add_path() {
  export PATH=$1:${PATH}
  log "PATH has been updated to ${PATH} "
}

function docker_api() {
  docker_api_url="http://localhost/${1}"
  docker_api_method="${2}"
  if [[ -z "${docker_api_method}" ]]; then
    docker_api_method="GET"
  fi

  curl -sS --connect-timeout 180 --unix-socket /var/run/docker.sock -X "${docker_api_method}" "${docker_api_url}"
}

function consul_api() {
  consul_api_url=http://127.0.0.1:8500/v1/"${1}"

  consul_api_method="${2}"
  if [[ -z "${consul_api_method}" ]]; then
    consul_api_method="GET"
  fi

  consul_api_data=""
  if [[ -z "${3}" ]]; then
    consul_api_data="--data ${3}"
  fi

  current_acl_agent_token=$(cat ${CONSUL_BOOTSTRAP_DIR}/server_acl_agent_acl_token.json | jq -r -M '.acl_agent_token')
  consul_api_token=""
  if [[ -z "${current_acl_agent_token}" ]]; then
    consul_api_token="--header X-Consul-Token: ${current_acl_agent_token}"
  fi
  curl -sS -X "${consul_api_token}" "${consul_api_method}" "${consul_api_data}" "${consul_api_url}"
}

function get_json_property() {
  if [[ -f "$1" ]]; then
    cat "$1" | jq -r -M ".${2}"
  else
    echo "$1" | jq -r -M ".${2}"
  fi
}

function keep_service_alive() {
  while [[ "${CONSUL_KEEP_SERVICE_ALIVE}" -eq "1" ]]; do
    echo "Sleeping so that container will stay running and can be accessed."
    sleep 300
  done
}

function log() {
  log_raw "[INF] $1"
}

function log_detail() {
  log_raw "[DTL]  ====> $1"
}

function log_error() {
  log_raw "[ERR] $1"
}

function log_warning() {
  log_raw "[WAR] $1"
}

function log_debug() {
  if [ ! -z "$CONSUL_DEBUG_LOG" ] && [ "$CONSUL_DEBUG_LOG" -ne "0" ] ; then
    log_raw "[DBG] $1"
  fi
}

function log_json() {
  if [ ! -z "$CONSUL_DEBUG_LOG" ] && [ "$CONSUL_DEBUG_LOG" -ne "0" ] ; then
    echo "1 ${1}"
    echo "2 ${2}"
    pretty_json=$(echo "${2}" | jq)
    echo "JSON ${pretty_json}"
    log_raw "[DBG] $1: ${pretty_json}"
  fi
}

function log_raw() {
  echo "$(timestamp): $1"
}

function timestamp() {
  date +"%T"
}

function merge_json() {
  generated_json="{}"
  if [ -f ${CONSUL_BOOTSTRAP_DIR}/generated.json ]; then
    generated_json=$(cat ${CONSUL_BOOTSTRAP_DIR}/generated.json)
    rm -f ${CONSUL_BOOTSTRAP_DIR}/generated.json
  fi
  config_json=$(cat ${CONSUL_BOOTSTRAP_DIR}/${1})
  generated_json=$(echo "${generated_json}" | jq ". + ${config_json}")
  log_detail "Adding ${1} to generated.json"
  echo "${generated_json}" | jq ". + ${config_json}" > ${CONSUL_BOOTSTRAP_DIR}/generated.json
}

function expand_config_file_from() {
  set +e
  log "Processing ${CONSUL_BOOTSTRAP_DIR}/$1 with variable expansion to ${CONSUL_CONFIG_DIR}/$1"
  rm -f "${CONSUL_CONFIG_DIR}/$1"
  cat "${CONSUL_BOOTSTRAP_DIR}/$1" | envsubst > "${CONSUL_CONFIG_DIR}/$1"
  set -e
}

function get_docker_details() {
  NODE_INFO=$(docker_api "info")
  export NUM_OF_MGR_NODES=$(echo ${NODE_INFO} | jq -r -M '.Swarm.Managers')
  export NODE_IP=$(echo ${NODE_INFO} | jq -r -M '.Swarm.NodeAddr')
  export NODE_ID=$(echo ${NODE_INFO} | jq -r -M '.Swarm.NodeID')
  export NODE_NAME=$(echo ${NODE_INFO} | jq -r -M '.Name')
  export NODE_IS_MANAGER=$(echo ${NODE_INFO} | jq -r -M '.Swarm.ControlAvailable')
}

function show_docker_details() {
    log ">=>=>=>=>=>  Swarm/Node Details  <=<=<=<=<=<"
    log "Number of Manager Nodes: ${NUM_OF_MGR_NODES}"
    log "Node IP: ${NODE_IP}"
    log "Node ID: ${NODE_ID}"
    log "Node Name: ${NODE_NAME}"
    log "Node Is Manager: ${NODE_IS_MANAGER}"
}

function wait_for_bootstrap_process() {
  if [ -z "$CONSUL_HTTP_TOKEN" ] || [ "$CONSUL_HTTP_TOKEN" -eq "0" ] ; then
    log_detail 'Waiting 60 seconds before inquiring if the Consul cluster bootstrapping service to be complete'
    sleep 60
    log "Querying the bootstrap process to see if it has completed."
    while [[ ! curl -sS -X http://consul-bootstrapper.service.consul/cluster.bootstrapped ]]; do
      sleep 5
      log_detail "re-querying the bootstrap process to see if it has completed."
    done
    log_detail "The consul cluster has been successfully bootstrapped."
    log "need to update config"
    exit 1
    fi
  else
    log_detail "The master ACL Token is present so skipping the bootstrap process."
  fi
}

