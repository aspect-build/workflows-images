#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

current_date=$(date +"%Y%m%d")
build_number=0 # increment if building multiple times on the same day, otherwise leave at 0

# version is the date built in yyyymmdd format, followed by a dash and the zero build number on that date
version="${current_date}-${build_number}"

architectures=(
  amd64
  arm64
)

aws_profile=workflows-images_AspectAdministration

aws_regions=(
  us-west-2
  us-east-1
  us-east-2
)

gcp_project=aspect-workflows-images

gcp_zone="us-central1-a"

all_images=(
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
    # AWS debian 13
    aws/debian-13/docker.pkr.hcl
    aws/debian-13/gcc.pkr.hcl
    aws/debian-13/kitchen-sink.pkr.hcl
    aws/debian-13/minimal.pkr.hcl
    # AWS ubuntu 2204
    aws/ubuntu-2204/docker.pkr.hcl
    aws/ubuntu-2204/gcc.pkr.hcl
    aws/ubuntu-2204/kitchen-sink.pkr.hcl
    aws/ubuntu-2204/minimal.pkr.hcl
    # AWS ubuntu 2404
    aws/ubuntu-2404/custom-0.pkr.hcl
    aws/ubuntu-2404/docker.pkr.hcl
    aws/ubuntu-2404/gcc.pkr.hcl
    aws/ubuntu-2404/kitchen-sink.pkr.hcl
    aws/ubuntu-2404/minimal.pkr.hcl
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
    # GCP ubuntu 2404
    gcp/ubuntu-2404/custom-0.pkr.hcl
    gcp/ubuntu-2404/docker.pkr.hcl
    gcp/ubuntu-2404/gcc.pkr.hcl
    gcp/ubuntu-2404/kitchen-sink.pkr.hcl
    gcp/ubuntu-2404/minimal.pkr.hcl
)

continue_or_exit() {
  read -p "$1 (y/N): " -n 1 choice
  echo
  case "$choice" in
    [Yy]*) return 0 ;;
    *) exit 0 ;;
  esac
}

function main() {
  dry_run=false
  new_args=()
  for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
      dry_run=true
    else
      new_args+=("$arg")
    fi
  done
  if [[ ${new_args[@]+"!"} == "!" ]]; then
    set -- "${new_args[@]}"
  else
    set --
  fi

  images=()
  if [[ -z "${1:-}" ]]; then
    images=("${all_images[@]}")
  else
    for i in "${all_images[@]}"; do
      for m in "$@"; do
        if [[ "$i" =~ "${m}" ]]; then
          images+=("${i}")
        fi
      done
    done
  fi

  if [[ ${images[@]+"!"} != "!" ]]; then
    echo "No matching images!"
    exit 1
  fi

  if [[ "$dry_run" == "true" ]]; then
    echo -e "\nThe following images will be built at version ${version} (DRY RUN):"
  else
    echo -e "\nThe following images will be built at version ${version}:"
  fi
  for i in "${images[@]}"; do
    echo -e "  - ${i}"
  done

  echo ""
  continue_or_exit "❓ Are you sure you want to proceed?"

  for image in "${images[@]}"; do
    IFS='/' read -a elems <<< "${image}"
    cloud="${elems[0]}"
    distro="${elems[1]}"
    file="${elems[2]}"
    variant="${file%.pkr.hcl}"
    if [ "${cloud}" == "aws" ]; then
      for arch in "${architectures[@]}"; do
        build_aws "${distro}" "${variant}" "${arch}" "${dry_run}"
      done
    elif [ "${cloud}" == "gcp" ]; then
      for arch in ${architectures[@]}; do
        build_gcp "${distro}" "${variant}" "${arch}" "${dry_run}"
      done
    else
      echo "ERROR: unrecognized cloud '${cloud}'"
      exit 1
    fi
  done
}

function build_aws() {
  local distro="$1"
  local variant="$2"
  local arch="$3"
  local dry_run="$4"

  local packer_file="aws/${distro}/${variant}.pkr.hcl"
  local family="aspect-workflows-${distro}-${variant}"
  local name="${family}-${arch}-${version}"

  local build_region="${aws_regions[0]}"
  local copy_regions=("${aws_regions[@]:1}")

  if [[ "$dry_run" == "true" ]]; then
    echo -e "\n\n\n\n======== ${name} (DRY RUN) ========"
  else
    echo -e "\n\n\n\n======== ${name} ========"
  fi

  if [ "${distro}" == "debian-11" ] && [ "${arch}" == "arm64" ]; then
    # No arm64 arch available for debian-11 yet.
    # See https://github.com/aspect-build/silo/issues/4001 for more context.
    echo "Skipping ${name} (currently no arm64 support for ${distro})"
    return
  fi

  # init packer
  echo "Packer init for ${name}"
  set -x
  packer init "${packer_file}"
  set +x

  # build the AMI
  echo "Building ${name}"
  set -x
  AWS_PROFILE="${aws_profile}" packer build -var "version=${version}" -var "region=${build_region}" -var "family=${family}" -var "arch=${arch}" -var "dry_run=${dry_run}" "$packer_file"
  set +x
  date

  # if this was a dry run then we're done here
  if [[ "$dry_run" == "true" ]]; then
    return
  fi

  # determine the ID of the new AMI
  describe_images=$(aws ec2 describe-images --profile "${aws_profile}" --region "${build_region}" --filters "Name=name,Values=${name}")
  amis=($(echo "${describe_images}" | jq  .Images[0].ImageId | jq . -r))
  if [ -z "${amis:-}" ]; then
    echo "ERROR: image $name not found in ${build_region}"
    exit 1
  fi
  if [ "${#amis[@]}" -ne 1 ]; then
    echo "ERROR: expected 1 ${name} image in ${build_region}"
    exit 1
  fi
  ami="${amis[0]}"
  # set newly built image to public
  aws ec2 modify-image-attribute --profile "${aws_profile}" --region "${build_region}" --image-id "${ami}" --launch-permission "Add=[{Group=all}]"

  # copy the new AMI to all copy regions
  for copy_region in ${copy_regions[@]}; do
    echo "Copying ${name} ("${ami}") to ${copy_region}"
    aws ec2 copy-image --profile "${aws_profile}" --region "${copy_region}" --name "${name}" --source-region "${build_region}" --source-image-id "${ami}"
  done
  date

  # wait until all image copies are available
  echo "Waiting until all image copies are available..."
  available=0
  num_copy_regions="${#copy_regions[@]}"
  until [ "${available}" -eq "${num_copy_regions}" ]
  do
    sleep 10
    available=0
    for copy_region in "${copy_regions[@]}"; do
      describe_images=$(aws ec2 describe-images --profile "${aws_profile}" --region "${copy_region}" --filters "Name=name,Values=${name}")
      states=($(echo "${describe_images}" | jq  .Images[0].State | jq . -r))
      amis=($(echo "${describe_images}" | jq  .Images[0].ImageId | jq . -r))
      if [ -z "${states:-}" ]; then
        echo "ERROR: image ${name} not found in ${copy_region}"
        exit 1
      fi
      if [ -z "${amis:-}" ]; then
        echo "ERROR: image ${name} not found in ${copy_region}"
        exit 1
      fi
      if [ "${#states[@]}" -ne 1 ]; then
        echo "ERROR: expected 1 ${name} image in ${copy_region}"
        exit 1
      fi
      if [ "${#amis[@]}" -ne 1 ]; then
        echo "ERROR: expected 1 ${name} image in ${copy_region}"
        exit 1
      fi
      state="${states[0]}"
      ami="${amis[0]}"
      echo "${name} in ${copy_region} is ${state}"
      if [ "${state}" == "available" ]; then
        # set image to public once it is available; this can be safely called multiple times
        aws ec2 modify-image-attribute --profile "${aws_profile}" --region "${copy_region}" --image-id "${ami}" --launch-permission "Add=[{Group=all}]"
        ((++available))
      fi
    done
    date
  done
}

function build_gcp() {
  local distro="$1"
  local variant="$2"
  local arch="$3"
  local dry_run="$4"

  local packer_file="gcp/${distro}/${variant}.pkr.hcl"
  local family="aspect-workflows-${distro}-${variant}"
  local name="${family}-${arch}-${version}"

  if [[ "$dry_run" == "true" ]]; then
    echo -e "\n\n\n\n======== ${name} (DRY RUN)"
  else
    echo -e "\n\n\n\n======== ${name}"
  fi

  if [ "${distro}" == "debian-11" ] && [ "${arch}" == "arm64" ]; then
    # No arm64 arch base image available for debian-11 on GCP.
    echo "Skipping ${name} (currently no arm64 support for ${distro})"
    return
  fi

  # init packer
  echo "Packer init for ${name}"
  set -x
  packer init "${packer_file}"
  set +x

  # build the AMI
  echo "Building ${name}"
  date
  set -x
  packer build -var "version=${version}" -var "project=${gcp_project}" -var "zone=${gcp_zone}" -var "family=${family}" -var "arch=${arch}" -var "dry_run=${dry_run}" "$packer_file"
  set +x
  date

  # if this was a dry run then we're done here
  if [[ "$dry_run" == "true" ]]; then
    return
  fi

  # set newly built image to public
  gcloud config set project "${gcp_project}"
  gcloud compute images add-iam-policy-binding "${name}" --member='allAuthenticatedUsers' --role='roles/compute.imageUser'
}

main "$@"
