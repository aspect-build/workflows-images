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
  default = "aspect-workflows-debian-12-docker"
}

locals {
  source_image = "debian-12-bookworm-v20230912"

  # System dependencies required for Aspect Workflows
  install_packages = [
    # Google operational monitoring tools, which are used to collect and alarm on critical telemetry.
    "google-osconfig-agent",
    "rsync",
    # fuse will be optional in future release although highly recommended for better performance
    "fuse",
    # xxd is required for Workflows bootstrap
    "xxd",
    # Install git so we can fetch the source code to be tested, obviously!
    "git",
    # (Optional) Patch is required by some rulesets and package managers during dependency fetching.
    "patch",
    # (Optional) zip is required if any tests create zips of undeclared test outputs
    # For more information about undecalred test outputs, see https://bazel.build/reference/test-encyclopedia
    "zip",
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
      # Install dependencies
      "sudo apt-get update",
      format("sudo apt-get install --assume-yes %s", join(" ", local.install_packages)),

      # Install Google Cloud Ops Agent
      "curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh",
      "sudo bash add-google-cloud-ops-agent-repo.sh --also-install",

      # Enable required services
      format("sudo systemctl enable %s", join(" ", local.enable_services)),
    ]
  }
}
