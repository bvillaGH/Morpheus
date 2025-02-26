#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2021-2022, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

NUMARGS=$#
ARGS=$*

function hasArg {
    (( ${NUMARGS} != 0 )) && (echo " ${ARGS} " | grep -q " $1 ")
}

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Need to build the development docker container to setup git safe.directory
export DOCKER_IMAGE_NAME=${DOCKER_IMAGE_NAME:-"morpheus"}
export DOCKER_IMAGE_TAG=${DOCKER_IMAGE_TAG:-"conda_build"}
export DOCKER_TARGET=${DOCKER_TARGET:-"development"}

CUR_UID=$(id -u ${LOGNAME})
CUR_GID=$(id -g ${LOGNAME})

MORPHEUS_ROOT=${MORPHEUS_ROOT:-$(git rev-parse --show-toplevel)}
mkdir -p ${MORPHEUS_ROOT}/.cache/ccache
mkdir -p ${MORPHEUS_ROOT}/.cache/cpm

echo "Building container"
# Call the build script to get a container ready to build conda packages
${SCRIPT_DIR}/build_container_dev.sh

# Now run the container with the volume mount to build the packages
CONDA_ARGS=()
CONDA_ARGS+=("--output-folder" "/workspace/.conda-bld")
CONDA_ARGS+=("--skip-existing")

DOCKER_EXTRA_ARGS=()

if hasArg libneo; then
   # If libneo is specified, you must set NEO_GIT_URL
   DOCKER_EXTRA_ARGS+=("--env" "NEO_GIT_URL=${NEO_GIT_URL:?"Cannot build libneo. Must set NEO_GIT_URL to git repo location to allow checkout of neo repository"}")

   url=${NEO_GIT_URL}

   # Remove the http/https/ssh
   url="${url#http://}"
   url="${url#https://}"
   url="${url#ssh://}"

   # Remove git@
   url="${url#git@}"

   # Remove username/password
   url="${url#*:*@}"
   url="${url#*@}"

   # Remove remaining
   url=${url%%/*}

   port=${url##*:}
   url=${url%%:*}

   # Add the command to auto accept this url/port combo
   if [[ -n "${port}" ]]; then
      BUILD_SCRIPT="${BUILD_SCRIPT:+${BUILD_SCRIPT}\n}mkdir -p \$HOME/.ssh && ssh-keyscan -t rsa -p ${port} ${url} > ~/.ssh/known_hosts"
   else
      BUILD_SCRIPT="${BUILD_SCRIPT:+${BUILD_SCRIPT}\n}mkdir -p \$HOME/.ssh && ssh-keyscan -t rsa ${url} > ~/.ssh/known_hosts"
   fi
fi

# Build the script to execute inside of the container (needed to set multiple statements in CONDA_ARGS)
BUILD_SCRIPT="${BUILD_SCRIPT}
export CONDA_ARGS=\"${CONDA_ARGS[@]}\"
./ci/conda/recipes/run_conda_build.sh "$@"
chown -R ${CUR_UID}:${CUR_GID} .cache .conda-bld
"

echo "Running conda build"

# Run with an output folder that is mounted and skip existing to avoid repeated builds
DOCKER_EXTRA_ARGS="${DOCKER_EXTRA_ARGS[@]}" ${SCRIPT_DIR}/run_container_dev.sh bash -c "${BUILD_SCRIPT}"

echo "Conda packages have been built. Use the following to install into an environment:"
echo "    mamba install -c file://$(realpath ${MORPHEUS_ROOT}/.conda-bld) -c nvidia -c rapidsai -c conda-forge $@"
