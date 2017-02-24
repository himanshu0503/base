# Setup our DO provider
provider "digitalocean" {
  token = "${var.do_token}"
}
