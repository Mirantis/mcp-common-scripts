Config drive creation tool
==========================

Script gives you an ability to build iso file for MCP instances.

No, it is not for VCP instances. VCP instances config drives are configured by
salt master. This script is intended only for building config drives for
salt master and aptly mirror(for offline deployments).

It has as many features as openstack cloud init format provides.
You can use network_data.json vendor_data.json or not specify them at all.

Networking part is a major part here.
If you specify --network-data key with network_data.json it has highest priority
on network set up, further network configuration is ignored and taken completely
from json file you specify.
This is how you can specify configuration for multiple interfaces if you wish.
Without this file instance should have network configuration being done somehow
and basic information is taken by passing:

     --ip,
     --netmask,
     --gateway(optional, used for default route),
     --interface(optional, default ens3 is used)

argumetns.

So in order to create iso file script should know these parameters and you need
to pass them, otherwise one should implement logic based on write_files: section
and catching SALT_MASTER_DEPLOY_IP or APTLY_DEPLOY_IP parameters which may
change its names in time.
In this case basic network configuration would be done and further actions, like
setting up mtu, vlans, bridges, should be taken by config management tool (salt).

You may want to skip network at all and just pass --skip-network, so instance
would start with meta_data.json and user_data.

Other parameters like MCP_VERSION are out of scope of this tool and are not
going to be calculated. You need to edit yaml files before creating iso files
and specify them on your own.

Vendor metadata can be specified in native json format of openstack:
- vendor_data.json (StaticJSON)

If you want to add ssh key to your instance, you can specify it via --ssh-key
parameter. If you are going to add multiple ssh keys, you need to use
--ssh-keys parameter and specify path to a file in authorized_keys format which
has them. If you specify both, they would be merged and deduplicated.

If you want to have an access to your instance via ssh, you need to know default
username for a cloud image.
However you can specify it using --cloud-user-name parameter and ssh keys would
be added to it. This user has sudo privileges.

If you feel you need to get an access to your instance via serial tty, you can
specify --cloud-user-pass parameter and user section would be updated.
