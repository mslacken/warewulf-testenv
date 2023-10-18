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
    echo "`tput bold`$comment`tput sgr0`"
  else 
    echo "`tput bold`running command $cmd host: $remhost`tput sgr0`"
  fi
  ssh -xo "StrictHostKeyChecking=no" root@$remhost $cmd
}

function run_on_host() {
  run_on_hostq() $1 $2 "${3} $2" 
}

function wait() {
  time=${1:-3}
  if read -r -s -n 1 -t 5 -p "Press any key to abort."; then
    echo
    exit
  fi
}

run_on_host $IPADDR "zypper ref"
wait 2
run_on_host $IPADDR "zypper in -y warewulf4" "Installing warewulf4"
wait 2
run_on_host $IPADDR "cat /etc/warewulf/warewulf.conf" "Check warewulf configuration /etc/warewulf/warewulf.conf"
wait 2
run_on_host $IPADDR "sed -i s/DHCPD_INTERFACE=\"\"/DHCPD_INTERFACE=\"ANY\"/ /etc/sysconfig/dhcpd" "Setting DHCPD_INTERFACE=\"ANY\" in /etc/sysconfig/dhcpd"
wait 2
run_on_host $IPADDR "wwctl configure -a" "Configure the warewulf"
run_on_host $IPADDR "wwctl node add demo[01-04] -I $IPSTART" "Adding 4 nodes"
