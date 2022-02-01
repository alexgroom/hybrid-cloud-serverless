# Script to deploy Skupper serverless demo
#
# PLEASE CHANGE THESE VARIABLES
#
export CLOUD1_LOGIN='https://api.cluster-6s5fq.6s5fq.sandbox693.opentlc.com:6443 -u user1 -p openshift'
export CLOUD2_LOGIN='https://api.cluster-6s5fq.6s5fq.sandbox693.opentlc.com:6443 -u user1 -p openshift'
export CLOUD3_LOGIN='https://api.cluster-6s5fq.6s5fq.sandbox693.opentlc.com:6443 -u user1 -p openshift'
export CLOUD1_PROJ=cloud1
export CLOUD2_PROJ=cloud2
export CLOUD3_PROJ=cloud3
export CLOUD1_DISP=cloud1
export CLOUD2_DISP=cloud2
export CLOUD3_DISP=cloud3
#
# create projects
oc login $CLOUD1_LOGIN
oc new-project $CLOUD1_PROJ
skupper init -n $CLOUD1_PROJ
# create short term single short tokens
# these need to be copied so accessible for the other namespaces
skupper token create tok1.yaml -n $CLOUD1_PROJ
skupper token create tok2.yaml -n $CLOUD1_PROJ
skupper status -n $CLOUD1_PROJ
#
# Now deploy front end app to first project
oc new-app --name='hybrid-cloud-frontend' quay.io/rhdevelopers/hybrid-cloud-demo-frontend \
  --env COM_REDHAT_DEVELOPERS_DEMO_SERVICE_BACKENDSERVICECLIENT_MP_REST_URL='http://hybrid-cloud-backend-skupper' \
  --env KNATIVE_BURST=true \
  --env KNATIVE_BURST_SLEEP_MILLISECONDS=2000 \
 -n $CLOUD1_PROJ
oc expose svc/hybrid-cloud-frontend -n $CLOUD1_PROJ
#
# Deploy backend KSVC to each project
kn service create 'hybrid-cloud-backend' --image=quay.io/agroom/hybrid-cloud-app-backend:latest \
  --label='app.openshift.io/runtime=quarkus'  \
  --annotation autoscaling.knative.dev/maxScale="1" \
  --annotation autoscaling.knative.dev/window="16s" \
  --concurrency-limit 1 \
  --env CLOUDID=$CLOUD1_DISP --namespace $CLOUD1_PROJ
#  
skupper expose service hybrid-cloud-backend.$CLOUD1_PROJ --port 80 --address hybrid-cloud-backend-skupper --protocol http -n $CLOUD1_PROJ
#
oc login $CLOUD2_LOGIN
oc new-project $CLOUD2_PROJ
skupper init -n $CLOUD2_PROJ
# connect namespaces (with set costings)
# link costs are important to get traffic to burst
skupper link create tok1.yaml  -n $CLOUD2_PROJ --cost 15
skupper status -n $CLOUD2_PROJ
#
kn service create 'hybrid-cloud-backend' --image=quay.io/agroom/hybrid-cloud-app-backend:latest \
  --label='app.openshift.io/runtime=quarkus'  \
  --annotation autoscaling.knative.dev/maxScale="1" \
  --annotation autoscaling.knative.dev/window="16s" \
  --concurrency-limit 1 \
  --env CLOUDID=$CLOUD2_DISP --namespace $CLOUD2_PROJ
#
skupper expose service hybrid-cloud-backend.$CLOUD2_PROJ --port 80 --address hybrid-cloud-backend-skupper  --protocol http -n $CLOUD2_PROJ
#
oc login $CLOUD3_LOGIN
oc new-project $CLOUD3_PROJ
skupper init -n $CLOUD3_PROJ
# connect namespaces (with set costings)
# link costs are important to get traffic to burst
skupper link create tok2.yaml  -n $CLOUD3_PROJ --cost 20
skupper status -n $CLOUD3_PROJ
#
kn service create 'hybrid-cloud-backend' --image=quay.io/agroom/hybrid-cloud-app-backend:latest \
  --label='app.openshift.io/runtime=quarkus'  \
  --annotation autoscaling.knative.dev/maxScale="1" \
  --annotation autoscaling.knative.dev/window="16s" \
  --concurrency-limit 1 \
  --env CLOUDID=$CLOUD3_DISP --namespace $CLOUD3_PROJ
# expose the backend service via skupper
skupper expose service hybrid-cloud-backend.$CLOUD3_PROJ --port 80 --address hybrid-cloud-backend-skupper --protocol http -n $CLOUD3_PROJ
#
# Clean up tokens
rm tok1.yaml
rm tok2.yaml
#
# set default to CLOUD1 since this is the master project with front end
oc login $CLOUD1_LOGIN
oc project $CLOUD1_PROJ
# setup env for hey scripts using front-end route in cloud1
export API_URL=http://$(oc get route hybrid-cloud-frontend -ojsonpath='{.spec.host}')
#
