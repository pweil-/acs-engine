#!/bin/bash -x

# TODO: /etc/dnsmasq.d/origin-upstream-dns.conf is currently hardcoded; it
# probably shouldn't be

# TODO: remove this once we generate the registry certificate
cat >>/etc/sysconfig/docker <<'EOF'
INSECURE_REGISTRY='--insecure-registry 172.30.0.0/16'
EOF

systemctl restart docker.service

echo "BOOTSTRAP_CONFIG_NAME=node-config-master" >>/etc/sysconfig/atomic-openshift-node

for dst in tcp,2379 tcp,2380 tcp,8443 tcp,8444 tcp,8053 udp,8053 tcp,9090; do
	proto=${dst%%,*}
	port=${dst##*,}
	iptables -A OS_FIREWALL_ALLOW -p $proto -m state --state NEW -m $proto --dport $port -j ACCEPT
done

iptables-save >/etc/sysconfig/iptables

sed -i -e "s#--master=.*#--master=https://$(hostname --fqdn):8443#" /etc/sysconfig/atomic-openshift-master-api

rm -rf /etc/etcd/* /etc/origin/master/* /etc/origin/node/*

oc adm create-bootstrap-policy-file --filename=/etc/origin/master/policy.json

( cd / && base64 -d <<< {{ .ConfigBundle }} | tar -xz)

chown -R etcd:etcd /etc/etcd

cp /etc/origin/node/ca.crt /etc/pki/ca-trust/source/anchors/openshift-ca.crt
update-ca-trust

# TODO: when enabling secure registry, may need:
# ln -s /etc/origin/node/node-client-ca.crt /etc/docker/certs.d/docker-registry.default.svc:5000

# note: atomic-openshift-node crash loops until master is up
for unit in etcd.service atomic-openshift-master-api.service atomic-openshift-master-controllers.service; do
	systemctl enable $unit
	systemctl start $unit
done

mkdir -p /root/.kube
cp /etc/origin/master/admin.kubeconfig /root/.kube/config

export KUBECONFIG=/etc/origin/master/admin.kubeconfig

while ! curl -o /dev/null -m 2 -kfs https://localhost:8443/healthz; do
	sleep 1
done

while ! oc get svc kubernetes &>/dev/null; do
	sleep 1
done

oc create configmap node-config-master --namespace openshift-node --from-file=node-config.yaml=/tmp/bootstrapconfigs/master-config.yaml
oc create configmap node-config-compute --namespace openshift-node --from-file=node-config.yaml=/tmp/bootstrapconfigs/compute-config.yaml
oc create configmap node-config-infra --namespace openshift-node --from-file=node-config.yaml=/tmp/bootstrapconfigs/infra-config.yaml

# must start atomic-openshift-node after master is fully up and running
# otherwise the implicit dns change may cause master startup to fail
systemctl enable atomic-openshift-node.service
systemctl start atomic-openshift-node.service &

# TODO: do this, and more (registry console, service catalog, tsb, asb), the proper way

oc patch project default -p '{"metadata":{"annotations":{"openshift.io/node-selector": ""}}}'

oc adm registry --images='registry.reg-aws.openshift.com:443/openshift3/ose-${component}:${version}' --selector='region=infra'

oc adm policy add-scc-to-user hostnetwork -z router
oc adm router --images='registry.reg-aws.openshift.com:443/openshift3/ose-${component}:${version}' --selector='region=infra'

oc create -f - <<'EOF'
kind: Project
apiVersion: v1
metadata:
  name: openshift-web-console
  annotations:
    openshift.io/node-selector: ""
EOF

oc process -f /usr/share/ansible/openshift-ansible/roles/openshift_web_console/files/console-template.yaml \
	-p API_SERVER_CONFIG="$(sed -e s/127.0.0.1/{{ .ExternalMasterHostname }}/g </usr/share/ansible/openshift-ansible/roles/openshift_web_console/files/console-config.yaml)" \
	-p NODE_SELECTOR='{"node-role.kubernetes.io/master":"true"}' \
	| oc create -f -

for file in /usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/v3.7/db-templates/*.json \
    /usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/v3.7/image-streams/*-rhel7.json \
	  /usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/v3.7/quickstart-templates/*.json \
	  /usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/v3.7/xpaas-streams/*.json \
	  /usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/v3.7/xpaas-templates/*.json; do
	oc create -n openshift -f $file
done

# TODO: possibly wait here for convergence?

# Run the auto approver to approve CSR requests from nodes coming in to the cluster.
docker run -d --net=host -v /etc/origin/master/admin.kubeconfig:/var/lib/origin/openshift.local.config/master/admin.kubeconfig docker.io/pweil/openshift-bootstrap-approver

exit 0
