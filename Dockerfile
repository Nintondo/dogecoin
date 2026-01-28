# Build stage
FROM debian:trixie AS builder

ARG VERSION_DOGE
ARG BUILD_JOBS=0
ARG RUN_TESTS=0
ARG PREFIX=/opt/dogecoin
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /usr/src/dogecoin

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libtool autotools-dev automake pkg-config \
    bsdmainutils curl ca-certificates ccache rsync git procps \
    bison python3 python3-pip python3-setuptools python3-wheel \
    bc tar python3-zmq python3-venv && \
    python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir setuptools==70.3.0 --upgrade && \
    /opt/venv/bin/pip install --no-cache-dir lief && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Download, extract, and clean up Dogecoin source
RUN curl -o dogecoin.tar.gz -Lk "https://github.com/dogecoin/dogecoin/archive/refs/tags/v${VERSION_DOGE}.tar.gz" && \
    tar -xf dogecoin.tar.gz && \
    mv dogecoin-${VERSION_DOGE}/* ./ && \
    rm -rf dogecoin-${VERSION_DOGE} && \
    rm -f dogecoin.tar.gz

# Build dependencies and Dogecoin
RUN if [ "${BUILD_JOBS}" = "0" ] || [ -z "${BUILD_JOBS}" ]; then BUILD_JOBS="$(nproc)"; fi && \
    ln -snf /usr/share/zoneinfo/Etc/UTC /etc/localtime && echo Etc/UTC > /etc/timezone && \
    ccache --max-size=100M && \
    make -j"${BUILD_JOBS}" -C depends HOST=x86_64-unknown-linux-gnu && \
    ./autogen.sh && \
    CONFIG_SITE="$PWD/depends/x86_64-unknown-linux-gnu/share/config.site" \
    ./configure --prefix="${PREFIX}" --enable-glibc-back-compat --enable-zmq \
      --enable-reduce-exports --enable-c++14 LDFLAGS=-static-libstdc++ && \
    make -j"${BUILD_JOBS}" && \
    if [ "${RUN_TESTS}" = "1" ]; then make -j"${BUILD_JOBS}" check VERBOSE=1; fi && \
    mkdir -p /build && \
    make DESTDIR=/build install

# Runtime stage
FROM debian:trixie AS runner

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gosu \
    libc6 \
    libgcc-s1 \
    tini && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd --system --gid 1001 appuser && \
    useradd --system --uid 1001 --gid appuser --home /home/appuser --shell /usr/sbin/nologin appuser && \
    mkdir -p /home/appuser/.cache /data && \
    chown -R 1001:1001 /home/appuser /data

WORKDIR /app

COPY --from=builder /build/opt/dogecoin/bin/ /app/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 19918

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["/app/dogecoind"]
