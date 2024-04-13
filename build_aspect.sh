#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

version="1.6.0"
dash_version=${version//\./-}

architectures=(
  amd64
  arm64
)

aws_regions=(
  us-west-1
  us-west-2
  us-east-1
  us-east-2
)

gcp_zone="us-central1-a"

images=(
    # AWS amazon linux 2
    aws/al2/docker.pkr.hcl
    aws/al2/gcc.pkr.hcl
    aws/al2/kitchen-sink.pkr.hcl
    aws/al2/minimal.pkr.hcl
    # AWS amazon linux 2023
    aws/al2023/docker.pkr.hcl
    aws/al2023/gcc.pkr.hcl
    aws/al2023/kitchen-sink.pkr.hcl
    aws/al2023/minimal.pkr.hcl
    # AWS debian 11
    aws/debian-11/docker.pkr.hcl
    aws/debian-11/gcc.pkr.hcl
    aws/debian-11/kitchen-sink.pkr.hcl
    aws/debian-11/minimal.pkr.hcl
    # AWS debian 12
    aws/debian-12/docker.pkr.hcl
    aws/debian-12/gcc.pkr.hcl
    aws/debian-12/kitchen-sink.pkr.hcl
    aws/debian-12/minimal.pkr.hcl
    # AWS ubuntu 2004
    aws/ubuntu-2004/docker.pkr.hcl
    aws/ubuntu-2004/gcc.pkr.hcl
    aws/ubuntu-2004/kitchen-sink.pkr.hcl
    aws/ubuntu-2004/minimal.pkr.hcl
    # GCP debian 11
    gcp/debian-11/docker.pkr.hcl
    gcp/debian-11/gcc.pkr.hcl
    gcp/debian-11/kitchen-sink.pkr.hcl
    gcp/debian-11/minimal.pkr.hcl
    # GCP debian 12
    gcp/debian-12/docker.pkr.hcl
    gcp/debian-12/gcc.pkr.hcl
    gcp/debian-12/kitchen-sink.pkr.hcl
    gcp/debian-12/minimal.pkr.hcl
    # GCP ubuntu 2304
    gcp/ubuntu-2304/docker.pkr.hcl
    gcp/ubuntu-2304/gcc.pkr.hcl
    gcp/ubuntu-2304/kitchen-sink.pkr.hcl
    gcp/ubuntu-2304/minimal.pkr.hcl
)

function main() {
  for image in ${images[@]}; do
    IFS='/' read -a elems <<< "${image}"
    cloud=${elems[0]}
    distro=${elems[1]}
    file=${elems[2]}
    variant=${file%.pkr.hcl}
    if [ "$cloud" == "aws" ]; then
      for arch in ${architectures[@]}; do
        build_aws $distro $variant $arch
      done
    elif [ "$cloud" == "gcp" ]; then
      for arch in ${architectures[@]}; do
        build_gcp $distro $variant $arch
      done
    else
      echo "ERROR: unrecognized cloud '$cloud'"
      exit 1
    fi
  done
}

function build_aws() {
  local distro=$1
  local variant=$2
  local arch=$3

  local packer_file="aws/${distro}/${variant}.pkr.hcl"
  local family="aspect-workflows-${distro}-${variant}"
  local name="${family}-${arch}-${dash_version}"

  local build_region=${aws_regions[0]}
  local copy_regions=("${aws_regions[@]:1}")

  echo -e "\n\n\n\n=================================================="

  if [ "$distro" == "debian-11" ] && [ "$arch" == "arm64" ]; then
    # No arm64 arch available for debian-11 yet.
    # See https://github.com/aspect-build/silo/issues/4001 for more context.
    echo "Skipping $name (no arm64 support for $distro yet)"
    return
  elif [ "$distro" == "debian-12" ] && [ "$arch" == "arm64" ]; then
    # No arm64 arch available for debian-12 yet.
    # See https://github.com/aspect-build/silo/issues/4001 for more context.
    echo "Skipping $name (no arm64 support for $distro yet)"
    return
  fi

  # build the AMI
  echo "Building $name"
  date
  ./tools/packer build -var "version=${dash_version}" -var "region=${build_region}" -var "family=${family}" -var "arch=${arch}" "$packer_file"
  date

  # determine the ID of the new AMI
  describe_images=$(aws ec2 describe-images --region ${build_region} --filters aws ec2 describe-images --filters Name=name,Values=${name})
  amis=($(echo "$describe_images" | jq  .Images[0].ImageId | jq . -r))
  if [ -z "${amis:-}" ]; then
    echo "ERROR: image $name not found in $build_region"
    exit 1
  fi
  if [ "${#amis[@]}" -ne 1 ]; then
    echo "ERROR: expected 1 $name image in $build_region"
    exit 1
  fi
  ami="${amis[0]}"
  # set newly built image to public
  aws ec2 modify-image-attribute --region ${build_region} --image-id "$ami" --launch-permission "Add=[{Group=all}]"

  # copy the new AMI to all copy regions
  for copy_region in ${copy_regions[@]}; do
    echo "Copying $name ("$ami") to ${copy_region}"
    aws ec2 copy-image --region "$copy_region" --name "$name" --source-region "$build_region" --source-image-id "$ami"
  done
  date

  # wait until all image copies are available
  echo "Waiting until all image copies are available..."
  available=0
  num_copy_regions="${#copy_regions[@]}"
  until [ $available -eq $num_copy_regions ]
  do
    sleep 10
    available=0
    for copy_region in ${copy_regions[@]}; do
      describe_images=$(aws ec2 describe-images --region ${copy_region} --filters aws ec2 describe-images --filters Name=name,Values=${name})
      states=($(echo "$describe_images" | jq  .Images[0].State | jq . -r))
      amis=($(echo "$describe_images" | jq  .Images[0].ImageId | jq . -r))
      if [ -z "${states:-}" ]; then
        echo "ERROR: image $name not found in $copy_region"
        exit 1
      fi
      if [ -z "${amis:-}" ]; then
        echo "ERROR: image $name not found in $copy_region"
        exit 1
      fi
      if [ "${#states[@]}" -ne 1 ]; then
        echo "ERROR: expected 1 $name image in $copy_region"
        exit 1
      fi
      if [ "${#amis[@]}" -ne 1 ]; then
        echo "ERROR: expected 1 $name image in $copy_region"
        exit 1
      fi
      state="${states[0]}"
      ami="${amis[0]}"
      echo "$name in $copy_region is $state"
      if [ "$state" == "available" ]; then
        # set image to public once it is available; this can be safely called multiple times
        aws ec2 modify-image-attribute --region ${copy_region} --image-id "$ami" --launch-permission "Add=[{Group=all}]"
         ((available++))
      fi
    done
    date
  done
}

function build_gcp() {
  local distro=$1
  local variant=$2
  local arch=$3

  local packer_file="gcp/${distro}/${variant}.pkr.hcl"
  local family="aspect-workflows-${distro}-${variant}"
  local name="${family}-${arch}-${dash_version}"

  echo -e "\n\n\n\n=================================================="

  if [ "$distro" == "ubuntu-2304" ] && [ "$arch" == "arm64" ]; then
    # No arm64 arch available for ubuntu-2304 yet.
    # Iamge build fails with "Unable to locate package google-cloud-ops-agent".
    echo "Skipping $name (no arm64 support for $distro yet)"
    return
  fi

  # build the AMI
  echo "Building $name"
  date
  ./tools/packer build -var "version=${dash_version}" -var "project=aspect-workflows-images" -var "zone=${gcp_zone}" -var "family=${family}" -var "arch=${arch}" "$packer_file"
  date

  # set newly built image to public
  gcloud config set project aspect-workflows-images
  gcloud compute images add-iam-policy-binding "$name" --member='allAuthenticatedUsers' --role='roles/compute.imageUser'
}

main
