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
  source_image = "ubuntu-2304-lunar-amd64-v20230613"

  # System dependencies required for Aspect Workflows
  install_packages = [
    # fuse will be optional in future releases although highly recommended for better performance
    "fuse",
    # (Optional) Patch is required by some rulesets and package managers during dependency fetching.
    "patch",
    # (Optional) zip is required if any tests create zips of undeclared test outputs
    # For more information about undecalred test outputs, see https://bazel.build/reference/test-encyclopedia
    "zip",
  ]
}

source "googlecompute" "image" {
  project_id = "${var.project}"
  image_family = "aspect-workflows-ubuntu-2304-minimal"
  image_name = "aspect-workflows-ubuntu-2304-minimal-${var.version}"
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
      # Disable automated apt updates
      "sudo systemctl disable apt-daily-upgrade.timer apt-daily.timer",

      # Disable snap refreshes
      "sudo snap refresh --hold=forever",

      # apt-get update is often running by the time this script begins,
      # causing a race condition to lock  /var/lib/apt/lists/lock. Kill
      # any ongoing apt processes to release the lock.
      "sudo killall apt apt-get || true",

      # Install dependencies
      "sudo apt-get update",
      format("sudo apt-get install --assume-yes %s", join(" ", local.install_packages)),
    ]
  }
}
