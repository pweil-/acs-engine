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

{{- if .IsInfra }}
echo "BOOTSTRAP_CONFIG_NAME=node-config-infra" >> /etc/sysconfig/atomic-openshift-node
{{ else }}
echo "BOOTSTRAP_CONFIG_NAME=node-config-compute" >> /etc/sysconfig/atomic-openshift-node
{{- end }}


rm -rf /etc/etcd/* /etc/origin/master/* /etc/origin/node/*

( cd / && base64 -d <<< {{ .ConfigBundle }} | tar -xz)

cp /etc/origin/node/ca.crt /etc/pki/ca-trust/source/anchors/openshift-ca.crt
update-ca-trust

# TODO: when enabling secure registry, may need:
# ln -s /etc/origin/node/node-client-ca.crt /etc/docker/certs.d/docker-registry.default.svc:5000

# note: atomic-openshift-node crash loops until master is up
systemctl enable atomic-openshift-node.service
systemctl start atomic-openshift-node.service

exit 0
