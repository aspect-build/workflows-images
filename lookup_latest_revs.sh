#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

aws_region=us-west-1

# AMIs to search for by name and owner
aws_amazon_images=(
  # Amazon Linux 2
  amzn2-ami-kernel-5.10-hvm-*-x86_64-gp2
  amzn2-ami-kernel-5.10-hvm-*-arm64-gp2
  # Amazon Linux 2023
  al2023-ami-2023.*-kernel-6.1-x86_64
  al2023-ami-2023.*-kernel-6.1-arm64
  # Debian 11
  debian-11-amd64-*
  debian-11-arm64-*
  # Debian 12
  debian-12-amd64-*
  debian-12-arm64-*
  # Ubuntu 20.04
  ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*
  ubuntu/images/hvm-ssd/ubuntu-focal-20.04-arm64-server-*
)

# Lookup for latest AWS AMIs
for name in "${aws_amazon_images[@]}"; do
  echo -e "\n\n================"
  echo "name: $name"
  aws ec2 describe-images \
    --profile silo \
    --region us-east-1 \
    --owners amazon \
    --filters "Name=name,Values=$name" \
              "Name=state,Values=available" \
              "Name=is-public,Values=true" \
              "Name=virtualization-type,Values=hvm" \
    --query "Images[*].{Name:Name, OwnerId:OwnerId, CreationDate:CreationDate, ImageOwnerAlias:ImageOwnerAlias, Description:Description, CreationDate:CreationDate, Architecture:Architecture} | sort_by(@, &CreationDate) | [-1]"
done
