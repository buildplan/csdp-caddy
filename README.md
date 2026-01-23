# csdp-caddy

[![Built with xcaddy](https://img.shields.io/badge/Built%20with-xcaddy-00ADD8?style=flat&logo=go&logoColor=white)](https://github.com/caddyserver/xcaddy) 
[![CrowdSec Bouncer](https://img.shields.io/badge/CrowdSec-Bouncer-orange?style=flat&logo=shield&logoColor=white)](https://github.com/hslatman/caddy-crowdsec-bouncer)
[![Docker Proxy](https://img.shields.io/badge/Docker-Proxy-blue?style=flat&logo=docker&logoColor=white)](https://github.com/lucaslorentz/caddy-docker-proxy)

[![Build and Push CSDP-Caddy](https://github.com/buildplan/csdp-caddy/actions/workflows/build-and-push.yml/badge.svg)](https://github.com/buildplan/csdp-caddy/actions/workflows/build-and-push.yml)
[![Check Caddy Release](https://github.com/buildplan/csdp-caddy/actions/workflows/check-caddy-release.yml/badge.svg)](https://github.com/buildplan/csdp-caddy/actions/workflows/check-caddy-release.yml)
[![Check Bouncer Release](https://github.com/buildplan/csdp-caddy/actions/workflows/check-bouncer-release.yml/badge.svg)](https://github.com/buildplan/csdp-caddy/actions/workflows/check-bouncer-release.yml)
[![Check Proxy Release](https://github.com/buildplan/csdp-caddy/actions/workflows/check-proxy-release.yml/badge.svg)](https://github.com/buildplan/csdp-caddy/actions/workflows/check-proxy-release.yml)

A custom Docker image for Caddy that combines **Dynamic Docker Configuration** with **CrowdSec Security**.

This image integrates three components into one binary:
1. **Caddy:** The ultimate server.
2. **Caddy Docker Proxy:** Auto-generates Caddy configuration from Docker labels (no manual Caddyfile editing).
3. **CrowdSec Bouncer:** Adds IP blocking and a Web Application Firewall (WAF) to every site you host.

The image is automatically rebuilt and updated on GHCR whenever there is a new release of Caddy, the CrowdSec module, or the Docker Proxy plugin.

## How It Works

This setup provides a fully automated, secure reverse proxy stack:

1.  **Dynamic Config (`caddy-docker-proxy`):** Caddy connects to the Docker socket. When you launch a new container with specific labels, Caddy automatically provisions SSL certificates and routes traffic to it.
2.  **IP Blocker (`crowdsec`):** Acts like a front-desk security guard. It checks the IP of every visitor against CrowdSec's blocklist before allowing access.
3.  **WAF (`appsec`):** Acts like a security team inside the building. It inspects the *content* of requests to block SQL injection, XSS, and known CVE exploits.

## How to Use This Image

Follow these steps to integrate this Caddy image into your Docker setup.

### Step 1: Deploy Caddy and CrowdSec

In your `docker-compose.yml`, use the image `ghcr.io/buildplan/csdp-caddy:latest`. 

> **Note on Configuration:** You must mount the Docker socket so the proxy can detect your containers. You also need a shared volume for logs so CrowdSec can read Caddy's access logs. You do **not** need to mount a `Caddyfile`. We configure the global CrowdSec settings (like the API key) using labels on the Caddy container itself.

```yaml
services:
  caddy:
    image: ghcr.io/buildplan/csdp-caddy:latest
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    environment:
      # Required: Tells Caddy which network to proxy traffic through
      - CADDY_INGRESS_NETWORKS=caddy_net
    networks:
      - caddy_net
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock # REQUIRED for auto-discovery
      - caddy_data:/data
      # Mount a volume for logs so CrowdSec can read them
      - ./caddy_logs:/var/log/caddy 
    
    # GLOBAL CONFIGURATION VIA LABELS
    labels:
      caddy.email: "you@example.com"
      
      # 1. Global Logging Configuration
      # We tell Caddy to write logs to a file that CrowdSec can see
      caddy.log.output: "file /var/log/caddy/access.log"
      caddy.log.format: "json"
      caddy.log.level: "INFO"
      
      # 2. CrowdSec Configuration
      # This creates the global { crowdsec { ... } } block
      caddy.crowdsec.api_url: "http://crowdsec:8080"
      caddy.crowdsec.api_key: "YOUR_BOUNCER_KEY_HERE" # See Step 3
      caddy.crowdsec.appsec_url: "http://crowdsec:7422" 

  crowdsec:
    image: crowdsecurity/crowdsec:latest
    container_name: crowdsec
    environment:
      - COLLECTIONS=crowdsecurity/caddy crowdsecurity/appsec-virtual-patching crowdsecurity/appsec-generic-rules
      # Listen on all interfaces so Caddy can reach it
      - CROWDSEC_LAPI_LISTEN_URI=0.0.0.0:8080
    networks:
      - caddy_net
    volumes:
      - ./crowdsec-db:/var/lib/crowdsec/data
      - ./crowdsec-config:/etc/crowdsec
      # Mount the custom acquisition file (Created in Step 2)
      - ./crowdsec-config/acquis.yaml:/etc/crowdsec/acquis.yaml
      # Shared logs volume
      - ./caddy_logs:/var/log/caddy

networks:
  caddy_net:
    external: true

volumes:
  caddy_data:
  crowdsec-db:
```

### Step 2: Configure CrowdSec Log Reading

You need to tell CrowdSec to read the file that Caddy is writing to.

Create a file named `acquis.yaml` inside your `./crowdsec-config/` directory:

```yaml
# ./crowdsec-config/acquis.yaml
filenames:
  - /var/log/caddy/access.log
labels:
  type: caddy
```

*Note: You also need to create the log file on the host initially to ensure permissions are correct:*

```bash
mkdir -p caddy_logs
touch caddy_logs/access.log
chmod 666 caddy_logs/access.log
```

### Step 3: Get a Bouncer API Key

Your Caddy bouncer needs a key to talk to the CrowdSec agent.
Start the CrowdSec container, then run:

```bash
docker exec crowdsec cscli bouncers add caddy-bouncer
```

Copy the API key generated and paste it into the `caddy.crowdsec.api_key` label in your `docker-compose.yml` (Step 1).

### Step 4: Enable AppSec in CrowdSec

To use the WAF features, enable the AppSec engine in CrowdSec.

1. **Create the AppSec config:** Inside your mounted CrowdSec config folder (e.g., `./crowdsec-config/acquis.d/`), create a file named `appsec.yaml`:

```yaml
# ./crowdsec-config/acquis.d/appsec.yaml
listen_addr: 0.0.0.0:7422
appsec_config: crowdsecurity/appsec-default
name: caddy-appsec-listener
source: appsec
labels:
  type: appsec
```

2. **Restart CrowdSec:**
```bash
docker restart crowdsec
```

### Step 5: Deploy a Protected Container

With `caddy-docker-proxy`, you add labels to the containers you want to expose.

**Crucial:** We explicitly configure logging labels (`caddy.log.output`) to ensure traffic logs go to the shared volume where CrowdSec can see them.

Here is an example `whoami` service protected by CrowdSec and AppSec:

```yaml
services:
  whoami:
    image: traefik/whoami
    networks:
      - caddy_net
    labels:
      # 1. Define the domain
      caddy: "whoami.example.com"

      # 2. LOGGING
      # Explicitly write logs to the shared volume
      caddy.log.output: "file /var/log/caddy/access.log"
      caddy.log.format: "json"

      # 3. SECURITY
      # We use numbered routes to ensure CrowdSec checks happen BEFORE the proxy
      caddy.route.0_crowdsec: ""
      caddy.route.1_appsec: ""
      
      # 4. SECURITY HEADERS (Optional)
      caddy.header.Strict-Transport-Security: "max-age=31536000; includeSubDomains"
      caddy.header.X-Frame-Options: "SAMEORIGIN"
      caddy.header.X-Content-Type-Options: "nosniff"

      # 5. REVERSE PROXY
      caddy.route.2_reverse_proxy: "{{upstreams 80}}"
      
      # Network Helper (Must match the network defined in Step 1)
      caddy_ingress_network: "caddy_net"
```

**Explanation of Labels:**

* `caddy`: Sets the URL for this container.
* `caddy.log.output`: configures the site to write logs to the shared `access.log` file.
* `caddy.route.0_crowdsec`: Initializes the IP blocker as the first step.
* `caddy.route.1_appsec`: Initializes the WAF as the second step.
* `caddy.route.2_reverse_proxy`: Sends the traffic to the container application.

### Step 6: Verify

1. **Start the stack:**

```bash
docker compose up -d
```

2. **Generate Traffic:**

Visit your site to generate some logs in the browser or in CLI:

```bash
curl -I https://whoami.example.com
```

3. **Check CrowdSec Metrics:**

Verify that CrowdSec is reading the logs and AppSec is receiving data.

```bash
docker exec crowdsec cscli metrics
```

* Look for **Acquisition Metrics**: Should show `file:/var/log/caddy/access.log` with "Lines read" > 0.
* Look for **Parser Metrics**: Should show `crowdsecurity/caddy-logs`.

## Included Utilities

Because this image is built with the CrowdSec module, you have access to the Caddy-CrowdSec CLI tools directly inside the container.

```bash
# Check if an IP is currently banned
docker exec caddy caddy crowdsec check 1.2.3.4
```

```bash
# Check the health of the bouncer connection
docker exec caddy caddy crowdsec health
```

---

## CLI Options

You could see the Caddyfile which docker-proxy plugin generates in-memory with:

```bash
docker logs caddy 2>&1 | grep "New Caddyfile" | tail -n 1 | sed 's/.*"caddyfile":"//' | sed 's/"}$//' | sed 's/\\n/\n/g' | sed 's/\\t/\t/g'
```

---

> Options below are taken from [https://github.com/hslatman/caddy-crowdsec-bouncer](https://github.com/hslatman/caddy-crowdsec-bouncer)

```text
$ docker exec caddy crowdsec ...

Commands related to the CrowdSec integration (experimental)

Usage:
  caddy crowdsec [command]

Available Commands:
  check       Checks an IP to be banned or not
  health      Checks CrowdSec integration health
  info        Shows CrowdSec runtime information
  ping        Pings the CrowdSec LAPI endpoint

Flags:
  -a, --adapter string   Name of config adapter to apply (when --config is used)
      --address string   The address to use to reach the admin API endpoint, if not the default
  -c, --config string    Configuration file to use to parse the admin address, if --address is not used
  -h, --help             help for crowdsec
  -v, --version          version for crowdsec

Use "caddy crowdsec [command] --help" for more information about a command.

Full documentation is available at:
https://caddyserver.com/docs/command-line
```

---

> For documentation on **Docker Proxy labels**, visit: [https://github.com/lucaslorentz/caddy-docker-proxy](https://github.com/lucaslorentz/caddy-docker-proxy)

caddy-docker-proxy extends caddy's CLI with the command `caddy docker-proxy`.

Run `docker exec caddy caddy help docker-proxy` to see all available flags.

```text
Usage of docker-proxy:
  --caddyfile-path string
        Path to a base Caddyfile that will be extended with Docker sites
  --envfile
        Path to an environment file with environment variables in the KEY=VALUE format to load into the Caddy process
  --controller-network string
        Network allowed to configure Caddy server in CIDR notation. Ex: 10.200.200.0/24
  --ingress-networks string
        Comma separated name of ingress networks connecting Caddy servers to containers.
        When not defined, networks attached to controller container are considered ingress networks
  --docker-sockets
        Comma separated docker sockets
        When not defined, DOCKER_HOST (or default docker socket if DOCKER_HOST not defined)
  --docker-certs-path
        Comma separated cert path, you could use empty value when no cert path for the concern index docker socket like cert_path0,,cert_path2
  --docker-apis-version
        Comma separated apis version, you could use empty value when no api version for the concern index docker socket like cert_path0,,cert_path2
  --label-prefix string
        Prefix for Docker labels (default "caddy")
  --mode
        Which mode this instance should run: standalone | controller | server
  --polling-interval duration
        Interval Caddy should manually check Docker for a new Caddyfile (default 30s)
  --event-throttle-interval duration
        Interval to throttle caddyfile updates triggered by docker events (default 100ms)
  --process-caddyfile
        Process Caddyfile before loading it, removing invalid servers (default true)
  --proxy-service-tasks
        Proxy to service tasks instead of service load balancer (default true)
  --scan-stopped-containers
        Scan stopped containers and use their labels for Caddyfile generation (default false)
```

This plugin extends caddy's CLI with the command `caddy docker-proxy`.

Run `caddy help docker-proxy` to see all available flags.

```text
Usage of docker-proxy:
  --caddyfile-path string
        Path to a base Caddyfile that will be extended with Docker sites
  --envfile
        Path to an environment file with environment variables in the KEY=VALUE format to load into the Caddy process
  --controller-network string
        Network allowed to configure Caddy server in CIDR notation. Ex: 10.200.200.0/24
  --ingress-networks string
        Comma separated name of ingress networks connecting Caddy servers to containers.
        When not defined, networks attached to controller container are considered ingress networks
  --docker-sockets
        Comma separated docker sockets
        When not defined, DOCKER_HOST (or default docker socket if DOCKER_HOST not defined)
  --docker-certs-path
        Comma separated cert path, you could use empty value when no cert path for the concern index docker socket like cert_path0,,cert_path2
  --docker-apis-version
        Comma separated apis version, you could use empty value when no api version for the concern index docker socket like cert_path0,,cert_path2
  --label-prefix string
        Prefix for Docker labels (default "caddy")
  --mode
        Which mode this instance should run: standalone | controller | server
  --polling-interval duration
        Interval Caddy should manually check Docker for a new Caddyfile (default 30s)
  --event-throttle-interval duration
        Interval to throttle caddyfile updates triggered by docker events (default 100ms)
  --process-caddyfile
        Process Caddyfile before loading it, removing invalid servers (default true)
  --proxy-service-tasks
        Proxy to service tasks instead of service load balancer (default true)
  --scan-stopped-containers
        Scan stopped containers and use their labels for Caddyfile generation (default false)
```