#!/usr/bin/bash
source config

# destroy ressources
#terraform destroy -auto-approve
show "Creating virtual cluster"
terraform apply -auto-approve > /dev/null || exit 1

# check that host is up
show "Waiting for the ww4-host ($IPADDR) to become online"
while true ; do 
  ssh -x root@$IPADDR uname -n 2> /dev/null && break || echo -n "."
  sleep 1
done
show "Waiting for ww4-host to finish initial configuration"
ssh -o 'ConnectionAttempts 5' -x root@$IPADDR "which cloud-init > /dev/null" && ssh -o 'ConnectionAttempts 5' -x root@$IPADDR "cloud-init status --wait"

run_on_hostq $IPADDR "zypper ref" "Refreshing repos"
run_on_host $IPADDR "zypper in -y nfs-kernel-server warewulf4" "Installing warewulf4"
wait 2
run_on_hostq $IPADDR "cat /etc/warewulf/warewulf.conf" "Check warewulf configuration /etc/warewulf/warewulf.conf"
wait 2
run_on_hostq $IPADDR "sed -i s/DHCPD_INTERFACE=\"\"/DHCPD_INTERFACE=\"ANY\"/ /etc/sysconfig/dhcpd" "Setting DHCPD_INTERFACE=\"ANY\" in /etc/sysconfig/dhcpd"
wait 2
run_on_host $IPADDR "systemctl enable --now warewulfd" "Start warewulfd"
wait 2
run_on_host $IPADDR "wwctl configure -a" "Configure warewulf, creating all the conguration files"
wait 2
run_on_host $IPADDR "wwctl node add demo[01-04] -I $IPSTART" "Adding 4 nodes"
wait 2
run_on_host $IPADDR "wwctl container import docker://registry.opensuse.org/science/warewulf/leap-15.4/containers/kernel:latest leap15.4 --setdefault" "Importing Leap15.4 as default container"
wait 2
run_on_host $IPADDR "wwctl node set demo01 --discoverable=yes -y" "Preparing node demo01 for booting"
show "Start the node demo1 and conncet with vier-viewer to it"
virsh -c qemu:///system start ww4-node1
virt-viewer -w -c qemu:///system ww4-node1 &
wait 20
kill %1

