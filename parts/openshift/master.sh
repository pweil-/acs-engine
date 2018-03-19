#!/bin/bash -x

# TODO: /etc/dnsmasq.d/origin-upstream-dns.conf is currently hardcoded; it
# probably shouldn't be

# TODO: remove this once we generate the registry certificate
cat >>/etc/sysconfig/docker <<'EOF'
INSECURE_REGISTRY='--insecure-registry 172.30.0.0/16'
EOF

systemctl restart docker.service

cat >/etc/sysconfig/atomic-openshift-master-api <<EOF
OPTIONS=--loglevel=2 --listen=https://0.0.0.0:8443 --master=https://$(hostname --fqdn):8443
CONFIG_FILE=/etc/origin/master/master-config.yaml
OPENSHIFT_DEFAULT_REGISTRY=docker-registry.default.svc:5000


# Proxy configuration
# See https://docs.openshift.com/enterprise/latest/install_config/install/advanced_install.html#configuring-global-proxy
EOF

cat >/etc/sysconfig/atomic-openshift-master-controllers <<'EOF'
OPTIONS=--loglevel=2 --listen=https://0.0.0.0:8444
CONFIG_FILE=/etc/origin/master/master-config.yaml
OPENSHIFT_DEFAULT_REGISTRY=docker-registry.default.svc:5000


# Proxy configuration
# See https://docs.openshift.com/enterprise/latest/install_config/install/advanced_install.html#configuring-global-proxy
EOF

echo "BOOTSTRAP_CONFIG_NAME=node-config-master" >>/etc/sysconfig/atomic-openshift-node

for dst in tcp,2379 tcp,2380 tcp,8443 tcp,8444 tcp,8053 udp,8053 tcp,9090; do
	proto=${dst%%,*}
	port=${dst##*,}
	iptables -A OS_FIREWALL_ALLOW -p $proto -m state --state NEW -m $proto --dport $port -j ACCEPT
done

iptables-save >/etc/sysconfig/iptables

systemctl mask atomic-openshift-master.service

cat >/usr/lib/systemd/system/atomic-openshift-master-api.service <<'EOF'
[Unit]
Description=Atomic OpenShift Master API
Documentation=https://github.com/openshift/origin
After=network-online.target
After=etcd.service
After=chronyd.service
After=ntpd.service
Before=atomic-openshift-node.service
Requires=network-online.target

[Service]
Type=notify
EnvironmentFile=/etc/sysconfig/atomic-openshift-master-api
Environment=GOTRACEBACK=crash
ExecStart=/usr/bin/openshift start master api --config=${CONFIG_FILE} $OPTIONS
LimitNOFILE=131072
LimitCORE=infinity
WorkingDirectory=/var/lib/origin
SyslogIdentifier=atomic-openshift-master-api
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
WantedBy=atomic-openshift-node.service
EOF

cat >/usr/lib/systemd/system/atomic-openshift-master-controllers.service <<'EOF'
[Unit]
Description=Atomic OpenShift Master Controllers
Documentation=https://github.com/openshift/origin
After=network-online.target
After=atomic-openshift-master-api.service
Wants=atomic-openshift-master-api.service
Requires=network-online.target

[Service]
Type=notify
EnvironmentFile=/etc/sysconfig/atomic-openshift-master-controllers
Environment=GOTRACEBACK=crash
ExecStart=/usr/bin/openshift start master controllers --config=${CONFIG_FILE} $OPTIONS
LimitNOFILE=131072
LimitCORE=infinity
WorkingDirectory=/var/lib/origin
SyslogIdentifier=atomic-openshift-master-controllers
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

rm -rf /etc/etcd/* /etc/origin/master/* /etc/origin/node/*

oc adm create-bootstrap-policy-file --filename=/etc/origin/master/policy.json

( cd / && base64 -d <<< {{ .ConfigBundle }} | tar -xz)

chown -R etcd:etcd /etc/etcd

cp /etc/origin/node/ca.crt /etc/pki/ca-trust/source/anchors/openshift-ca.crt
update-ca-trust

# TODO: when enabling secure registry, may need:
# ln -s /etc/origin/node/node-client-ca.crt /etc/docker/certs.d/docker-registry.default.svc:5000

# note: atomic-openshift-node crash loops until master is up
for unit in etcd.service atomic-openshift-master-api.service atomic-openshift-master-controllers.service atomic-openshift-node.service; do
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

# TODO: run a CSR auto-approver
# https://github.com/kargakis/acs-engine/issues/46
csrs=($(oc get csr -o name))
while [[ ${#csrs[@]} != "3" ]]; do
	sleep 2
	csrs=($(oc get csr -o name))
	if [[ ${#csrs[@]} == "3" ]]; then
		break
	fi
done

for csr in ${csrs[@]}; do
	oc adm certificate approve $csr
done

csrs=($(oc get csr -o name))
while [[ ${#csrs[@]} != "6" ]]; do
	sleep 2
	csrs=($(oc get csr -o name))
	if [[ ${#csrs[@]} == "6" ]]; then
		break
	fi
done

for csr in ${csrs[@]}; do
	oc adm certificate approve $csr
done

# TODO: possibly wait here for convergence?

exit 0
