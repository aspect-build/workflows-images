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
  default = "aspect-workflows-ubuntu-2404-kitchen-sink"
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
  source_image = "ubuntu-2404-noble-${var.arch}-v20250606"

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
    "libasound2t64",
    "libatk-bridge2.0-0",
    "libatk1.0-0",
    "libcups2",
    "libgbm-dev",
    "libgtk-3-0",
    "libgtk2.0-0",
    "libnotify-dev",
    "libnss3",
    "libstdc++-11-dev",
    "libxss1",
    "libxtst6",
    "libzstd1",
    "make",
    "moreutils",
    "xauth",
    "xvfb",
    "yq",
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
      # Disable automated apt updates
      "sudo systemctl disable apt-daily-upgrade.timer apt-daily.timer",

      # Disable snap refreshes
      "sudo snap refresh --hold=forever",

      # apt-get update is often running by the time this script begins,
      # causing a race condition to lock  /var/lib/apt/lists/lock. Kill
      # any ongoing apt processes to release the lock.
      "sudo killall apt apt-get || true",

      # Add docker repository
      "sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",

      # Install apt dependencies
      "sudo apt-get update",
      format("sudo apt-get install --assume-yes %s", join(" ", local.install_packages)),

      # Install Google Cloud Ops Agent
      "curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh",
      "sudo bash add-google-cloud-ops-agent-repo.sh --also-install",

      # Enable required services
      format("sudo systemctl enable %s", join(" ", local.enable_services)),

      # Disable Ubuntu 24.04 AppArmor mount operations restrictions so Bazel can use linux-sandbox
      "echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | sudo tee /etc/sysctl.d/99-disable-userns-restriction.conf",
      "sudo chmod 0644 /etc/sysctl.d/99-disable-userns-restriction.conf",
      "sudo chown root:root /etc/sysctl.d/99-disable-userns-restriction.conf",
      "sudo sysctl --load=/etc/sysctl.d/99-disable-userns-restriction.conf",

      # Exit with 325 if this is a dry run
      format("if [ \"%s\" = \"true\" ]; then echo 'DRY RUN COMPLETE for %s-%s'; exit 325; fi", var.dry_run, var.family, var.arch),
    ]
  }
}
