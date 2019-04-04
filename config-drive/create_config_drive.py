#!/usr/bin/env python3
#
# Generate config drives v2 for MCP instances.
#
# Config Drive v2 links:
# - structure: https://cloudinit.readthedocs.io/en/latest/topics/datasources/configdrive.html#version-2
# - network configuration: https://cloudinit.readthedocs.io/en/latest/topics/network-config.html
#
# This script uses OpenStack Metadata Service Network format for configuring networking.
#
__author__ = "Dzmitry Stremkouski"
__copyright__ = "Copyright 2019, Mirantis Inc."
__license__ = "Apache 2.0"

import argparse
import ipaddress
from crypt import crypt
from json import dump as json_dump
from os import makedirs, umask
from shutil import copytree, copyfile, copyfileobj, rmtree
from subprocess import call as run
from sys import argv, exit
from uuid import uuid1 as uuidgen


def crash_with_error(msg, exit_code=1):
    print("ERROR: \n" + msg)
    exit(exit_code)


def xprint(msg):
    if not args.quiet:
        print(msg)


def calculate_hostnames(name, hostname):
    if len(name.split('.')) > 1:
        crash_with_error(
            "instance name should be in short format without domain")
    else:
        if len(hostname.split('.')) == 1:
            if not name == uuid:
                hostname = name
            else:
                name = hostname
        else:
            if name == uuid:
                name = hostname.split('.')[0]

    return [name, hostname]


def validate_args(args):
    if not args.user_data:
        if args.cloud_user_name or args.cloud_user_pass:
            crash_with_error(
                "You have not specified user-data file path, but require"
                "cloud-user setup, which requires it.")

    if not args.skip_network and not args.network_data:
        try:
            ipaddress.ip_address(args.ip)
        except Exception:
            raise Exception(
                "Unable to parse ip addr:{}".format(args.ip))
        try:
            ipaddress.ip_network(args.netmask)
        except Exception:
            raise Exception(
                "Unable to parse netmask:{}".format(args.netmask))
        if args.gateway:
            try:
                ipaddress.ip_address(args.gateway)
            except Exception:
                raise Exception(
                    "Unable to parse gateway IP:{}".format(args.gateway))
        if args.dns_nameservers:
            for ns in args.dns_nameservers.split(','):
                try:
                    ipaddress.ip_address(ns)
                except Exception:
                    raise Exception(
                        "Unable to parse nameserver IP:{}".format(ns))
        if not args.ip or not args.netmask or not args.interface:
            crash_with_error(
                "You have not specified neither ip nor netmask nor interface "
                "nor network_data.json file. Either skip network configuration "
                "or provide network_data.json file path.")

    if args.skip_network and args.network_data:
        crash_with_error(
            "--skip-network and --network-data are mutually exclusive.")


def generate_iso(cfg_file_path, cfg_dir_path, quiet=''):
    xprint("Generating config drive image: %s" % cfg_file_path)
    cmd = ["mkisofs", "-r", "-J", "-V", "config-2", "-input-charset", "utf-8"]
    if quiet:
        cmd.append("-quiet")
    cmd += ["-o", cfg_file_path, cfg_dir_path]
    run(cmd)


def create_config_drive(args):
    name, hostname = calculate_hostnames(args.name, args.hostname)
    username = args.cloud_user_name
    if args.cloud_user_pass:
        userpass = args.cloud_user_pass
    else:
        userpass = ""

    cfg_file_path = hostname + '-config.iso'
    cfg_dir_path = '/var/tmp/config-drive-' + uuid
    mcp_dir_path = cfg_dir_path + '/mcp'
    model_path = mcp_dir_path + '/model'
    mk_pipelines_path = mcp_dir_path + '/mk-pipelines'
    pipeline_lib_path = mcp_dir_path + '/pipeline-library'
    meta_dir_path = cfg_dir_path + '/openstack/latest'
    meta_file_path = meta_dir_path + '/meta_data.json'
    user_file_path = meta_dir_path + '/user_data'
    net_file_path = meta_dir_path + '/network_data.json'
    vendor_file_path = meta_dir_path + '/vendor_data.json'
    gpg_file_path = mcp_dir_path + '/gpg'

    umask(0o0027)
    makedirs(mcp_dir_path)
    makedirs(meta_dir_path)

    meta_data = {"uuid": uuid, "hostname": hostname, "name": name}
    network_data = {}

    ssh_keys = []

    if args.ssh_key:
        xprint("Adding authorized key to config drive: %s" % str(args.ssh_key))
        ssh_keys.append(args.ssh_key)

    if args.ssh_keys:
        xprint("Adding authorized keys file entries to config drive: %s" % str(
            args.ssh_keys))
        with open(args.ssh_keys, 'r') as ssh_keys_file:
            ssh_keys += ssh_keys_file.readlines()
        ssh_keys = [x.strip() for x in ssh_keys]

    # Deduplicate keys if any
    ssh_keys = list(set(ssh_keys))

    # Load keys
    if len(ssh_keys) > 0:
        meta_data["public_keys"] = {}
        for i in range(len(ssh_keys)):
            meta_data["public_keys"][str(i)] = ssh_keys[i]

    if args.model:
        xprint("Adding cluster model to config drive: %s" % str(args.model))
        copytree(args.model, model_path)

    if args.pipeline_library:
        xprint("Adding pipeline-library to config drive: %s" % str(
            args.pipeline_library))
        copytree(args.pipeline_library, pipeline_lib_path)

    if args.mk_pipelines:
        xprint(
            "Adding mk-pipelines to config drive: %s" % str(args.mk_pipelines))
        copytree(args.mk_pipelines, mk_pipelines_path)

    if args.gpg_key:
        xprint("Adding gpg keys file to config drive: %s" % str(args.gpg_key))
        makedirs(gpg_file_path)
        copyfile(args.gpg_key, gpg_file_path + '/salt_master_pillar.asc')

    if args.vendor_data:
        xprint("Adding vendor metadata file to config drive: %s" % str(
            args.vendor_data))
        copyfile(args.vendor_data, vendor_file_path)

    with open(meta_file_path, 'w') as meta_file:
        json_dump(meta_data, meta_file)

    if args.user_data:
        xprint(
            "Adding user data file to config drive: %s" % str(args.user_data))
        if username:
            with open(user_file_path, 'a') as user_file:
                users_data = "#cloud-config\n"
                users_data += "users:\n"
                users_data += "  - name: %s\n" % username
                users_data += "    sudo: ALL=(ALL) NOPASSWD:ALL\n"
                users_data += "    groups: admin\n"
                users_data += "    lock_passwd: false\n"
                if userpass:
                    users_data += "    passwd: %s\n" % str(
                        crypt(userpass, '$6$'))
                if ssh_keys:
                    users_data += "    ssh_authorized_keys:\n"
                    for ssh_key in ssh_keys:
                        users_data += "    - %s\n" % ssh_key
                users_data += "\n"
                user_file.write(users_data)
                with open(args.user_data, 'r') as user_data_file:
                    copyfileobj(user_data_file, user_file)
        else:
            copyfile(args.user_data, user_file_path)

    if args.network_data:
        xprint("Adding network metadata file to config drive: %s" % str(
            args.network_data))
        copyfile(args.network_data, net_file_path)
    else:
        if not args.skip_network:
            xprint("Configuring network metadata from specified parameters.")
            network_data["links"] = []
            network_data["networks"] = []
            network_data["links"].append(
                {"type": "phy", "id": args.interface, "name": args.interface})
            network_data["networks"].append(
                {"type": "ipv4", "netmask": args.netmask,
                 "link": args.interface, "id": "private-ipv4",
                 "ip_address": args.ip})
            if args.dns_nameservers:
                network_data["services"] = []
                for nameserver in args.dns_nameservers.split(','):
                    network_data["services"].append(
                        {"type": "dns", "address": nameserver})
            if args.gateway:
                network_data["networks"][0]["routes"] = []
                network_data["networks"][0]["routes"].append(
                    {"netmask": "0.0.0.0", "gateway": args.gateway,
                     "network": "0.0.0.0"})

    # Check if network metadata is not skipped
    if len(network_data) > 0:
        with open(net_file_path, 'w') as net_file:
            json_dump(network_data, net_file)

    generate_iso(cfg_file_path, cfg_dir_path, args.quiet)
    if args.clean_up:
        xprint("Cleaning up working dir.")
        rmtree(cfg_dir_path)


if __name__ == '__main__':
    uuid = str(uuidgen())
    parser = argparse.ArgumentParser(
        description='Config drive generator for MCP instances.', prog=argv[0],
        usage='%(prog)s [options]')
    parser.add_argument('--gpg-key', type=str,
                        help='Upload gpg key for salt master. Specify path to file in asc format.',
                        required=False)
    parser.add_argument('--name', type=str, default=uuid,
                        help='Specify instance name. Hostname in short format, without domain.',
                        required=False)
    parser.add_argument('--hostname', type=str, default=uuid,
                        help='Specify instance hostname. FQDN. Hostname in full format with domain. Shortname would be trated as name.',
                        required=False)
    parser.add_argument('--skip-network', action='store_true',
                        help='Do not generate network_data for the instance.',
                        required=False)
    parser.add_argument('--interface', type=str, default='ens3',
                        help='Specify interface for instance to configure.',
                        required=False)
    parser.add_argument('--ssh-key', type=str,
                        help='Specify ssh public key to upload to cloud image.',
                        required=False)
    parser.add_argument('--ssh-keys', type=str,
                        help='Upload authorized_keys to cloud image. Specify path to file in authorized_keys format.',
                        required=False)
    parser.add_argument('--cloud-user-name', type=str,
                        help='Specify cloud user name.', required=False)
    parser.add_argument('--cloud-user-pass', type=str,
                        help='Specify cloud user password.', required=False)
    parser.add_argument('--ip', type=str,
                        help='Specify IP address for instance.', required=False)
    parser.add_argument('--netmask', type=str,
                        help='Specify netmask for instance.', required=False)
    parser.add_argument('--gateway', type=str,
                        help='Specify gateway address for instance.',
                        required=False)
    parser.add_argument('--dns-nameservers', type=str,
                        help='Specify DNS nameservers delimited by comma.',
                        required=False)
    parser.add_argument('--user-data', type=str,
                        help='Specify path to user_data file in yaml format.',
                        required=False)
    parser.add_argument('--vendor-data', type=str,
                        help='Specify path to vendor_data.json in openstack vendor metadata format.',
                        required=False)
    parser.add_argument('--network-data', type=str,
                        help='Specify path to network_data.json in openstack network metadata format.',
                        required=False)
    parser.add_argument('--model', type=str,
                        help='Specify path to cluster model.', required=False)
    parser.add_argument('--mk-pipelines', type=str,
                        help='Specify path to mk-pipelines folder.',
                        required=False)
    parser.add_argument('--pipeline-library', type=str,
                        help='Specify path to pipeline-library folder.',
                        required=False)
    parser.add_argument('--clean-up', action='store_true',
                        help='Clean-up config-drive dir once ISO is created.',
                        required=False)
    parser.add_argument('--quiet', action='store_true',
                        help='Keep silence. Do not write any output messages to stout.',
                        required=False)
    args = parser.parse_args()

    if len(argv) < 2:
        parser.print_help()
        exit(0)

    validate_args(args)
    create_config_drive(args)
