# main creds for DigitalOcean connection

variable "do_token" {
  description = "Digital Ocean connection token "
}

variable "ssh_keys" {
  description = "ssh key id to access machines, Get key IDs using DO API and export them in ENV as 'export TF_VAR_ssh_keys='[key1, key2]'"
  type = "list"
}

variable "region" {
  description = "Region to provision nodes in"
  default = "nyc2"
}

variable "image" {
  description = "Type of node to provision"
  default = "ubuntu-14-04-x64"
}

variable "size" {
  description = "Size of node to provision"
  //value = "4GB"
  default = "512mb"
}

variable "node_name_prefix" {
  description = "Naming scheme for nodes"
  default = "test-shippable-server"
}
