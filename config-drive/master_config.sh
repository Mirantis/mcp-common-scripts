#!/bin/bash -xe

export SALT_MASTER_DEPLOY_IP=172.16.164.15
export SALT_MASTER_MINION_ID=cfg01.deploy-name.local
export DEPLOY_NETWORK_GW=172.16.164.1
export DEPLOY_NETWORK_NETMASK=255.255.255.192
export DNS_SERVERS=8.8.8.8
export http_proxy=
export https_proxy=
export PIPELINES_FROM_ISO=true
export PIPELINE_REPO_URL=https://github.com/Mirantis
export MCP_VERSION=stable
export MCP_SALT_REPO_KEY=http://apt.mirantis.com/public.gpg
export MCP_SALT_REPO_URL=http://apt.mirantis.com/xenial
export MCP_SALT_REPO="deb [arch=amd64] $MCP_SALT_REPO_URL $MCP_VERSION salt"
export FORMULAS="salt-formula-*"
# Not avaible in 2018.4 and pre.
export LOCAL_REPOS=false
export SALT_OPTS=${SALT_OPTS:-"-l debug -t 30 --retcode-passthrough --no-color"}
#for cloning from aptly image use port 8088
#export PIPELINE_REPO_URL=http://172.16.47.182:8088

function _apt_cfg(){
  # TODO remove those function after 2018.4 release
  echo "Acquire::CompressionTypes::Order gz;" >/etc/apt/apt.conf.d/99compression-workaround-salt
  echo "Acquire::EnableSrvRecords false;" >/etc/apt/apt.conf.d/99enablesrvrecords-false
  echo "Acquire::http::Pipeline-Depth 0;" > /etc/apt/apt.conf.d/99aws-s3-mirrors-workaround-salt
  echo "APT::Install-Recommends false;" > /etc/apt/apt.conf.d/99dont_install_recommends-salt
  echo "APT::Install-Suggests false;" > /etc/apt/apt.conf.d/99dont_install_suggests-salt
  echo "Acquire::Languages none;" > /etc/apt/apt.conf.d/99dont_acquire_all_languages-salt
  echo "APT::Periodic::Update-Package-Lists 0;" > /etc/apt/apt.conf.d/99dont_update_package_list-salt
  echo "APT::Periodic::Download-Upgradeable-Packages 0;" > /etc/apt/apt.conf.d/99dont_update_download_upg_packages-salt
  echo "APT::Periodic::Unattended-Upgrade 0;" > /etc/apt/apt.conf.d/99disable_unattended_upgrade-salt
  echo "INFO: cleaning sources lists"
  rm -rv /etc/apt/sources.list.d/* || true
  echo > /etc/apt/sources.list  || true
}

function _post_maas_cfg(){
  local PROFILE=mirantis
  # TODO: remove those check, and use only new version, adfter 2018.4 release
  if [[ -f /var/lib/maas/.maas_login.sh ]]; then
    /var/lib/maas/.maas_login.sh
  else
    echo "WARNING: Attempt to use old maas login schema.."
    TOKEN=$(cat /var/lib/maas/.maas_credentials);
    maas list | cut -d' ' -f1 | xargs -I{} maas logout {}
    maas login $PROFILE http://127.0.0.1:5240/MAAS/api/2.0/ "${TOKEN}"
  fi
  # disable backports for maas enlist pkg repo
  maas ${PROFILE} package-repository update 1 "disabled_pockets=backports"
  maas ${PROFILE} package-repository update 1 "arches=amd64"
  # Download ubuntu image from MAAS local mirror
  if [[ "$LOCAL_REPOS" == "true" ]] ; then
    maas ${PROFILE} boot-source-selections create 2 os="ubuntu" release="xenial" arches="amd64" subarches="*" labels="*"
    echo "WARNING: Removing default MAAS stream:"
    maas ${PROFILE} boot-source read 1
    maas ${PROFILE} boot-source delete 1
    maas ${PROFILE} boot-resources import
    # TODO wait for finish,and stop import.
  fi
}

function process_maas(){
      maas_cluster_enabled=$(salt-call --out=text pillar.get maas:cluster:enabled | awk '{print $2}' | tr "[:upper:]" "[:lower:]" )
      _region=$(salt-call --out=text pillar.get maas:region:enabled | awk '{print $2}' | tr "[:upper:]" "[:lower:]" )

      if [[ "${maas_cluster_enabled}" == "true" ]] || [[ "$_region" == "true" ]]; then
        salt-call state.sls maas.cluster,maas.region || salt-call state.sls maas.cluster,maas.region
      else
        echo "WARNING: maas.cluster skipped!"
      fi
      # Do not move it under first cluster-only check!
      if [[ "${maas_cluster_enabled}" == "true" ]]; then
        _post_maas_cfg
      fi
}


### Body
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

echo "Preparing metadata model"
mount /dev/cdrom /mnt/
cp -rT /mnt/model/model /srv/salt/reclass
chown -R root:root /srv/salt/reclass/*
chown -R root:root /srv/salt/reclass/.git* || true
chmod -R 644 /srv/salt/reclass/classes/cluster/* || true
chmod -R 644 /srv/salt/reclass/classes/system/*  || true

echo "Configuring salt"
#service salt-master restart
envsubst < /root/minion.conf > /etc/salt/minion.d/minion.conf
service salt-minion restart
while true; do
    salt-key | grep "$SALT_MASTER_MINION_ID" && break
    sleep 5
done
sleep 5
for i in $(salt-key -l accepted | grep -v Accepted | grep -v "$SALT_MASTER_MINION_ID"); do
    salt-key -d $i -y
done

find /var/lib/jenkins/jenkins.model.JenkinsLocationConfiguration.xml -type f -print0 | xargs -0 sed -i -e 's/10.167.4.15/'$SALT_MASTER_DEPLOY_IP'/g'

echo "updating git repos"
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

echo "installing formulas"
_apt_cfg
curl -s $MCP_SALT_REPO_KEY | sudo apt-key add -
echo $MCP_SALT_REPO > /etc/apt/sources.list.d/mcp_salt.list
apt-get update
apt-get install -y $FORMULAS
rm -rf /srv/salt/reclass/classes/service/*
cd /srv/salt/reclass/classes/service/;ls /usr/share/salt-formulas/reclass/service/ -1 | xargs -I{} ln -s /usr/share/salt-formulas/reclass/service/{};cd /root

salt-call saltutil.refresh_pillar
salt-call saltutil.sync_all
if ! $(reclass -n ${SALT_MASTER_MINION_ID} > /dev/null ) ; then
  echo "ERROR: Reclass render failed!"
  exit 1
fi

salt-call state.sls linux.network,linux,openssh,salt
salt-call state.sls salt
salt-call state.sls reclass
process_maas

ssh-keyscan cfg01 > /var/lib/jenkins/.ssh/known_hosts || true

pillar=$(salt-call pillar.data jenkins:client)

if [[ $pillar == *"job"* ]]; then
  salt-call state.sls jenkins.client
fi

reboot
