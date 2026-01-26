#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

aws_region=us-west-1

# AWS AMIs to search for by name
aws_images=(
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
  # Debian 13
  debian-13-amd64-*
  debian-13-arm64-*
  # Ubuntu 22.04
  ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*
  ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*
  # Ubuntu 24.04
  ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-*
  ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-*
)

# GCP machine images to search for by name & project
gcp_images=(
  # Debian 11
  debian-11-bullseye- debian-cloud
  # Debian 12
  debian-12-bookworm- debian-cloud
  debian-12-bookworm-arm64- debian-cloud
  # Ubuntu 24.04
  ubuntu-2404-noble-amd64- ubuntu-os-cloud
  ubuntu-2404-noble-arm64- ubuntu-os-cloud
)

# Lookup for latest AWS AMIs
for name in "${aws_images[@]}"; do
  echo -e "\n\n================ AWS ================"
  echo "name: $name"
  aws ec2 describe-images \
    --profile awd-silo-prod_AspectEngineering \
    --region us-east-1 \
    --owners amazon \
    --filters "Name=name,Values=$name" \
              "Name=state,Values=available" \
              "Name=is-public,Values=true" \
              "Name=virtualization-type,Values=hvm" \
    --query "Images[*].{Name:Name, OwnerId:OwnerId, CreationDate:CreationDate, ImageOwnerAlias:ImageOwnerAlias, Description:Description, CreationDate:CreationDate, Architecture:Architecture} | sort_by(@, &CreationDate) | [-1]"
done

# Lookup for latest GCP machine images
for ((i = 0; i < ${#gcp_images[@]}; i+=2)); do
  name="${gcp_images[$i]}"
  project="${gcp_images[$i+1]}"
  echo -e "\n\n================ GCP ================"
  echo "name: $name"
  gcloud compute images list \
    --project="$project" \
    --filter="name~'$name' AND status=READY" \
    --sort-by="~creationTimestamp" \
    --limit=1
done
