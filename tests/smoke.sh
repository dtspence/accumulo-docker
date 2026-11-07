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

# Exercise the exact final runtime image; compilation happens on the CI host.
set -euo pipefail
image=${1:?image required}
arch=${2:?architecture required}
version=${3:?Accumulo version required}
case "$arch" in amd64) machine=x86_64 ;; arm64) machine=aarch64 ;; *) exit 1 ;; esac
[[ $(docker image inspect "$image" --format '{{.Architecture}}') == "$arch" ]]
docker run --rm --entrypoint bash "$image" -euc '
  [[ $(uname -m) == "$1" ]]
  java_version=$(java -version 2>&1)
  echo "$java_version"
  grep -Eq "version \"11[.]" <<< "$java_version"
  for library in /opt/hadoop/lib/native/libhadoop.so /opt/accumulo/lib/native/libaccumulo.so; do
    dependencies=$(ldd "$library")
    echo "$dependencies"
    if grep -q "not found" <<< "$dependencies"; then exit 1; fi
  done
' -- "$machine"
output=$(docker run --rm "$image" version)
echo "$output"
grep -F "$version" <<< "$output"
# checknative can report unavailable optional codecs; Hadoop and zlib are mandatory.
output=$(docker run --rm --entrypoint /opt/hadoop/bin/hadoop "$image" checknative -a 2>&1) || true
echo "$output"
grep -Eq '^hadoop:[[:space:]]+true' <<< "$output"
grep -Eq '^zlib:[[:space:]]+true' <<< "$output"
work=$(mktemp -d)
container=$(docker create "$image")
trap 'docker rm -f "$container" >/dev/null; rm -rf "$work"' EXIT
docker cp "$container:/opt/accumulo/lib" "$work/accumulo"
docker cp "$container:/opt/hadoop/share/hadoop" "$work/hadoop"
docker cp "$container:/opt/zookeeper/lib" "$work/zookeeper"
classpath=$(find "$work" -name '*.jar' -print | paste -sd: -)
javac -proc:none --release 11 -cp "$classpath" -d "$work/classes" "$(dirname "$0")/NativeMapSmoke.java"
docker run --rm -v "$work/classes:/smoke:ro" --entrypoint bash "$image" -euc '
  classpath=$(find /opt/accumulo/lib /opt/hadoop/share/hadoop /opt/zookeeper/lib -name "*.jar" -print | paste -sd: -)
  java -cp "/smoke:$classpath" NativeMapSmoke
'
