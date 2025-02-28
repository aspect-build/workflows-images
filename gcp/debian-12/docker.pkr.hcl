packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/googlecompute"
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
  type    = string
  default = "aspect-workflows-debian-12-docker"
}

variable "arch" {
  type        = string
  default     = "amd64"
  description = "Target architecture"

  validation {
    condition     = var.arch == "amd64" || var.arch == "arm64"
    error_message = "Expected arch to be either amd64 or arm64."
  }
}

variable "dry_run" {
  type    = bool
  default = false
}

locals {
  source_image = "debian-12-bookworm-${var.arch == "arm64" ? "arm64-" : ""}v20250212"

  # System dependencies required for Aspect Workflows
  install_packages = [
    # Dependencies of Aspect Workflows
    "fuse",                  # required for the Workflows high-performance remote cache configuration
    "git",                   # required so we can fetch the source code to be tested, obviously!
    "google-osconfig-agent", # Google operational monitoring tools used to collect and alarm on critical telemetry
    "rsync",                 # reqired for bootstrap
    # Recommended dependencies
    "git-lfs", # support git repositories with LFS
    "patch",   # patch may be used by some rulesets and package managers during dependency fetching
    "zip",     # zip may be used by bazel if there are tests that produce undeclared test outputs which bazel zips; for more information about undeclared test outputs, see https://bazel.build/reference/test-encyclopedia
    # Additional deps on top of minimal
    "docker.io",
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
  project_id   = "${var.project}"
  image_family = "${var.family}-${var.arch}"
  image_name   = "${var.family}-${var.arch}-${var.version}"
  source_image = "${local.source_image}"
  ssh_username = "packer"
  machine_type = "${local.machine_types[var.arch]}"
  zone         = "${var.zone}"
}

build {
  sources = [
    "source.googlecompute.image",
  ]

  provisioner "shell" {
    inline = [
      # Install apt dependencies
      "sudo apt-get update",
      format("sudo apt-get install --assume-yes %s", join(" ", local.install_packages)),

      # Install Google Cloud Ops Agent
      "curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh",
      "sudo bash add-google-cloud-ops-agent-repo.sh --also-install",

      # Enable required services
      format("sudo systemctl enable %s", join(" ", local.enable_services)),

      # Exit with 325 if this is a dry run
      format("if [ \"%s\" = \"true\" ]; then echo 'DRY RUN COMPLETE for %s-%s'; exit 325; fi", var.dry_run, var.family, var.arch),
    ]
  }
}
