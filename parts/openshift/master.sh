#!/bin/bash -x

cat >/var/lib/yum/client-cert.pem <<'EOF'
{{ .YumCert }}
EOF

cat >/var/lib/yum/client-key.pem <<'EOF'
{{ .YumKey }}
EOF
chmod 0600 /var/lib/yum/client-key.pem

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

[ansible]
name=ansible
baseurl=https://mirror.openshift.com/enterprise/rhel/rhel-7-server-ansible-2.4-rpms/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
sslclientcert=/var/lib/yum/client-cert.pem
sslclientkey=/var/lib/yum/client-key.pem

[ose]
name=OSE
baseurl=https://mirror.openshift.com/enterprise/enterprise-3.9/v3.9.11-1_2018-03-15.3/x86_64/os/
enabled=1
gpgcheck=0
sslclientcert=/var/lib/yum/client-cert.pem
sslclientkey=/var/lib/yum/client-key.pem
EOF

RPMS=(
	atomic-openshift-docker-excluder
	atomic-openshift-excluder
	atomic-openshift-master
	atomic-openshift-sdn-ovs
	ceph-common
	cockpit-docker
	cockpit-kubernetes
	cockpit-ws
	device-mapper-multipath
	dnsmasq
	etcd
	glusterfs-fuse
	iscsi-initiator-utils
	kexec-tools
	openshift-ansible
	python-docker
)

yum -y install ${RPMS[*]}

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

# TODO: probably shouldn't be hardcoded
cat >/etc/dnsmasq.d/origin-upstream-dns.conf <<'EOF'
server=168.63.129.16
EOF

systemctl enable dnsmasq.service
systemctl start dnsmasq.service

# TODO: remove this once we generate the registry certificate
cat >>/etc/sysconfig/docker <<'EOF'
INSECURE_REGISTRY='--insecure-registry 172.30.0.0/16'
EOF

mkdir /var/lib/origin/.docker
cat >/var/lib/origin/.docker/config.json <<'EOF'
{{ .DockerConfig }}
EOF

systemctl enable docker.service
systemctl start docker.service

cat >/etc/multipath.conf <<'EOF'
# LIO iSCSI
# TODO: Add env variables for tweaking
devices {
        device {
                vendor "LIO-ORG"
                user_friendly_names "yes"
                path_grouping_policy "failover"
                path_selector "round-robin 0"
                failback immediate
                path_checker "tur"
                prio "const"
                no_path_retry 120
                rr_weight "uniform"
        }
}
defaults {
	user_friendly_names yes
	find_multipaths yes
}


blacklist {
}
EOF

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

cat >/etc/profile.d/etcdctl.sh <<'EOF'
#!/bin/bash
# Sets up handy aliases for etcd, need etcdctl2 and etcdctl3 because
# command flags are different between the two. Should work on stand
# alone etcd hosts and master + etcd hosts too because we use the peer keys.
etcdctl2() {
 /usr/bin/etcdctl --cert-file /etc/etcd/peer.crt --key-file /etc/etcd/peer.key --ca-file /etc/etcd/ca.crt -C https://`hostname`:2379 ${@}

}

etcdctl3() {
 ETCDCTL_API=3 /usr/bin/etcdctl --cert /etc/etcd/peer.crt --key /etc/etcd/peer.key --cacert /etc/etcd/ca.crt --endpoints https://`hostname`:2379 ${@}
}
EOF

setsebool -P virt_use_fusefs=1 virt_sandbox_use_fusefs=1

cat >/etc/sysconfig/atomic-openshift-master-api <<'EOF'
OPTIONS=--loglevel=2 --listen=https://0.0.0.0:8443 --master=https://master.4cbn1uxzm15ubkznys5dzhjadf.bx.internal.cloudapp.net:8443
CONFIG_FILE=/etc/origin/master/master-config.yaml
OPENSHIFT_DEFAULT_REGISTRY=docker-registry.default.svc:5000


# Proxy configuration
# See https://docs.openshift.com/enterprise/latest/install_config/install/advanced_install.html#configuring-global-proxy
EOF

cat >/etc/sysconfig/atomic-openshift-master-api <<'EOF'
OPTIONS=--loglevel=2 --listen=https://0.0.0.0:8443 --master=https://master.4cbn1uxzm15ubkznys5dzhjadf.bx.internal.cloudapp.net:8443
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

cat >/etc/sysconfig/atomic-openshift-node <<'EOF'
OPTIONS=--loglevel=2
# /etc/origin/node/ should contain the entire contents of
# /var/lib/origin.local.certificates/node-${node-fqdn} generated by
# running 'openshift admin create-node-config' on your master
#
# If if your node is running on a separate host you can rsync the contents
# rsync -a root@openshift-master:/var/lib/origin/origin.local.certificates/node-`hostname`/ /etc/origin/node
CONFIG_FILE=/etc/origin/node/node-config.yaml

# Proxy configuration
# Origin uses standard HTTP_PROXY environment variables. Be sure to set
# NO_PROXY for your master
#NO_PROXY=master.example.com
#HTTP_PROXY=http://USER:PASSWORD@IPADDR:PORT
#HTTPS_PROXY=https://USER:PASSWORD@IPADDR:PORT
IMAGE_VERSION=v3.9.11
EOF

cat >/etc/sysconfig/iptables <<'EOF'
# Generated by iptables-save v1.4.21 on Sat Mar 17 04:18:28 2018
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [81:5636]
:POSTROUTING ACCEPT [81:5636]
:DOCKER - [0:0]
-A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
-A OUTPUT ! -d 127.0.0.0/8 -m addrtype --dst-type LOCAL -j DOCKER
-A POSTROUTING -s 172.17.0.0/16 ! -o docker0 -j MASQUERADE
-A DOCKER -i docker0 -j RETURN
COMMIT
# Completed on Sat Mar 17 04:18:28 2018
# Generated by iptables-save v1.4.21 on Sat Mar 17 04:18:28 2018
*filter
:INPUT ACCEPT [11:4226]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [11:4226]
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
# Completed on Sat Mar 17 04:18:28 2018
# Generated by iptables-save v1.4.21 on Sat Mar 17 04:18:28 2018
*security
:INPUT ACCEPT [325534:387682758]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [155151:118912961]
-A OUTPUT -d 168.63.129.16/32 -p tcp -m owner --uid-owner 0 -j ACCEPT
-A OUTPUT -d 168.63.129.16/32 -p tcp -m conntrack --ctstate INVALID,NEW -j ACCEPT
COMMIT
# Completed on Sat Mar 17 04:18:28 2018
EOF

iptables-restore </etc/sysconfig/iptables

cat >/etc/sysctl.d/99-openshift.conf <<'EOF'
net.ipv4.ip_forward=1
EOF

sysctl -p

cat >/etc/systemd/journald.conf <<'EOF'
#  This file is part of systemd.
#
#  systemd is free software; you can redistribute it and/or modify it
#  under the terms of the GNU Lesser General Public License as published by
#  the Free Software Foundation; either version 2.1 of the License, or
#  (at your option) any later version.
#
# Entries in this file show the compile time defaults.
# You can change settings by editing this file.
# Defaults can be restored by simply deleting this file.
#
# See journald.conf(5) for details.

[Journal]
 Storage=persistent
 Compress=True
#Seal=yes
#SplitMode=uid
 SyncIntervalSec=1s
 RateLimitInterval=1s
 RateLimitBurst=10000
 SystemMaxUse=8G
 SystemMaxFileSize=10M
#RuntimeKeepFree=
#RuntimeMaxFileSize=
 MaxRetentionSec=1month
 ForwardToSyslog=False
#ForwardToKMsg=no
#ForwardToConsole=no
 ForwardToWall=False
#TTYPath=/dev/console
#MaxLevelStore=debug
#MaxLevelSyslog=debug
#MaxLevelKMsg=notice
#MaxLevelConsole=info
#MaxLevelWall=emerg
EOF

systemctl restart systemd-journald.service

systemctl mask atomic-openshift-master.service

cat >/etc/systemd/system/atomic-openshift-node.service <<'EOF'
[Unit]
Description=OpenShift Node
After=docker.service
After=chronyd.service
After=ntpd.service
Wants=openvswitch.service
After=ovsdb-server.service
After=ovs-vswitchd.service
Wants=docker.service
Documentation=https://github.com/openshift/origin
Wants=dnsmasq.service
After=dnsmasq.service

[Service]
Type=notify
EnvironmentFile=/etc/sysconfig/atomic-openshift-node
Environment=GOTRACEBACK=crash
ExecStartPre=/usr/bin/cp /etc/origin/node/node-dnsmasq.conf /etc/dnsmasq.d/
ExecStartPre=/usr/bin/dbus-send --system --dest=uk.org.thekelleys.dnsmasq /uk/org/thekelleys/dnsmasq uk.org.thekelleys.SetDomainServers array:string:/in-addr.arpa/127.0.0.1,/cluster.local/127.0.0.1
ExecStopPost=/usr/bin/rm /etc/dnsmasq.d/node-dnsmasq.conf
ExecStopPost=/usr/bin/dbus-send --system --dest=uk.org.thekelleys.dnsmasq /uk/org/thekelleys/dnsmasq uk.org.thekelleys.SetDomainServers array:string:
ExecStart=/usr/bin/openshift start node  --config=${CONFIG_FILE} $OPTIONS
LimitNOFILE=65536
LimitCORE=infinity
WorkingDirectory=/var/lib/origin/
SyslogIdentifier=atomic-openshift-node
Restart=always
RestartSec=5s
TimeoutStartSec=300
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF

mkdir /etc/systemd/system/atomic-openshift-node.service.wants
ln -s /usr/lib/systemd/system/atomic-openshift-master-api.service /etc/systemd/system/atomic-openshift-node.service.wants

mkdir -p /etc/systemd/system/openvswitch.service.d
cat >/etc/systemd/system/openvswitch.service.d/01-avoid-oom.conf <<'EOF'
# Avoid the OOM killer for openvswitch and it's children:
[Service]
OOMScoreAdjust=-1000
EOF

# note: /etc/tuned should also be set up

# note: ansible updates exclude= in /etc/yum.conf

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

# TODO: does systemd need to be reloaded?

for unit in cockpit.socket iscsid.service; do
	systemctl enable $unit
	systemctl start $unit
done

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
