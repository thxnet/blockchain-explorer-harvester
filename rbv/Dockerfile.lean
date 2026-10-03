ARG BASE_IMAGE=ghcr.io/thxnet/blockchain-explorer-harvester:230825-c6fe5d3
FROM ${BASE_IMAGE}
COPY app /usr/src/app
