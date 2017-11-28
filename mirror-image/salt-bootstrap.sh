#!/bin/bash
apt-get update
apt-get install git -y
apt-get install salt-formula* -y
git clone $CLUSTER_MODEL --recursive /srv/salt/reclass
git clone https://github.com/salt-formulas/salt-formulas-scripts /srv/salt/scripts
export FORMULAS_SOURCE=pkg
export HOSTNAME=apt01
export DOMAIN=$CLUSTER_NAME.local
export CLUSTER_NAME=$CLUSTER_NAME
/srv/salt/scripts/bootstrap.sh
ln -s  /usr/share/salt-formulas/reclass/service/ntp /srv/salt/reclass/classes/service
ln -s  /usr/share/salt-formulas/reclass/service/aptly /srv/salt/reclass/classes/service
ln -s  /usr/share/salt-formulas/reclass/service/nginx /srv/salt/reclass/classes/service
ln -s  /usr/share/salt-formulas/reclass/service/iptables /srv/salt/reclass/classes/service
ln -s  /usr/share/salt-formulas/reclass/service/docker /srv/salt/reclass/classes/service
salt-call state.sls salt
echo "COMPLETED" > /srv/initComplete