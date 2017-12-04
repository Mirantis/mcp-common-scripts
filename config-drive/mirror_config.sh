#!/bin/bash -xe

export SALT_MASTER_DEPLOY_IP=10.1.0.14
export APTLY_DEPLOY_IP=10.1.0.14
export APTLY_DEPLOY_NETMASK=255.255.0.0
export APTLY_MINION_ID=apt01.deploy-name.local

echo "Configuring network interfaces"
envsubst < /root/interfaces > /etc/network/interfaces
ip a flush dev ens3
rm -f /var/run/network/ifstate.ens3
if [[ $(grep -E '^\ *gateway\ ' /etc/network/interfaces) ]]; then
(ip r s | grep ^default) && ip r d default || /bin/true
fi;
ifup ens3

echo "Configuring salt"
service salt-minion stop
systemctl disable salt-minion.service
envsubst < /root/minion.conf > /etc/salt/minion.d/minion.conf
#service salt-minion restart
