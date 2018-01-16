#!/bin/bash -xe
export SALT_MASTER_DEPLOY_IP=172.16.164.15
export SALT_MASTER_MINION_ID=cfg01.deploy-name.local
export DEPLOY_NETWORK_GW=172.16.164.1
export DEPLOY_NETWORK_NETMASK=255.255.255.192
export DNS_SERVERS=8.8.8.8
export SYSTEM_URL=https://github.com/Mirantis/reclass-system-salt-model.git
export http_proxy=
export https_proxy=
export PIPELINES_FROM_ISO=true
export PIPELINE_REPO_URL=https://github.com/Mirantis
#for cloning from aptly image use port 8088
#export PIPELINE_REPO_URL=http://172.16.47.182:8088

rm -vf /etc/update-motd.d/52-info
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
cp -r /mnt/model/model/* /srv/salt/reclass/
cp -r /mnt/model/model/.git /srv/salt/reclass/
envsubst < /root/gitmodules > /srv/salt/reclass/.gitmodules
cd /srv/salt/reclass/classes/system/
git remote remove origin
git remote add origin $SYSTEM_URL
cd /srv/salt/reclass/
git submodule update --init --recursive
chown -R root:root /srv/salt/reclass/*
chown -R root:root /srv/salt/reclass/.git*
chmod -R 644 /srv/salt/reclass/classes/cluster/*
chmod -R 644 /srv/salt/reclass/classes/system/*

echo "Configuring salt"
#service salt-master restart
envsubst < /root/minion.conf > /etc/salt/minion.d/minion.conf
service salt-minion restart
while true; do
    salt-key | grep "$SALT_MASTER_MINION_ID" && break
    sleep 5
done
sleep 5
for i in `salt-key -l accepted | grep -v Accepted | grep -v "$SALT_MASTER_MINION_ID"`; do
    salt-key -d $i -y
done

find /var/lib/jenkins/jenkins.model.JenkinsLocationConfiguration.xml -type f -print0 | xargs -0 sed -i -e 's/10.167.4.15/'$SALT_MASTER_DEPLOY_IP'/g'

echo "updating git repos"
if [ "$PIPELINES_FROM_ISO" = true ] ; then
  cp -r /mnt/mk-pipelines/* /home/repo/mk/mk-pipelines/
  cp -r /mnt/pipeline-library/* /home/repo/mcp-ci/pipeline-library/
  umount /dev/cdrom
  chown -R git:www-data /home/repo/mk/mk-pipelines/*
  chown -R git:www-data /home/repo/mcp-ci/pipeline-library/*
else
  umount /dev/cdrom
  git clone --mirror $PIPELINE_REPO_URL/mk-pipelines.git /home/repo/mk/mk-pipelines/
  git clone --mirror $PIPELINE_REPO_URL/pipeline-library.git /home/repo/mcp-ci/pipeline-library/
  chown -R git:www-data /home/repo/mk/mk-pipelines/*
  chown -R git:www-data /home/repo/mcp-ci/pipeline-library/*
fi

ssh-keyscan cfg01 > /var/lib/jenkins/.ssh/known_hosts

salt-call saltutil.refresh_pillar
salt-call saltutil.sync_all
salt-call state.sls linux.network,linux,openssh,salt
salt-call state.sls maas.cluster,maas.region,reclass

pillar=`salt-call pillar.data jenkins:client`

if [[ $pillar == *"job"* ]]; then
  salt-call state.sls jenkins.client
fi

reboot
