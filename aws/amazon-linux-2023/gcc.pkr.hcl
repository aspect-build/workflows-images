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
# Quickstart AMI: Amazon Linux 2023 AMI 2023.1.20230725.0 x86_64 HVM kernel-6.1
# Definition of this AMI: https://github.com/aws/amazon-ecs-ami/blob/main/al2023.pkr.hcl
data "amazon-ami" "al2023" {
    filters = {
        virtualization-type = "hvm"
        name = "al2023-ami-2023.1.20230725.0-kernel-6.1-x86_64",
        root-device-type = "ebs"
    }
    owners = ["137112412989"] # Amazon
    region = "${var.region}"
    most_recent = true
}

locals {
    source_ami = data.amazon-ami.al2023.id

    # System dependencies required for Aspect Workflows or for build & test
    install_packages = [
        # Dependencies of Aspect Workflows
        "rsyslog",
        "mdadm",
        # Install libicu which is needed by GitHub Actions agent (https://github.com/actions/runner/issues/2511)
        "libicu",
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
  ami_name                                  = "aspect-workflows-al2023-gcc-${var.version}"
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
