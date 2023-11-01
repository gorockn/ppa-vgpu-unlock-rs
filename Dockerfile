ARG DISTRIB
ARG RELEASE

FROM docker.io/library/$DISTRIB:$RELEASE

RUN export DEBIAN_FRONTEND=noninteractive \
 && apt-get update \
 && apt-get install --no-install-recommends -y \
        build-essential \
        curl \
        ca-certificates \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal
ENV PATH "/root/.cargo/bin:${PATH}"

RUN cargo install cargo-deb

ARG DEBFULLNAME
ENV DEBFULLNAME "${DEBFULLNAME}"

ARG DEBEMAIL
ENV DEBEMAIL "${DEBEMAIL}"

WORKDIR /build
