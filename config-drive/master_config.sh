#!/bin/bash -xe

#==============================================================================
# Required packages:
#   apt-get install -y jq
#==============================================================================
export SALT_MASTER_DEPLOY_IP=${SALT_MASTER_DEPLOY_IP:-"172.16.164.15"}
export SALT_MASTER_MINION_ID=${SALT_MASTER_MINION_ID:-"cfg01.deploy-name.local"}
export DEPLOY_NETWORK_GW=${DEPLOY_NETWORK_GW:-"172.16.164.1"}
export DEPLOY_NETWORK_NETMASK=${DEPLOY_NETWORK_NETMASK:-"255.255.255.192"}
export DEPLOY_NETWORK_MTU=${DEPLOY_NETWORK_MTU:-"1500"}
export DNS_SERVERS=${DNS_SERVERS:-"8.8.8.8"}
export http_proxy=${http_proxy:-""}
export https_proxy=${https_proxy:-""}
export PIPELINES_FROM_ISO=${PIPELINES_FROM_ISO:-"true"}
export PIPELINE_REPO_URL=${PIPELINE_REPO_URL:-"https://github.com/Mirantis"}
export MCP_VERSION=${MCP_VERSION:-"stable"}
export MCP_SALT_REPO_KEY=${MCP_SALT_REPO_KEY:-"http://apt.mirantis.com/public.gpg"}
export MCP_SALT_REPO_URL=${MCP_SALT_REPO_URL:-"http://apt.mirantis.com/xenial"}
export MCP_SALT_REPO="deb [arch=amd64] $MCP_SALT_REPO_URL $MCP_VERSION salt"
export FORMULAS="salt-formula-*"
# for cloning from aptly image use port 8088
#export PIPELINE_REPO_URL=http://172.16.47.182:8088
#
SALT_OPTS="-l debug -t 10 --retcode-passthrough --no-color"

# Funcs =======================================================================
function _post_maas_cfg(){
  chmod 0755 /var/lib/maas/.maas_login.sh
  source /var/lib/maas/.maas_login.sh
  # disable backports for maas enlist pkg repo. Those operation enforce maas
  # to re-create sources.list and drop [source] fetch-definition from it.
  main_arch_id=$(maas ${PROFILE} package-repositories read | jq -r '.[] | select(.name=="main_archive") | .id')
  maas ${PROFILE} package-repository update ${main_arch_id} "disabled_pockets=backports" || true
  maas ${PROFILE} package-repository update ${main_arch_id} "disabled_components=multiverse" || true
  maas ${PROFILE} package-repository update ${main_arch_id} "arches=amd64" || true
  # Remove stale notifications, which appear during sources configuration.
  for i in $(maas ${PROFILE} notifications read | jq '.[]| .id'); do
    maas ${PROFILE} notification delete ${i} || true
  done
}

function process_formulas(){
    local RECLASS_ROOT=${RECLASS_ROOT:-/srv/salt/reclass/}
    local FORMULAS_PATH=${FORMULAS_PATH:-/usr/share/salt-formulas}

    echo "Configuring formulas ..."
    curl -s $MCP_SALT_REPO_KEY | apt-key add -
    echo $MCP_SALT_REPO > /etc/apt/sources.list.d/mcp_salt.list
    apt-get update
    apt-get install -y $FORMULAS

    [ ! -d ${RECLASS_ROOT}/classes/service ] && mkdir -p ${RECLASS_ROOT}/classes/service
    for formula_service in $(ls /usr/share/salt-formulas/reclass/service/); do
        #Since some salt formula names contain "-" and in symlinks they should contain "_" adding replacement
        formula_service=${formula_service//-/$'_'}
        [ ! -L "${RECLASS_ROOT}/classes/service/${formula_service}" ] && \
            ln -sf ${FORMULAS_PATH}/reclass/service/${formula_service} ${RECLASS_ROOT}/classes/service/${formula_service}
    done
}

function enable_services(){
  local services="postgresql.service salt-api salt-master salt-minion jenkins"
  for s in ${services} ; do
    systemctl enable ${s} || true
    systemctl restart ${s} || true
  done
}

function process_network(){
  echo "Configuring network interfaces"
  find /etc/network/interfaces.d/ -type f -delete
  kill $(pidof /sbin/dhclient) || /bin/true
  envsubst < /root/interfaces > /etc/network/interfaces
  ip a flush dev ens3
  rm -f /var/run/network/ifstate.ens3
  if [[ $(grep -E '^\ *gateway\ ' /etc/network/interfaces) ]]; then
  (ip r s | grep ^default) && ip r d default || /bin/true
  fi;
  ifup ens3
}

# Body ========================================================================
process_network

echo "Preparing metadata model"
mount /dev/cdrom /mnt/
cp -rT /mnt/model/model /srv/salt/reclass
chown -R root:root /srv/salt/reclass/* || true
chown -R root:root /srv/salt/reclass/.git* || true
chmod -R 644 /srv/salt/reclass/classes/cluster/* || true
chmod -R 644 /srv/salt/reclass/classes/system/*  || true

echo "Configuring salt"
envsubst < /root/minion.conf > /etc/salt/minion.d/minion.conf
enable_services
while true; do
    salt-key | grep "$SALT_MASTER_MINION_ID" && break
    sleep 5
done

sleep 5
for i in $(salt-key -l accepted | grep -v Accepted | grep -v "$SALT_MASTER_MINION_ID"); do
    salt-key -d $i -y
done

find /var/lib/jenkins/jenkins.model.JenkinsLocationConfiguration.xml -type f -print0 | xargs -0 sed -i -e 's/10.167.4.15/'$SALT_MASTER_DEPLOY_IP'/g'

echo "updating local git repos"
if [[ "$PIPELINES_FROM_ISO" == "true" ]] ; then
  cp -r /mnt/mk-pipelines/* /home/repo/mk/mk-pipelines/
  cp -r /mnt/pipeline-library/* /home/repo/mcp-ci/pipeline-library/
  umount /dev/cdrom || true
  chown -R git:www-data /home/repo/mk/mk-pipelines/*
  chown -R git:www-data /home/repo/mcp-ci/pipeline-library/*
else
  umount /dev/cdrom || true
  git clone --mirror "${PIPELINE_REPO_URL}/mk-pipelines.git" /home/repo/mk/mk-pipelines/
  git clone --mirror "${PIPELINE_REPO_URL}/pipeline-library.git" /home/repo/mcp-ci/pipeline-library/
  chown -R git:www-data /home/repo/mk/mk-pipelines/*
  chown -R git:www-data /home/repo/mcp-ci/pipeline-library/*
fi

process_formulas

salt-call saltutil.refresh_pillar
salt-call saltutil.sync_all
if ! $(reclass -n ${SALT_MASTER_MINION_ID} > /dev/null ) ; then
  echo "ERROR: Reclass render failed!"
  exit 1
fi

salt-call ${SALT_OPTS} state.sls linux.network,linux,openssh,salt
salt-call ${SALT_OPTS} pkg.install salt-master,salt-minion
sleep 5
salt-call ${SALT_OPTS} state.sls salt
salt-call ${SALT_OPTS} state.sls maas.cluster,maas.region
salt-call ${SALT_OPTS} state.sls reclass

_post_maas_cfg

ssh-keyscan cfg01 > /var/lib/jenkins/.ssh/known_hosts || true

pillar=$(salt-call pillar.data jenkins:client)

if [[ $pillar == *"job"* ]]; then
  salt-call ${SALT_OPTS} state.sls jenkins.client
fi

stop_services="salt-api salt-master salt-minion jenkins maas-rackd.service maas-regiond.service postgresql.service"
for s in ${stop_services} ; do
  systemctl stop ${s} || true
  sleep 1
done
sync
reboot
