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
  default = "aspect-workflows-al2023-minimal"
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

# Lookup the base AMI we want:
# Amazon Linux 2023 AMI <rev> <arch> HVM kernel-6.1
# https://github.com/aws/amazon-ecs-ami/blob/main/al2023.pkr.hcl
data "amazon-ami" "al2023" {
  filters = {
    virtualization-type = "hvm"
    name                = "al2023-ami-2023.9.20250929.0-kernel-6.1-${var.arch == "amd64" ? "x86_64" : var.arch}",
    root-device-type    = "ebs"
  }
  owners      = ["137112412989"] # Amazon
  region      = "${var.region}"
  most_recent = true
}

locals {
  source_ami = data.amazon-ami.al2023.id

  install_packages = [
    # Dependencies of Aspect Workflows
    "amazon-cloudwatch-agent", # install cloudwatch-agent so that bootstrap logs are easier to locate
    "fuse",                    # required for the Workflows high-performance remote cache configuration
    "git",                     # required so we can fetch the source code to be tested, obviously!
    "libicu",                  # libicu is needed by GitHub Actions agent (https://github.com/actions/runner/issues/2511)
    "mdadm",                   # required when mounting multiple nvme drives with raid 0
    "rsyslog",                 # reqired for system logging
    # Recommended dependencies
    "git-lfs", # support git repositories with LFS
    "patch",   # patch may be used by some rulesets and package managers during dependency fetching
    "zip",     # zip may be used by bazel if there are tests that produce undeclared test outputs which bazel zips; for more information about undeclared test outputs, see https://bazel.build/reference/test-encyclopedia
  ]

  enable_services = [
    "amazon-cloudwatch-agent",
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
  ssh_username                              = "ec2-user"
  source_ami                                = local.source_ami
  temporary_security_group_source_public_ip = true
  encrypt_boot                              = var.encrypt_boot
}

build {
  sources = ["source.amazon-ebs.runner"]

  provisioner "shell" {
    inline = [
      # Install yum dependencies
      format("sudo yum --setopt=skip_missing_names_on_install=False --assumeyes install %s", join(" ", local.install_packages)),

      # Enable required services
      format("sudo systemctl enable %s", join(" ", local.enable_services)),

      # Exit with 325 if this is a dry run
      format("if [ \"%s\" = \"true\" ]; then echo 'DRY RUN COMPLETE for %s-%s'; exit 325; fi", var.dry_run, var.family, var.arch),
    ]
  }
}
