FROM alpine:3.15.0 as alpine

FROM ubuntu:focal-20211006 as ubuntu

FROM golang:1.13-alpine AS gobuilder

RUN apk add --no-cache \
	bash \
	build-base \
	gcc \
	git \
	libseccomp-dev \
	linux-headers \
	make \
    ca-certificates

FROM gobuilder AS img

RUN go get github.com/go-bindata/go-bindata/go-bindata
WORKDIR /
RUN git clone https://github.com/EcoMind/img.git -b img-load
WORKDIR /img
RUN make static && mv img /usr/bin/img

FROM alpine as downloader

WORKDIR /

RUN apk add curl


FROM downloader AS trivy-downloader

ARG OS=${TARGETOS:-Linux}
ARG ARCH=${TARGETARCH:-64bit}
ARG TRIVY_VERSION="0.21.2"
RUN wget "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_${OS}-${ARCH}.deb" -O /tmp/trivy.deb


FROM ubuntu AS trivy-installer
COPY --from=trivy-downloader --chown=1000:1000 /tmp/trivy.deb /tmp/trivy.deb
RUN apt-get install /tmp/trivy.deb

FROM downloader as yq-downloader

ARG OS=${TARGETOS:-linux}
ARG ARCH=${TARGETARCH:-amd64}
ARG YQ_VERSION="v4.16.1"
ARG YQ_BINARY="yq_${OS}_$ARCH"
RUN wget "https://github.com/mikefarah/yq/releases/download/$YQ_VERSION/$YQ_BINARY" -O /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq


FROM ubuntu as fuse-downloader

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        git ca-certificates \
    && update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone https://github.com/containers/fuse-overlayfs.git -b v1.4.0

FROM ubuntu as fuse-builder
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


FROM ubuntu

RUN apt-get update && \
    apt-get install -y software-properties-common && \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys CC86BB64 && \
    rm -rf /var/lib/apt/lists/*

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    curl \
    git \
    jq \
    maven \
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

COPY --from=trivy-installer --chown=1000:1000 /usr/local/bin/trivy /usr/local/bin/trivy
COPY --from=img --chown=1000:1000 /usr/bin/img /usr/bin/img
COPY --from=yq-downloader --chown=1000:1000 /usr/local/bin/yq /usr/local/bin/yq
COPY --from=fuse-builder --chown=1000:1000 /build/fuse-overlayfs/fuse-overlayfs /usr/bin/fuse-overlayfs
RUN ["ln", "-sf", "/usr/bin/img", "/usr/bin/docker"]

USER 1000

RUN ./dep-bootstrap.sh 0.5.1 install

