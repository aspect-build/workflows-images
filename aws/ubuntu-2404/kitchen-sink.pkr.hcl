packer {
  required_plugins {
    amazon = {
      version = ">= 1.1.5"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "version" {
  type = string
}

variable "region" {
  type = string
}

variable "family" {
  type    = string
  default = "aspect-workflows-ubuntu-2404-kitchen-sink"
}

variable "vpc_id" {
  type    = string
  default = null
}

variable "subnet_id" {
  type    = string
  default = null
}

variable "encrypt_boot" {
  type    = bool
  default = false
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

# Lookup the base AMI we want
# Canonical, Ubuntu, 24.04 LTS, <arch> focal image build on <rev>
data "amazon-ami" "ubuntu" {
  filters = {
    virtualization-type = "hvm"
    name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-${var.arch}-server-20250610"
    root-device-type    = "ebs"
  }
  owners      = ["099720109477"] # amazon
  region      = "${var.region}"
  most_recent = true
}

locals {
  install_packages = [
    # Dependencies of Aspect Workflows
    "amazon-cloudwatch-agent", # install cloudwatch-agent for logging
    "fuse",                    # required for the Workflows high-performance remote cache configuration
    "git",                     # required so we can fetch the source code to be tested, obviously!
    "mdadm",                   # required for mounting multiple nvme drives with raid 0
    "rsync",                   # required for bootstrap
    "rsyslog",                 # reqired for system logging
    # Recommended dependencies
    "git-lfs", # support git repositories with LFS
    "patch",   # patch may be used by some rulesets and package managers during dependency fetching
    "zip",     # zip may be used by bazel if there are tests that produce undeclared test outputs which bazel zips; for more information about undeclared test outputs, see https://bazel.build/reference/test-encyclopedia
    # Additional deps on top of minimal
    "clang",
    "cmake",
    "containerd.io",
    "chromium",
    "docker-buildx-plugin",
    "docker-ce-cli",
    "docker-ce",
    "docker-compose-plugin",
    "fonts-liberation",
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
    "nodejs",
    "xauth",
    "xdg-utils",
    "xvfb",
    "yq",
  ]

  enable_services = [
    "amazon-cloudwatch-agent",
    "docker.service",
  ]

  instance_types = {
    amd64 = "t3a.small"
    arm64 = "c7g.medium"
  }

  awscli_url = {
    amd64 = "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    arm64 = "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
  }
}

source "amazon-ebs" "runner" {
  ami_name                                  = "${var.family}-${var.arch}-${var.version}"
  instance_type                             = "${local.instance_types[var.arch]}"
  region                                    = "${var.region}"
  vpc_id                                    = "${var.vpc_id}"
  subnet_id                                 = "${var.subnet_id}"
  ssh_username                              = "ubuntu"
  source_ami                                = data.amazon-ami.ubuntu.id
  temporary_security_group_source_public_ip = true
  encrypt_boot                              = var.encrypt_boot
}

build {
  sources = ["source.amazon-ebs.runner"]

  provisioner "shell" {
    inline = concat([
      # Install amazon cloud watch agent
      "sudo curl https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/${var.arch}/latest/amazon-cloudwatch-agent.deb -O",
      "sudo dpkg --install --skip-same-version amazon-cloudwatch-agent.deb",

      # Add docker repository
      "sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",

      # Add Node.js repository
      "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -",

      # Install apt dependencies
      "sudo add-apt-repository ppa:xtradeb/apps -y", # repository for chromium package (the Ubuntu chromium-browser packages installs chromium-browser as a snap package which breaks tests on CI)
      "sudo apt update",
      format("sudo apt-get install --assume-yes %s", join(" ", local.install_packages)),

      # Enable required services
      format("sudo systemctl enable %s", join(" ", local.enable_services)),

      # Install AWS CLI
      "curl \"${local.awscli_url[var.arch]}\" -o \"awscliv2.zip\"",
      "unzip awscliv2.zip",
      "sudo ./aws/install",

      # Exit with 325 if this is a dry run
      format("if [ \"%s\" = \"true\" ]; then echo 'DRY RUN COMPLETE for %s-%s'; exit 325; fi", var.dry_run, var.family, var.arch),
    ])
  }
}
