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
  default = "aspect-workflows-ubuntu-20-kitchen-sink"
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
  description = "Architecture to use for the ami"

  validation {
    condition     = var.arch == "amd64" || var.arch == "arm64"
    error_message = "Only amd64 and arm64 architectures are available for ubuntu 20.04 AMI's."
  }
}

variable "instance_types" {
  type = object({
    amd64 = string
    arm64 = string
  })
  default = {
    amd64 = "t3a.small"
    arm64 = "c7g.medium"
  }
}

variable "awscli_url" {
  type = object({
    amd64 = string
    arm64 = string
  })
  default = {
    amd64 = "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    arm64 = "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
  }
}

# Lookup the base AMI we want
data "amazon-ami" "ubuntu" {
    filters = {
        virtualization-type = "hvm"
        name = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-${var.arch}-server-20231127"
        root-device-type = "ebs"
    }
    owners = ["099720109477"] # Ubuntu
    region = "${var.region}"
    most_recent = true
}

locals {
    install_debs = [
        # Install cloudwatch-agent so that bootstrap logs are easier to locale
        "https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/${var.arch}/latest/amazon-cloudwatch-agent.deb",
    ]

    # System dependencies required for Aspect Workflows or for build & test
    install_packages = [
        # Dependencies of Aspect Workflows
        "rsync",
        "rsyslog",
        "mdadm",
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
        "docker.service",
    ]
}

source "amazon-ebs" "runner" {
  ami_name                                  = "${var.family}-${var.version}-${var.arch}"
  instance_type                             = "${var.instance_types[var.arch]}"
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
    # Install dependencies
    inline = concat([
        for url in local.install_debs : format("sudo curl %s -O", url)
    ], [
    ],
    [
        format("sudo dpkg --install --skip-same-version %s", join(" ", [
          for url in local.install_debs : basename(url)
        ]))
    ], [
        "sudo apt update",
        format("sudo apt-get install --assume-yes %s", join(" ", local.install_packages)),

        # Enable required services
        format("sudo systemctl enable %s", join(" ", local.enable_services)),
    ], [
      "curl \"${var.awscli_url[var.arch]}\" -o \"awscliv2.zip\"",
      "unzip awscliv2.zip",
      "sudo ./aws/install"
    ])
  }
}
