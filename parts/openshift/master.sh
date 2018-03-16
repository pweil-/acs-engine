#!/bin/bash -x

# todo this should come from the config tar and be put in /etc/sysconfig/iptables
iptables -A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 8443 -j ACCEPT
iptables-save > /etc/sysconfig/iptables
systemctl restart iptables

cat >>/etc/sysconfig/docker <<'EOF'
INSECURE_REGISTRY='--insecure-registry 172.30.0.0/16'
EOF

systemctl restart docker.service

cat >/etc/dnsmasq.d/node-dnsmasq.conf <<'EOF'
server=/in-addr.arpa/127.0.0.1
server=/cluster.local/127.0.0.1
EOF


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

# TODO openshift-ansible-roles not currently installed in custom image
#for file in /usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/v3.7/db-templates/*.json \
#    /usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/v3.7/image-streams/*-rhel7.json \
#	  /usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/v3.7/quickstart-templates/*.json \
#	  /usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/v3.7/xpaas-streams/*.json \
#	  /usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/v3.7/xpaas-templates/*.json; do
#	oc create -n openshift -f $file
#done

# TODO: possibly wait here for convergence?

mkdir -p /root/.kube
cp /etc/origin/master/admin.kubeconfig /root/.kube/config

exit 0
