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
      # A dependency of aspect workflows
      "rsync",
      # Needed for bb-clientd
      "fuse",
    ]

    # We'll need to tell systemctl to enable these when the image boots next.
    enable_services = [
        "amazon-cloudwatch-agent",
        "amazon-ssm-agent",
    ]
}

source "amazon-ebs" "runner" {
  ami_name                                  = "aspect-workflows-debian-minimal-${var.version}"
  instance_type                             = "t3a.small"
  region                                    = "${var.region}"
  ssh_username                              = "admin"
  source_ami                                = data.amazon-ami.debian.id
  temporary_security_group_source_public_ip = true
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