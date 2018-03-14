#!/bin/bash

USERNAME=$1
SSHPRIVATEDATA=$2
SSHPUBLICDATA=$3

ps -ef | grep master.sh > cmdline.out

mkdir -p /home/$USERNAME/.ssh
echo $SSHPUBLICDATA > /home/$USERNAME/.ssh/id_rsa.pub
echo $SSHPRIVATEDATA | base64 --d > /home/$USERNAME/.ssh/id_rsa
chown $USERNAME /home/$USERNAME/.ssh/id_rsa.pub
chmod 600 /home/$USERNAME/.ssh/id_rsa.pub
chown $USERNAME /home/$USERNAME/.ssh/id_rsa
chmod 600 /home/$USERNAME/.ssh/id_rsa

mkdir -p /root/.ssh
echo $SSHPUBLICDATA > /root/.ssh/id_rsa.pub
echo $SSHPRIVATEDATA | base64 --d > /root/.ssh/id_rsa
chown root /root/.ssh/id_rsa.pub
chmod 600 /root/.ssh/id_rsa.pub
chown root /root/.ssh/id_rsa
chmod 600 /root/.ssh/id_rsa

mkdir -p /var/lib/origin/openshift.local.volumes

cat <<EOF > /home/${USERNAME}/.ansible.cfg
[defaults]
host_key_checking = False
EOF
chown ${USERNAME} /home/${USERNAME}/.ansible.cfg

cat <<EOF > /root/.ansible.cfg
[defaults]
host_key_checking = False
EOF


touch /root/.updateok
