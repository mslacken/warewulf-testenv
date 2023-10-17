terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
    }
  }
}

variable "nr_nodes" {
  default = "4"
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

resource "libvirt_volume" "my-vdisk" {
  name   = "${var.profile}-vdisk-${random_id.base.hex}.qcow2"
  pool   = "tmp"
  source = "Leap-15.5_appliance.x86_64-0.0.1.qcow2"
  format = "qcow2"
}

resource "libvirt_network" "my_net" {
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
  cpu = {
    mode = "host-passthrough"
  }

  network_interface {
    network_id     = libvirt_network.my_net.id
  }

  disk {
    volume_id = libvirt_volume.my-vdisk.id
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

