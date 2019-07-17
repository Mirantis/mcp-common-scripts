#!/bin/bash

set -e

functionsFile="$(pwd)/functions.sh"

if [[ ! -f ${functionsFile} ]]; then
  echo "ERROR: Can not find 'functions' libfile (${functionsFile}), check your mcp/mcp-common-scripts repo."
  exit 1
else
  source ${functionsFile}
fi

if [[ -z ${VM_NAME} ]]; then
  echo "ERROR: \$VM_NAME not set!"
  exit 1
fi
if [[ -z ${VM_SOURCE_DISK} ]] || [[ ! -f ${VM_SOURCE_DISK} ]]; then
  echo "ERROR: \$VM_SOURCE_DISK not set, or file does not exist!"
  exit 1
fi
if [[ -z ${VM_CONFIG_DISK} ]] || [[ ! -f ${VM_CONFIG_DISK} ]]; then
  echo "ERROR: \$VM_CONFIG_DISK not set, or file does not exist!"
  exit 1
fi

prereq_check

#### Make sure that both files are saved to system path which is available for libvirt-qemu:kvm
export VM_SOURCE_DISK=$(place_file_under_libvirt_owned_dir ${VM_SOURCE_DISK} ${NON_DEFAULT_LIBVIRT_DIR})
export VM_CONFIG_DISK=$(place_file_under_libvirt_owned_dir ${VM_CONFIG_DISK} ${NON_DEFAULT_LIBVIRT_DIR})

render_config "${VM_NAME}" "${VM_MEM_KB}" "${VM_CPUS}" "${VM_SOURCE_DISK}" "${VM_CONFIG_DISK}"

virsh define $(pwd)/${VM_NAME}-vm.xml
virsh autostart ${VM_NAME}

allocationDataFile=$(isoinfo -i ${VM_CONFIG_DISK} -J -f | grep -w "allocation_data.yml")
secretsFile=$(isoinfo -i ${VM_CONFIG_DISK} -J -f | grep "infra/secrets.yml")
cfgJenkinsPassword=$(isoinfo -i ${VM_CONFIG_DISK} -J -x ${secretsFile} | grep 'jenkins_cfg_admin_password_generated' | cut -f 2 -d ':' | tr -d ' ')
cfgJenkinsAddress=$(isoinfo -i ${VM_CONFIG_DISK} -J -x ${allocationDataFile} | grep 'infra_config_deploy_address' | cut -f 2 -d ':' | tr -d ' ')
echo "Once deployed, Jenkins will be available via: http://${cfgJenkinsAddress}:8081 and login creds are: admin / ${cfgJenkinsPassword}"