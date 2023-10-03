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
  default = "aspect-workflows-debian-11-kitchen-sink"
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

# Lookup the base AMI we want
data "amazon-ami" "debian" {
    filters = {
        virtualization-type = "hvm"
        name = "debian-11-amd64-20230515-1381"
        root-device-type = "ebs"
    }
    owners = ["136693071363"] # Amazon
    region = "${var.region}"
    most_recent = true
}

locals {
    install_debs = [
        # Install cloudwatch-agent so that bootstrap logs are easier to locale
        "https://s3.amazonaws.com/amazoncloudwatch-agent/debian/amd64/latest/amazon-cloudwatch-agent.deb",
        # Install system manager so it's easy to login to a machine
        "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb",
    ]

    # System dependencies required for Aspect Workflows or for build & test
    install_packages = [
        # A dependency of Aspect Workflows
        "rsync",
        # Needed for bb-clientd
        "fuse",
        # (Optional) Patch is required by some rulesets and package managers during dependency fetching.
        "patch",
        # (Optional) zip is required if any tests create zips of undeclared test outputs
        # For more information about undecalred test outputs, see https://bazel.build/reference/test-encyclopedia
        "zip",
        # Additional deps on top of minimal
        "docker.io",
        "g++",
        "make",
    ]

    # We'll need to tell systemctl to enable these when the image boots next.
    enable_services = [
        "amazon-cloudwatch-agent",
        "amazon-ssm-agent",
        "docker.service",
    ]
}

source "amazon-ebs" "runner" {
  ami_name                                  = "${var.family}-${var.version}"
  instance_type                             = "t3a.small"
  region                                    = "${var.region}"
  vpc_id                                    = "${var.vpc_id}"
  subnet_id                                 = "${var.subnet_id}"
  ssh_username                              = "admin"
  source_ami                                = data.amazon-ami.debian.id
  temporary_security_group_source_public_ip = true
  encrypt_boot                              = var.encrypt_boot
}

build {
  sources = ["source.amazon-ebs.runner"]

  provisioner "shell" {
    # Install dependencies
    inline = concat([
        for url in local.install_debs : format("sudo curl %s -O", url)
    ], [
        format("sudo dpkg --install --skip-same-version %s", join(" ", [
          for url in local.install_debs : basename(url)
        ]))
    ], [
        "sudo apt update",
        format("sudo apt-get install --assume-yes %s", join(" ", local.install_packages)),

        # Enable required services
        format("sudo systemctl enable %s", join(" ", local.enable_services)),
    ])
  }
}
