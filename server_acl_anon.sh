#!/bin/sh

set -e
source "${CONSUL_SCRIPT_DIR}"/common_functions.sh
# locks down our consul server from leaking any data to anybody - full anon block
if [ ! -f ${CONSUL_BOOTSTRAP_DIR}/.aclanonsetup ]; then
    log "Configuring anon access"

    ACL_MASTER_TOKEN=`cat ${CONSUL_BOOTSTRAP_DIR}/server_acl_master_token.json | jq -r -M '.acl_master_token'`
    # this is actually not needed with 1.0 - thats the defaul. So no permissions at all
    curl -sS -X PUT --header "X-Consul-Token: ${ACL_MASTER_TOKEN}" \
        --data \
    '{
      "Name": "Anonymous token",
      "ID": "anonymous",
      "Type": "client",
      "Rules": "node \"\" { policy = \"deny\" }"
    }' http://127.0.0.1:8500/v1/acl/update > /dev/null

    touch ${CONSUL_BOOTSTRAP_DIR}/.aclanonsetup
else
    log "Skipping acl_anon setup .. already configured";
fi

