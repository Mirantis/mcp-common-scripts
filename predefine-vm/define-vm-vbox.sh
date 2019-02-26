#!/bin/bash

count_netmask() {
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

create_host_net() {
    local manageControlNet='yes'
    vboxmanage list hostonlyifs | grep -o -e "^Name:.*" | grep -q "${CONTROL_NET_NAME}"
    if [[ $? -ne 0 ]]; then
        vboxmanage hostonlyif create
    else
        if [[ ! ${AUTO_USER_CONFIRM} ]]; then
            echo "Hosted-network ${CONTROL_NET_NAME} already exists, shall we override it? Type 'yes' to confirm or anything else to skip."
            read manageControlNet
        fi
    fi
    if [[ "${manageControlNet}" == 'yes' ]]; then
        vboxmanage hostonlyif ipconfig "${CONTROL_NET_NAME}" --ip "${CONTROL_GATEWAY}" --netmask "${CONTROL_NETMASK}"
    fi
}

create_nat_net() {
    local manageDeployNet='yes'
    vboxmanage natnetwork list | grep -o -e "^Name:.*" | grep -q "${DEPLOY_NET_NAME}"
    if [[ $? -ne 0 ]]; then
        vboxmanage natnetwork add --netname "${DEPLOY_NET_NAME}" --network "${DEPLOY_NETWORK}" --enable --dhcp off
    else
        if [[ ! ${AUTO_USER_CONFIRM} ]]; then
            echo "Nat network ${DEPLOY_NET_NAME} already exists, shall we override it? Type 'yes' to confirm or anything else to skip."
            read manageDeployNet
        fi
        if [[ "${manageDeployNet}" == 'yes' ]]; then
            vboxmanage natnetwork modify --netname "${DEPLOY_NET_NAME}" --network "${natNetwork}/${natCIDR}" --enable --dhcp off
        fi
    fi
}

update_iso() {
    local mac1=${1}
    local mac2=${2}
    local mountPoint="cfg-iso"
    local mountPointUpdated="cfg-iso-new"
    local oshost=$(uname)
    mkdir "${mountPoint}" "${mountPointUpdated}"
    if [[ "${oshost}" == 'Darwin' ]]; then
        hdiutil mount -mountpoint "${mountPoint}" "${CONFIG_DRIVE_ISO}"
    else
        mount "${CONFIG_DRIVE_ISO}" "${mountPoint}"
    fi
    cp -rf "${mountPoint}"/* "${mountPointUpdated}"
    if [[ "${oshost}" == 'Darwin' ]]; then
        hdiutil unmount "${mountPoint}"
    else
        umount "${mountPoint}"
    fi
    chmod -R +w "${mountPointUpdated}"
    local openstackConfig="${mountPointUpdated}/openstack/latest"
    local iso_label=''
    if [[ -d "${openstackConfig}" ]]; then
        local networkConfigOpenstack="${openstackConfig}/network_data.json"
        local ens="[{'ethernet_mac_address': '${mac1}', 'type': 'phy', 'id': 'ens3', 'name': 'ens3'}, {'ethernet_mac_address': '${mac2}', 'type': 'phy', 'id': 'ens4', 'name': 'ens4'}]"
        python -c "import json; networkData=json.load(open('${networkConfigOpenstack}', 'r')); networkData['links']=${ens4}; json.dump(networkData, open('${networkConfigOpenstack}', 'w'))"
        iso_label='config-2'
    else
        local networkConfigV2Template="""
version: 2
ethernets:
  if0:
    match:
      macaddress: "${mac1}"
    set-name: ens3
    wakeonlan: true
    addresses:
    - "${DEPLOY_IP_ADDRESS}/${DEPLOY_NETMASK}"
    gateway4: "${DEPLOY_GATEWAY}"
  if1:
    match:
      macaddress: "${mac2}"
    set-name: ens4
    addresses:
    - "${CONTROL_IP_ADDRESS}/${CONTROL_NETMASK}"
    gateway4: "${CONTROL_GATEWAY}"
    wakeonlan: true
"""
        echo -e "${networkConfigV2Template}" > "${mountPointUpdated}/network-config"
        iso_label='cidata'
    fi
    if [[ "${oshost}" == 'Darwin' ]]; then
        hdiutil makehybrid -o "${CONFIG_DRIVE_ISO}" "${mountPointUpdated}" -iso -joliet -ov -iso-volume-name "${iso_label}" -default-volume-name "${iso_label}"
    else
        genisoimage -output "${CONFIG_DRIVE_ISO}" -volid "${iso_label}" -joliet -rock "${mountPointUpdated}"
    fi
    rm -rf "${mountPoint}" "${mountPointUpdated}"
}

define_vm() {
    vboxmanage createvm --name "${VM_NAME}" --register
    vboxmanage modifyvm "${VM_NAME}" --ostype Ubuntu_64 \
        --memory 8188 --cpus 2 --vram 16 \
        --acpi on --ioapic on --x2apic on \
        --nic1 natnetwork --hostonlyadapter1 "${DEPLOY_NET_NAME}" --nictype1 virtio \
        --nic2 hostonly --hostonlyadapter2 "${CONTROL_NET_NAME}" --nictype2 virtio \
        --pae off --rtcuseutc on --uart1 0x3F8 4 \
        --usb on --usbehci on --audiocodec ad1980 \
        --mouse usbtablet

    vboxmanage storagectl "${VM_NAME}" --name "IDE"  --add ide
    vboxmanage storagectl "${VM_NAME}" --name "SATA"  --add sata --portcount 1

    vboxmanage storageattach "${VM_NAME}" \
        --storagectl "SATA" --port 0 --device 0 \
        --type hdd --medium "${VM_DISK}"

    macaddress1=$(vboxmanage showvminfo "${VM_NAME}" --details --machinereadable | grep macaddress1 | cut -f 2 -d '=' | tr -d '"' | sed 's/../&:/g; s/:$//')
    macaddress2=$(vboxmanage showvminfo "${VM_NAME}" --details --machinereadable | grep macaddress2 | cut -f 2 -d '=' | tr -d '"' | sed 's/../&:/g; s/:$//')

    [[ ${UPDATE_ISO_INTERFACES} ]] && update_iso ${macaddress1} ${macaddress2}

    vboxmanage storageattach "${VM_NAME}" \
        --storagectl "IDE" --port 0 --device 0 \
        --type dvddrive --medium "${CONFIG_DRIVE_ISO}"
}

[ -f env_overrides ] && source env_overrides

CFG01_IMAGE_LINK=$1
CONFIG_DRIVE_ISO_LINK=$2

VM_NAME=${VM_NAME:-'cfg01-mcp.local'}
VM_DISK=${VM_DISK:-'cfg01-disk.vdi'}
CONFIG_DRIVE_ISO=${CONFIG_DRIVE_ISO:-'cfg01.deploy-local.local-config.iso'}

if [ -z "${CFG01_IMAGE_LINK}" ]; then
    echo "URL to cfg01 VDI disk image was not provided!"
    if [ -f "${VM_DISK}" ]; then
        echo "Found local copy: ${VM_DISK}"
    else
        exit 1
    fi
else
    curl -O ${VM_DISK} ${CFG01_IMAGE_LINK}
fi

if [ -z "${CONFIG_DRIVE_ISO_LINK}" ]; then
    echo "URL to config-drive ISO image was not provided!"
    if [ -f "${CONFIG_DRIVE_ISO}" ]; then
        echo "Found local copy: ${CONFIG_DRIVE_ISO}"
    else
        exit 1
    fi
else
    curl -O ${CONFIG_DRIVE_ISO} ${CONFIG_DRIVE_ISO_LINK}
fi

AUTO_USER_CONFIRM=${AUTO_USER_CONFIRM:-false}
UPDATE_ISO_INTERFACES=${UPDATE_ISO_INTERFACES:-true}

CONTROL_NET_NAME=${CONTROL_NET_NAME:-'vboxnet0'}
CONTROL_GATEWAY=${CONTROL_GATEWAY:-'192.168.56.1'}
CONTROL_NETWORK=${CONTROL_NETWORK:-'192.168.56.0/24'}
CONTROL_IP_ADDRESS=${CONTROL_IP_ADDRESS:-'192.168.56.15'}

DEPLOY_NET_NAME=${DEPLOY_NET_NAME:-'deploy_nat_network'}
DEPLOY_NETWORK=${DEPLOY_NETWORK:-'192.168.15.0/24'}
DEPLOY_GATEWAY=${DEPLOY_GATEWAY:-'192.168.15.1'}
DEPLOY_IP_ADDRESS=${DEPLOY_IP_ADDRESS:-'192.168.15.15'}

CONTROL_NETMASK=$(count_netmask "${CONTROL_NETWORK}")
DEPLOY_NETMASK=$(count_netmask "${DEPLOY_NETWORK}")

create_nat_net
create_host_net
define_vm
vboxmanage startvm "${VM_NAME}" --type headless
echo "VM successfully started, check the VM console"
