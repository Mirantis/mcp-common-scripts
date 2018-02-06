#!/bin/bash

echo "deb [arch=amd64] http://apt.mirantis.com/xenial/ ${MCP_VERSION} salt" > /etc/apt/sources.list.d/mcp_salt.list
wget -O - http://apt.mirantis.com/public.gpg | apt-key add -
apt-get update
apt-get install git -y
apt-get install salt-formula* -y
git clone --recursive -b ${CLUSTER_MODEL_REF} ${CLUSTER_MODEL} /srv/salt/reclass
git clone https://github.com/salt-formulas/salt-formulas-scripts /srv/salt/scripts
# Parameters, for salt-formulas-scripts/bootstrap.sh
export FORMULAS_SOURCE=pkg
export HOSTNAME=apt01
export DOMAIN=${CLUSTER_NAME}.local
export CLUSTER_NAME=${CLUSTER_NAME}
export DISTRIB_REVISION=${MCP_VERSION}
export EXTRA_FORMULAS="ntp aptly nginx iptables docker"
/srv/salt/scripts/bootstrap.sh
salt-call state.sls salt
echo "COMPLETED" > /srv/initComplete
