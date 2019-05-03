#!/bin/bash

envFile="$(pwd)/env_vars.sh"
if [[ ! -f ${envFile} ]]; then
  echo "ERROR: Can not find 'env_vars' libfile (${envFile}), check your mcp/mcp-common-scripts repo."
  exit 1
else
  source ${envFile}
fi

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
    cat <<EOF > $(pwd)/${network}.xml
<network>
  <name>${network}</name>
  <forward mode="bridge"/>
  <bridge name="${bridge_name}" />
</network>
EOF
    create_network ${network}
}

function create_host_network {
    local network=$1
    local gateway=$2
    local netmask=$3
    local nat=${4:-false}
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
}

function place_file_under_libvirt() {
  local libvirtPath="/var/lib/libvirt/images"
  local image=${1}
  local basenameFile=$(basename ${image})
  cp "${image}" "${libvirtPath}/${basenameFile}"
  chown -R libvirt-qemu:kvm "${libvirtPath}"
  echo "${libvirtPath}/${basenameFile}"
}

function render_config() {
  local vmName=$1
  local vmMemKB=$2
  local vmCPUs=$3
  local vmSourceDisk=$4
  local vmConfigDisk=$5
  local createNetworks=${6:-true}
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

  if [[ "${VM_MGM_BRIDGE_DISABLE}" =~ [Ff]alse ]]; then
      [[ "${createNetworks}" =~ [Tt]rue ]] && create_bridge_network "${VM_MGM_NETWORK_NAME}" "${VM_MGM_BRIDGE_NAME}"
      cat <<EOF >> $(pwd)/${vmName}-vm.xml
    <interface type='bridge'>
      <source bridge='$VM_MGM_BRIDGE_NAME'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
EOF
  else
      [[ "${createNetworks}" =~ [Tt]rue ]] && create_host_network "${VM_MGM_NETWORK_NAME}" "${VM_MGM_NETWORK_GATEWAY}" "${VM_MGM_NETWORK_MASK}" true
      cat <<EOF >> $(pwd)/${vmName}-vm.xml
    <interface type='network'>
      <source network='$VM_MGM_NETWORK_NAME'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
EOF
fi

  if [[ "${VM_MGM_BRIDGE_DISABLE}" =~ [Ff]alse ]]; then
      [[ "${createNetworks}" =~ [Tt]rue ]] && create_bridge_network "${VM_CTL_NETWORK_NAME}" "${VM_CTL_BRIDGE_NAME}"
      cat <<EOF >> $(pwd)/${vmName}-vm.xml
    <interface type='bridge'>
      <source bridge='$VM_CTL_BRIDGE_NAME'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </interface>
EOF
  else
      [[ "${createNetworks}" =~ [Tt]rue ]] && create_host_network "${VM_CTL_NETWORK_NAME}" "${VM_CTL_NETWORK_GATEWAY}" "${VM_CTL_NETWORK_MASK}"
      cat <<EOF >> $(pwd)/${vmName}-vm.xml
    <interface type='network'>
      <source network='$VM_CTL_NETWORK_NAME'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </interface>
EOF
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