# Apache Accumulo Docker Image

This is the first release of this project. Eventually, this project will create an `apache/accumulo` image at DockerHub.
Until then, you will need to build your own image. The main branch of this repo creates a Docker image for
Accumulo 2.0+. If you want to create a Docker image for Accumulo 1.9, there is a
[1.9 branch](https://github.com/apache/accumulo-docker/tree/1.9) for that.

## Obtain the Docker image

To obtain the docker image created by this project, you can either pull it from DockerHub at
`apache/accumulo` or build it yourself. To pull the image from DockerHub, run the command below:

    docker pull apache/accumulo

While it is easier to pull from DockerHub, the image will default to the software versions below:

| Software    | Version       |
|-------------|---------------|
| [Accumulo]  | 2.1.2         |
| [Hadoop]    | 3.3.6         |
| [ZooKeeper] | 3.8.2         |

If these versions do not match what is running on your cluster, you should consider building
your own image with matching versions. However, Accumulo must be 2.0.0+. Below are instructions for
building an image:

1. Clone the Accumulo docker repo

        git clone git@github.com:apache/accumulo-docker.git

2. Build the default Accumulo docker image using the command below.

        cd /path/to/accumulo-docker
        docker build -t accumulo .

   Or build the Accumulo docker image with specific released versions of Hadoop, Zookeeper, etc that will downloaded from Apache using the command below:

        docker build --build-arg ZOOKEEPER_VERSION=3.4.8 --build-arg HADOOP_VERSION=2.7.0 -t accumulo .

   Or build with an Accumulo tarball (located in same directory as DockerFile) using the command below:

        docker build --build-arg ACCUMULO_FILE=accumulo-<version>-bin.tar.gz -t accumulo .

## Supported architectures and local builds

The Dockerfile supports `linux/amd64` and `linux/arm64` only. BuildKit supplies
`TARGETARCH`; Hadoop uses the standard binary archive on AMD64 and the
`-aarch64` archive on ARM64. Accumulo native libraries are compiled for the target
architecture. Build-only ELF checks reject a Hadoop or Accumulo native library
with the wrong architecture before it reaches the runtime image.

The `HADOOP_FILE`, `ZOOKEEPER_FILE`, and `ACCUMULO_FILE` build arguments accept
local tarballs. A supplied Hadoop archive must contain native libraries matching
the target architecture; Java-only archives and wrong-architecture archives fail.
Versions without an Apache ARM64 Hadoop archive require a compatible local
`HADOOP_FILE`. The default Dockerfile versions above remain unchanged; CI uses
the versions listed below.

```bash
# Load a single architecture locally (Docker selects the host architecture by default).
docker buildx build --platform linux/arm64 --load -t accumulo:arm64 .
# Push both architectures to a registry; cross-platform local builds need emulation.
docker buildx build --platform linux/amd64,linux/arm64 \
  --push -t ghcr.io/<group>/accumulo:custom .
# Test a local final image; requires a host JDK with javac supporting --release 11.
tests/smoke.sh accumulo:arm64 arm64 2.1.2
```

CI compiles each architecture on its own native runner. Local cross-platform
builds can use Buildx/QEMU, but native builders are recommended for compilation.
The final image contains the JRE and runtime installations, without the build JDK,
compiler, or ELF inspection tools.

## GitHub Actions

The Docker workflow builds and tests the image for `linux/amd64` and `linux/arm64`
on native Ubuntu runners on pull requests, branch
pushes, version tags (`v*`), and manual runs. It publishes to
`ghcr.io/<group>/accumulo` on the default branch and version tags only. Other
branches and pull requests build without publishing.

The group defaults to the GitHub repository owner (converted to lowercase).
To override it, set the repository Actions variable `IMAGE_GROUP` to the desired
GitHub user or organization. The repository's `GITHUB_TOKEN` must have permission
to publish packages in that namespace; changing the variable does not grant access.
No additional registry secret is needed for the default namespace.

The workflow uses a version matrix. The `2.1` series builds Accumulo `2.1.6`
with ZooKeeper `3.9.5` by passing `ACCUMULO_VERSION` and `ZOOKEEPER_VERSION`
to the Docker build. Add entries to the matrix
to build additional versions in the prepare job; designate only one entry as `latest`.

Default-branch builds publish `2.1`, `2.1.6`, and `latest` for this entry.
Every published build also receives a `2.1.6-sha-<full-commit-sha>` tag.
Git tags produce version-qualified image tags, such as `2.1.6-v1.0.0` for
Git tag `v1.0.0`, so matrix entries cannot overwrite each other's images.
Each architecture and version uses its own build cache. Git tags must be valid Docker tags.

Both native builds must pass before shared tags are published as a multi-platform
manifest. The exact tested images are pushed using unique staging tags containing
the version, commit, workflow run, attempt, and architecture; the merge job combines
their immutable digests. Runs for the same Git ref are serialized without cancelling
an active publication. Pull requests and nondefault branches do not log in or push.

Smoke tests check the final runtime image architecture, Java and Accumulo versions,
native shared-library dependencies, Hadoop and zlib native support, and Accumulo
NativeMap JNI put/get, ordered iteration, size, and deletion. Optional Hadoop codecs
are reported but are not required. These checks do not start a complete cluster.

```bash
docker pull ghcr.io/<group>/accumulo:latest
```

GHCR packages may initially be private. Change the package visibility to public
in GitHub if anonymous pulls are desired.

## Image basics

The entrypoint for the Accumulo docker image is the `accumulo` script. While the primary use
case for this image is to start Accumulo processes (i.e tserver, master, etc), you can run other
commands in the `accumulo` script to test out the image:

```bash
# No arguments prints Accumulo command usage
docker run accumulo
# Print Accumulo version
docker run accumulo version
# Print Accumulo classpath
docker run accumulo classpath
```

# Run Accumulo using Docker

Before you can run Accumulo services in Docker, you will need to install Accumulo, configure `accumulo.properties`,
and initialize your instance with `--upload-accumulo-props`. This will upload configuration to Zookeeper and limit
how much configuration needs to be set on the command line.

```bash
$ accumulo init --upload-accumulo-props
...
Uploading properties in accumulo.properties to Zookeeper. Properties that cannot be set in Zookeeper will be skipped:
Skipped - instance.secret = <hidden>
Skipped - instance.volumes = hdfs://localhost:8020/accumulo
Skipped - instance.zookeeper.host = localhost:2181
Uploaded - table.durability = flush
Uploaded - tserver.memory.maps.native.enabled = false
Uploaded - tserver.readahead.concurrent.max = 64
Uploaded - tserver.server.threads.minimum = 64
Uploaded - tserver.walog.max.size = 512M
```

Any configuration that is skipped above will need to be passed in as a command line option to Accumulo services running
in Docker containers. These options can be set in an environment variable which is used in later commands.

```
export ACCUMULO_CL_OPTS="-o instance.secret=mysecret -o instance.volumes=hdfs://localhost:8020/accumulo -o instance.zookeeper.host=localhost:2181"
```

The Accumulo docker image expects that the HDFS path set by `instance.volumes` is owned by the `accumulo` user. This
can be accomplished by running the command below (replace the HDFS path with yours):

```bash
hdfs dfs -chown -R accumulo hdfs://localhost:8020/accumulo
```

## Docker engine

Use the `docker` command to start local docker containers. The commands below will start a local Accumulo cluster
with two tablet servers.

```
docker run -d --network="host" accumulo monitor $ACCUMULO_CL_OPTS
docker run -d --network="host" accumulo tserver $ACCUMULO_CL_OPTS
docker run -d --network="host" accumulo tserver $ACCUMULO_CL_OPTS
docker run -d --network="host" accumulo master $ACCUMULO_CL_OPTS
docker run -d --network="host" accumulo gc $ACCUMULO_CL_OPTS
```

If you would like to set Java heap size inside the Docker container, start the local docker container using the
command below:

```
docker run -e ACCUMULO_JAVA_OPTS='-Xmx1g' -d --network="host" accumulo tserver $ACCUMULO_CL_OPTS
```

## Marathon

Using the Marathon UI, you can start Accumulo services using the following
JSON configuration template.  The template is configured to start an Accumulo
monitor but it can be modified to start other Accumulo services such as
`master`, `tserver` and `gc`. For tablet servers, set `instances` to the number
of tablet servers that you want to run.

```json
{
  "id": "accumulo-monitor",
  "cmd": "accumulo monitor -o instance.secret=mysecret -o instance.volumes=hdfs://localhost:8020/accumulo -o instance.zookeeper.host=localhost:2181",
  "cpus": 1,
  "mem": 512,
  "disk": 0,
  "instances": 1,
  "container": {
    "docker": {
      "image": "apache/accumulo",
      "network": "HOST"
    },
    "type": "DOCKER"
  }
}
```

[Accumulo]: https://accumulo.apache.org/
[Hadoop]: https://hadoop.apache.org/
[ZooKeeper]: https://zookeeper.apache.org/
