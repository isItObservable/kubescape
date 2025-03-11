#!/usr/bin/env bash

################################################################################
### Script deploying the Observ-K8s environment
### Parameters:
### Clustern name: name of your k8s cluster
### dttoken: Dynatrace api token with ingest metrics and otlp ingest scope
### dturl : url of your DT tenant wihtout any / at the end for example: https://dedede.live.dynatrace.com
################################################################################


### Pre-flight checks for dependencies
if ! command -v jq >/dev/null 2>&1; then
    echo "Please install jq before continuing"
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "Please install git before continuing"
    exit 1
fi


if ! command -v helm >/dev/null 2>&1; then
    echo "Please install helm before continuing"
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "Please install kubectl before continuing"
    exit 1
fi
echo "parsing arguments"
while [ $# -gt 0 ]; do
  case "$1" in
   --dtoperatortoken)
          DTOPERATORTOKEN="$2"
         shift 2
          ;;
       --dtingesttoken)
          DTTOKEN="$2"
         shift 2
          ;;
       --dturl)
          DTURL="$2"
         shift 2
          ;;
       --clustername)
         CLUSTERNAME="$2"
         shift 2
         ;;

  *)
    echo "Warning: skipping unsupported option: $1"
    shift
    ;;
  esac
done
echo "Checking arguments"
 if [ -z "$CLUSTERNAME" ]; then
   echo "Error: clustername not set!"
   exit 1
 fi
 if [ -z "$DTURL" ]; then
   echo "Error: Dt url not set!"
   exit 1
 fi

 if [ -z "$DTTOKEN" ]; then
   echo "Error: Data ingest api-token not set!"
   exit 1
 fi

 if [ -z "$DTOPERATORTOKEN" ]; then
   echo "Error: DT operator token not set!"
   exit 1
 fi

#### Deploy the cert-manager
echo "Deploying Cert Manager ( for OpenTelemetry Operator)"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.10.0/cert-manager.yaml
# Wait for pod webhook started
kubectl wait pod -l app.kubernetes.io/component=webhook -n cert-manager --for=condition=Ready --timeout=2m
# Deploy the opentelemetry operator
sleep 10
echo "Deploying the OpenTelemetry Operator"
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml

 # installing Ingress controller
helm upgrade --install ingress-nginx ingress-nginx  --repo https://kubernetes.github.io/ingress-nginx  --namespace ingress-nginx --create-namespace --set controller.opentelemetry.enabled=true --set controller.metrics.enabled=true \
                                                                                                                                                                                                --set-string controller.podAnnotations."prometheus\.io/scrape"="true" \

### get the ip adress of ingress ####
IP=""
while [ -z $IP ]; do
  echo "Waiting for external IP"
  IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -ojson | jq -j '.status.loadBalancer.ingress[].ip')
   [ -z "$IP" ] && sleep 10
done
echo 'Found external IP: '$IP

echo '
  apiVersion: v1
  kind: ConfigMap
  data:
    enable-opentelemetry: "true"
    opentelemetry-operation-name: "HTTP $request_method $service_name $uri"
    opentelemetry-trust-incoming-span: "true"
    otlp-collector-host: "otel-collector.default.svc.cluster.local"
    otlp-collector-port: "4317"
    otel-max-queuesize: "2048"
    otel-schedule-delay-millis: "5000"
    otel-max-export-batch-size: "512"
    otel-service-name: "nginx-proxy" # Opentelemetry resource name
    otel-sampler: "AlwaysOn" # Also: AlwaysOff, TraceIdRatioBased
    otel-sampler-ratio: "1.0"
    otel-sampler-parent-based: "false"
  metadata:
    name: ingress-nginx-controller
    namespace: ingress-nginx
  ' | kubectl replace -n ingress-nginx -f -
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx

# Install Kubescape
helm repo add kubescape https://kubescape.github.io/helm-charts/
helm repo update
helm upgrade --install kubescape kubescape/kubescape-operator -n kubescape --create-namespace -f kubescape/values.yaml --set clusterName=`kubectl config current-context`
# Install inspektor gadget
helm repo add gadget https://inspektor-gadget.github.io/charts
helm install gadget gadget/gadget --namespace=gadget --create-namespace -f inspecktor-gadget/values.yaml
kubectl apply -f inspecktor-gadget/configmap.yaml -n gadget

kubectl rollout restart ds gadget -n gadget
kubectl apply -f inspecktor-gadget/gadget_top.yaml
### Deploy the Dynatrace Operator
kubectl create namespace dynatrace
kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/download/v1.4.0/kubernetes.yaml
kubectl apply -f https://github.com/Dynatrace/dynatrace-operator/releases/download/v1.4.0/kubernetes.yaml
kubectl -n dynatrace wait pod --for=condition=ready --selector=app.kubernetes.io/name=dynatrace-operator,app.kubernetes.io/component=webhook --timeout=300s
kubectl -n dynatrace create secret generic dynakube --from-literal="apiToken=$DTOPERATORTOKEN" --from-literal="dataIngestToken=$DTTOKEN"
sed -i  '' "s,TENANTURL_TOREPLACE,$DTURL," dynatrace/dynakube.yaml
sed -i  '' "s,CLUSTER_NAME_TO_REPLACE,$CLUSTERNAME,"  dynatrace/dynakube.yaml

### Update the ip of the ip adress for the ingres
#TODO to update this part to create the various Gateway rules
sed -i  '' "s,IP_TO_REPLACE,$IP," opentelemetry/deploy_1_12.yaml
sed -i  '' "s,IP_TO_REPLACE,$IP," opentelemetry/loadtest_job.yaml
#Deploy collector
kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="$DTURL" --from-literal=clustername="$CLUSTERNAME"  --from-literal=clusterid=$CLUSTERID  --from-literal=dt_api_token="$DTTOKEN"
kubectl label namespace  default oneagent=false
kubectl apply -f opentelemetry/rbac.yaml

kubectl apply -f opentelemetry/openTelemetry-manifest_ds.yaml

#deploy demo application
kubectl apply -f dynatrace/dynakube.yaml -n dynatrace
kubectl create ns otel-demo
kubectl label namespace  otel-demo oneagent=false
kubectl apply -f opentelemetry/deploy_1_12.yaml -n otel-demo


kubectl create ns goat-app
kubectl label namespace  goat-app oneagent=false
kubectl apply -f k8sGoat/unsafejob.yaml -n goat-app

helm repo add bitnami https://charts.bitnami.com/bitnami
helm install unguard-mariadb bitnami/mariadb --version 11.5.7 --set primary.persistence.enabled=false --wait --namespace unguard --create-namespace
helm install unguard  oci://ghcr.io/dynatrace-oss/unguard/chart/unguard --set maliciousLoadGenerat.enabled=true --wait --namespace unguard

kubectl apply -f opentelemetry/openTelemetry-manifest_statefulset.yaml

#Deploy the ingress rules
echo "--------------Demo--------------------"
echo "url of the demo: "
echo " otel-demo : http://oteldemo.$IP.nip.io"
echo "========================================================"


