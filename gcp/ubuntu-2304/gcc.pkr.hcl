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

variable "family" {
  type = string
  default = "aspect-workflows-ubuntu-2304-gcc"
}

locals {
  source_image = "ubuntu-2304-lunar-amd64-v20230613"

  # System dependencies required for Aspect Workflows
  install_packages = [
    # Google operational monitoring tools, which are used to collect and alarm on critical telemetry.
    "google-osconfig-agent",
    # fuse will be optional in future releases although highly recommended for better performance
    "fuse",
    # (Optional) Patch is required by some rulesets and package managers during dependency fetching.
    "patch",
    # (Optional) zip is required if any tests create zips of undeclared test outputs
    # For more information about undecalred test outputs, see https://bazel.build/reference/test-encyclopedia
    "zip",
    # Additional deps on top of minimal
    "g++",
  ]
}

source "googlecompute" "image" {
  project_id = "${var.project}"
  image_family = "${var.family}"
  image_name = "${var.family}-${var.version}"
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

      # Install Google Cloud Ops Agent
      "curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh",
      "sudo bash add-google-cloud-ops-agent-repo.sh --also-install",
    ]
  }
}
