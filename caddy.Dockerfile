# 1. GLOBAL ARGS
ARG GO_VERSION=1.25
ARG CADDY_VERSION=2

# --- Stage 1: Builder ---
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS builder

# 2. REDECLARE ARGS FOR BUILDER
ARG CADDY_VERSION
ARG BOUNCER_VERSION
ARG PROXY_VERSION
ARG TARGETARCH
ARG TARGETOS

# Install git and xcaddy
RUN apk add --no-cache git && \
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

WORKDIR /app

# 3. Build with Cross-Compilation Support
RUN GOOS=${TARGETOS} GOARCH=${TARGETARCH} xcaddy build v${CADDY_VERSION} \
    --output /usr/bin/caddy \
    --with github.com/lucaslorentz/caddy-docker-proxy/v2@v${PROXY_VERSION} \
    --with github.com/hslatman/caddy-crowdsec-bouncer/appsec@v${BOUNCER_VERSION} \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http@v${BOUNCER_VERSION} \
    --with github.com/hslatman/caddy-crowdsec-bouncer/layer4@v${BOUNCER_VERSION}

# --- Stage 2: Final Image ---
FROM caddy:${CADDY_VERSION}-alpine

# Install dependencies (Process supervision, timezones, etc)
RUN apk add --no-cache ca-certificates tzdata mailcap

# Copy binary from builder
COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# REQUIRED: Overwrite CMD to start in docker-proxy mode
CMD ["caddy", "docker-proxy"]

# Metadata
LABEL org.opencontainers.image.title="csdp-caddy" \
      org.opencontainers.image.description="Caddy with CrowdSec Bouncer and Docker Proxy" \
      org.opencontainers.image.source="https://github.com/buildplan/csdp-caddy" \
      org.opencontainers.image.version="${CADDY_VERSION}-P${PROXY_VERSION}-B${BOUNCER_VERSION}"
