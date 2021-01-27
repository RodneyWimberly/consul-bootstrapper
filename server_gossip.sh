#!/bin/sh

set -e
source "${CONSUL_SCRIPT_DIR}"/common_functions.sh
if [ -z "${CONSUL_ENABLE_GOSSIP}" ] || [ "${CONSUL_ENABLE_GOSSIP}" -eq "0" ]; then
    log_warning "GOSSIP is disabled, skipping configuration"
    exit 0
fi

log "Configuring Gossip encryption"
if [ ! -f ${CONSUL_BOOTSTRAP_DIR}/gossip.json ]; then
    log "Generating new Gossip Encryption Key"
	GOSSIP_KEY=`consul keygen`
	echo "{\"encrypt\": \"${GOSSIP_KEY}\"}" > ${CONSUL_BOOTSTRAP_DIR}/gossip.json
    merge_json "gossip.json"
fi
