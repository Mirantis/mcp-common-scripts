#!/bin/bash

functionsFile="$(pwd)/functions.sh"

if [[ ! -f ${functionsFile} ]]; then
  echo "ERROR: Can not find 'functions' libfile (${functionsFile}), check your mcp/mcp-common-scripts repo."
  exit 1
else
  source ${functionsFile}
fi

if [[ -z ${SLAVE_VM_NAME} ]]; then
  echo "ERROR: \$SLAVE_VM_NAME not set!"
  exit 1
fi
if [[ -z ${SLAVE_VM_SOURCE_DISK} ]] || [[ ! -f ${SLAVE_VM_SOURCE_DISK} ]]; then
  echo "ERROR: \$SLAVE_VM_SOURCE_DISK not set, or file does not exist!"
  exit 1
fi
if [[ -z ${VM_CONFIG_DISK} ]] || [[ ! -f ${VM_CONFIG_DISK} ]]; then
  echo "ERROR: \$VM_CONFIG_DISK not set, or file does not exist!"
  exit 1
fi

prereq_check "slave"

qemu-img resize ${SLAVE_VM_SOURCE_DISK} 80G
#### Make sure that disk saved to system path which is available for libvirt-qemu:kvm
export SLAVE_VM_SOURCE_DISK=$(place_file_under_libvirt_owned_dir ${SLAVE_VM_SOURCE_DISK} ${NON_DEFAULT_LIBVIRT_DIR})

### Create simple ISO file for a slave vm
networkDataFileBaseName='network_data.json'
networkDataFile=$(isoinfo -i ${VM_CONFIG_DISK} -J -f | grep -w "${networkDataFileBaseName}")
contextFilePath=$(isoinfo -i ${VM_CONFIG_DISK} -J -f | grep -w "context_data.yml")
allocationDataFile=$(isoinfo -i ${VM_CONFIG_DISK} -J -f | grep -w "allocation_data.yml")
saltMasterIp=$(isoinfo -i ${VM_CONFIG_DISK} -J -x ${allocationDataFile} | grep -w 'infra_config_deploy_address' | cut -f 2 -d ':' | tr -d ' ')
clusterDomain=$(isoinfo -i ${VM_CONFIG_DISK} -J -x ${contextFilePath} | grep -w 'cluster_domain:' | cut -f 2 -d ':' | tr -d ' ')
aioIp=$(isoinfo -i ${VM_CONFIG_DISK} -J -x ${allocationDataFile} | grep -w 'aio_node_deploy_address:' | cut -f 2 -d ':' | tr -d ' ')
aioHostname=$(isoinfo -i ${VM_CONFIG_DISK} -J -x ${allocationDataFile} | grep -w 'aio_node_hostname:' | cut -f 2 -d ':' | tr -d ' ')
aioFailSafeUserKey=$(isoinfo -i ${VM_CONFIG_DISK} -J -x ${contextFilePath} | grep -w 'cfg_failsafe_ssh_public_key:' | cut -f 2 -d ':' | sed 's/ //')
aioFailSafeUser=$(isoinfo -i ${VM_CONFIG_DISK} -J -x ${contextFilePath} | grep -w 'cfg_failsafe_user:' | cut -f 2 -d ':' | tr -d ' ')
networkDataForSlave=$(isoinfo -i ${VM_CONFIG_DISK} -J -x ${networkDataFile} | sed -e "s/${saltMasterIp}/${aioIp}/g")

configDriveDir="$(dirname $0)/../config-drive"
pushd "${configDriveDir}"
echo -e ${networkDataForSlave} > ${networkDataFileBaseName}
cat <<EOF > ./user_data
#cloud-config
output : { all : '| tee -a /var/log/cloud-init-output.log' }
growpart:
  mode: auto
  devices:
    - '/'
    - '/dev/vda3'
  ignore_growroot_disabled: false
write_files:
  - content: |
      root:
        size: '70%VG'
      var_log:
        size: '10%VG'
      var_log_audit:
        size: '500M'
      var_tmp:
        size: '3000M'
      tmp:
        size: '500M'
    owner: root:root
    path: /usr/share/growlvm/image-layout.yml
slave_boot:
  - &slave_boot |
    #!/bin/bash

    # Redirect all outputs
    exec > >(tee -i /tmp/cloud-init-bootstrap.log) 2>&1
    set -xe

    echo "Configuring Salt minion ..."
    [ ! -d /etc/salt/minion.d ] && mkdir -p /etc/salt/minion.d
    echo -e "id: ${aioHostname}.${clusterDomain}\nmaster: ${saltMasterIp}" > /etc/salt/minion.d/minion.conf
    cat >> /etc/salt/minion.d/minion.conf << EOF
    log_level: info
    max_event_size: 100000000
    acceptance_wait_time_max: 60
    acceptance_wait_time: 10
    random_reauth_delay: 270
    recon_default: 1000
    recon_max: 60000
    recon_randomize: True
    auth_timeout: 60
    EOF

    systemctl restart salt-minion
    sleep 90
    cat /var/log/salt/minion
    sync


runcmd:
  - 'if lvs vg0; then pvresize /dev/vda3; fi'
  - 'if lvs vg0; then /usr/bin/growlvm.py --image-layout-file /usr/share/growlvm/image-layout.yml; fi'
  - [bash, -cex, *slave_boot]
EOF

isoArgs="--name ${aioHostname} --hostname ${aioHostname}.${clusterDomain} --user-data $(pwd)/user_data --network-data $(pwd)/${networkDataFileBaseName} --quiet --clean-up"
if [[ -n "${aioFailSafeUser}" ]] && [[ -n "${aioFailSafeUserKey}" ]]; then
  echo "${aioFailSafeUserKey}" > "failSafeKey.pub"
  isoArgs="${isoArgs} --cloud-user-name ${aioFailSafeUser} --ssh-keys failSafeKey.pub"
fi
python ./create_config_drive.py ${isoArgs}
#### Make sure that iso file is saved to system path which is available for libvirt-qemu:kvm
export SLAVE_VM_CONFIG_DISK=$(place_file_under_libvirt_owned_dir ${aioHostname}.${clusterDomain}-config.iso ${NON_DEFAULT_LIBVIRT_DIR})
popd

render_config "${SLAVE_VM_NAME}" "${SLAVE_VM_MEM_KB}" "${SLAVE_VM_CPUS}" "${SLAVE_VM_SOURCE_DISK}" "${SLAVE_VM_CONFIG_DISK}"

virsh define $(pwd)/${SLAVE_VM_NAME}-vm.xml
virsh autostart ${SLAVE_VM_NAME}
