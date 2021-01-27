#!/bin/sh

set -e
source "${CONSUL_SCRIPT_DIR}"/common_functions.sh
if [ -z "$CONSUL_ENABLE_TLS" ] || [ "$CONSUL_ENABLE_TLS" -eq "0" ]; then
    log_warning "TLS is disabled, skipping configuration"
    exit 0
fi

if [ -z "$1" ]; then
    log_warning "please pass the ip as the first parameter as host or IP"
    exit 1
fi
ip=$1

log "Configuring TLS communication"

# Set our CSR variables
SUBJ="
C=US
ST=OR
O=MicroserviceInc
localityName=Portland
commonName=$ip
organizationalUnitName=Consul
emailAddress=info@MicroserviceInc.net
"

# Create our SSL directory
# in case it doesn't exist
mkdir -p "$CONSUL_BOOTSTRAP_DIR"

# Generate our Private Key, CSR and Certificate
# consul NEEDS a CA signed certificate, since we can only trust CAs but not certificates, running into
# consul: error getting server health from "consulserver": rpc error getting client: failed to get conn: x509: certificate signed by unknown authority (possibly because of "crypto/rsa: verification error" while trying to verify candidate authority certificate "127.0.0.1")
openssl req -nodes -days 1825 -x509 -newkey rsa:2048 -keyout ${CONSUL_BOOTSTRAP_DIR}/ca.key -out ${CONSUL_BOOTSTRAP_DIR}/ca.crt -subj "$(echo -n "$SUBJ" | tr "\n" "/")"
openssl req -nodes -newkey rsa:2048 -keyout ${CONSUL_BOOTSTRAP_DIR}/tls.key -out ${CONSUL_BOOTSTRAP_DIR}/cert.csr -subj "$(echo -n "$SUBJ" | tr "\n" "/")"
openssl x509 -req -days 1825 -in ${CONSUL_BOOTSTRAP_DIR}/cert.csr -CA ${CONSUL_BOOTSTRAP_DIR}/ca.crt -CAkey ${CONSUL_BOOTSTRAP_DIR}/ca.key -CAcreateserial -out ${CONSUL_BOOTSTRAP_DIR}/cert.crt

cp ${CONSUL_BOOTSTRAP_DIR}/ca.crt /usr/local/share/ca-certificates/consul-ca.crt

log "Updating the local CA Authority with our certs"
update-ca-certificates 2>/dev/null || true

log "Updating file permissions for the new certs"
chown consul:consul $CONSUL_BOOTSTRAP_DIR/tls.key
chmod 400 $CONSUL_BOOTSTRAP_DIR/tls.key
chown consul:consul $CONSUL_BOOTSTRAP_DIR/cert.crt

cat > ${CONSUL_BOOTSTRAP_DIR}/tls.json <<EOL
{
	"key_file": "${CONSUL_BOOTSTRAP_DIR}/tls.key",
	"cert_file": "${CONSUL_BOOTSTRAP_DIR}/cert.crt",
	"ca_file": "${CONSUL_BOOTSTRAP_DIR}/ca.crt",
    "ca_path": "${CONSUL_BOOTSTRAP_DIR}",
	"addresses": {
		"http": "0.0.0.0",
		"https": "0.0.0.0"
	},
	"ports": {
		"http": 8500,
		"https": 8501
	}
}
EOL
merge_json "tls.json"
