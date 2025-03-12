# Is it Observable
<p align="center"><img src="/image/logo.png" width="40%" alt="Is It observable Logo" /></p>

## Episode : Kubescape
This repository contains all the files required to run the tutorial environment related to the episode dedicated to Kubescape <img src="/image/kubescape.png" width="40%" alt="kubescape Logo" /></p>

this repository will use solutions to measure the usage of those agents, we will rely on: 
* the OpenTelemetry Demo
* ungard application
* Goat application to generate security violation


* All the observability data generated by the environment would be sent to Dynatrace.

## Prerequisite
The following tools need to be install on your machine :
- jq
- kubectl
- git
- gcloud ( if you are using GKE)
- Helm


### 1.Create a Google Cloud Platform Project
```shell
PROJECT_ID="<your-project-id>"
gcloud services enable container.googleapis.com --project ${PROJECT_ID}
gcloud services enable monitoring.googleapis.com \
cloudtrace.googleapis.com \
clouddebugger.googleapis.com \
cloudprofiler.googleapis.com \
--project ${PROJECT_ID}
```
### 2.Create a GKE cluster
```shell
ZONE=europe-west3-a
NAME=isitobservable-kubescape
gcloud container clusters create ${NAME} --zone=${ZONE} --machine-type=e2-standard-4 --num-nodes=2
```


### 3. Clone Github repo

```shell
git clone  https://github.com/isitobservable/kubescape
cd kubescape
```



## Getting started


### Dynatrace Tenant
#### 1. Dynatrace Tenant - start a trial
If you don't have any Dynatrace tenant , then I suggest to create a trial using the following link : [Dynatrace Trial](https://dt-url.net/observable-trial)
Once you have your Tenant save the Dynatrace tenant url in the variable `DT_TENANT_URL` (for example : https://dedededfrf.live.dynatrace.com)
```
DT_TENANT_URL=<YOUR TENANT Host>
```

##### 2. Create the Dynatrace API Tokens
The dynatrace operator will require to have several tokens:
* Token to deploy and configure the various components
* Token to ingest metrics and Traces


###### Operator Token
One for the operator having the following scope:
* Create ActiveGate tokens
* Read entities
* Read Settings
* Write Settings
* Access problem and event feed, metrics and topology
* Read configuration
* Write configuration
* Paas integration - installer downloader
<p align="center"><img src="/image/operator_token.png" width="40%" alt="operator token" /></p>

Save the value of the token . We will use it later to store in a k8S secret
```shell
API_TOKEN=<YOUR TOKEN VALUE>
```
###### Ingest data token
Create a Dynatrace token with the following scope:
* Ingest metrics (metrics.ingest)
* Ingest logs (logs.ingest)
* Ingest events (events.ingest)
* Ingest OpenTelemetry
* Read metrics
<p align="center"><img src="/image/data_ingest_token.png" width="40%" alt="data token" /></p>
Save the value of the token . We will use it later to store in a k8S secret

```shell
DATA_INGEST_TOKEN=<YOUR TOKEN VALUE>
```

### 1. Deploy the  environment without security solutions
The application will deploy the entire environment:
```shell

chmod 777 deployment.sh
./deployment.sh  --clustername "${NAME}" --dturl "${DT_TENANT_URL}" --dtingesttoken "${DATA_INGEST_TOKEN}" --dtoperatortoken "${API_TOKEN}" 
```
## Tutorial Steps

### Kubearmor Notebook


### Kubescape Dashboard

Let's deploy the dashboard located : `dynatrace/kubescape dashboard.json`

In dynatrace , Open The Dashboard application and click on upload
<p align="center"><img src="/image/kubescape dashboard.json" width="40%" alt="kubescape dashboard" /></p>

This dashboard will keep track on the health of tetragon:
- ressource usage
- the various rules


all those dashboard are uisng the logs , spans and metris

