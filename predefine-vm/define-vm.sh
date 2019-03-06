#!/bin/bash -xe

VM_MGM_BRIDGE_DISABLE=${VM_MGM_BRIDGE_DISABLE:-false}
VM_CTL_BRIDGE_DISABLE=${VM_CTL_BRIDGE_DISABLE:-false}
VM_MGM_BRIDGE_NAME=${VM_MGM_BRIDGE_NAME:-"br-mgm"}
VM_CTL_BRIDGE_NAME=${VM_CTL_BRIDGE_NAME:-"br-ctl"}
VM_MGM_NETWORK_NAME=${VM_MGM_NETWORK_NAME:-"mgm_network"}
VM_CTL_NETWORK_NAME=${VM_CTL_NETWORK_NAME:-"ctl_network"}
VM_MEM_KB=${VM_MEM_KB:-"12589056"}
VM_CPUS=${VM_CPUS:-"4"}
# optional params if you won't use bridge on host
VM_MGM_NETWORK_GATEWAY=${VM_MGM_NETWORK_GATEWAY:-"192.168.56.1"}
VM_MGM_NETWORK_MASK=${VM_MGM_NETWORK_MASK:-"255.255.255.0"}
VM_CTL_NETWORK_GATEWAY=${VM_CTL_NETWORK_GATEWAY:-"192.168.57.1"}
VM_CTL_NETWORK_MASK=${VM_CTL_NETWORK_MASK:-"255.255.255.0"}

if [[ -z ${VM_NAME} ]]; then
  echo "ERROR: \$VM_NAME not set!"
  exit 1
fi
if [[ ! -f ${VM_SOURCE_DISK} ]] || [[ -z ${VM_SOURCE_DISK} ]]; then
  echo "ERROR: \$VM_SOURCE_DISK not set, or file does not exist!"
  exit 1
fi
if [[ ! -f ${VM_CONFIG_DISK} ]] || [[ -z ${VM_CONFIG_DISK} ]]; then
  echo "ERROR: \$VM_CONFIG_DISK not set, or file does not exist!"
  exit 1
fi

function check_packages {
    PACKAGES="qemu-utils libvirt-bin qemu-kvm"
    for i in $PACKAGES; do
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
    if [[ ${nat} ]]; then
        cat <<EOF>> $(pwd)/${network}.xml
  <forward mode="nat"/>
EOF
    fi
    cat <<EOF>> $(pwd)/${network}.xml
</network>
EOF
    create_network ${network}
}

check_packages

# Template definition
cat <<EOF > $(pwd)/${VM_NAME}-vm.xml
<domain type='kvm'>
  <name>$VM_NAME</name>
  <memory unit='KiB'>$VM_MEM_KB</memory>
  <currentMemory unit='KiB'>$VM_MEM_KB</currentMemory>
  <vcpu placement='static'>$VM_CPUS</vcpu>
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
      <source file='$VM_SOURCE_DISK'/>
      <target dev='vda' bus='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x0'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$VM_CONFIG_DISK'/>
      <backingStore/>
      <target dev='hda' bus='ide'/>
      <readonly/>
      <address type='drive' controller='0' bus='0' target='0' unit='0'/>
    </disk>
EOF
if [[ ! ${VM_MGM_BRIDGE_DISABLE} ]]; then
    create_bridge_network "${VM_MGM_NETWORK_NAME}" "${VM_MGM_BRIDGE_NAME}"
    cat <<EOF >> $(pwd)/${VM_NAME}-vm.xml
    <interface type='bridge'>
      <source bridge='$VM_MGM_BRIDGE_NAME'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
EOF
else
    create_host_network "${VM_MGM_NETWORK_NAME}" "${VM_MGM_NETWORK_GATEWAY}" "${VM_MGM_NETWORK_MASK}" true
    cat <<EOF >> $(pwd)/${VM_NAME}-vm.xml
    <interface type='network'>
      <source network='$VM_MGM_NETWORK_NAME'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </interface>
EOF
fi

if [[ ! ${VM_CTL_BRIDGE_DISABLE} ]]; then
    create_bridge_network "${VM_CTL_NETWORK_NAME}" "${VM_CTL_BRIDGE_NAME}"
    cat <<EOF >> $(pwd)/${VM_NAME}-vm.xml
    <interface type='bridge'>
      <source bridge='$VM_CTL_BRIDGE_NAME'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </interface>
EOF
else
    create_host_network "${VM_CTL_NETWORK_NAME}" "${VM_CTL_NETWORK_GATEWAY}" "${VM_CTL_NETWORK_MASK}"
    cat <<EOF >> $(pwd)/${VM_NAME}-vm.xml
    <interface type='network'>
      <source network='$VM_CTL_NETWORK_NAME'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </interface>
EOF
fi

cat <<EOF >> $(pwd)/${VM_NAME}-vm.xml
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
cat $(pwd)/${VM_NAME}-vm.xml

virsh define $(pwd)/${VM_NAME}-vm.xml
virsh autostart ${VM_NAME}
