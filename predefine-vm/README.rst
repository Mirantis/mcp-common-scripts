====================
Deploy cfg01 locally
====================

Deploy cfg01 on Ubuntu with QEMU/KVM (libvirt)
==============================================

**Prerequisites**

Script will check and install next required packages: qemu-utils libvirt-bin virtinst qemu-kvm.

**Common info**

Script ``define-vm.sh`` gives you an ability to deploy cfg01 VM with provided cfg01 Qcwo2 disk
image and config-drive iso file on your local laptop.

Script is operating by next ENV variables:

    * VM_NAME - the name of VM to be created in VirtualBox. Default: 'cfg01-mcp.local'.
    * VM_SOURCE_DISK - the name of virtual disk to be used for virtual machine. Can be relative or absolute path.
      You can download and use the following image: http://images.mcp.mirantis.net/cfg01-day01-2019.2.0.qcow2
    * VM_CONFIG_DISK - Config-drive ISO file, can be relative or absolute path.
    * VM_MGM_BRIDGE_NAME - Bridge name to use for deploy management network. Should have Internet access if not
      offline case. Optional, default: 'br-mgm'
    * VM_CTL_BRIDGE_NAME - Bridge name to use for control network. Optional, default: 'br-ctl'
    * VM_MGM_BRIDGE_DISABLE - Do not use host bridge for deploy management network and create new nat-network.
      Optional, default: false
    * VM_CTL_BRIDGE_DISABLE - Do not use host bridge for control network and create host-only based new network.
      Optional, default: false
    * VM_MGM_NETWORK_NAME - Name for deploy management network. Optional, default: 'mgm_network'
    * VM_CTL_NETWORK_NAME - Name for control network. Optional, default: 'ctl_network'

Script will check that disk and config-drive are present and then define needed networks and spawn virtual machine.
Start VM with ``virsh start <VM_NAME>``. Then check that VM is up and running.

Once VM is up and running you can use ``virsh console`` to check what is going on during deploy.
It is recommended to specify username and password/ssh-key during model generation for login via VM console or ssh if
something goes wrong. Once you are logged in you can follow usual debug procedure for cfg01 node.

When cfg01 is bootstrapped and configured, Jenkins is available via: http://<salt_master_management_address>:8081/
Default login creds are: root/r00tme

Deploy OpenStack All-In-One node on Ubuntu with QEMU/KVM (libvirt)
==================================================================

**Prerequisites**

Setup cfg01 node and it's up, running and configured.

**Common info**

Script ``define-slave-vm.sh`` gives you an ability to deploy OpenStack All-in-one VM with provided Qcwo2 disk
image and config-drive iso file on your local laptop.

Script is operating by next ENV variables:

    * SLAVE_VM_NAME - the name of VM to be created in VirtualBox.
    * SLAVE_VM_SOURCE_DISK - the name of virtual disk to be used for virtual machine. Can be relative or absolute path.
      You can download and use the following image: http://images.mcp.mirantis.net/ubuntu-16-04-x64-mcp2019.2.0.qcow2
    * SLAVE_VM_MEM_KB - amount of RAM for VM in KB. Default is: 16777216
    * SLAVE_VM_CPUS - amount of CPUs to use. Default is: 4.

Next parameters should be same as for cfg01 node:

    * VM_CONFIG_DISK
    * VM_MGM_BRIDGE_NAME
    * VM_CTL_BRIDGE_NAME
    * VM_MGM_BRIDGE_DISABLE
    * VM_CTL_BRIDGE_DISABLE
    * VM_MGM_NETWORK_NAME
    * VM_CTL_NETWORK_NAME

Also once you setup cfg01 setup the next parameter: export CREATE_NEWORKS=false
This parameter will disable network recreation, which can be needed in case of changing network setup.

Also if you are not going to use system bridges, set next parameters to true:

    * VM_MGM_BRIDGE_DISABLE=true
    * VM_CTL_BRIDGE_DISABLE=true

This will switch using to locally created virsh networks.

Script will check that disk and cfg01 config-drive are present and then prepare config-drive for all-in-one node.
Start VM with ``virsh start <SLAVE_VM_NAME>``. Once VM is up and running you can use ``virsh console`` to check what is
going on during bootstrap. For that VM will be used same fail safe user as specified for cfg01.

Deploy cfg01 on Mac OS with VirtualBox
======================================

**Prerequisites**

Recommended VirtualBox version is 5.2.26, with Extenstion pack for the same version:

    * Get VirtualBox package for your system: https://download.virtualbox.org/virtualbox/5.2.26/
    * Extension pack: https://download.virtualbox.org/virtualbox/5.2.26/Oracle_VM_VirtualBox_Extension_Pack-5.2.26.vbox-extpack
    * Python JSON module

**Common info**

Script gives you an ability to deploy cfg01 VM with provided cfg01 VDI disk
image and config-drive iso file on your local laptop.

Script takes as arguments two URLs: for cfg01 disk image and for config-drive ISO file.
Both arguments are required in specified order. All other parameters are optional and can
be overrided by exporting them via 'export' command or by creating in script's
run directory env file 'env_overrides' with next possible arguments:

    * VM_NAME - the name of VM to be created in VirtualBox. Default: 'cfg01-mcp.local'.
    * VM_DISK - the name of virtual disk to be used for virtual machine. Can be
      an absolute path as well. This variable will be used as target file name for
      downloading virtual machine disk, please be sure that path exists.
      Default: 'cfg01-disk.vdi'
    * CONFIG_DRIVE_ISO - same as VM_DISK, but for config-drive ISO file.
      Default: 'cfg01.deploy-local.local-config.iso'
    * AUTO_USER_CONFIRM - do not ask user confirmation to override some resource if already exists.
      Default: false
    * UPDATE_ISO_INTERFACES - Update network settings in provided config-drive ISO file.
      The target and main hosts, which is used to deploy cfg01 instance, are based under
      OS Linux family and QEMU/KVM virtualization and virtio net-driver. Xenial system, which
      used for cfg01, already contains a new SystemD predictable network interface names mechanism [0],
      which automatically assigns ens[3-9] interface names for VMs. VirtualBox is using multi-functional
      network card, which leads to renaming all network interfaces to enp0s* names.
      [0] https://www.freedesktop.org/wiki/Software/systemd/PredictableNetworkInterfaceNames/
      Default: true

    * DEPLOY_NET_NAME - NAT-Service network name, which is used as primary interface for cfg01. This network
      doesn't provided direct access to VM, it is possible to add manually port forwarding rules if needed, but
      for VM access use host-only network CONTROL_NET. Default: 'deploy_nat_network'
    * DEPLOY_NETWORK - NAT-Service network with CIDR to use. Should be same as on model generation
      step 'networking'. Default: '192.168.15.0/24'
    * DEPLOY_GATEWAY - NAT-Service network gateway. Should be same as on model generation step 'networking'.
      Default: '192.168.15.1'
    * DEPLOY_IP_ADDRESS - Primary deploy IP address, which is also specified during model generation.
      Default: '192.168.15.15'

    * CONTROL_NET_NAME - Host-only based network name, which has static names 'vboxnetX', where 'X' is simple
      count of existing networks for such type. Default: 'vboxnet0'
    * CONTROL_GATEWAY - Host-only based network gateway. Default: '192.168.56.1'
    * CONTROL_NETWORK - Host-only based network with CIDR to use. Should be same as on model generation
      step 'networking'. Default: '192.168.56.0/24'
    * CONTROL_IP_ADDRESS - Control IP address, which is also specified during model generation.
      Default: '192.168.56.15'

Script will go through next steps:

    * Download disk image and config drive ISO;
    * Define virtual machine with provided parameters;
    * If needed config-drive ISO network data will be updated on a fly;
    * Run virtual machine.

Once VM is up and running you can use VirtualBox VM console to check what is going on during deploy.
It will drop all logs into console and it doesn't matter loged in user or not. It is recommended to specify
username and password during model generation for login via VM console if something goes wrong.
Once you are logged in you can follow usual debug procedure for cfg01 node.