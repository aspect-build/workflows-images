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
    ]
}

source "amazon-ebs" "runner" {
  ami_name                                  = "aspect-workflows-buildkite-al2-minimal-${var.version}"
  instance_type                             = "t3a.small"
  region                                    = "${var.region}"
  ssh_username                              = "ec2-user"
  source_ami                                = local.source_ami
  temporary_security_group_source_public_ip = true
}

build {
  sources = ["source.amazon-ebs.runner"]

  provisioner "shell" {
      inline = [
          format("sudo yum --setopt=skip_missing_names_on_install=False --assumeyes install %s", join(" ", local.install_packages)),
      ]
  }
}
