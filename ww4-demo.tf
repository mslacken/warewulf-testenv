terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
    }
  }
}

variable "profile" {
  default = "ww4-demo"
}

locals {
  config = jsondecode(file("${path.module}/config.json"))
  reg = jsondecode(file("${path.module}/sle-keys.json"))
  ed25519_public = file("${path.module}/kiwi-description/root/etc/ssh/ssh_host_ed25519_key.pub")
  ed25519_private = file("${path.module}/kiwi-description/root/etc/ssh/ssh_host_ed25519_key")
  dsa_public = file("${path.module}/kiwi-description/root/etc/ssh/ssh_host_ed25519_key.pub")
  dsa_private = file("${path.module}/kiwi-description/root/etc/ssh/ssh_host_ed25519_key")
  ecdsa_public = file("${path.module}/kiwi-description/root/etc/ssh/ssh_host_ed25519_key.pub")
  ecdsa_private = file("${path.module}/kiwi-description/root/etc/ssh/ssh_host_ed25519_key")
  rsa_public = file("${path.module}/kiwi-description/root/etc/ssh/ssh_host_ed25519_key.pub")
  rsa_private = file("${path.module}/kiwi-description/root/etc/ssh/ssh_host_ed25519_key")
  authorized =file("~/.ssh/authorized_keys")
}



provider "libvirt" {
  uri = "qemu:///system"
}

resource "random_id" "base" {
  byte_length = 2
}

resource "libvirt_pool" "demo-pool" {
  name = "${var.profile}-pool"
  type = "dir"
  path = local.config.STORAGE
}


resource "libvirt_volume" "ww4-host-vol" {
  name   = "${var.profile}-vdisk-${random_id.base.hex}.qcow2"
  pool   = libvirt_pool.demo-pool.name
  source = local.config.IMAGE
  format = "qcow2"
}

resource "libvirt_volume" "ww4-node-vol" {
  name   = "${var.profile}-vdisk-${count.index}-${random_id.base.hex}.qcow2"
  pool   = libvirt_pool.demo-pool.name
  format = "qcow2"
  size   = 33554432
  count  = local.config.NODES
}

resource "libvirt_network" "ww4-net" {
  name      = "ww4-demo-${random_id.base.hex}"
  addresses = ["${local.config.IPNET}/24"]
  dhcp {
    enabled = false
  }
  dns {
    enabled = true
  }
}

data "template_file" "user_data" {
  template = file("${path.module}/cloud_init.cfg")
  vars = {
    email = local.reg.EMAIL
    sle-reg = local.reg.SLE-REG
    sle-hpc-reg = local.reg.SLE-HPC-REG
    ed25519_private = local.ed25519_private
    ed25519_public = local.ed25519_public
    dsa_private = local.ed25519_private
    dsa_public = local.ed25519_public
    ecdsa_private = local.ed25519_private
    ecdsa_public = local.ed25519_public
    rsa_private = local.ed25519_private
    rsa_public = local.ed25519_public
    authorized = local.authorized
  }
}

data "template_file" "network_config" {
  template = file("${path.module}/network_config.cfg")
  vars = {
    ip_addr = local.config.IPADDR
    ip_gateway = local.config.GATEWAY
    ip_netmask = local.config.NETMASK
    dns = local.config.DNS
  }
}

resource "libvirt_cloudinit_disk" "hostinit" {
  name           = "commoninit.iso"
  user_data      = data.template_file.user_data.rendered
  network_config = data.template_file.network_config.rendered
  pool           = libvirt_pool.demo-pool.name
}


resource "libvirt_domain" "ww4-host" {
  name   = "ww4-host"
  cloudinit = libvirt_cloudinit_disk.hostinit.id
  memory = "8192"
  vcpu   = 8
  cpu = {
    mode = "host-passthrough"
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


resource "libvirt_domain" "ww4-node" {
  running = false
  count  = local.config.NODES
  name   = format("demo%02s",count.index + 1)
  memory = "4096"
  vcpu  = 4
  cpu = {
    mode = "host-passthrough"
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


output "vm_names" {
  value = concat(libvirt_domain.ww4-node.*.name, libvirt_domain.ww4-host.*.name)
}

resource "local_file" "vm_mac" {
  content = jsonencode({for x in libvirt_domain.ww4-node: x.name => x.network_interface.0.mac })
  filename = "macs.json"
}

