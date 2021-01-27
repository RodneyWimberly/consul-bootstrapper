#!/bin/sh

source "${CONSUL_SCRIPT_DIR}"/consul.env
source "${CONSUL_SCRIPT_DIR}"/common_functions.sh

log "Bootstrapping the current cluster, Please Wait..."

pkill consul

set -e

add_path ${CONSUL_SCRIPT_DIR}
current_acl_agent_token=$(cat ${CONSUL_CONFIG_DIR}/server.json | jq -r -M '.acl_agent_token')
if [ -z "${current_acl_agent_token}" ] || [ -f  ${CONSUL_BOOTSTRAP_DIR}/cluster.bootstrapped ]; then
  if [ -z "$CONSUL_ENABLE_ACL" ] || [ "$CONSUL_ENABLE_ACL" -eq "0" ]; then
    if [ -f ${CONSUL_BOOTSTRAP_DIR}/.aclanonsetup ]; then
      log_warning "ACL flag is no longer present, removing the ACL configuration"
      rm -f ${CONSUL_BOOTSTRAP_DIR}/.aclanonsetup \
        ${CONSUL_BOOTSTRAP_DIR}/general_acl_token.json \
        ${CONSUL_BOOTSTRAP_DIR}/server_acl_master_token.json \
        ${CONSUL_BOOTSTRAP_DIR}/server_acl_agent_acl_token.json
    fi
  elif [ ! -f ${CONSUL_BOOTSTRAP_DIR}/.aclanonsetup ] || \
    [ ! -f ${CONSUL_BOOTSTRAP_DIR}/general_acl_token.json ] ||  \
    [ ! -f ${CONSUL_BOOTSTRAP_DIR}/server_acl_master_token.json ] || \
    [ ! -f ${CONSUL_BOOTSTRAP_DIR}/server_acl_agent_acl_token.json ] || \
    [ -z "${current_acl_agent_token}" ]; then

    log_warning "ACL is misconfigured / outdated"
    configure_acl
  else
    log_detail "Cluster has already been bootstrapped and is correctly configured."
  fi
else
  ${CONSUL_SCRIPT_DIR}/server_tls.sh `hostname -f`
  ${CONSUL_SCRIPT_DIR}/server_gossip.sh

  log "Configuring ACL support before we start the server"
  echo "{ \"acl\": { \"enabled\": true, \"default_policy\": \"deny\", \"down_policy\": \"deny\" } }" > ${CONSUL_BOOTSTRAP_DIR}/server_acl.json
  merge_json "server_acl.json"
  cp "${CONSUL_BOOTSTRAP_DIR}/server_acl.json" "${CONSUL_CONFIG_DIR}/server_acl.json"

  configure_acl

  log "Updating db that the cluster bootstrapping process is complete and the startup restriction has been removed"
  touch ${CONSUL_BOOTSTRAP_DIR}/cluster.bootstrapped

  log "Starting file server so other clients can acquire the newly bootstrapped configuration"
  nginx-entrypoint.sh "$@"
fi
