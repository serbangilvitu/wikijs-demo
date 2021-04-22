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
helm install pg bitnami/postgresql \
    --version 10.3.18 \
    --values helm/postgres/values.yaml
```
#### Connecting to the database
```
export POSTGRES_PASSWORD=$(kubectl get secret --namespace default postgres -o jsonpath="{.data.postgresql-password}" | base64 --decode)

kubectl run pg-postgresql-client --rm --tty -i --restart='Never' --namespace default --image docker.io/bitnami/postgresql:11.11.0-debian-10-r71 --env="PGPASSWORD=$POSTGRES_PASSWORD" --command -- psql --host pg-postgresql -U postgres -d postgres -p 5432
```