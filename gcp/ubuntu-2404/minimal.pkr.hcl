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
  default = "aspect-workflows-ubuntu-2404-minimal"
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
  source_image = "ubuntu-2404-noble-${var.arch}-v20251001"

  # System dependencies required for Aspect Workflows
  install_packages = [
    # Dependencies of Aspect Workflows
    "fuse",                  # required for the Workflows high-performance remote cache configuration
    "google-osconfig-agent", # Google operational monitoring tools used to collect and alarm on critical telemetry
    # Recommended dependencies
    "git-lfs", # support git repositories with LFS
    "patch",   # patch may be used by some rulesets and package managers during dependency fetching
    "zip",     # zip may be used by bazel if there are tests that produce undeclared test outputs which bazel zips; for more information about undeclared test outputs, see https://bazel.build/reference/test-encyclopedia
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

      # Install apt dependencies
      "sudo apt-get update",
      format("sudo apt-get install --assume-yes %s", join(" ", local.install_packages)),

      # Install Google Cloud Ops Agent
      "curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh",
      "sudo bash add-google-cloud-ops-agent-repo.sh --also-install",

      # Disable Ubuntu 24.04 AppArmor mount operations restrictions so Bazel can use linux-sandbox
      "echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | sudo tee /etc/sysctl.d/99-disable-userns-restriction.conf",
      "sudo chmod 0644 /etc/sysctl.d/99-disable-userns-restriction.conf",
      "sudo chown root:root /etc/sysctl.d/99-disable-userns-restriction.conf",
      "sudo sysctl --load=/etc/sysctl.d/99-disable-userns-restriction.conf",

      # Disable unattended-upgrades by removing the package
      "sudo apt purge -y unattended-upgrades",
      # Disable needrestart by setting to list-only mode (or purge if preferred)
      "sudo sed -i \"s/#\\$nrconf{restart} = 'i';/\\$nrconf{restart} = 'l';/\" /etc/needrestart/needrestart.conf",

      # Exit with 325 if this is a dry run
      format("if [ \"%s\" = \"true\" ]; then echo 'DRY RUN COMPLETE for %s-%s'; exit 325; fi", var.dry_run, var.family, var.arch),
    ]
  }
}
