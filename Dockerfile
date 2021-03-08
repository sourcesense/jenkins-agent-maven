FROM alpine:3.12.4 as curl

WORKDIR /

RUN apk add curl

FROM curl as yq-downloader

ARG OS=${TARGETOS:-linux}
ARG ARCH=${TARGETARCH:-amd64}
ARG YQ_VERSION="v4.6.0"
ARG YQ_BINARY="yq_${OS}_$ARCH"
RUN wget "https://github.com/mikefarah/yq/releases/download/$YQ_VERSION/$YQ_BINARY" -O /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

FROM curl as img-downloader

ARG IMG_SHA256="cc9bf08794353ef57b400d32cd1065765253166b0a09fba360d927cfbd158088"
RUN curl -fSL "https://github.com/genuinetools/img/releases/download/v0.5.11/img-linux-amd64" -o "/usr/bin/docker" \
	&& ( echo "${IMG_SHA256}  /usr/bin/docker" | sha256sum -c - ) \
	&& chmod a+x "/usr/bin/docker"


FROM ubuntu:groovy-20210115 as fuse-downloader

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        git ca-certificates \
    && update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone https://github.com/containers/fuse-overlayfs.git -b v1.4.0

FROM ubuntu:groovy-20210115 as fuse-builder
WORKDIR /build
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        libc6-dev gcc g++ make automake autoconf clang pkgconf libfuse3-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=fuse-downloader /build /build
RUN cd fuse-overlayfs && \
    sh autogen.sh && \
    LIBS="-ldl" LDFLAGS="-static" ./configure --prefix /usr && \
    make


FROM ubuntu:groovy-20210115

RUN apt-get update && \
    apt-get install -y software-properties-common && \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys CC86BB64 && \
    rm -rf /var/lib/apt/lists/*

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    curl \
    git \
    jq \
    xmlstarlet \
    uidmap \
    libseccomp-dev \
    fuse3 \
    && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY dep-bootstrap.sh .
RUN chmod +x ./dep-bootstrap.sh

ENV USER=jenkins
USER root
RUN useradd -u 1000 -s /bin/bash jenkins
RUN mkdir -p /home/jenkins
RUN chown 1000:1000 /home/jenkins
RUN export IMG_DISABLE_EMBEDDED_RUNC=1 \
    && chmod u-s /usr/bin/newuidmap /usr/bin/newgidmap \
    && echo "jenkins:100000:65536" > /etc/subgid \
    && echo "jenkins:100000:65536" > /etc/subuid \
    && setcap cap_setuid+ep /usr/bin/newuidmap \
    && setcap cap_setgid+ep /usr/bin/newgidmap \
    && mkdir -p /run/runc && chmod 777 /run/runc

ENV JENKINS_USER=jenkins

COPY --from=img-downloader --chown=1000:1000 /usr/bin/docker /usr/bin/docker
COPY --from=yq-downloader --chown=1000:1000 /usr/local/bin/yq /usr/local/bin/yq
COPY --from=fuse-builder --chown=1000:1000 /build/fuse-overlayfs/fuse-overlayfs /usr/bin/fuse-overlayfs

USER 1000

RUN ./dep-bootstrap.sh 0.4.3 install

