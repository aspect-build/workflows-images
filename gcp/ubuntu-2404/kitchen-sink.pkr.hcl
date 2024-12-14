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
  default = "aspect-workflows-ubuntu-2404-kitchen-sink"
}

variable "arch" {
  type = string
  default = "amd64"
  description = "Target architecture"

  validation {
    condition     = var.arch == "amd64" || var.arch == "arm64"
    error_message = "Expected arch to be either amd64 or arm64."
  }
}

locals {
  source_image = "ubuntu-2404-noble-${var.arch}-v20241115"

  # System dependencies required for Aspect Workflows
  install_packages = [
    # Dependencies of Aspect Workflows
    "fuse",  # required for the Workflows high-performance remote cache configuration
    "google-osconfig-agent",  # Google operational monitoring tools used to collect and alarm on critical telemetry
    # Optional but recommended dependencies
    "patch",  # patch may be used by some rulesets and package managers during dependency fetching
    "zip",  # zip may be used by bazel if there are tests that produce undeclared test outputs which bazel zips; for more information about undeclared test outputs, see https://bazel.build/reference/test-encyclopedia
    # Additional deps on top of minimal
    "docker.io",
    "g++",
    "jq",
    "make",
  ]

  # We'll need to tell systemctl to start these when the image boots next.
  enable_services = [
    "docker.service",
  ]

  machine_types = {
    amd64 = "e2-medium"
    arm64 = "t2a-standard-1"
  }
}

source "googlecompute" "image" {
  project_id = "${var.project}"
  image_family = "${var.family}-${var.arch}"
  image_name = "${var.family}-${var.arch}-${var.version}"
  source_image = "${local.source_image}"
  ssh_username = "packer"
  machine_type = "${local.machine_types[var.arch]}"
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

      # Enable required services
      format("sudo systemctl enable %s", join(" ", local.enable_services)),
    ]
  }
}
