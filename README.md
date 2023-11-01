# ppa-vgpu-unlock-rs

Personal Package Archive for libvgpu-unlock-rs

## What is libvgpu-unlock-rs?

Unlock vGPU functionality for consumer-grade NVIDIA GPUs.

## Supported platforms

- Debian 11 (bullseye)
- Debian 12 (bookworm)
- Ubuntu 20.04 (focal)
- Ubuntu 22.04 (jammy)

## Install required packages

```
sudo apt-get update
```

```
sudo apt-get install apt-transport-https wget ca-certificates lsb-release
```

## Download GPG public key

```
sudo mkdir -p -m 0755 /etc/apt/keyrings
```

```
sudo wget -O /etc/apt/keyrings/ppa-vgpu-unlock-rs.asc https://gorockn.github.io/ppa-vgpu-unlock-rs/public.gpg.asc
```

## Configure APT sources.list

```
echo "deb [signed-by=/etc/apt/keyrings/ppa-vgpu-unlock-rs.asc] https://gorockn.github.io/ppa-vgpu-unlock-rs $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/ppa-vgpu-unlock-rs.list
```

## Install package

```
sudo apt-get update
```

```
sudo apt-get install libvgpu-unlock-rs
```

## Reference

- Origin Repository
  - https://github.com/mbilker/vgpu_unlock-rs
