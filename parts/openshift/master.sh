#!/bin/bash

cat >/var/lib/yum/client-cert.pem <<'EOF'
{{ .OrchestratorProfile.OpenShiftConfig.YumCert }}
EOF

cat >/var/lib/yum/client-key.pem <<'EOF'
{{ .OrchestratorProfile.OpenShiftConfig.YumKey }}
EOF

cat >/etc/yum.repos.d/ose.repo <<'EOF'
[rhel7]
name=RHEL7
baseurl=https://mirror.openshift.com/libra/rhui-rhel-server-7-releases/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
sslclientcert=/var/lib/yum/client-cert.pem
sslclientkey=/var/lib/yum/client-key.pem

[extras]
name=RHEL7-extras
baseurl=https://mirror.openshift.com/libra/rhui-rhel-server-7-extras/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
sslclientcert=/var/lib/yum/client-cert.pem
sslclientkey=/var/lib/yum/client-key.pem

[fast-datapath]
name=RHEL7-fast-datapath
baseurl=https://mirror.openshift.com/libra/rhui-rhel-7-fast-datapath-rpms/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
sslclientcert=/var/lib/yum/client-cert.pem
sslclientkey=/var/lib/yum/client-key.pem

[ose]
name=OSE
baseurl=https://mirror.openshift.com/enterprise/enterprise-3.7/v3.7.23-1_2018-01-11.2/RH7-RHAOS-3.7/x86_64/os/
enabled=1
gpgcheck=0
sslclientcert=/var/lib/yum/client-cert.pem
sslclientkey=/var/lib/yum/client-key.pem
EOF

yum -y install atomic-openshift-master atomic-openshift-node atomic-openshift-sdn-ovs dnsmasq etcd openshift-ansible-roles openvswitch

cat >/etc/cni/net.d/80-openshift-network.conf <<'EOF'
{
  "cniVersion": "0.2.0",
  "name": "openshift-sdn",
  "type": "openshift-sdn"
}
EOF

cat >>/etc/sysconfig/docker <<'EOF'
INSECURE_REGISTRY='--insecure-registry 172.30.0.0/16'
ADD_REGISTRY='--add-registry registry.access.redhat.com'
EOF

systemctl enable docker.service
systemctl start docker.service

cat >/etc/dnsmasq.d/node-dnsmasq.conf <<'EOF'
server=/in-addr.arpa/127.0.0.1
server=/cluster.local/127.0.0.1
EOF

cat >/etc/dnsmasq.d/origin-dns.conf <<'EOF'
no-resolv
domain-needed
no-negcache
max-cache-ttl=1
enable-dbus
dns-forward-max=5000
cache-size=5000
bind-dynamic
except-interface=lo
# End of config
EOF

cat >/etc/dnsmasq.d/origin-upstream-dns.conf <<'EOF'
server=168.63.129.16
EOF

systemctl enable dnsmasq.service
systemctl start dnsmasq.service

rm -rf /etc/etcd/* /etc/origin/master/* /etc/origin/node/*

( cd / && base64 -d <<< {{ Base64 (index .OrchestratorProfile.OpenShiftConfig.ConfigBundles "master") }} | tar -xz)

chown -R etcd:etcd /etc/etcd

systemctl enable etcd.service
systemctl start etcd.service

systemctl enable atomic-openshift-master.service
systemctl start atomic-openshift-master.service

systemctl enable atomic-openshift-node.service
systemctl start atomic-openshift-node.service

export KUBECONFIG=/etc/origin/master/admin.kubeconfig

while ! curl -o /dev/null -m 2 -kfs https://localhost:8443/healthz; do
	sleep 1
done

while ! oc get svc kubernetes &>/dev/null; do
	sleep 1
done

oc adm registry

oc adm policy add-scc-to-user hostnetwork -z router
oc adm router

for file in /usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/v3.7/db-templates/*.json \
    /usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/v3.7/image-streams/*-rhel7.json \
	  /usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/v3.7/quickstart-templates/*.json \
	  /usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/v3.7/xpaas-streams/*.json \
	  /usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/v3.7/xpaas-templates/*.json; do
	oc create -n openshift -f $file
done

# TODO: possibly wait here for convergence?

exit 0
