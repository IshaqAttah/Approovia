# Distributed Go Web Services Infrastructure

This project provisions a distributed system with three virtual machines (`wg1`, `wg2`, and `wg3`) using Vagrant. It sets up secure networking via WireGuard, deploys two Go-based web services (`AppA` and `AppB`), configures a local Docker registry, reverse proxy via HAProxy, CI/CD with Drone CI, and monitoring using Prometheus + Grafana. Everything was set up and ran on a mac m1.

---

## What Was Done

### 1. Infrastructure Setup

- Three VMs (`wg1`, `wg2`, `wg3`) were provisioned with Vagrant.
- Static private IPs assigned (192.168.56.11–13).
- Docker installed on all nodes.

### 2. WireGuard VPN

- WireGuard configured on all three VMs.
- Each node communicates securely via tunnel interfaces (10.0.0.x).
- Nodes can ping each other over the tunnel.

### 3. Go Web Services

- `AppA` and `AppB` are two minimal Go apps returning:

- `Hello from A` and `Hello from B`

- Dockerized using multi-stage builds with non-root user.

### 4. Docker Registry

- A local registry was set up on `wg1` (port 5000).
- Docker images are built on `wg1` and pushed to the registry.

### 5. Deployment

- `deploy.sh` builds and pushes the images. SSHs into each node, pulls the latest images, and runs containers on ports `8081` and `8082`.

### 6. Reverse Proxy with HAProxy

- Installed HAProxy on `wg1`.
- Routes:

- `/service-a` → AppA (localhost:8081)
- `/service-b` → AppB (localhost:8082)

- SSL termination with self-signed certs implemented.
- HAProxy stats enabled at `/haproxy_stats`.

### 7. CI/CD with Drone

- Drone CI installed on `wg1`.
- `.drone.yml` pipeline:

- Runs unit tests
- Builds & pushes images
- SSHs into `wg2` and `wg3` to run `deploy.sh`

- Secrets (e.g., SSH keys, registry creds) managed via Drone secret store.

### 8. Monitoring

- Prometheus and Grafana deployed via Docker on `wg1`.
- Node Exporter and cAdvisor expose metrics from each node.
- Alerts defined for container restarts.
- Dashboards created in Grafana.

## How to Run It

1. Clone the repository and run `vagrant up` from the project root.
2. SSH into `wg1`, with vagrant ssh wg1 and run:

```bash
./deploy.sh
```

3. Visit:

- `http://192.168.56.11/service-a`
- `http://192.168.56.11/service-b`
- `http://192.168.56.11:3000` (Grafana)
- `http://192.168.56.11:8404/haproxy_stats`

## Assumptions Made

- All VMs use the same base box (Ubuntu 20.04).
- `wg1` acts as registry, reverse proxy, and monitoring hub.
- SSH access from `wg1` to `wg2` and `wg3` is passwordless (via Vagrant keys).
- Docker registry uses insecure HTTP (trusted internally).
- CI/CD runs from Drone CI hosted on `wg1`.

## Troubleshooting Tips

- WireGuard not connecting?

- Run `sudo wg show` on all nodes.
- Confirm correct `AllowedIPs` and public keys.

- Docker pull from registry fails?

- Add `"insecure-registries"` to `/etc/docker/daemon.json` on `wg2` and `wg3`.
- Restart Docker.

- Drone build fails?

- Check logs in `drone/drone` container.
- Confirm secrets are set properly.

- HAProxy returns 503?

- Ensure AppA and AppB containers are running and bound to ports 8081 and 8082.
- Use `curl localhost:8081` to test locally.

- Grafana not loading?

- Check if port `3000` is exposed.
- Default credentials: `admin / admin`.
