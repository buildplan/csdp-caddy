# Stage 1: Build custom Caddy with CrowdSec and Docker Proxy
ARG GO_VERSION=1.25
FROM golang:${GO_VERSION}-alpine AS builder

# Arguments for version locking (passed from GH Actions)
ARG BOUNCER_VERSION
ARG PROXY_VERSION

RUN apk add --no-cache git

WORKDIR /app

# Create main.go with all plugins
RUN tee main.go <<EOF
package main

import (
	caddycmd "github.com/caddyserver/caddy/v2/cmd"

	_ "github.com/caddyserver/caddy/v2/modules/standard"
	_ "github.com/hslatman/caddy-crowdsec-bouncer/appsec"
	_ "github.com/hslatman/caddy-crowdsec-bouncer/http"
	_ "github.com/hslatman/caddy-crowdsec-bouncer/layer4"
	_ "github.com/lucaslorentz/caddy-docker-proxy/v2"
)

func main() {
	caddycmd.Main()
}
EOF

# Initialize module and fetch specific versions
RUN go mod init custom-caddy

RUN go get github.com/hslatman/caddy-crowdsec-bouncer/http@v${BOUNCER_VERSION} \
           github.com/hslatman/caddy-crowdsec-bouncer/appsec@v${BOUNCER_VERSION} \
           github.com/hslatman/caddy-crowdsec-bouncer/layer4@v${BOUNCER_VERSION} \
           github.com/lucaslorentz/caddy-docker-proxy/v2@v${PROXY_VERSION} \
    && go mod tidy

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build \
    -o /usr/bin/caddy \
    -ldflags "-w -s" .

# Stage 2: Final Image
FROM caddy:latest

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# REQUIRED: Overwrite CMD to start in docker-proxy mode
CMD ["caddy", "docker-proxy"]

LABEL org.opencontainers.image.title="csdp-caddy" \
      org.opencontainers.image.description="Caddy with CrowdSec Bouncer and Docker Proxy" \
      org.opencontainers.image.source="https://github.com/buildplan/csdp-caddy"
