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
}

provider "libvirt" {
  uri = "qemu:///system"
}

resource "random_id" "base" {
  byte_length = 2
}

resource "libvirt_pool" "demo-pool" {
  name = "demo-pool"
  type = "dir"
  path = local.config.STORAGE
}


resource "libvirt_volume" "ww4-host-vol" {
  name   = "${var.profile}-vdisk-${random_id.base.hex}.qcow2"
  pool   = libvirt_pool.demo-pool.name
  source = "Leap-15.5_appliance.x86_64-0.0.1.qcow2"
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

resource "libvirt_domain" "ww4-host" {
  name   = "ww4-host"
  memory = "8192"
  vcpu   = 8
  cpu  {
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
  name   = "ww4-node${count.index+1}"
  memory = "4096"
  vcpu   = 4
  cpu  {
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
