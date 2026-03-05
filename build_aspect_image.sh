#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

aws_profile=workflows-images_AspectAdministration

aws_regions=(
  us-east-1
  us-east-2
  us-west-1
  us-west-2
  eu-central-1
  eu-west-1
)

gcp_project=aspect-workflows-images

gcp_zone="us-central1-a"

function build_aws() {
  local distro="$1"
  local variant="$2"
  local arch="$3"
  local dry_run="$4"
  local version="$5"

  local packer_file="aws/${distro}/${variant}.pkr.hcl"
  local family="aspect-workflows-${distro}-${variant}"
  local name="${family}-${arch}-${version}"

  local build_region="${aws_regions[0]}"
  local copy_regions=("${aws_regions[@]:1}")

  if [[ "$dry_run" == "true" ]]; then
    echo -e "\n======== ${name} (DRY RUN) ========"
  else
    echo -e "\n======== ${name} ========"
  fi

  # Check if image already exists in build region
  existing_ami=$(aws ec2 describe-images --profile "${aws_profile}" --region "${build_region}" --filters "Name=name,Values=${name}" --query 'Images[0].ImageId' --output text 2>/dev/null || true)
  if [ -n "${existing_ami}" ] && [ "${existing_ami}" != "None" ]; then
    echo "${name} already exists in ${build_region}"
  else
    # build the AMI (packer init already run by orchestrator)
    echo "Building ${name}"
    set -x
    AWS_PROFILE="${aws_profile}" packer build -var "version=${version}" -var "region=${build_region}" -var "family=${family}" -var "arch=${arch}" -var "dry_run=${dry_run}" "$packer_file"
    set +x
    date

    # if this was a dry run then we're done here
    if [[ "$dry_run" == "true" ]]; then
      return
    fi
  fi

  # determine the ID of the AMI in the build region
  describe_images=$(aws ec2 describe-images --profile "${aws_profile}" --region "${build_region}" --filters "Name=name,Values=${name}")
  mapfile -t amis < <(echo "${describe_images}" | jq -r '.Images[0].ImageId')
  if [ -z "${amis:-}" ]; then
    echo "ERROR: image $name not found in ${build_region}"
    exit 1
  fi
  if [ "${#amis[@]}" -ne 1 ]; then
    echo "ERROR: expected 1 ${name} image in ${build_region}"
    exit 1
  fi
  ami="${amis[0]}"

  # copy the AMI to copy regions that don't already have it
  for copy_region in "${copy_regions[@]}"; do
    existing_copy=$(aws ec2 describe-images --profile "${aws_profile}" --region "${copy_region}" --filters "Name=name,Values=${name}" --query 'Images[0].ImageId' --output text 2>/dev/null || true)
    if [ -n "${existing_copy}" ] && [ "${existing_copy}" != "None" ]; then
      echo "${name} already exists in ${copy_region}"
    else
      echo "Copying ${name} (${ami}) to ${copy_region}"
      aws ec2 copy-image --profile "${aws_profile}" --region "${copy_region}" --name "${name}" --source-region "${build_region}" --source-image-id "${ami}"
    fi
  done
  date

  # wait until all images are available across all regions and ensure they are public
  echo "Ensuring all images are available and public..."
  available=0
  num_regions="${#aws_regions[@]}"
  until [ "${available}" -eq "${num_regions}" ]
  do
    available=0
    for region in "${aws_regions[@]}"; do
      describe_images=$(aws ec2 describe-images --profile "${aws_profile}" --region "${region}" --filters "Name=name,Values=${name}")
      mapfile -t states < <(echo "${describe_images}" | jq -r '.Images[0].State')
      mapfile -t amis < <(echo "${describe_images}" | jq -r '.Images[0].ImageId')
      if [ -z "${states:-}" ]; then
        echo "ERROR: image ${name} not found in ${region}"
        exit 1
      fi
      if [ -z "${amis:-}" ]; then
        echo "ERROR: image ${name} not found in ${region}"
        exit 1
      fi
      if [ "${#states[@]}" -ne 1 ]; then
        echo "ERROR: expected 1 ${name} image in ${region}"
        exit 1
      fi
      if [ "${#amis[@]}" -ne 1 ]; then
        echo "ERROR: expected 1 ${name} image in ${region}"
        exit 1
      fi
      state="${states[0]}"
      ami="${amis[0]}"
      if [ "${state}" == "available" ]; then
        # set image to public once it is available; this can be safely called multiple times
        aws ec2 modify-image-attribute --profile "${aws_profile}" --region "${region}" --image-id "${ami}" --launch-permission "Add=[{Group=all}]"
        echo "${name} in ${region} is available and public"
        ((++available))
      else
        echo "${name} in ${region} is ${state}"
      fi
    done
    date
    if [ "${available}" -ne "${num_regions}" ]; then
      sleep 10
    fi
  done
}

function build_gcp() {
  local distro="$1"
  local variant="$2"
  local arch="$3"
  local dry_run="$4"
  local version="$5"

  local packer_file="gcp/${distro}/${variant}.pkr.hcl"
  local family="aspect-workflows-${distro}-${variant}"
  local name="${family}-${arch}-${version}"

  if [[ "$dry_run" == "true" ]]; then
    echo -e "\n======== ${name} (DRY RUN)"
  else
    echo -e "\n======== ${name}"
  fi

  # Check if image already exists
  if gcloud compute images describe "${name}" --project="${gcp_project}" &>/dev/null; then
    echo "${name} already exists in ${gcp_project}"
  else
    # build the image (packer init already run by orchestrator)
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
  fi

  # ensure image is public
  gcloud config set project "${gcp_project}" 2>/dev/null
  existing_policy=$(gcloud compute images get-iam-policy "${name}" --format=json 2>/dev/null || echo '{}')
  if echo "${existing_policy}" | jq -e '.bindings[]? | select(.role == "roles/compute.imageUser") | .members[]? | select(. == "allAuthenticatedUsers")' &>/dev/null; then
    echo "${name} in ${gcp_project} is public"
  else
    gcloud compute images add-iam-policy-binding "${name}" --member='allAuthenticatedUsers' --role='roles/compute.imageUser'
    echo "${name} in ${gcp_project} is now public"
  fi
}

function main() {
  local image=""
  local arch=""
  local version=""
  local dry_run=false

  for arg in "$@"; do
    case "$arg" in
      --image=*) image="${arg#--image=}" ;;
      --arch=*) arch="${arg#--arch=}" ;;
      --version=*) version="${arg#--version=}" ;;
      --dry-run) dry_run=true ;;
      *) echo "ERROR: unknown argument '${arg}'"; exit 1 ;;
    esac
  done

  if [[ -z "$image" || -z "$arch" || -z "$version" ]]; then
    echo "Usage: $0 --image=<path> --arch=<amd64|arm64> --version=<version> [--dry-run]"
    exit 1
  fi

  IFS='/' read -ra elems <<< "${image}"
  local cloud="${elems[0]}"
  local distro="${elems[1]}"
  local file="${elems[2]}"
  local variant="${file%.pkr.hcl}"

  if [ "${cloud}" == "aws" ]; then
    build_aws "${distro}" "${variant}" "${arch}" "${dry_run}" "${version}"
  elif [ "${cloud}" == "gcp" ]; then
    build_gcp "${distro}" "${variant}" "${arch}" "${dry_run}" "${version}"
  else
    echo "ERROR: unrecognized cloud '${cloud}'"
    exit 1
  fi
}

main "$@"
