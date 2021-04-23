# Setup
## docker-compose
docker-compose yaml based on [this article](https://velog.io/@snoop2head/Running-Wiki.js-on-local-with-docker-compose)
Start the wikijs and postgres containers
```
cd docker-compose
docker-compose up
```

To cleanup the resources
```
docker-compose rm
```

## Kubernetes
For each chart the `original-values.yaml` file will contain the default values, which will make it easier to compare with `values.yaml` and get the diff.

### Postgres
More information regarding the paramters can be found [here](https://artifacthub.io/packages/helm/bitnami/postgresql)

#### Deployment
Create a Postgres DB using a Helm chart.
Specifying an exact chart version will help with future upgrades and ensure the same version is rolled out across clusters.

```
helm repo add bitnami https://charts.bitnami.com/bitnami
# Search the repo to get the exact version for the chart
helm search repo bitnami/postgresql
helm show values bitnami/postgresql --version 10.3.18 > helm/postgres/original-values.yaml
```
```
kubectl create secret generic postgres \
  --from-literal=postgresql-password=wikijsrocks
```

```
helm upgrade -i pg bitnami/postgresql \
    --version 10.3.18 \
    --values helm/postgres/values.yaml
```
#### (Optional) Connect to the database
```
export POSTGRES_PASSWORD=$(kubectl get secret --namespace default postgres -o jsonpath="{.data.postgresql-password}" | base64 --decode)

kubectl run pg-postgresql-client --rm --tty -i --restart='Never' --namespace default --image docker.io/bitnami/postgresql:11.11.0-debian-10-r71 --env="PGPASSWORD=$POSTGRES_PASSWORD" --command -- psql --host pg-postgresql -U postgres -d postgres -p 5432 -c 'CREATE DATABASE wiki'
```

### pgbouncer
The [original helm chart](
https://github.com/cradlepoint/kubernetes-helm-chart-pgbouncer/tree/master/pgbouncer) was copied in this repository for convenience.

The version used is [v1.0.11](https://github.com/cradlepoint/kubernetes-helm-chart-pgbouncer/archive/refs/tags/v1.0.11.tar.gz)

I added a parameter named `createUsersSecret` which controlls whether the secret containing the config will be created.
This is set to false, to avoid comitting credentials in git.

#### Prerequisites
Use `helm template` to generate the secret and apply it with `kubectl`.
1. Run `helm template`
```
helm template pgb helm/pgbouncer/ \
    --values helm/pgbouncer/values.yaml \
    --output-dir=out \
    --set createUsersSecret=true \
    --set users.postgres='wikijsrocks'
```
2. Apply the rendered secret yaml
```
kubectl apply -f out/pgbouncer/templates/secret-pgbouncer-configfiles.yaml
```

#### Deployment
```
helm upgrade -i pgb helm/pgbouncer/ --values helm/pgbouncer/values.yaml
```

### wiki.js
The original chart can be found [here](https://github.com/Requarks/wiki/tree/dev/dev/helm)

Customized the chart to create the postgres secret only when `postgres.createSecret` is set to `true`.

#### Prerequisites
Use `helm template` to generate the `wiki` secret and apply it with `kubectl`.
1. Run `helm template`
```
helm template wiki helm/wikijs/ \
    --values helm/wikijs/values.yaml \
    --output-dir=out \
    --set postgresql.createSecret=true \
    --set postgresql.postgresqlPassword='wikijsrocks'
```
2. Apply the rendered secret yaml
```
kubectl apply -f out/wiki/templates/secret.yaml
```
#### Deployment
```
helm upgrade -i wiki helm/wikijs/ --values helm/wikijs/values.yaml
```
#### (Optional) Test using port forwarding
Expose the service on port http://localhost:8080
```
kubectl port-forward svc/wiki 8080:80
```