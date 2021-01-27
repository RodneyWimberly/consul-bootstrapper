#!/bin/sh

set -e
source "${CONSUL_SCRIPT_DIR}"/common_functions.sh
if [ -z "$CONSUL_ENABLE_ACL" ] || [ "$CONSUL_ENABLE_ACL" -eq "0" ] ; then
    log_warning "ACLs is disabled, skipping configuration"
    log "Creating dummy general_acl_token.json file so the clients can start"

    mkdir -p ${CONSUL_BOOTSTRAP_DIR}
    echo "{}" > ${CONSUL_BOOTSTRAP_DIR}/general_acl_token.json
    exit 0
fi

log "Configuring ACL security"
# get our one-time boostrap token we can use to generate all other tokens. It can only be done once thus save the token
if [ ! -f ${CONSUL_BOOTSTRAP_DIR}/server_acl_master_token.json ]; then
    log_detail 'The server will remain in ACL Legacy mode unti an election occurs and a leader is chosen.'
    until [ ! -z ${ACL_MASTER_TOKEN} ]; do
        log_detail "Waiting 1 second before tring to obtain an ACL bootstrap token"
        sleep 1
        log_detail "Getting ACL bootstrap token / generating master token"
        ACL_RESPONSE=$(curl -sS -X PUT http://127.0.0.1:8500/v1/acl/bootstrap)
        echo "${ACL_RESPONSE} "
        ACL_MASTER_TOKEN=$(echo ${ACL_RESPONSE} | jq -r -M '.ID')
        export CONSUL_HTTP_TOKEN=${ACL_MASTER_TOKEN}
    done
    log "Master token  ${ACL_MASTER_TOKEN} was generated"
	# save our token
	cat > ${CONSUL_BOOTSTRAP_DIR}/server_acl_master_token.json <<EOL
{
  "acl_master_token": "${ACL_MASTER_TOKEN}"
}
EOL
merge_json "server_acl_master_token.json"
fi

${CONSUL_SCRIPT_DIR}/server_acl_server_agent_token.sh
${CONSUL_SCRIPT_DIR}/server_acl_anon.sh
${CONSUL_SCRIPT_DIR}/server_acl_client_general_token.sh
