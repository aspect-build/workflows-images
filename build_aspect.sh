#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

current_date=$(date +"%Y%m%d")
build_number=0 # increment if building multiple times on the same day, otherwise leave at 0

architectures=(
  amd64
  arm64
)

# Distros that do not support arm64
no_arm64_distros=(
  debian-11
)

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
  read -rp "$1 (y/N): " -n 1 choice
  echo
  case "$choice" in
    [Yy]*) return 0 ;;
    *) exit 0 ;;
  esac
}

# Check if a distro supports arm64
supports_arch() {
  local distro="$1"
  local arch="$2"
  if [[ "$arch" == "arm64" ]]; then
    for d in "${no_arm64_distros[@]}"; do
      if [[ "$distro" == "$d" ]]; then
        return 1
      fi
    done
  fi
  return 0
}

# Print over the in-progress status line when stdout is a TTY.
status_println() {
  if [[ -t 1 ]]; then
    printf "\r\033[K%s\n" "$1"
  else
    echo "$1"
  fi
}

# Format an elapsed-seconds value as "Ns" or "MmNs".
fmt_elapsed() {
  local sec=$1
  if (( sec >= 60 )); then
    printf '%dm%02ds' $((sec / 60)) $((sec % 60))
  else
    printf '%ds' "$sec"
  fi
}

# Refresh the in-progress status line in place; only on a TTY.
# When few jobs remain (<= status_detail_threshold), inline their short
# names and elapsed time so the user can see exactly what is stuck.
status_detail_threshold=5
status_refresh() {
  [[ -t 1 ]] || return
  local remaining=${#pids[@]}
  if (( remaining > 0 && remaining <= status_detail_threshold )); then
    local details=""
    for pid in "${pids[@]}"; do
      local elapsed=$(( SECONDS - ${pid_start_times[$pid]:-$SECONDS} ))
      local short="${pid_labels[$pid]#aspect-workflows-}"
      short="${short%-${version}}"
      details+=" ${short}($(fmt_elapsed "$elapsed"))"
    done
    printf "\r\033[K  In progress: %d remaining (succeeded: %d, failed: %d):%s" \
      "$remaining" "${#succeeded[@]}" "${#failed[@]}" "$details"
  else
    printf "\r\033[K  In progress: %d remaining (succeeded: %d, failed: %d)" \
      "$remaining" "${#succeeded[@]}" "${#failed[@]}"
  fi
}

# Collect any finished jobs from the pids array
collect_finished() {
  local new_pids=()
  for pid in "${pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      new_pids+=("$pid")
    else
      wait "$pid" && true
      local exit_code=$?
      local label="${pid_labels[$pid]}"
      local logfile="${pid_logfiles[$pid]}"
      local elapsed
      elapsed=$(fmt_elapsed $(( SECONDS - ${pid_start_times[$pid]:-$SECONDS} )))
      if [[ $exit_code -eq 0 ]]; then
        status_println "  DONE: ${label} [${elapsed}]"
        succeeded+=("$label")
      elif [[ "$dry_run" == "true" ]] && grep -q "DRY RUN COMPLETE" "$logfile" 2>/dev/null; then
        status_println "  DONE: ${label} (dry run) [${elapsed}]"
        succeeded+=("$label")
      else
        status_println "  FAIL: ${label} (exit code ${exit_code}, log: ${logfile}) [${elapsed}]"
        failed+=("${label} (log: ${logfile})")
      fi
    fi
  done
  pids=()
  if [[ ${#new_pids[@]} -gt 0 ]]; then
    pids=("${new_pids[@]}")
  fi
}

# Wait for a job slot to open up when at max concurrency
wait_for_slot() {
  local max_jobs="$1"
  while [[ ${#pids[@]} -ge $max_jobs ]]; do
    collect_finished
    if [[ ${#pids[@]} -ge $max_jobs ]]; then
      sleep 1
    fi
  done
}

function main() {
  dry_run=false
  version=""
  max_jobs=100
  new_args=()
  for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
      dry_run=true
    elif [[ "$arg" == --version=* ]]; then
      version="${arg#--version=}"
    elif [[ "$arg" == --build-number=* ]]; then
      build_number="${arg#--build-number=}"
    elif [[ "$arg" == --jobs=* ]]; then
      max_jobs="${arg#--jobs=}"
    else
      new_args+=("$arg")
    fi
  done

  # version is the date built in yyyymmdd format, followed by a dash and the build number on that date
  if [[ -z "$version" ]]; then
    version="${current_date}-${build_number}"
  fi
  if [[ ${#new_args[@]} -gt 0 ]]; then
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
        if [[ "$i" =~ $m ]]; then
          images+=("${i}")
        fi
      done
    done
  fi

  if [[ ${#images[@]} -eq 0 ]]; then
    echo "No matching images!"
    exit 1
  fi

  # Build list of (image, arch) jobs to run, skipping unsupported combos
  declare -a job_images=()
  declare -a job_arches=()
  for image in "${images[@]}"; do
    IFS='/' read -ra elems <<< "${image}"
    local distro="${elems[1]}"
    for arch in "${architectures[@]}"; do
      if supports_arch "$distro" "$arch"; then
        job_images+=("$image")
        job_arches+=("$arch")
      fi
    done
  done

  local total_jobs=${#job_images[@]}

  if [[ "$dry_run" == "true" ]]; then
    echo -e "\nThe following ${total_jobs} image builds will run at version ${version} (DRY RUN), max ${max_jobs} parallel:"
  else
    echo -e "\nThe following ${total_jobs} image builds will run at version ${version}, max ${max_jobs} parallel:"
  fi
  for idx in "${!job_images[@]}"; do
    echo -e "  - ${job_images[$idx]} (${job_arches[$idx]})"
  done

  echo ""
  continue_or_exit "❓ Are you sure you want to proceed?"

  # Run packer init serially for all unique packer files to avoid race conditions
  declare -A inited_files=()
  echo -e "\nRunning packer init for all unique packer files..."
  for image in "${images[@]}"; do
    if [[ -z "${inited_files[$image]:-}" ]]; then
      echo "  packer init ${image}"
      packer init "${image}"
      inited_files[$image]=1
    fi
  done

  # Create log directory
  local log_dir="logs/${version}"
  mkdir -p "${log_dir}"
  echo -e "\nLogs will be written to ${log_dir}/"

  # Spawn parallel builds
  declare -a pids=()
  declare -A pid_labels=()
  declare -A pid_logfiles=()
  declare -A pid_start_times=()
  declare -a succeeded=()
  declare -a failed=()

  echo -e "\nStarting builds..."
  for idx in "${!job_images[@]}"; do
    local image="${job_images[$idx]}"
    local arch="${job_arches[$idx]}"

    IFS='/' read -ra elems <<< "${image}"
    local cloud="${elems[0]}"
    local distro="${elems[1]}"
    local file="${elems[2]}"
    local variant="${file%.pkr.hcl}"
    local name="aspect-workflows-${distro}-${variant}-${arch}-${version}"
    local logfile="${log_dir}/${cloud}-${distro}-${variant}-${arch}.log"

    # Wait for a slot if at max concurrency
    wait_for_slot "$max_jobs"

    echo "  START: ${name} -> ${logfile}"

    local worker_args=(
      --image="${image}"
      --arch="${arch}"
      --version="${version}"
    )
    if [[ "$dry_run" == "true" ]]; then
      worker_args+=(--dry-run)
    fi

    "${SCRIPT_DIR}/build_aspect_image.sh" "${worker_args[@]}" > "${logfile}" 2>&1 &
    local pid=$!
    pids+=("$pid")
    pid_labels[$pid]="$name"
    pid_logfiles[$pid]="$logfile"
    pid_start_times[$pid]=$SECONDS
  done

  # Wait for all remaining jobs to finish
  echo -e "\nWaiting for remaining builds to finish..."
  while [[ ${#pids[@]} -gt 0 ]]; do
    collect_finished
    if [[ ${#pids[@]} -gt 0 ]]; then
      status_refresh
      sleep 1
    fi
  done
  if [[ -t 1 ]]; then printf "\r\033[K"; fi

  # Summary
  echo -e "\n\n======== BUILD SUMMARY ========"
  echo "Total: ${total_jobs} | Succeeded: ${#succeeded[@]} | Failed: ${#failed[@]}"

  if [[ ${#succeeded[@]} -gt 0 ]]; then
    echo -e "\nSucceeded (${#succeeded[@]}):"
    while IFS= read -r s; do
      echo "  ✓ ${s}"
    done < <(printf '%s\n' "${succeeded[@]}" | sort)
  fi

  if [[ ${#failed[@]} -gt 0 ]]; then
    echo -e "\nFailed (${#failed[@]}):"
    while IFS= read -r f; do
      echo "  ✗ ${f}"
    done < <(printf '%s\n' "${failed[@]}" | sort)
  fi

  echo -e "\n${#succeeded[@]} passed, ${#failed[@]} failed (of ${total_jobs} total)"

  if [[ ${#failed[@]} -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
