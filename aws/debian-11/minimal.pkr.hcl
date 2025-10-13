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
  default = "aspect-workflows-debian-11-minimal"
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
    condition     = var.arch == "amd64"
    error_message = "Only an arch of amd64 is currently supported on this distro."
  }
}

variable "dry_run" {
  type    = bool
  default = false
}

# Lookup the base AMI we want
# Debian 11 (<rev>)
data "amazon-ami" "debian" {
  filters = {
    virtualization-type = "hvm"
    name                = "debian-11-${var.arch}-20251006-2257"
    root-device-type    = "ebs"
  }
  owners      = ["136693071363"] # Amazon
  region      = "${var.region}"
  most_recent = true
}

locals {
  source_ami = data.amazon-ami.debian.id

  install_debs = [
    # Install cloudwatch-agent so that bootstrap logs are easier to locale
    "https://s3.amazonaws.com/amazoncloudwatch-agent/debian/${var.arch}/latest/amazon-cloudwatch-agent.deb",
    # Install system manager so it's easy to login to a machine
    "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_${var.arch}/amazon-ssm-agent.deb",
  ]

  install_packages = [
    # Dependencies of Aspect Workflows
    "fuse",  # required for the Workflows high-performance remote cache configuration
    "git",   # required so we can fetch the source code to be tested, obviously!
    "rsync", # required for bootstrap
    # Recommended dependencies
    "git-lfs", # support git repositories with LFS
    "patch",   # patch may be used by some rulesets and package managers during dependency fetching
    "zip",     # zip may be used by bazel if there are tests that produce undeclared test outputs which bazel zips; for more information about undeclared test outputs, see https://bazel.build/reference/test-encyclopedia
  ]

  enable_services = [
    "amazon-cloudwatch-agent",
    "amazon-ssm-agent",
  ]

  instance_types = {
    amd64 = "t3a.small"
    arm64 = "c7g.medium"
  }
}

source "amazon-ebs" "runner" {
  ami_name                                  = "${var.family}-${var.arch}-${var.version}"
  instance_type                             = "${local.instance_types[var.arch]}"
  region                                    = "${var.region}"
  vpc_id                                    = "${var.vpc_id}"
  subnet_id                                 = "${var.subnet_id}"
  ssh_username                              = "admin"
  source_ami                                = local.source_ami
  temporary_security_group_source_public_ip = true
  encrypt_boot                              = var.encrypt_boot
}

build {
  sources = ["source.amazon-ebs.runner"]

  provisioner "shell" {
    inline = concat([
      # Fetch debian dependencies
      for url in local.install_debs : format("sudo curl %s -O", url)
      ], [
      # Install debian dependencies
      format("sudo dpkg --install --skip-same-version %s", join(" ", [
        for url in local.install_debs : basename(url)
      ])),

      # Install apt dependencies
      "sudo apt update",
      format("sudo apt-get install --assume-yes %s", join(" ", local.install_packages)),

      # Enable required services
      format("sudo systemctl enable %s", join(" ", local.enable_services)),

      # Exit with 325 if this is a dry run
      format("if [ \"%s\" = \"true\" ]; then echo 'DRY RUN COMPLETE for %s-%s'; exit 325; fi", var.dry_run, var.family, var.arch),
    ])
  }
}
