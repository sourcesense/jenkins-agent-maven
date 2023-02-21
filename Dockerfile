FROM alpine:3.17.2 as alpine

FROM ubuntu:focal-20221019 as ubuntu

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
RUN git clone https://github.com/EcoMind/img.git -b v0.8.0
WORKDIR /img
RUN make static && mv img /usr/bin/img

FROM alpine as downloader

WORKDIR /

RUN apk add curl


FROM downloader AS trivy-downloader

ARG OS=${TARGETOS:-Linux}
ARG ARCH=${TARGETARCH:-64bit}
ARG TRIVY_VERSION="0.37.3"
RUN wget "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_${OS}-${ARCH}.deb" -O /tmp/trivy.deb


FROM ubuntu AS trivy-installer
COPY --from=trivy-downloader --chown=1000:1000 /tmp/trivy.deb /tmp/trivy.deb
RUN apt-get install -y /tmp/trivy.deb

FROM downloader as yq-downloader

ARG OS=${TARGETOS:-linux}
ARG ARCH=${TARGETARCH:-amd64}
ARG YQ_VERSION="v4.31.1"
# ARG YQ_VERSION="v4.30.5em"
ARG YQ_BINARY="yq_${OS}_$ARCH"
RUN wget "https://github.com/mikefarah/yq/releases/download/$YQ_VERSION/$YQ_BINARY" -O /usr/local/bin/yq && \
   chmod +x /usr/local/bin/yq
# RUN wget "https://github.com/brunobottazzini/yq/releases/download/$YQ_VERSION/$YQ_BINARY" -O /usr/local/bin/yq && \
#     chmod +x /usr/local/bin/yq


FROM ubuntu as fuse-downloader

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        git ca-certificates \
    && update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone https://github.com/containers/fuse-overlayfs.git -b v1.10

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
    openjdk-17-jdk \
    && \
    rm -rf /var/lib/apt/lists/*

# Downloading and installing Maven
RUN apt-get remove maven -y

ARG MAVEN_VERSION=3.8.6
ARG USER_HOME_DIR="/root"
ARG SHA=f790857f3b1f90ae8d16281f902c689e4f136ebe584aba45e4b1fa66c80cba826d3e0e52fdd04ed44b4c66f6d3fe3584a057c26dfcac544a60b301e6d0f91c26
ARG BASE_URL=https://apache.osuosl.org/maven/maven-3/${MAVEN_VERSION}/binaries

RUN mkdir -p /usr/share/maven /usr/share/maven/ref \
  && echo "Downlaoding maven" \
  && curl -fsSL -o /tmp/apache-maven.tar.gz ${BASE_URL}/apache-maven-${MAVEN_VERSION}-bin.tar.gz \
  \
  && echo "Checking download hash" \
  && echo "${SHA}  /tmp/apache-maven.tar.gz" | sha512sum -c - \
  \
  && echo "Unziping maven" \
  && tar -xzf /tmp/apache-maven.tar.gz -C /usr/share/maven --strip-components=1 \
  \
  && echo "Cleaning and setting links" \
  && rm -f /tmp/apache-maven.tar.gz \
  && ln -s /usr/share/maven/bin/mvn /usr/bin/mvn

ENV MAVEN_HOME /usr/share/maven
ENV MAVEN_CONFIG "$USER_HOME_DIR/.m2"

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

