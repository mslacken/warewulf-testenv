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
run_on_host $IPADDR "zypper in -y nfs-kernel-server bash-completion warewulf4" "Installing warewulf4"
wait 2
run_on_hostq $IPADDR "cat /etc/warewulf/warewulf.conf" "Check warewulf configuration /etc/warewulf/warewulf.conf"
wait 2
run_on_hostq $IPADDR "sed -i s/DHCPD_INTERFACE=\"\"/DHCPD_INTERFACE=\"ANY\"/ /etc/sysconfig/dhcpd" "Setting DHCPD_INTERFACE=\"ANY\" in /etc/sysconfig/dhcpd"
wait 2
run_on_host $IPADDR "systemctl enable --now warewulfd" "Start warewulfd"
wait 2
run_on_host $IPADDR "wwctl configure -a" "Configure warewulf, creating all the configuration files"
wait 2
run_on_host $IPADDR "wwctl node add demo[01-04] -I $IPSTART" "Adding 4 nodes"
wait 2
run_on_host $IPADDR "wwctl container import $DEMOCONTSRC $DEMOCONT --setdefault" "Importing Leap15.4 as default container"
wait 2
show "Add the MAC addresses for the rest of the nodes from pre defined json/csv"
for host in $(jq "keys[]" macs.json ) ; do
  mac=$(jq ".$host" macs.json)
  run_on_host $IPADDR "wwctl node set $host -y --netname default --hwaddr $mac" 
done

