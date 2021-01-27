#!/bin/sh

set -e
source "${CONSUL_SCRIPT_DIR}"/common_functions.sh
# fairly odd we actually need to add an agent acl token to the server since the server has an acl_master_token
# but well... this lets us get rid of
# [WARN] agent: Node info update blocked by ACLs
# [WARN] agent: Coordinate update blocked by ACLs
if [ -f ${CONSUL_BOOTSTRAP_DIR}/server_acl_agent_acl_token.json ]; then
    current_acl_agent_token=$(cat ${CONSUL_BOOTSTRAP_DIR}/server_acl_agent_acl_token.json | jq -r -M '.acl_agent_token')
fi

if [ ! -f ${CONSUL_BOOTSTRAP_DIR}/server_acl_agent_acl_token.json ] || \
  [ ! -f ${CONSUL_BOOTSTRAP_DIR}/server_general_acl_token.json ] || \
  [ -z "${current_acl_agent_token}" ]; then

    log "Configuring server agent token to let the server access by ACLs"
    ACL_MASTER_TOKEN=`cat ${CONSUL_BOOTSTRAP_DIR}/server_acl_master_token.json | jq -r -M '.acl_master_token'`

    # this is actually not neede with 1.0 - thats the defaul. So no permissions at all
    ACL_AGENT_TOKEN=`curl -sS -X PUT --header "X-Consul-Token: ${ACL_MASTER_TOKEN}" \
        --data \
    '{
      "Name": "Server agent token",
      "Type": "client",
      "Rules": "agent \"\" { policy = \"write\" } event \"\" { policy = \"read\" } key \"\" { policy = \"write\" } node \"\" { policy = \"write\" } service \"\" { policy = \"write\" } operator = \"read\""
    }' http://127.0.0.1:8500/v1/acl/create | jq -r -M '.ID'`

    if [ -z "$ACL_AGENT_TOKEN" ]; then
      log_error "error generating ACL agent token, return acl token was empty when talking the the REST endpoint - no permissions?"
    else
      log "Configuring acl agent token for the server"
      echo "{\"acl_agent_token\": \"${ACL_AGENT_TOKEN}\"}" > ${CONSUL_BOOTSTRAP_DIR}/server_acl_agent_acl_token.json
      merge_json "server_acl_agent_acl_token.json"

      log "Configuring acl token for the server"
      echo "{\"acl_token\": \"${ACL_AGENT_TOKEN}\"}" > ${CONSUL_BOOTSTRAP_DIR}/server_general_acl_token.json
      merge_json "server_general_acl_token.json"
    fi
else
    log "Skipping acl_agent_token setup .. already configured";
fi
