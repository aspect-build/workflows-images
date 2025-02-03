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
  type = string
  default = "aspect-workflows-al2-kitchen-sink"
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

variable "arch" {
  type = string
  default = "amd64"
  description = "Target architecture"

  validation {
    condition     = var.arch == "amd64" || var.arch == "arm64"
    error_message = "Expected arch to be either amd64 or arm64."
  }
}

# Lookup the base AMI we want:
# Amazon Linux 2 Kernel 5.10 AMI <rev> <arch> HVM gp2
# https://github.com/aws/amazon-ecs-ami/blob/main/al2kernel5dot10.pkr.hcl
data "amazon-ami" "al2" {
    filters = {
        virtualization-type = "hvm"
        name = "amzn2-ami-kernel-5.10-hvm-2.0.20250123.4-${var.arch == "amd64" ? "x86_64" : var.arch}-gp2",
        root-device-type = "ebs"
    }
    owners = ["137112412989"] # Amazon
    region = "${var.region}"
    most_recent = true
}

locals {
    source_ami = data.amazon-ami.al2.id

    # System dependencies required for Aspect Workflows or for build & test
    # if you have a working docker setup, you can query the packages like so:
    #   -> % docker run --rm -it --entrypoint bash amazonlinux:2
    #   bash-4.2# yum search <package>
    install_packages = [
        # Dependencies of Aspect Workflows
        "amazon-cloudwatch-agent",  # install cloudwatch-agent so that bootstrap logs are easier to locate
        "fuse",  # required for the Workflows high-performance remote cache configuration
        "git",  # required so we can fetch the source code to be tested, obviously!
        # Optional but recommended dependencies
        "patch",  # patch may be used by some rulesets and package managers during dependency fetching
        # Additional deps on top of minimal
        "clang",
        "cmake",
        "docker",
        "gcc-c++",
        "gcc",
        "jq",
        "libzstd",
        "make",
    ]

    # We'll need to tell systemctl to enable these when the image boots next.
    enable_services = [
        "amazon-cloudwatch-agent",
        "docker.service",
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
          # Install dependencies
          format("sudo yum --setopt=skip_missing_names_on_install=False --assumeyes install %s", join(" ", local.install_packages)),

          # Enable required services
          format("sudo systemctl enable %s", join(" ", local.enable_services)),
      ]
  }
}
