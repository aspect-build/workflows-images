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
# Quickstart AMI: Amazon Linux 2 AMI (HVM) - Kernel 5.10, SSD Volume Type (x86)
# Definition of this AMI: https://github.com/aws/amazon-ecs-ami/blob/main/al2.pkr.hcl
data "amazon-ami" "al2" {
    filters = {
        virtualization-type = "hvm"
        name = "amzn2-ami-kernel-5.10-hvm-2.0.20230612.0-x86_64-gp2",
        root-device-type = "ebs"
    }
    owners = ["137112412989"] # Amazon
    region = "${var.region}"
    most_recent = true
}

locals {
    source_ami = data.amazon-ami.al2.id

    # System dependencies required for Aspect Workflows or for build & test
    install_packages = [
        # Install cloudwatch-agent so that bootstrap logs are easier to locale
        "amazon-cloudwatch-agent",
        # Install fuse so that launch_bb_clientd_linux.sh can run.
        "fuse",
        # Install git so we can fetch the source code to be tested, obviously!
        "git",
        # Additional deps on top of minimal
        "gcc-c++",
        "gcc",
    ]

    # We'll need to tell systemctl to enable these when the image boots next.
    enable_services = [
        "amazon-cloudwatch-agent",
    ]
}

source "amazon-ebs" "runner" {
  ami_name                                  = "aspect-workflows-al2-minimal-${var.version}"
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

          # Enable required services
          format("sudo systemctl enable %s", join(" ", local.enable_services)),
      ]
  }
}
