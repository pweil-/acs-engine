#!/bin/bash -x

# todo add this to the image
cat >>/etc/sysconfig/docker <<'EOF'
INSECURE_REGISTRY='--insecure-registry 172.30.0.0/16'
EOF

systemctl restart docker.service

cat >/etc/dnsmasq.d/node-dnsmasq.conf <<'EOF'
server=/in-addr.arpa/127.0.0.1
server=/cluster.local/127.0.0.1
EOF

systemctl restart dnsmasq.service

rm -rf /etc/etcd/* /etc/origin/master/* /etc/origin/node/*

( cd / && base64 -d <<< {{ Base64 (index .OrchestratorProfile.OpenShiftConfig.ConfigBundles "node1") }} | tar -xz)

systemctl enable atomic-openshift-node.service
systemctl start atomic-openshift-node.service

exit 0
