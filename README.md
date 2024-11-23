# Incus AWS OVN Setup

This project prepares aws ec2 nodes for a basic incus cluster setup with OVN. After running terraform apply there will still be a few steps left to complete this setup.

## Steps

- Run `terraform apply`
- Log on to the first instance
- Run `incus cluster add Node2` Take not of the output token
- Run `incus cluster add Node3` Take not of the output token
- Run `incus admin init` the 2 remaining cluster nodes and use the tokens from the commands above
- On any instance run
```
incus network create UPLINK --type=physical parent=incusbr0 --target=Node1
incus network create UPLINK --type=physical parent=incusbr0 --target=Node2
incus network create UPLINK --type=physical parent=incusbr0 --target=Node3
incus network create UPLINK --type=physical \
   ipv4.ovn.ranges=10.200.100.1-10.200.100.200 \
   ipv4.gateway=10.200.0.1/16 \
   dns.nameservers=8.8.8.8


incus config set network.ovn.northbound_connection tcp:10.238.10.30:6641,tcp:10.238.10.31:6641,tcp:10.238.10.32:6641
```

After these steps are done you should be able create ovn networks use peering and acls. You can test instance creation using:

```
incus network create my-ovn --type=ovn
incus launch images:ubuntu/22.04 c1 --network my-ovn
incus launch images:ubuntu/22.04 c2 --network my-ovn
incus launch images:ubuntu/22.04 c3 --network my-ovn
incus launch images:ubuntu/22.04 c4 --network my-ovn
```
