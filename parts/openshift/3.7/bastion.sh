#!/bin/bash

###
# Place the ssh keys on bastion so it can reach all the other hosts
###
mkdir -p ~/.ssh

echo $1 | base64 --d > ~/.ssh/id_rsa
echo $2 > ~/.ssh/id_rsa.pub
chmod 600 ~/.ssh/id_rsa*

echo "Done!"