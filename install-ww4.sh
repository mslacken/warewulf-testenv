#!/usr/bin/bash
source config


function run_on_hostq() {
  local remhost=$1
  if [ -z "$remhost" ] ; then 
    echo "`tput bold`no remote host given`tput sgr0`"
    return
  fi
  local cmd=$2
  local comment=$3
  if [ -n "$comment" ]; then 
    echo -e "`tput bold``tput smul`$comment`tput rmul``tput sgr0`"
  fi
  ssh -xo "StrictHostKeyChecking=no" root@$remhost $cmd
}

function run_on_host() {
  run_on_hostq "$1" "$2" "${3}`tput rmul`\n$2"
}

function wait() {
  time=${1:-3}
  if read -r -s -n 1 -t 5 -p "Press any key to abort."; then
    echo
    exit
  fi
  echo -ne "\r"
}

function show() {
  echo `tput bold``tput smul`$@`tput rmul``tput sgr0`
}
# destroy ressources
terraform destroy -auto-approve
terraform apply -auto-approve

# check that host is up
show "Waiting for the ww4-host ($IP) to become online"
while true ; do 
  ssh root@$IPADDR uname -n 2> /dev/null && break || echo -n "."
  sleep 1
done

run_on_hostq $IPADDR "zypper ref" "Refreshing repos"
run_on_host $IPADDR "zypper in -y warewulf4" "Installing warewulf4"
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
write "Start the node demo1 and conncet with vier-viewer to it"
virsh -c qemu:///system start ww4-node1
virt-viewer -w -c qemu:///system ww4-node1 &
sleep 60
kill %1

