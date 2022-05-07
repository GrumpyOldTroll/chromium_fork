# Intro

This directory is about how to use docker to have a sandboxed build of epoll_quic_server and epoll_quic_client inside a docker container.

The purpose is to make it easier to build for people who are using an incompatible linux distro.

# How-to

## First run

The first run is for coming up starting with nothing but this directory.

### Build Initial Image

~~~
docker build -t qbuilder:latest \
    --build-arg USER_ID=$(id -u ${USER}) \
    --build-arg GROUP_ID=$(id -g ${USER}) \
    --build-arg GITEMAIL=$(git config user.email) \
    --build-arg GITNAME="$(git config user.name)" \
  -f ./Dockerfile .
~~~

### Run Initial Setup/Fetch

This should take a while but should complete successfully:

~~~
SRCDIR=~/mc/quiche-work
mkdir -p ${SRCDIR}
docker run -it --name qbuild \
  --mount type=bind,src="${SRCDIR}",dst=/build \
  qbuilder:latest
~~~

Afterwards, you should have a `src` directory under ${SRCDIR}, and it should contain the [chromium source tree](https://github.com/chromium/chromium).  It should also be sync'd to the [quic-multicast-dev](https://github.com/GrumpyOldTroll/chromium/tree/quic-multicast-dev) branch of the quic multicast fork, plus the depot_tools that were used in the build:

~~~
$ ls ${SRCDIR}
depot_tools  src
~~~

In the appropriate location under that, the net/third_party/quiche/src directory should be sync'd to the [quic-multicast-dev](https://github.com/GrumpyOldTroll/quiche/tree/quic-multicast-dev) branch of the quiche multicast fork:

~~~
$ git -C ${SRCDIR}/src status
On branch quic-multicast-dev
Your branch is up to date with 'multicast/quic-multicast-dev'.
$ git -C ${SRCDIR}/src/net/third_party/quiche/src status
On branch quic-multicast-dev
Your branch is up to date with 'multicast/quic-multicast-dev'.
~~~

## Later Runs

Once you've got the setup/fetch performed, you can launch the build part by running this way:

~~~
docker start -i qbuild
~~~

That enters the docker context, where you can run ninja.

You can also pull the branch you actually want to build first (or you can do it from outside the docker context):

~~~
qbuild@879d4717997b:/build/src$ git checkout issue-1-integration
...
qbuild@879d4717997b:/build/src$ git -C net/third_party/quiche/src checkout issue-1-integration
...
qbuild@879d4717997b:/build/src$ ninja -C out/Default epoll_quic_server epoll_quic_client qpush
~~~

(Inside the container you can also sudo if you need to install things or whatever.)

(NB: You MUST have a src/ directory inside ${SRCDIR} at this point or it'll try to do the long chrome fetch, but if you're doing something odd where you don't have one for now but you want to enter the container without pulling that down, you can create a ${SRCDIR}/src directory.)

This should leave built executables in the appropriate locations on your filesystem, so after you leave docker (ctrl-D, exit, etc.):

~~~
$ ${SRCDIR}/src/out/Default/epoll_quic_server --help
Usage: quic_server [options]
Options:
...
~~~

From here you can `cd ${SRCDIR}/src` and do the rest of the steps in <../README.md> (making a local cert, running server and client, etc.).  These likewise can optionally be run from inside the container if preferred.

If you need multiple shells inside the container, your 2nd shell can run `docker exec -it qbuild /bin/bash`.  (If you run start -i a second time, you'll end up sharing a single shell across multiple terminals, probably not what you want.)

