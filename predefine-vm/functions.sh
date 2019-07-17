#!/bin/bash

set -e

envFile="$(pwd)/env_vars.sh"
if [[ ! -f ${envFile} ]]; then
  echo "ERROR: Can not find 'env_vars' libfile (${envFile}), check your mcp/mcp-common-scripts repo."
  exit 1
else
  source ${envFile}
fi

function count_netmask {
    local network=$1
    local cidr=$(echo $network | cut -f 2 -d '/')
    local ones="printf '1%.0s' {1..${cidr}}"
    local zeros="printf '0%.0s' {1..$(( 32 - ${cidr} ))}"
    local netmask_binary="$(echo $ones | bash)$(echo $zeros | bash)"
    local netmask_decimal=""
    for i in 0 8 16 24; do
        netmask_decimal+="$(echo $((2#${netmask_binary:${i}:8})))"
        [[ "${i}" != '24' ]] && netmask_decimal+='.'
    done
    echo "${netmask_decimal}"
}

function check_packages {
    local slave=$1
    local packages="libvirt-bin qemu-kvm"
    if [[ -n "${slave}" ]]; then
       packages="${packages} qemu-utils python-ipaddress genisoimage"
    fi
    for i in $packages; do
       dpkg -s $i &> /dev/null || { echo "Package $i is not installed!"; exit 1; }
    done
}

function check_bridge_exists {
    local bridgeName=${1}
    local optionName=${2}
    local bridgeExists=$(brctl show | grep ${bridgeName})
    if [ -z "${bridgeExists}" ]; then
        echo "Option ${optionName} is set to False, which means using bridge ${bridgeName}, but it doesn't exist."
        echo "Consider to switch to ${optionName}=True, which will lead to using local hosted networks."
        echo "Or create bridge ${bridgeName} manually: https://docs.mirantis.com/mcp/q4-18/mcp-deployment-guide/deploy-mcp-drivetrain/prerequisites-dtrain.html"
        exit 1
    fi
}

function prereq_check {
    local slave=${1}
    check_packages "${slave}"
    if [[ "${VM_MGM_BRIDGE_DISABLE}" =~ [Ff]alse ]]; then
      check_bridge_exists "${VM_MGM_BRIDGE_NAME}" "VM_MGM_BRIDGE_DISABLE"
    fi
    if [[ "${VM_CTL_BRIDGE_DISABLE}" =~ [Ff]alse ]]; then
      check_bridge_exists "${VM_CTL_BRIDGE_NAME}" "VM_CTL_BRIDGE_DISABLE"
    fi
    if [[ -n "${NON_DEFAULT_LIBVIRT_DIR}" ]]; then
      echo "All files will be saved under ${NON_DEFAULT_LIBVIRT_DIR} directory. Make sure that libvirt-qemu:kvm has access rights to that path."
    fi
}

function do_create_new_network {
    local netName=${1}
    local netExists=$(virsh net-list | grep ${netName})
    if [ -n "${netExists}" ] && [[ "${RECREATE_NETWORKS_IF_EXISTS}" =~ [Ff]alse ]]; then
        echo 'false'
    else
        echo 'true'
    fi
}

function create_network {
    local network=${1}
    virsh net-destroy ${network} 2> /dev/null || true
    virsh net-undefine ${network} 2> /dev/null || true
    virsh net-define ${network}.xml
    virsh net-autostart ${network}
    virsh net-start ${network}
}

function create_bridge_network {
    local network=$1
    local bridge_name=$2
    local createNetwork=$(do_create_new_network "${network}")
    if [ "${createNetwork}" == 'true' ]; then
        cat <<EOF > $(pwd)/${network}.xml
<network>
  <name>${network}</name>
  <forward mode="bridge"/>
  <bridge name="${bridge_name}" />
</network>
EOF
        create_network ${network}
    fi
}

function create_host_network {
    local network=$1
    local gateway=$2
    local netmask=$3
    local nat=${4:-false}
    local createNetwork=$(do_create_new_network "${network}")
    if [ "${createNetwork}" == 'true' ]; then
        cat <<EOF > $(pwd)/${network}.xml
<network>
  <name>${network}</name>
  <bridge name="${network}" />
  <ip address="${gateway}" netmask="${netmask}"/>
EOF
        if [[ "${nat}" =~ [Tt]rue ]]; then
            cat <<EOF>> $(pwd)/${network}.xml
  <forward mode="nat"/>
EOF
        fi
        cat <<EOF>> $(pwd)/${network}.xml
</network>
EOF
        create_network ${network}
    fi
}

function place_file_under_libvirt_owned_dir() {
  local file=${1}
  local libvirtPath=${2-'/var/lib/libvirt/images'}
  local basenameFile=$(basename ${file})
  cp "${file}" "${libvirtPath}/${basenameFile}"
  chown libvirt-qemu:kvm "${libvirtPath}/${basenameFile}"
  echo "${libvirtPath}/${basenameFile}"
}

function render_config() {
  local vmName=$1
  local vmMemKB=$2
  local vmCPUs=$3
  local vmSourceDisk=$4
  local vmConfigDisk=$5
  # Template definition
  cat <<EOF > $(pwd)/${vmName}-vm.xml
<domain type='kvm'>
  <name>$vmName</name>
  <memory unit='KiB'>$vmMemKB</memory>
  <currentMemory unit='KiB'>$vmMemKB</currentMemory>
  <vcpu placement='static'>$vmCPUs</vcpu>
  <resource>
    <partition>/machine</partition>
  </resource>
  <os>
    <type >hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
  </features>
  <clock offset='utc'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hpet' present='no'/>
  </clock>
  <pm>
    <suspend-to-mem enabled='no'/>
    <suspend-to-disk enabled='no'/>
  </pm>
  <devices>
    <emulator>/usr/bin/kvm-spice</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none'/>
      <source file='$vmSourceDisk'/>
      <target dev='vda' bus='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x0'/>
    </disk>
EOF
  if [[ -n "${vmConfigDisk}" ]]; then
    cat <<EOF >> $(pwd)/${vmName}-vm.xml
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$vmConfigDisk'/>
      <backingStore/>
      <target dev='hda' bus='ide'/>
      <readonly/>
      <address type='drive' controller='0' bus='0' target='0' unit='0'/>
    </disk>
EOF
  fi

  local allocationDataFile=$(isoinfo -i ${VM_CONFIG_DISK} -J -f | grep -w "allocation_data.yml")
  if [[ "${VM_MGM_BRIDGE_DISABLE}" =~ [Ff]alse ]]; then
      create_bridge_network "${VM_MGM_NETWORK_NAME}" "${VM_MGM_BRIDGE_NAME}"
      cat <<EOF >> $(pwd)/${vmName}-vm.xml
    <interface type='bridge'>
      <source bridge='$VM_MGM_BRIDGE_NAME'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
EOF
  else
      local vmMgmNetworkGateway=$(isoinfo -i ${VM_CONFIG_DISK} -J -x ${allocationDataFile} | grep -w 'deploy_network_gateway' | cut -f 2 -d ':' | tr -d ' ')
      local vmMgmNetworkMask=$(isoinfo -i ${VM_CONFIG_DISK} -J -x ${allocationDataFile} | grep -w 'deploy_network_netmask' | cut -f 2 -d ':' | tr -d ' ')
      create_host_network "${VM_MGM_NETWORK_NAME}" "${vmMgmNetworkGateway}" "${vmMgmNetworkMask}" true
      cat <<EOF >> $(pwd)/${vmName}-vm.xml
    <interface type='network'>
      <source network='$VM_MGM_NETWORK_NAME'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
EOF
fi

  if [[ "${VM_MGM_BRIDGE_DISABLE}" =~ [Ff]alse ]]; then
      create_bridge_network "${VM_CTL_NETWORK_NAME}" "${VM_CTL_BRIDGE_NAME}"
      cat <<EOF >> $(pwd)/${vmName}-vm.xml
    <interface type='bridge'>
      <source bridge='$VM_CTL_BRIDGE_NAME'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </interface>
EOF
  else
      local vmCtlNetworkGateway=$(isoinfo -i ${VM_CONFIG_DISK} -J -x ${allocationDataFile} | grep -w 'infra_config_address' | cut -f 2 -d ':' | tr -d ' ' | sed -r "s/\.[[:digit:]]+$/\.1/g")
      local vmCtlNetworkMask=$(isoinfo -i ${VM_CONFIG_DISK} -J -x ${allocationDataFile} | grep -w 'control_network_netmask' | cut -f 2 -d ':' | tr -d ' ')
      create_host_network "${VM_CTL_NETWORK_NAME}" "${vmCtlNetworkGateway}" "${vmCtlNetworkMask}"
      cat <<EOF >> $(pwd)/${vmName}-vm.xml
    <interface type='network'>
      <source network='$VM_CTL_NETWORK_NAME'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </interface>
EOF
fi

  if [[ "${VM_PUBLIC_NET_NEEDED}" =~ [Tt]rue ]]; then
    if [[ "${VM_PUBLIC_BRIDGE_DISABLE}" =~ [Ff]alse ]]; then
        create_bridge_network "${VM_PUBLIC_NETWORK_NAME}" "${VM_PUBLIC_BRIDGE_NAME}"
        cat <<EOF >> $(pwd)/${vmName}-vm.xml
    <interface type='bridge'>
      <source bridge='$VM_PUBLIC_BRIDGE_NAME'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0'/>
    </interface>
EOF
    else
        local vmPublicNetworkGateway=$(isoinfo -i ${VM_CONFIG_DISK} -J -x ${allocationDataFile} | grep -w 'openstack_public_neutron_subnet_gateway' | cut -f 2 -d ':' | tr -d ' ')
        local vmPublicNetworkCIDR=$(isoinfo -i ${VM_CONFIG_DISK} -J -x ${allocationDataFile} | grep -w 'openstack_public_neutron_subnet_cidr' | cut -f 2 -d ':' | tr -d ' ')
        local vmPublicNetworkMask=$(count_netmask "${vmPublicNetworkCIDR}")
        create_host_network "${VM_PUBLIC_NETWORK_NAME}" "${vmPublicNetworkGateway}" "${vmPublicNetworkMask}" true
        cat <<EOF >> $(pwd)/${vmName}-vm.xml
    <interface type='network'>
      <source network='$VM_PUBLIC_NETWORK_NAME'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0'/>
    </interface>
EOF
    fi
fi

  cat <<EOF >> $(pwd)/${vmName}-vm.xml
    <serial type='pty'>
      <source path='/dev/pts/1'/>
      <target port='0'/>
    </serial>
    <console type='pty' tty='/dev/pts/1'>
      <source path='/dev/pts/1'/>
      <target type='serial' port='0'/>
    </console>
    <graphics type='vnc' port='-1' autoport='yes' listen='127.0.0.1'>
      <listen type='address' address='127.0.0.1'/>
    </graphics>
    <rng model='virtio'>
      <backend model='random'>/dev/random</backend>
    </rng>
  </devices>
</domain>
EOF

  echo "INFO: rendered VM config:"
  cat $(pwd)/${vmName}-vm.xml
}