terraform {
 required_version = ">= 0.13"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.6.14"
    }
  }
}

variable "nr_nodes" {
  default = "4"
}


variable "profile" {
  default = "ww4-demo"
}

provider "libvirt" {
  uri = "qemu:///system"
}

resource "random_id" "base" {
  byte_length = 2
}

resource "libvirt_pool" "ww4-demo" {
  name = "terraform-pool${random_id.base.hex}"
  type = "dir"
  path = "${var.poolStorage}/${random_id.base.hex}"
}

resource "libvirt_volume" "my-vdisk" {
  name   = "${var.profile}-vdisk-${count.index}-${random_id.base.hex}.qcow2"
  count  = var.nr_machines
  pool   = libvirt_pool.ww4-demo.name
  source = "Leap-15.5_appliance.x86_64-0.0.1.qcow2"
  format = "qcow2"
}

resource "libvirt_network" "my_net" {
  name      = "ww4-demo-${random_id.base.hex}"
  addresses = ["var.IPNET/24"]
  dhcp {
    enabled = false
  }
  dns {
    enabled = true
  }
}

resource "libvirt_domain" "domain" {
  name   = "slurm-node${count.index+1}-${random_id.base.hex}"
  memory = "8192"
  vcpu   = 8
  count  = var.nr_machines
  cpu = {
    mode = "host-passthrough"
  }

  network_interface {
    network_id     = libvirt_network.my_net.id
    wait_for_lease = true
    hostname       = "node%{ if count.index < 9 }0%{ endif }${count.index+1}"
    addresses      = ["172.16.${random_integer.ip_prefix.result}.${count.index+11}"]
  }

  disk {
    volume_id = libvirt_volume.my-vdisk[count.index].id
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

output "vm_ips" {
  value = libvirt_domain.domain.*.network_interface.0.addresses
}

output "vm_names" {
  value = libvirt_domain.domain.*.name
}

