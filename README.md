# warewulf-testenv
Terraform template for setting up a virtual warewulf test cluster. It pull an OS 
appliance and install `warewulf` on it.  You can login to the nodes as `root` with the password `linux`.

## Prerequisites
Terraform must be installed and the user should be part of the `libvirt` group.

## Usage
Simply run
```
terraform apply
```
after the run remove the virtual machines with
```
terraform destroy
```

### Configure number of nodes
```
terraform apply -var="nr_nodes=2"
```

### Don't install warewulf
```
terraform apply -var="packages=fortune"
```

## known errors
The key in `~/.ssh/authorized_keys` are copied over to `ww4-host`. If there is more than
one key, cloud-init fails.