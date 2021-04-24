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
### Setup using a script
To setup using the demo script just run
```
./k8s-setup.sh
```

The Postgres password will default to `wikijsrocks` and the ingress hostname to `wiki.local`

If you want to customize these values, set the following variables
```
WIKI_DB_PASSWORD=s0mepwd \
WIKI_INGRESS_HOSTNAME=wiki.example.com \
./k8s-setup.sh
```
### Accessing the application
#### Port forwarding
```
kubectl port-forward svc/wiki 8080:80
```
The service is now accessible at http://localhost:8080/

#### Create a load balancer and add a DNS record
If you're running this on the cloud, values.yaml for nginx-ingress and change the type from `NodePort` to `LoadBalancer` and a load balancer will be created.

Add a DNS record for that load balancer matching INGRESS_HOSTNAME.

#### Add entry in /etc/hosts
1. To access the application without creating a DNS record (as this is just for test purposes), add an entry in `/etc/hosts` for one of the Kubernetes nodes, using the following command
```
echo $(kubectl get pod -l app=ni-nginx-ingress -o jsonpath='{.items[0].status.hostIP}') wiki.local | sudo tee -a /etc/hosts
```

2. wiki.js can now be accessed at http://wiki.local:30080/

### Manual setup
The following steps are not required if `k8s-setup.sh` was used.
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

#### (Optional) Inspecting the Dockerfile
I couldn't find the actual Dockerfile used to create the images which are being published, though there is a [dev Dockerfile](https://github.com/Requarks/wiki/blob/dev/dev/containers/Dockerfile).
To have a look at the way the image was built, [dfimage](https://hub.docker.com/r/alpine/dfimage) can be used
```
alias dfimage="docker run -v /var/run/docker.sock:/var/run/docker.sock --rm alpine/dfimage"
dfimage docker.io/requarks/wiki:2.5
```
What can be observed is:
* image is running as user `node`
* image is based on Alpine Linux
* entrypoint looks minimal - can be checked using `docker run -it --rm docker.io/requarks/wiki:2.5 cat /usr/local/bin/docker-entrypoint.sh`

### nginx-ingress
#### Prerequisites
```
helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update
helm search repo nginx-stable/nginx-ingress
helm show values nginx-stable/nginx-ingress --version 0.9.1 > helm/nginx-ingress/original-values.yaml
```

#### Deployment
```
helm upgrade -i ni nginx-stable/nginx-ingress \
  --version 0.9.1 \
  --values helm/nginx-ingress/values.yaml
```