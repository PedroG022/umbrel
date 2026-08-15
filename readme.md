<h1 align="center">umbrelOS<br />
<div align="center">
<a href="https://github.com/dockur/umbrel"><img src="https://raw.githubusercontent.com/dockur/umbrel/master/.github/header.png" title="Logo" style="max-width:100%;" width="256" /></a>
</div>
<div align="center">

[![Build]][build_url]
[![Version]][tag_url]
[![Size]][tag_url]
[![Package]][pkg_url]
[![Pulls]][hub_url]

</div></h1>

Docker container of [Umbrel](https://umbrel.com/umbrelos), an OS for self-hosting.

## Features ✨

- Runs UmbrelOS inside a Docker container
- Does not need dedicated hardware or a virtual machine
- Provides access to the Umbrel web interface
- Supports installing and running Umbrel apps
- Uses the host Docker daemon for app containers

## Quick Start 🚀

### 1. Proxmox VE (LXC Container)
Run the following command directly on your Proxmox VE host shell to create an LXC container with Docker and TUN pass-through:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/PedroG022/umbrel/refactor/proxmox-lxc.sh)"
```

### 2. Manual / Existing Linux Host

1. Clone the repository:
   ```bash
   git clone -b refactor https://github.com/PedroG022/umbrel.git
   cd umbrel
   ```

2. Run the interactive setup wizard:
   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

---

## Operating Modes 🌐

The setup script configures one of three network and access modes:

1. **Mode 1: Local Network Only (mDNS)**
   - Accessible at `http://umbrel.local`
   - Avahi mDNS discovery enabled, HTTP-only.
2. **Mode 2: Private Domain via VPN with SSL**
   - Accessible at `https://umbrel.<your-domain>/` (and wildcard `*.umbrel.<your-domain>`)
   - Automatic DNS-01 Let's Encrypt certificates via Traefik.
   - Mode-aware app subdomains (`https://<app>.umbrel.<your-domain>/`).
3. **Mode 3: Tailscale MagicDNS / Remote Network**
   - Accessible via Tailscale hostname (e.g. `http://<node>.<tailnet>.ts.net/`).

---

## Manual Docker Compose 🐳

```yaml
services:
  umbrel:
    image: ghcr.io/pedrog022/umbrel:latest
    container_name: umbrel
    pid: host
    network_mode: host
    volumes:
      - ./umbrel:/data
      - /var/run/docker.sock:/var/run/docker.sock
    restart: always
    stop_grace_period: 1m
```

## FAQ 💬

### How do I change the storage location?

  To change the storage location, include the following bind mount in your compose file:

  ```yaml
  volumes:
    - ./umbrel:/data
  ```

  Replace the example path `./umbrel` with the desired storage folder or named volume.

### How do I run CasaOS in a container?

  See [dockur/casa](https://github.com/dockur/casa) for a CasaOS container.

### How do I run ZimaOS in a container?

  See [dockur/zima](https://github.com/dockur/zima) for a ZimaOS container.

## Stars 🌟
[![Stargazers](https://raw.githubusercontent.com/star-stats/stars/refs/heads/data/charts/dockur-umbrel.svg)](https://github.com/dockur/umbrel/stargazers)

[build_url]: https://github.com/dockur/umbrel/
[hub_url]: https://hub.docker.com/r/dockurr/umbrel
[tag_url]: https://hub.docker.com/r/dockurr/umbrel/tags
[pkg_url]: https://github.com/dockur/umbrel/pkgs/container/umbrel

[Build]: https://github.com/dockur/umbrel/actions/workflows/build.yml/badge.svg
[Size]: https://img.shields.io/docker/image-size/dockurr/umbrel/latest?color=066da5&label=size
[Pulls]: https://img.shields.io/docker/pulls/dockurr/umbrel.svg?style=flat&label=pulls&logo=docker
[Version]: https://img.shields.io/docker/v/dockurr/umbrel/latest?arch=amd64&sort=semver&color=066da5
[Package]:https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fipitio.github.io%2Fbackage%2Fdockur%2Fumbrel%2Fumbrel.json&query=%24.downloads&logo=github&style=flat&color=066da5&label=pulls
