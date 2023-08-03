packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.0.0"
      source = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "version" {
  type = string
}

variable "project" {
  type = string
}

variable "zone" {
  type = string
}

locals {
  source_image = "debian-11-bullseye-v20230629"

  # System dependencies required for Aspect Workflows
  install_packages = [
    "rsync",
    # fuse will be optional in future release although highly recommended for better performance
    "fuse",
    # Additional deps on top of minimal
    "docker.io",
  ]

  # We'll need to tell systemctl to start these when the image boots next.
  enable_services = [
    "docker.service",
  ]
}

source "googlecompute" "image" {
  project_id = "${var.project}"
  image_family = "aspect-workflows-debian-11"
  image_name = "aspect-workflows-debian-11-docker-${var.version}"
  source_image = "${local.source_image}"
  ssh_username = "packer"
  machine_type = "e2-medium"
  zone = "${var.zone}"
}

build {
  sources = [
    "source.googlecompute.image",
  ]

  // Install dependencies
  provisioner "shell" {
    inline = [
      # Install dependencies
      "sudo apt-get update",
      format("sudo apt-get install --assume-yes %s", join(" ", local.install_packages)),

      # Enable required services
      format("sudo systemctl enable %s", join(" ", local.enable_services)),
    ]
  }
}
