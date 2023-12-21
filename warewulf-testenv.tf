terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
    }
  }
}

variable "distribution" {
  default = "leap"
}

variable "nr-nodes" {
  default = 4
}

variable "packages" {
  default = "warewulf_package"
}
locals {
  network      = "172.16.${random_integer.ip_prefix.result}.0"
  network_size = "24"
  ip_host      = "172.16.${random_integer.ip_prefix.result}.250"
  dns          = "172.16.${random_integer.ip_prefix.result}.1"
  gateway      = "172.16.${random_integer.ip_prefix.result}.1"
  profile      = "warewulf-testenv"
  storage-path = "/var/tmp"
  authorized   = file("~/.ssh/authorized_keys")

  distros = {
      "leap" = {
      "image": "https://download.opensuse.org/distribution/openSUSE-stable/appliances/openSUSE-Leap-15.5-Minimal-VM.x86_64-Cloud.qcow2"
      "package_manager": "zypper install -y --allow-unsigned-rpm"
      "warewulf_package": "warewulf4"
      }
      "tw" = {
      "image": "http://download.opensuse.org/tumbleweed/appliances/openSUSE-Tumbleweed-Minimal-VM.x86_64-Cloud.qcow2"
      "package_manager": "zypper install -y --allow-unsigned-rpm"
      "warewulf_package": "warewulf4"
      }
      "local-zypp" = {
        "image": "local.qcow2"
        "package_manager":  "zypper install -y --allow-unsigned-rpm"
        "warewulf_package": "https://github.com/hpcng/warewulf/releases/download/v4.4.1/warewulf-4.4.1-1.git_d6f6fed.suse.lp153.x86_64.rpm"
      }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

resource "random_id" "base" {
  byte_length = 2
}

resource "random_integer" "ip_prefix" {
  min = 0
  max = 254
}

resource "libvirt_pool" "demo-pool" {
  # don't have a randome id attached to the pool as recreate a new pool can take ages
  name = "${local.profile}-pool"
  type = "dir"
  path = "${local.storage-path}/${local.profile}-${random_id.base.hex}"
}

resource "libvirt_volume" "ww4-host-base-vol" {
  name   = "${local.profile}-base-vol"
  pool   = libvirt_pool.demo-pool.name
  source = local.distros[var.distribution]["image"]
  format = "qcow2"
}

resource "libvirt_volume" "ww4-host-vol" {
  name   = "host-${random_id.base.hex}.qcow2"
  pool   = libvirt_pool.demo-pool.name
  base_volume_id = libvirt_volume.ww4-host-base-vol.id
  format = "qcow2"
  #size = 40399536128
  size = 80799072256
}

resource "libvirt_volume" "ww4-node-vol" {
  name   = "node-${count.index}-${random_id.base.hex}.qcow2"
  pool   = libvirt_pool.demo-pool.name
  format = "qcow2"
  size = 40399536128
  count  = var.nr-nodes
}

resource "libvirt_network" "ww4-net" {
  name      = "${local.profile}-net-${random_id.base.hex}"
  addresses = ["${local.network}/${local.network_size}"]
  dhcp {
    enabled = false
  }
  dns {
    enabled = true
  }
}

resource "tls_private_key" "rsa" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "tls_private_key" "edcsa" {
  algorithm = "ECDSA"
}
resource "tls_private_key" "ed25519" {
  algorithm = "ED25519"
}

data "template_file" "user_data" {
  template = file("${path.module}/cloud_init.cfg")
  vars = {
    ed25519_private = tls_private_key.ed25519.private_key_openssh
    ed25519_public  = tls_private_key.ed25519.public_key_openssh
    ecdsa_private   = tls_private_key.edcsa.private_key_openssh 
    ecdsa_public    = tls_private_key.edcsa.public_key_openssh
    rsa_private     = tls_private_key.rsa.private_key_openssh
    rsa_public      = tls_private_key.rsa.public_key_openssh
    authorized      = local.authorized
    package_manager = local.distros[var.distribution]["package_manager"]
    packages        = lookup(local.distros[var.distribution],var.packages,var.packages)
  }
}


data "template_file" "network_config" {
  template = file("${path.module}/network_config.cfg")
  vars = {
    ip_host      = local.ip_host
    ip_gateway   = local.gateway
    dns          = local.dns
    network_size = local.network_size
  }
}

resource "libvirt_cloudinit_disk" "hostinit" {
  name           = "commoninit.iso"
  user_data      = data.template_file.user_data.rendered
  network_config = data.template_file.network_config.rendered
  pool           = libvirt_pool.demo-pool.name
}


resource "libvirt_domain" "ww4-host" {
  name   = "ww4-host-${random_id.base.hex}"
  cloudinit = libvirt_cloudinit_disk.hostinit.id
  memory = "8192"
  vcpu   = 8
  cpu {
    mode = "host-passthrough"
  }

  tpm {
    backend_version = "2.0"
  }

  network_interface {
    network_id     = libvirt_network.ww4-net.id
  }

  disk {
    volume_id = libvirt_volume.ww4-host-vol.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
    autoport    = "true"
  }
}


resource "libvirt_domain" "ww4-nodes" {
  running = false
  count  = var.nr-nodes
  name   = format("n%02s-${random_id.base.hex}",count.index + 1)
  memory = "4096"
  vcpu  = 4
  cpu {
    mode = "host-passthrough"
  }
#  machine = "pc-q35-6.1"
#  firmware = "/usr/share/qemu/ovmf-x86_64-smm-ms-code.bin"
#  nvram {
#    file     = "/var/tmp/efi${count.index}_EFIVARS.fd"
#    template = "/usr/share/qemu/ovmf-x86_64-smm-ms-vars.bin"
#  }

  tpm {
    backend_version = "2.0"
  }

  boot_device {
    dev = [ "network" ]
  }

  network_interface {
    network_id     = libvirt_network.ww4-net.id
  }

  disk {
    volume_id = libvirt_volume.ww4-node-vol[count.index].id
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
    autoport    = "true"
  }
  
}

output "VM_names" {
  value = concat(libvirt_domain.ww4-nodes.*.name, libvirt_domain.ww4-host.*.name)
}

output "network_config" {
  value = [local.ip_host,local.network]
}

resource "local_file" "vm_mac" {
  content = yamlencode({for x in concat(libvirt_domain.ww4-nodes): x.name => x.network_interface.0.mac })
  filename = "macs.yaml"
}

