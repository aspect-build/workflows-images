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

variable "vpc_id" {
  type = string
  default = null
}

variable "subnet_id" {
  type = string
  default = null
}

variable "encrypt_boot" {
  type = bool
  default = false
}

# Lookup the base AMI we want:
# Buildkite Elastic Stack (Amazon Linux 2 LTS w/ docker)
# Definition of this AMI: https://github.com/buildkite/elastic-ci-stack-for-aws/blob/v5.22.1/packer/linux/buildkite-ami.json
data "amazon-ami" "buildkite-al2" {
    filters = {
        virtualization-type = "hvm"
        # From https://s3.amazonaws.com/buildkite-aws-stack/v5.22.1/aws-stack.yml
        name = "buildkite-stack-linux-x86_64-2023-07-21T07-35-32Z-${var.region}",
        root-device-type = "ebs"
    }
    owners = ["172840064832"] # Buildkite
    region = "${var.region}"
    most_recent = true
}

locals {
    source_ami = data.amazon-ami.buildkite-al2.id

    # System dependencies required for Aspect Workflows or for build & test
    install_packages = [
        # Install fuse so that launch_bb_clientd_linux.sh can run.
        "fuse",
        # (Optional) Patch is required by some rulesets and package managers during dependency fetching.
        "patch",
        # Additional deps on top of minimal
        "gcc-c++",
        "gcc",
    ]
}

source "amazon-ebs" "runner" {
  ami_name                                  = "aspect-workflows-buildkite-al2-gcc-${var.version}"
  instance_type                             = "t3a.small"
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
          # Install dependencies
          format("sudo yum --setopt=skip_missing_names_on_install=False --assumeyes install %s", join(" ", local.install_packages)),
      ]
  }
}
