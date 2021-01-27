FROM consul
LABEL Author rodneywimberly
LABEL Name consul-bootstrapper
LABEL Version 1.0

ENV NGINX_VERSION 1.19.6
ENV NJS_VERSION   0.5.0

RUN apk update && \
    apk add \
        nginx \
        bash \
        curl \
        jq \
        openssl \
        gettext \
        iputils \
        nfs-utils \
        bash \
        iproute2 && \
    mkdir -p /etc/nginx/www && \
    mkdir -p /usr/local/scripts && \
    mkdir -p /consul/data/bootstrap && \
    mkdir -p /consul/data/certs && \
    mkdir -p /consul/data/bootstrap && \
    mkdir -p /docker-entrypoint.d

EXPOSE 80

STOPSIGNAL SIGQUIT

COPY ./nginx.conf /etc/nginx/nginx.conf
COPY ./*.sh /usr/local/scripts/
COPY ./consul.env /usr/local/scripts/consul.env
COPY nginx-entrypoint.sh /
COPY 10-listen-on-ipv6-by-default.sh /docker-entrypoint.d
COPY 20-envsubst-on-templates.sh /docker-entrypoint.d

run chown consul:consul /etc/nginx && \
    chown consul:consul /usr/local/scripts && \
    chown consul:consul /consul && \
    chmod u+x /usr/local/scripts/*.sh

ENTRYPOINT ["/usr/local/scripts/bootstrapper-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
