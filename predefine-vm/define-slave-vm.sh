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

check_packages "slave"

configDriveDir="$(dirname $0)/../config-drive"
pushd "${configDriveDir}"
tmpDir=$(mktemp -d -p $(pwd))
mount ${VM_CONFIG_DISK} ${tmpDir}
contextFile=$(find ${tmpDir}/mcp -name context_data.yml)
allocationDataFile=$(find ${tmpDir}/mcp -name allocation_data.yml)
saltMasterIp=$(grep salt_master_management_address ${contextFile} | cut -f 2 -d ':' | tr -d ' ')
clusterDomain=$(grep cluster_domain ${contextFile} | cut -f 2 -d ':' | tr -d ' ')
aioIp=$(grep 'aio_node_deploy_address:' ${allocationDataFile} | cut -f 2 -d ':' | tr -d ' ')
aioHostname=$(grep 'aio_node_hostname:' ${allocationDataFile} | cut -f 2 -d ':' | tr -d ' ')
aioFailSafeUserKey=$(grep cfg_failsafe_ssh_public_key ${contextFile} | cut -f 2 -d ':' | tr -d ' ')
aioFailSafeUser=$(grep cfg_failsafe_user ${contextFile} | cut -f 2 -d ':' | tr -d ' ')
networkDataFile=$(find ${tmpDir}/openstack -name network_data.json )
networkDataFileBaseName=$(basename ${networkDataFile})
cp ${networkDataFile} ./${networkDataFileBaseName}
sed -i ${networkDataFileBaseName} -e "s/${saltMasterIp}/${aioIp}/g"
umount ${tmpDir}
rm -rf ${tmpDir}

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
    max_event_size: 100000000
    acceptance_wait_time_max: 60
    acceptance_wait_time: 10
    random_reauth_delay: 270
    recon_default: 1000
    recon_max: 60000
    recon_randomize: True
    auth_timeout: 60
    EOF
    service salt-minion restart
runcmd:
  - 'if lvs vg0; then pvresize /dev/vda3; fi'
  - 'if lvs vg0; then /usr/bin/growlvm.py --image-layout-file /usr/share/growlvm/image-layout.yml; fi'
  - [bash, -cex, *slave_boot]
EOF

isoArgs="--name ${aioHostname} --hostname ${aioHostname}.${clusterDomain} --user-data $(pwd)/user_data --network-data $(pwd)/${networkDataFileBaseName} --quiet --clean-up"
if [[ -n "${aioFailSafeUser}" ]] && [[ -n "${aioFailSafeUserKey}" ]]; then
	isoArgs="${isoArgs} --cloud-user-name ${aioFailSafeUser} --ssh-key ${aioFailSafeUserKey}"
fi
python ./create_config_drive.py ${isoArgs}
qemu-img resize ${SLAVE_VM_SOURCE_DISK} 80G
if [ -z "${NON_DEFAULT_LIBVIRT_DIR}" ]; then
  #### Make sure that both files are saved to system path which is available for libvirt-qemu:kvm
  export SLAVE_VM_SOURCE_DISK=$(place_file_under_libvirt ${SLAVE_VM_SOURCE_DISK})
  export SLAVE_VM_CONFIG_DISK=$(place_file_under_libvirt ${aioHostname}.${clusterDomain}-config.iso)
fi
export CREATE_NETWORKS=${CREATE_NETWORKS:-true}
popd

render_config "${SLAVE_VM_NAME}" "${SLAVE_VM_MEM_KB}" "${SLAVE_VM_CPUS}" "${SLAVE_VM_SOURCE_DISK}" "${SLAVE_VM_CONFIG_DISK}" "${CREATE_NETWORKS}"

virsh define $(pwd)/${SLAVE_VM_NAME}-vm.xml
virsh autostart ${SLAVE_VM_NAME}
