packer {
  required_plugins {
    amazon = {
      version = ">= 1.1.5"
      source  = "github.com/hashicorp/amazon"
    }
    docker = {
      version = ">= 1.0.8"
      source = "github.com/hashicorp/docker"
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
  default = "aspect-workflows-ubuntu-2004-minimal"
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

locals {
    install_debs = [
        # Install cloudwatch-agent so that bootstrap logs are easier to locale
        "https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/${var.arch}/latest/amazon-cloudwatch-agent.deb",
    ]

    # System dependencies required for Aspect Workflows or for build & test
    install_packages = [
        # (optional) fuse is optional but highly recommended for better Bazel performance
        "fuse",
        # (optional) patch may be used by some rulesets and package managers during dependency fetching
        "patch",
        # (optional) zip may be used by bazel if there are tests that produce undeclared test outputs which bazel zips;
        # for more information about undeclared test outputs, see https://bazel.build/reference/test-encyclopedia
        "zip",
    ]

    # We'll need to tell systemctl to enable these when the image boots next.
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
  source_ami_filter {
    filters = {
        virtualization-type = "hvm"
        name = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-${var.arch}-server-20231127"
        root-device-type = "ebs"
    }
    owners = ["099720109477"] # Ubuntu
    most_recent = true
  }
}

source "docker" "ubuntu" {
  image  = "ubuntu:focal-20240216"
  commit = true
  // TODO: Look into using export_path here. Tried once and got an error from bazel about a missing manifest.
  // So I just had docker export as a tar and that works for some reason. 
}

build {
  sources = [
    "source.amazon-ebs.runner",
    "source.docker.ubuntu"
  ]

  post-processor "docker-tag" {
    only = ["docker.ubuntu"]
    repository =  "workflows-images"
    tags = ["ubuntu-2004-minimal"]
  }

  provisioner "shell" {
    only = ["docker.ubuntu"]
    inline = [
      "apt-get update",
      "apt-get install sudo curl systemd -y"
    ]
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
  }

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
    ], [
      "curl \"${local.awscli_url[var.arch]}\" -o \"awscliv2.zip\"",
      "unzip awscliv2.zip",
      "sudo ./aws/install"
    ])
  }
}
