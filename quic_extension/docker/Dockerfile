FROM ubuntu:20.04
LABEL maintainer="jholland@akamai.com"

ENV container docker
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV TZ=Etc/UTC
ENV APT_LISTCHANGES_FRONTEND=none

RUN \
  echo 'libc6 libraries/restart-without-asking boolean true' | debconf-set-selections; \
  apt-get update; \
  DEBIAN_FRONTEND=noninteractive \
  apt-get --allow-downgrades --allow-remove-essential --allow-change-held-packages -fuy dist-upgrade

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
      snapd \
      build-essential \
      curl \
      git \
      python3 \
      python-is-python3 \
      lsb-release \
      sudo \
      vim \
      wget

RUN mkdir /base
COPY initial-run.sh /base/initial-run.sh
RUN chmod +x /base/initial-run.sh

RUN echo "qbuild ALL=NOPASSWD: ALL" | tee -a /etc/sudoers

# The container does a build that tries to use the host's uids, based on: 
# https://jtreminio.com/blog/running-docker-containers-as-current-host-user/#ok-so-what-actually-works

# NB: Doing this during the run requires breaking into 2 stages, but not
#     necessary here since this is during the build:
#     https://stackoverflow.com/a/1988265/3427357

ARG USER_ID
ARG GROUP_ID

RUN if [ ${USER_ID:-0} -ne 0 ] && [ ${GROUP_ID:-0} -ne 0 ]; then \
    if getent passwd qbuild; then userdel -f qbuild; fi && \
    if getent group qbuild ; then groupdel qbuild; fi && \
    groupadd -g ${GROUP_ID} qbuild && \
    useradd -l -u ${USER_ID} -g qbuild qbuild && \
    install -d -m 0755 -o qbuild -g qbuild /home/qbuild && \
    chown --changes --silent --no-dereference --recursive \
          --from=33:33 ${USER_ID}:${GROUP_ID} \
      /base/initial-run.sh \
  ; else echo "Run docker build with --build-arg USER_ID=\$(id -u \${USER}) --build-arg GROUP_ID=\$(id -g \${USER})" ; exit 1 \
  ;fi

USER qbuild

ARG GITNAME
ARG GITEMAIL

RUN if [ ! -z "${GITNAME}" -a ! -z "${GITEMAIL}" ]; then \
    git config --global user.email "${GITEMAIL}" && \
    git config --global user.name "${GITNAME}" ; \
  else \
    echo "Run docker build with --build-arg GITEMAIL=\$(git config user.email) --build-arg GITNAME=\"\$(git config user.name)\""  && \
    exit 1; \
  fi

ENTRYPOINT [ "/base/initial-run.sh" ]
