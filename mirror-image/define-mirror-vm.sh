!/bin/bash -xe
MIRROR_VM_MGM_BRIDGE_NAME=${MIRROR_VM_MGM_BRIDGE_NAME:-"br_mgm"}
MIRROR_VM_MEM_KB=${MIRROR_VM_MEM_KB:-"4194304"}
MIRROR_VM_CPUS=${MIRROR_VM_CPUS:-"4"}
echo "<domain type='kvm'>
  <name>$MIRROR_VM_NAME</name>
  <memory unit='KiB'>$MIRROR_VM_MEM_KB</memory>
  <currentMemory unit='KiB'>$MIRROR_VM_MEM_KB</currentMemory>
  <vcpu placement='static'>$MIRROR_VM_CPUS</vcpu>
  <resource>
    <partition>/machine</partition>
  </resource>
  <os>
    <type >hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
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
      <source file='$MIRROR_VM_SOURCE_DISK'/>
      <target dev='vda' bus='virtio'/>
      <alias name='virtio-disk0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x0'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$MIRROR_VM_CONFIG_DISK'/>
      <backingStore/>
      <target dev='hda' bus='ide'/>
      <readonly/>
      <alias name='ide0-0-0'/>
      <address type='drive' controller='0' bus='0' target='0' unit='0'/>
    </disk>
    <interface type='bridge'>
      <source bridge='$MIRROR_VM_MGM_BRIDGE_NAME'/>
      <target dev='vnet0'/>
      <model type='virtio'/>
      <alias name='net0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <serial type='pty'>
      <source path='/dev/pts/1'/>
      <target port='0'/>
      <alias name='serial0'/>
    </serial>
    <console type='pty' tty='/dev/pts/1'>
      <source path='/dev/pts/1'/>
      <target type='serial' port='0'/>
      <alias name='serial0'/>
    </console>
    <graphics type='vnc' port='5900' autoport='yes' listen='127.0.0.1'>
      <listen type='address' address='127.0.0.1'/>
    </graphics>
  </devices>
</domain>" > $PWD/mirror-vm.xml
virsh define $PWD/mirror-vm.xml