# hybrid-cloud-serverless
Hybrid cloud demo with serverless

= Hybrid Cloud
:experimental:
:cloud-1: gcp
:cloud-1-weight: 0
:cloud-2: azr
:cloud-2-weight: 15
:cloud-3: aws
:cloud-3-weight: 20

image:https://img.shields.io/badge/OpenShift-v4.5.x-red?style=for-the-badge[link=https://try.openshift.com]
image:https://img.shields.io/badge/OpenShift%20Serverless-v1.10-red?style=for-the-badge[link=
https://www.openshift.com/learn/topics/serverless]
image:https://img.shields.io/badge/skupper-v0.3.0-red?style=for-the-badge[link=
https://skupper.io]

This description is heavly based on the repo https://github.com/redhat-developer-demos/hybrid-cloud-serverless
but has been simplified and made specific to OpenShift, Skupper CLI and kn CLI rather than kubectl yaml

== Prerequisites

You need an OpenShift cluster at least with 3 namespaces and non-privelged account

The advanced demo uses 3 seperate OpenShift clusters with skupper used to span the namespaces.

You must install OpenShift Serverless via the Operator and at least create the Serving instance on each cluster

These demos all use http to communicate. Knative Serving now supports mTLS which breaks things so suggest 
this change to force http. https://docs.openshift.com/container-platform/4.8/serverless/serverless-release-notes.html

You can override the default by adding the following YAML to your KnativeServing custom resource (CR):

```
...
spec:
  config:
    network:
      defaultExternalScheme: "http"
...
```

Let us call the OpenShift Clusters/Namespaces as *Cloud-1(`{cloud-1}`)*, *Cloud-2(`{cloud-2}`)* and *Cloud-3(`{cloud-3}`)*.

The following table shows the cloud and what components gets installed on each of them:

.Clouds and Components
[cols="<2,^1,^1,^1", options="header"]
|===
| Component | Cloud-1  |  Cloud-2 | Cloud-3
| Cloud Provider  | {cloud-1}  |  {cloud-2} | {cloud-3}
| Backend   | &#x2713;  | &#x2713;  | &#x2713;
| Frontend  | &#x2713;  | &#x274C; | &#x274C;
| Generate Site Token(`token.yaml`)  | &#x2713;  | &#x274C; | &#x274C;
| Weight    | 0 | 15 | 20
|===

[NOTE]
====
* You can use any cloud provider for any OpenShift4 supported cloud
* *Weight* controls how many requests that cloud can handle before skupper bursts them out to other clouds
====

=== Single cluster multiple namespaces

Before the `backend` or `frontend` applications are deployed, execute the following to setup the namespaces:

[source,bash]
----
oc login -u user1 -p openshift
oc new-project cloud1
oc new-project cloud2
oc new-project cloud3
----

Install the Skupper CLI and then execute the following installing skupper into each project

[source,bash]
----
skupper init -n cloud1
skupper init -n cloud2
skupper init -n cloud3
----

Now link the projects with skupper by creating tokens on cloud1 and sharing them with the other
projects to link them. The tokens by default have a short expiry time and can only be used once

The links created between the projects have a weighting so traffic is preferred locally, then cloud2 
and if really necessary cloud3

[source,bash]
----
skupper token create tok1.yaml -n cloud1
skupper token create tok2.yaml -n cloud1
skupper link create tok1.yaml  -n cloud2 --cost 15
skupper link create tok2.yaml  -n cloud2 --cost 20
----

Now check the status of skupper to make sure all the links are good.

[source,bash]
----
skupper status -n cloud1
skupper status -n cloud2
skupper status -n cloud3
---

Now for Cloud1 deploy the (only) front end application. We use an existing image for this:

[source,bash]
----
oc new-app --name='hybrid-cloud-frontend' quay.io/rhdevelopers/hybrid-cloud-demo-frontend \
  --env COM_REDHAT_DEVELOPERS_DEMO_SERVICE_BACKENDSERVICECLIENT_MP_REST_URL='http://hybrid-cloud-backend-skupper' \
  --env KNATIVE_BURST=true \
  --env KNATIVE_BURST_SLEEP_MILLISECONDS=2000 \
 -n cloud1
oc expose svc/hybrid-cloud-frontend -n cloud1
---

Now for each project deploy the backend system. This is a Serverless based app so first install
the kn CLI so this script can execute. Again an existing image is used, sligjhtly modified from the 
original demo since it makes labelling easier. The image is Java/Quarkus bu in JVM mode. A more advanced 
demo would rebuild this a native image so improve the startup (and bursting) time.

Note the use of the CLOUDID env. This is used to distinguish the traffic coming from each backend. 
A more advanced demo might use this field to represent the cluster type in use eg AWS, GCP, Azure

Note the limits set on the Serverless service, it cannot scale and has limited capacity, this forces it 
to burst traffic through the skupper proxy to another cloud.

[source,bash]
----
kn service create 'hybrid-cloud-backend' --image=quay.io/agroom/hybrid-cloud-app-backend:latest \
  --label='app.openshift.io/runtime=quarkus'  \
  --annotation autoscaling.knative.dev/maxScale="1" \
  --annotation autoscaling.knative.dev/window="16s" \
  --concurrency-limit 1 \
  --env CLOUDID=cloud1 --namespace cloud1
kn service create 'hybrid-cloud-backend' --image=quay.io/agroom/hybrid-cloud-app-backend:latest \
  --label='app.openshift.io/runtime=quarkus'  \
  --annotation autoscaling.knative.dev/maxScale="1" \
  --annotation autoscaling.knative.dev/window="16s" \
  --concurrency-limit 1 \
  --env CLOUDID=cloud2 --namespace cloud2
kn service create 'hybrid-cloud-backend' --image=quay.io/agroom/hybrid-cloud-app-backend:latest \
  --label='app.openshift.io/runtime=quarkus'  \
  --annotation autoscaling.knative.dev/maxScale="1" \
  --annotation autoscaling.knative.dev/window="16s" \
  --concurrency-limit 1 \
  --env CLOUDID=cloud3 --namespace cloud3
---

Finally we have to expose the back-end services to skupper, which in turn then expose these backend services 
to the frontend.

[source,bash]
----
skupper expose service hybrid-cloud-backend.cloud1 --port 80 --address hybrid-cloud-backend-skupper --protocol http -n cloud1
skupper expose service hybrid-cloud-backend.cloud2 --port 80 --address hybrid-cloud-backend-skupper  --protocol http -n cloud2
skupper expose service hybrid-cloud-backend.cloud3 --port 80 --address hybrid-cloud-backend-skupper --protocol http -n cloud3
---

=== Cloud-1


=== Cloud-2


=== Cloud-3


Run the following commands on *Cloud-1*, *Cloud-2* and *Cloud-3* to wait for skupper deployments to be ready:


Run the following command to check the status:

[source,bash,subs="macros+,attributes+"]
----
oc get pods,svc,ksvc
----

A successful deployments of components, should show an output like:

[source,text]
----
NAME                                                        READY   STATUS    RESTARTS   AGE
pod/hybrid-cloud-backend-p948k-deployment-b49c9569b-ggv8z   2/2     Running   0          26s
pod/skupper-router-56c4544bbc-dhckt                         3/3     Running   0          43m
pod/skupper-service-controller-5bcf486799-v2hl2             2/2     Running   0          43m
pod/skupper-site-controller-5cf967f858-z2dx8                1/1     Running   0          43m

NAME                                         TYPE           CLUSTER-IP       EXTERNAL-IP                                                  PORT(S)                             AGE
service/hybrid-cloud-backend                 ExternalName   <none>           kourier-internal.knative-serving-ingress.svc.cluster.local   <none>                              21s
service/hybrid-cloud-backend-p948k           ClusterIP      172.30.223.229   <none>                                                       80/TCP                              26s
service/hybrid-cloud-backend-p948k-private   ClusterIP      172.30.140.107   <none>                                                       80/TCP,9090/TCP,9091/TCP,8022/TCP   26s
service/hybrid-cloud-backend-skupper         LoadBalancer   172.30.1.23      <pending>                                                    80:31554/TCP                        29s
service/skupper-controller                   ClusterIP      172.30.119.15    <none>                                                       443/TCP                             43m
service/skupper-internal                     ClusterIP      172.30.205.136   <none>                                                       55671/TCP,45671/TCP                 43m
service/skupper-messaging                    ClusterIP      172.30.14.214    <none>                                                       5671/TCP                            43m
service/skupper-router-console               ClusterIP      172.30.72.116    <none>                                                       443/TCP                             43m

NAME                                               URL                                                                 LATESTCREATED                LATESTREADY                  READY   REASON
service.serving.knative.dev/hybrid-cloud-backend    http://hybrid-cloud-backend.hybrid-cloud-demo.svc.cluster.local   hybrid-cloud-backend-p948k   hybrid-cloud-backend-p948k   True
----

== Connecting Clouds


The `site-token` seceret will be used to connect clouds *Cloud-2* and *Cloud-3* to *Cloud-1* forming a _Virtual Application Network(VAN)_. 

Run the following command to export the `site-token` secret:


Get the URL to access the frontend application:

[source,bash]
----
export API_URL=http://$(oc get route -n cloud1 hybrid-cloud-frontend -ojsonpath='{.spec.host}')
----

== Burst Testing

It is possible to verify the burst without user input using the  following https://github.com/rakyll/hey[hey] scripts:

=== Cloud-1 burst to Cloud-2

In order to burst from Cloud-1 to Cloud-2, you need to send atleast `{cloud-2-weight}` requests to the API:

[source,bash,subs="macros+,attributes+"]
----
hey -z 2s -c 20 -m POST -d '{"text": "1+2","uppercase": false,"reverse": false}' -H "Content-Type: application/json" $API_URL/api/send-request
----

=== Cloud-1 burst to Cloud-2 burst to Cloud-3

In order to burst from Cloud-1 to Cloud-2, you need to send atleast `{cloud-2-weight} + {cloud-3-weight} = 35` requests to the API:

[source,bash,subs="macros+,attributes+"]
----
hey -z 2s -c 35 -m POST -d '{"text": "1+2+3","uppercase": false,"reverse": false}' -H "Content-Type: application/json" $API_URL/api/send-request
----
