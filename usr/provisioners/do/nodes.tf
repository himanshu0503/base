resource "digitalocean_droplet" "cs01" {
  image = "${var.image}"
  region = "${var.region}"
  size = "${var.size}"
  name = "${var.node_name_prefix}-cs01"
  ssh_keys = "${var.ssh_keys}"
}

resource "digitalocean_droplet" "cs02" {
  image = "${var.image}"
  region = "${var.region}"
  size = "${var.size}"
  name = "${var.node_name_prefix}-cs02"
  ssh_keys = "${var.ssh_keys}"
}

resource "digitalocean_droplet" "ms01" {
  image = "${var.image}"
  region = "${var.region}"
  size = "${var.size}"
  name = "${var.node_name_prefix}-ms01"
  ssh_keys = "${var.ssh_keys}"
}

resource "digitalocean_droplet" "ms02" {
  image = "${var.image}"
  region = "${var.region}"
  size = "${var.size}"
  name = "${var.node_name_prefix}-ms02"
  ssh_keys = "${var.ssh_keys}"
}
