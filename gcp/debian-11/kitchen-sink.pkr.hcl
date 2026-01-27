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
  default = "aspect-workflows-debian-11-kitchen-sink"
}

variable "arch" {
  type        = string
  default     = "amd64"
  description = "Target architecture"

  validation {
    condition     = var.arch == "amd64"
    error_message = "Only an arch of amd64 is currently supported on this distro."
  }
}

variable "dry_run" {
  type    = bool
  default = false
}

locals {
  source_image = "debian-11-bullseye-v20260114"

  # System dependencies required for Aspect Workflows
  install_packages = [
    # Dependencies of Aspect Workflows
    "fuse",                  # required for the Workflows high-performance remote cache configuration
    "git",                   # required so we can fetch the source code to be tested, obviously!
    "mdadm",                 # required for mounting multiple nvme drives with raid 0
    "google-osconfig-agent", # Google operational monitoring tools used to collect and alarm on critical telemetry
    "rsync",                 # reqired for bootstrap
    "rsyslog",               # reqired for system logging
    # Recommended dependencies
    "git-lfs", # support git repositories with LFS
    "patch",   # patch may be used by some rulesets and package managers during dependency fetching
    "zip",     # zip may be used by bazel if there are tests that produce undeclared test outputs which bazel zips; for more information about undeclared test outputs, see https://bazel.build/reference/test-encyclopedia
    # Additional deps on top of minimal
    "clang",
    "cmake",
    "containerd.io",
    "docker-buildx-plugin",
    "docker-ce-cli",
    "docker-ce",
    "docker-compose-plugin",
    "g++",
    "jq",
    "libasound2",
    "libatk-bridge2.0-0",
    "libatk1.0-0",
    "libcups2",
    "libgbm-dev",
    "libgtk-3-0",
    "libgtk2.0-0",
    "libnotify-dev",
    "libnss3",
    "libstdc++-10-dev",
    "libyaml-dev",
    "libxss1",
    "libxtst6",
    "libzstd1",
    "make",
    "moreutils",
    "xauth",
    "xvfb",
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
      # Add Docker repository
      "sudo apt-get update",
      "sudo apt-get install -y ca-certificates curl",
      "sudo install -m 0755 -d /etc/apt/keyrings",
      "sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc",
      "sudo chmod a+r /etc/apt/keyrings/docker.asc",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bullseye stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",

      # Install apt dependencies
      "sudo apt-get update",
      format("sudo apt-get install --assume-yes %s", join(" ", local.install_packages)),

      # We've observed networking issues with Docker on Debian 11 that are resolved by setting
      # { "ipv6": true, "fixed-cidr-v6": "2001:db8:1::/64" } in the daemon config.
      "sudo mkdir -p /etc/docker",
      "echo '{ \"ipv6\": true, \"fixed-cidr-v6\": \"2001:db8:1::/64\" }' | sudo tee /etc/docker/daemon.json",

      # Install Google Cloud Ops Agent
      "curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh",
      "sudo bash add-google-cloud-ops-agent-repo.sh --also-install",

      # Install yq
      "sudo curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${var.arch} -o /usr/bin/yq",
      "sudo chmod +x /usr/bin/yq",
      "yq --version",

      # Enable required services
      format("sudo systemctl enable %s", join(" ", local.enable_services)),

      # Exit with 325 if this is a dry run
      format("if [ \"%s\" = \"true\" ]; then echo 'DRY RUN COMPLETE for %s-%s'; exit 325; fi", var.dry_run, var.family, var.arch),
    ]
  }
}
