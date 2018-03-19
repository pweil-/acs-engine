#!/bin/bash -x

# note: this is laid down by atomic-openshift-node.service
cat >/etc/dnsmasq.d/node-dnsmasq.conf <<'EOF'
server=/in-addr.arpa/127.0.0.1
server=/cluster.local/127.0.0.1
EOF

# TODO: probably shouldn't be hardcoded
cat >/etc/dnsmasq.d/origin-upstream-dns.conf <<'EOF'
server=168.63.129.16
EOF

systemctl restart dnsmasq.service

# TODO: remove this once we generate the registry certificate
cat >>/etc/sysconfig/docker <<'EOF'
INSECURE_REGISTRY='--insecure-registry 172.30.0.0/16'
EOF

systemctl restart docker.service

# note: for now we don't use /etc/NetworkManager/dispatcher.d/99-origin-dns.sh
# because it insists on placing cluster.local before the internal azure domain
# name in the search list.  This causes a deadlock at startup when the apiserver
# tries to connect to etcd: it tries to resolve master.cluster.local against
# dnsmasq, which tries the apiserver dns, which isn't up yet.
# TODO: revisit this code.

# ensure our image doesn't have this script
rm -f /etc/NetworkManager/dispatcher.d/99-origin-dns.sh

systemctl restart NetworkManager.service

nmcli con modify eth0 ipv4.dns-search "$(dnsdomainname) cluster.local"
nmcli con modify eth0 ipv4.dns "$(ifconfig eth0 | awk '/inet / { print $2; }')"

systemctl restart NetworkManager.service

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


echo "BOOTSTRAP_CONFIG_NAME=changeme" >> /etc/sysconfig/atomic-openshift-node

cat >/etc/sysconfig/iptables <<'EOF'
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
:DOCKER - [0:0]
-A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
-A OUTPUT ! -d 127.0.0.0/8 -m addrtype --dst-type LOCAL -j DOCKER
-A POSTROUTING -s 172.17.0.0/16 ! -o docker0 -j MASQUERADE
-A DOCKER -i docker0 -j RETURN
COMMIT
*filter
:INPUT ACCEPT [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
:DOCKER - [0:0]
:DOCKER-ISOLATION - [0:0]
:OS_FIREWALL_ALLOW - [0:0]
-A INPUT -j OS_FIREWALL_ALLOW
-A FORWARD -j DOCKER-ISOLATION
-A FORWARD -o docker0 -j DOCKER
-A FORWARD -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -i docker0 ! -o docker0 -j ACCEPT
-A FORWARD -i docker0 -o docker0 -j ACCEPT
-A DOCKER-ISOLATION -j RETURN
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 2379 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 2380 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 8443 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 8444 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 8053 -j ACCEPT
-A OS_FIREWALL_ALLOW -p udp -m state --state NEW -m udp --dport 8053 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 9090 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 10250 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT
-A OS_FIREWALL_ALLOW -p udp -m state --state NEW -m udp --dport 4789 -j ACCEPT
COMMIT
*security
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A OUTPUT -d 168.63.129.16/32 -p tcp -m owner --uid-owner 0 -j ACCEPT
-A OUTPUT -d 168.63.129.16/32 -p tcp -m conntrack --ctstate INVALID,NEW -j ACCEPT
COMMIT
EOF

iptables-restore </etc/sysconfig/iptables

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

export KUBECONFIG=/etc/origin/master/admin.kubeconfig

while ! curl -o /dev/null -m 2 -kfs https://localhost:8443/healthz; do
	sleep 1
done

while ! oc get svc kubernetes &>/dev/null; do
	sleep 1
done

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

mkdir -p /root/.kube
cp /etc/origin/master/admin.kubeconfig /root/.kube/config

# TODO: possibly wait here for convergence?

exit 0
