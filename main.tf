data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main"
  }
}

resource "aws_route" "gw" {
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.gw.id
  route_table_id = aws_vpc.main.main_route_table_id
}

resource "aws_network_interface" "incus_first" {
  subnet_id   = aws_subnet.incus_subnet.id
  private_ips = ["10.238.10.30"]
  security_groups = [aws_security_group.ssh.id]

  tags = {
    Name = "primary_network_interface"
  }
}
# resource "aws_network_interface" "incus_first_2" {
#   subnet_id   = aws_subnet.incus_subnet.id
#   private_ips = ["10.238.10.40"]
#   security_groups = [aws_security_group.ssh.id]

#   tags = {
#     Name = "secondary_network_interface"
#   }
# }
resource "aws_instance" "incus_first" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  key_name      = aws_key_pair.deployer.key_name
  network_interface {
    network_interface_id = aws_network_interface.incus_first.id
    device_index = 0
  }
  # network_interface {
  #   network_interface_id = aws_network_interface.incus_first_2.id
  #   device_index = 1
  # }
  
  root_block_device {
    volume_size = 50
  }
  user_data_replace_on_change = true
  user_data = <<EOFUD
#!/bin/bash 
LOCAL_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
sudo su
curl -fsSL https://pkgs.zabbly.com/key.asc -o /etc/apt/keyrings/zabbly.asc
sh -c 'cat <<EOF > /etc/apt/sources.list.d/zabbly-incus-lts-6.0.sources
Enabled: yes
Types: deb
URIs: https://pkgs.zabbly.com/incus/lts-6.0
Suites: $(. /etc/os-release && echo $${VERSION_CODENAME})
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/zabbly.asc

EOF'

apt update
apt install -y incus ovn-central ovn-host
systemctl enable ovn-central
systemctl enable ovn-host
systemctl stop ovn-central

cat <<-EOF >> /etc/default/ovn-central
OVN_CTL_OPTS=" \\
     --db-nb-addr=$LOCAL_IP \\
     --db-nb-create-insecure-remote=yes \\
     --db-sb-addr=$LOCAL_IP \\
     --db-sb-create-insecure-remote=yes \\
     --db-nb-cluster-local-addr=$LOCAL_IP \\
     --db-sb-cluster-local-addr=$LOCAL_IP \\
     --ovn-northd-nb-db=tcp:10.238.10.30:6641,tcp:10.238.10.31:6641,tcp:10.238.10.32:6641 \\
     --ovn-northd-sb-db=tcp:10.238.10.30:6642,tcp:10.238.10.31:6642,tcp:10.238.10.32:6642"
EOF

sudo ovs-vsctl set open_vswitch . \
   external_ids:ovn-remote=tcp:10.238.10.30:6642,tcp:10.238.10.31:6642,tcp:10.238.10.32:6642 \
   external_ids:ovn-encap-type=geneve \
   external_ids:ovn-encap-ip=$LOCAL_IP

cat <<-EOF > /etc/netplan/incusbr0.yaml
network:
  version: 2
  renderer: networkd
  bridges:
    incusbr0:
      dhcp4: no
      addresses: 
        - 10.200.0.1/16
  
EOF

netplan apply
systemctl start ovn-central

cat <<EOF | incus admin init --preseed
config:
  core.https_address: 10.238.10.30:8443
networks: []
storage_pools:
- config:
    size: 9GiB
  description: ""
  name: local
  driver: btrfs
profiles:
- config: {}
  description: ""
  devices:
    root:
      path: /
      pool: local
      type: disk
  name: default
projects: []
cluster:
  server_name: Node1
  enabled: true
  member_config: []
  cluster_address: ""
  cluster_certificate: ""
  server_address: ""
  cluster_token: ""
  cluster_certificate_path: ""
EOF

sysctl -w net.ipv4.ip_forward=1
systemctl start ovn-central
iptables -t nat -A POSTROUTING -s 10.200.0.0/16 ! -o incusbr0 -j MASQUERADE
sudo iptables -A FORWARD -i incusbr0 -o ens5 -j ACCEPT
sudo iptables -A FORWARD -i incusbr0 -o ens5 -j ACCEPT

EOFUD

  tags = {
    Name = "Incus"
  }
}

resource "aws_network_interface" "incus" {
  count = 2
  subnet_id   = aws_subnet.incus_subnet.id
  private_ips = ["10.238.10.3${count.index+1}"]
  security_groups = [aws_security_group.ssh.id]

  tags = {
    Name = "primary_network_interface"
  }
}

# resource "aws_network_interface" "incus_2" {
#   count = 2
#   subnet_id   = aws_subnet.incus_subnet.id
#   private_ips = ["10.238.10.4${count.index+1}"]
#   security_groups = [aws_security_group.ssh.id]

#   tags = {
#     Name = "secondary_network_interface"
#   }
# }
resource "aws_instance" "incus" {
  count = 2
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  key_name      = aws_key_pair.deployer.key_name
  network_interface {
    network_interface_id = aws_network_interface.incus[count.index].id
    device_index = 0
  }
  # network_interface {
  #   network_interface_id = aws_network_interface.incus_2[count.index].id
  #   device_index = 1
  # }
  root_block_device {
    volume_size = 50
  }
  user_data_replace_on_change = true
  user_data = <<EOFUD
#!/bin/bash 
LOCAL_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
sudo su
curl -fsSL https://pkgs.zabbly.com/key.asc -o /etc/apt/keyrings/zabbly.asc
sh -c 'cat <<EOF >> /etc/apt/sources.list.d/zabbly-incus-lts-6.0.sources
Enabled: yes
Types: deb
URIs: https://pkgs.zabbly.com/incus/lts-6.0
Suites: $(. /etc/os-release && echo $${VERSION_CODENAME})
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/zabbly.asc

EOF'

apt update
apt install -y incus ovn-central ovn-host
systemctl enable ovn-central
systemctl enable ovn-host
systemctl stop ovn-central

cat <<-EOF >> /etc/default/ovn-central
OVN_CTL_OPTS=" \\
     --db-nb-addr=$LOCAL_IP \\
     --db-nb-cluster-remote-addr=10.238.10.30 \\
     --db-nb-create-insecure-remote=yes \\
     --db-sb-addr=$LOCAL_IP \\
     --db-sb-cluster-remote-addr=10.238.10.30 \\
     --db-sb-create-insecure-remote=yes \\
     --db-nb-cluster-local-addr=$LOCAL_IP \\
     --db-sb-cluster-local-addr=$LOCAL_IP \\
     --ovn-northd-nb-db=tcp:10.238.10.30:6641,tcp:10.238.10.31:6641,tcp:10.238.10.32:6641 \\
     --ovn-northd-sb-db=tcp:10.238.10.30:6642,tcp:10.238.10.31:6642,tcp:10.238.10.32:6642"
EOF


sudo ovs-vsctl set open_vswitch . \
   external_ids:ovn-remote=tcp:10.238.10.30:6642,tcp:10.238.10.31:6642,tcp:10.238.10.32:6642 \
   external_ids:ovn-encap-type=geneve \
   external_ids:ovn-encap-ip=$LOCAL_IP


cat <<-EOF > /etc/netplan/incusbr0.yaml
network:
  version: 2
  renderer: networkd
  bridges:
    incusbr0:
      dhcp4: no
      addresses: 
        - 10.200.0.1/16
EOF
netplan apply

sysctl -w net.ipv4.ip_forward=1
systemctl start ovn-central
iptables -t nat -A POSTROUTING -s 10.200.0.0/16 ! -o incusbr0 -j MASQUERADE
sudo iptables -A FORWARD -i incusbr0 -o ens5 -j ACCEPT
sudo iptables -A FORWARD -i incusbr0 -o ens5 -j ACCEPT

EOFUD

  tags = {
    Name = "Incus"
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = "insert your public key here"
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block = "10.238.0.0/16"
}

resource "aws_security_group" "ssh" {
  name        = "ssh"
  description = "Allow ssh"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "allow_ssh"
  }
}

resource "aws_vpc_security_group_egress_rule" "egress_rule" {
  security_group_id = aws_security_group.ssh.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol = -1
}

resource "aws_vpc_security_group_ingress_rule" "ssh_rule" {
  security_group_id = aws_security_group.ssh.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22 
  ip_protocol       = "tcp"
  to_port           = 22
}
resource "aws_vpc_security_group_ingress_rule" "incus_rule" {
  security_group_id = aws_security_group.ssh.id
  cidr_ipv4         = aws_vpc.main.cidr_block
  from_port         = 8443
  ip_protocol       = "tcp"
  to_port           = 8443
}

resource "aws_vpc_security_group_ingress_rule" "ovn_nb" {
  security_group_id = aws_security_group.ssh.id
  cidr_ipv4         = aws_vpc.main.cidr_block
  ip_protocol       = -1
}
resource "aws_subnet" "incus_subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.238.10.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "incus"
  }
}
