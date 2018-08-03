#!/bin/bash -xe

export SALT_MASTER_DEPLOY_IP=10.1.0.14
export APTLY_DEPLOY_IP=10.1.0.14
export APTLY_DEPLOY_NETMASK=255.255.0.0
export APTLY_MINION_ID=apt01.deploy-name.local

# Funcs =======================================================================
function docker_ca_wa(){
  crt="/var/lib/docker/swarm/certificates/swarm-node.crt"
  if ! $(openssl x509 -checkend 86400 -noout -in ${crt}); then
    echo "WARNING: swarm CA not expired yet.Something wrong with docker"
    echo "WARNING: docker CA WA not applied"
    exit 1
  fi
  echo 'WARNING: re-creating docker stack services!'

  systemctl stop docker || true
  rm -rf /var/lib/docker/swarm/*
  systemctl restart docker
  sleep 5
  docker swarm init --advertise-addr 127.0.0.1
  sleep 5
  for c in docker aptly; do
    pushd /etc/docker/compose/${c}/
    retry=5
    i=1
    while [[ $i -lt $retry ]]; do
    docker stack deploy --compose-file docker-compose.yml ${c};
    ret=$?;
    if [[ $ret -eq 0 ]]; then echo 'Stack created'; break;
    else
      echo "Stack creation failed, retrying in 3 seconds.." >&2;
      sleep 3;
      i=$(( i + 1 ));
    fi;
    if [[ $i -ge $retry ]]; then
      echo "Stack creation failed!"; exit 1;
    fi;
  done;
    popd
  sleep 1
  done
}

# Body ========================================================================
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

echo "Configuring salt"
rm -f /etc/salt/pki/minion/minion_master.pub
envsubst < /root/minion.conf > /etc/salt/minion.d/minion.conf
service salt-minion restart

# Check for failed docker-start.
# WA PROD-21676
if [[ ! $(docker stack ls) ]] ; then
  docker_ca_wa
fi

