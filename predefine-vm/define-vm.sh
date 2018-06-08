#!/bin/bash -xe

VM_MGM_BRIDGE_NAME=${VM_MGM_BRIDGE_NAME:-"br-mgm"}
VM_MEM_KB=${VM_MEM_KB:-"8388608"}
VM_CPUS=${VM_CPUS:-"4"}

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
    <interface type='bridge'>
      <source bridge='$VM_MGM_BRIDGE_NAME'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
EOF
if [[ -n ${VM_CTL_BRIDGE_NAME} ]]; then
echo "\$VM_CTL_BRIDGE_NAME detected, adding one more nic to VM"
cat <<EOF >> $(pwd)/${VM_NAME}-vm.xml
    <interface type='bridge'>
      <source bridge='$VM_CTL_BRIDGE_NAME'/>
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
  </devices>
</domain>
EOF

echo "INFO: rendered VM config:"
cat $(pwd)/${VM_NAME}-vm.xml

virsh define $(pwd)/${VM_NAME}-vm.xml
virsh autostart ${VM_NAME}
