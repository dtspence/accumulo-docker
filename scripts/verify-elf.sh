#!/usr/bin/env bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Build-only check: reject incompatible native libraries, including supplied tarballs.
set -euo pipefail
case "$1" in
  amd64) machine='Advanced Micro Devices X86-64' ;;
  arm64) machine='AArch64' ;;
  *) echo "Unsupported TARGETARCH: $1" >&2; exit 1 ;;
esac
shift
for library in "$@"; do
  header=$(LC_ALL=C readelf -h "$library")
  if ! grep -Eq "Class:[[:space:]]+ELF64" <<< "$header" ||
     ! grep -Eq "Machine:[[:space:]]+${machine}[[:space:]]*$" <<< "$header"; then
    echo "Wrong ELF architecture for $library; expected $machine" >&2
    echo "$header" >&2
    exit 1
  fi
done
