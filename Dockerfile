FROM ubuntu:focal
LABEL maintainer="jholland@akamai.com"

ARG USER_ID
ARG GROUP_ID
ARG PATCHFILE

ENV container docker
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
      snapd \
      build-essential \
      git \
      curl \
      jq \
      python2.7 \
      python3 \
      python-is-python3 \
      lsb-release \
      sudo \
      vim

COPY cb-start.sh /tmp/cb-start.sh
COPY ${PATCHFILE} /tmp/patch.diff

# The container does a build that tries to use the host's uids, based on: 
# https://jtreminio.com/blog/running-docker-containers-as-current-host-user/#ok-so-what-actually-works

RUN if [ ${USER_ID:-0} -ne 0 ] && [ ${GROUP_ID:-0} -ne 0 ]; then \
    if getent passwd cbuilder; then userdel -f cbuilder; fi && \
    if getent group cbuilder ; then groupdel cbuilder; fi && \
    groupadd -g ${GROUP_ID} cbuilder && \
    useradd -l -u ${USER_ID} -g cbuilder cbuilder && \
    install -d -m 0755 -o cbuilder -g cbuilder /home/cbuilder && \
    chown --changes --silent --no-dereference --recursive \
          --from=33:33 ${USER_ID}:${GROUP_ID} \
      /tmp/patch.diff \
      /tmp/cb-start.sh \
;fi
        
USER cbuilder
WORKDIR /tmp

ENTRYPOINT [ "/tmp/cb-start.sh" ]
