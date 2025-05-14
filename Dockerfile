# Set up base image for builder
FROM ubuntu:22.04 AS builder

# Set environment variables
ARG VERSION_DOGE
ENV DEBIAN_FRONTEND=noninteractive
ENV MAKEJOBS="-j8"
ENV CHECK_DOC="0"
ENV CCACHE_SIZE="100M"
ENV CCACHE_TEMPDIR="/tmp/.ccache-temp"
ENV CCACHE_COMPRESS="1"
ENV PYTHON_DEBUG="1"
ENV CACHE_NONCE="1"
ENV SDK_URL="https://depends.dogecoincore.org"

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    libtool \
    autotools-dev \
    automake \
    pkg-config \
    bsdmainutils \
    curl \
    ca-certificates \
    ccache \
    rsync \
    git \
    procps \
    bison \
    python3 \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    bc \
    tar \
    python3-zmq && \
    python3 -m pip install setuptools==70.3.0 --upgrade && \
    python3 -m pip install lief && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /dogecoin

# Download, extract, and clean up Dogecoin source
RUN curl -o dogecoin.tar.gz -Lk "https://github.com/dogecoin/dogecoin/archive/refs/tags/v${VERSION_DOGE}.tar.gz" && \
    tar -xf dogecoin.tar.gz && \
    mv dogecoin-${VERSION_DOGE}/* ./ && \
    rm -rf dogecoin-${VERSION_DOGE} && \
    rm -f dogecoin.tar.gz

# Build dependencies
RUN ln -snf /usr/share/zoneinfo/Etc/UTC /etc/localtime && echo Etc/UTC > /etc/timezone && \
    ccache --max-size=$CCACHE_SIZE && \
    make $MAKEJOBS -C depends HOST=x86_64-unknown-linux-gnu

# Build Dogecoin
RUN ./autogen.sh && \
    ./configure --prefix=$(pwd)/depends/x86_64-unknown-linux-gnu --enable-glibc-back-compat --enable-zmq --enable-reduce-exports --enable-c++14 LDFLAGS=-static-libstdc++ && \
    make $MAKEJOBS install && \
    make check $MAKEJOBS VERBOSE=1

# Set up base image for runner
FROM debian:bookworm-slim AS runner

# Install dependencies
RUN apt-get update && apt-get install -y libc6 libgcc-s1 curl && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /dogecoin

# Copy built binaries from the builder stage
COPY --from=builder /dogecoin/depends/x86_64-unknown-linux-gnu/bin ./

# Default port
EXPOSE 19918

# Entrypoint
ENTRYPOINT ["./dogecoind"]