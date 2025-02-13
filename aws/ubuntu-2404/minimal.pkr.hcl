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
  default = "aspect-workflows-ubuntu-2404-minimal"
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
    name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-${var.arch}-server-20250115"
    root-device-type    = "ebs"
  }
  owners      = ["099720109477"] # amazon
  region      = "${var.region}"
  most_recent = true
}

locals {
  install_debs = [
    # Install cloudwatch-agent so that bootstrap logs are easier to locale
    "https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/${var.arch}/latest/amazon-cloudwatch-agent.deb",
  ]

  install_packages = [
    # Dependencies of Aspect Workflows
    "fuse", # required for the Workflows high-performance remote cache configuration
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

      # Install AWS CLI
      "curl \"${local.awscli_url[var.arch]}\" -o \"awscliv2.zip\"",
      "unzip awscliv2.zip",
      "sudo ./aws/install",

      # Exit with 325 if this is a dry run
      format("if [ \"%s\" = \"true\" ]; then echo 'DRY RUN COMPLETE for %s-%s'; exit 325; fi", var.dry_run, var.family, var.arch),
    ])
  }
}
