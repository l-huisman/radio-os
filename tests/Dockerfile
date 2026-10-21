FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

COPY packages/build.txt /tmp/build.txt
RUN apt-get update \
    && grep -v '^#' /tmp/build.txt | xargs apt-get install -y --no-install-recommends \
        bats shellcheck python3 \
    && rm -rf /var/lib/apt/lists/*
