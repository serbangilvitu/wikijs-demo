#!/bin/bash

secret_exists() {
    kubectl get secrets --field-selector=metadata.name=$1 --no-headers 2>/dev/null | wc -l
}

wait_for_postgres() {
    PG_READY_CMD="kubectl get pod pg-postgresql-0 -o jsonpath='{.status.containerStatuses[0].ready}'"
    echo "Postgres is initializing"
    while [[ $(${PG_READY_CMD} | grep -c true) -lt 1 ]];do
        sleep 5
        echo "....."
    done
}

if [[ -z "${WIKI_DB_PASSWORD}" ]]; then
    WIKI_DB_PASSWORD="wikijsrocks"
fi

if [[ -z "${WIKI_INGRESS_HOSTNAME}" ]]; then
    WIKI_INGRESS_HOSTNAME="wiki.local"
fi

set -u

echo "WIKI_DB_PASSWORD=${WIKI_DB_PASSWORD}"
echo "WIKI_INGRESS_HOSTNAME=${WIKI_INGRESS_HOSTNAME}"

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update

# postgres
if [[ $(secret_exists postgres) -eq 0 ]]; then
    kubectl create secret generic postgres \
    --from-literal=postgresql-password=${WIKI_DB_PASSWORD}
fi

helm upgrade -i pg bitnami/postgresql \
    --version 10.3.18 \
    --values helm/postgres/values.yaml

## Create the wiki database

wait_for_postgres

kubectl run pg-postgresql-client --rm --tty -i --restart='Never' \
    --namespace default \
    --image docker.io/bitnami/postgresql:11.11.0-debian-10-r71 \
    --env="PGPASSWORD=${WIKI_DB_PASSWORD}" \
    --command -- psql --host pg-postgresql -U postgres -d postgres -p 5432 -c 'CREATE DATABASE wiki'

# pgbouncer
helm template pgb helm/pgbouncer/ \
    --values helm/pgbouncer/values.yaml \
    --output-dir=out \
    --set createUsersSecret=true \
    --set users.postgres=${WIKI_DB_PASSWORD}

kubectl apply -f out/pgbouncer/templates/secret-pgbouncer-configfiles.yaml

helm upgrade -i pgb helm/pgbouncer/ --values helm/pgbouncer/values.yaml

# wiki.js
helm template wiki helm/wikijs/ \
    --values helm/wikijs/values.yaml \
    --output-dir=out \
    --set postgresql.createSecret=true \
    --set postgresql.postgresqlPassword=${WIKI_DB_PASSWORD}

kubectl apply -f out/wiki/templates/secret.yaml

helm upgrade -i wiki helm/wikijs/ --values helm/wikijs/values.yaml

# nginx-ingress
helm upgrade -i ni nginx-stable/nginx-ingress \
  --version 0.9.1 \
  --values helm/nginx-ingress/values.yaml