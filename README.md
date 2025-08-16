# Build Infra for XLibre Deb Repos

## Repositories

- Debian: https://github.com/xlibre-deb/debian
- (TODO) Devuan: https://github.com/xlibre-deb/devuan
- (TODO) Ubuntu: https://github.com/xlibre-deb/ubuntu

## Directory structure

- `misc/`
- `tasks/`: build tasks
- `matrix.yaml`: distro info

Untracked:

- `output/`: built packages
- `packages/`: workspace for packages
- `repos/`: workspace for repos

## Workflows

### Build
#### Requirements

- thor (ruby-thor)
- docker
- docker-buildx

#### Prepare build environments

1. Add your user to the `docker` group to use Docker without `sudo`.
  ```
  sudo groupadd docker
  sudo usermod -aG docker $USER
  # Restart system.
  ```
  You can skip this and use Docker with sudo, but the build output files will be owned by root.

2. Clone package source repositories.
  ```
  thor packages:clone
  ls packages/
  ```

3. (Optional) Use a remote BuildKit builder instance.
  ```
  thor build:use-remote-builder remote tcp://remote.buildkit.instance:1234
  ```

#### Build packages

```sh
# Generate docker-bake.hcl for targets (all by default) and build
thor build:bake:gen # [--targets] [--packages] [--arch]
thor build:bake

# Build single target without bake file
thor build:target debian-sid-amd64 # [--packages]

# List targets
thor build:list-targets

# Build packages on the host system without using Docker
sudo thor build:local --systemd # [--no-systemd] [--packages]
ls tmp/*.deb
```

The build results will be stored in the `output/` directory.

### Manage repos
#### Requirements

- thor (ruby-thor)
- apt-utils
- devscripts
- gpg (with signing key)

Clone the repositories:

```
thor repos:clone
ls repos/
```

#### Include packages

Add the built packages from the `output/` directory to the repos.

```
thor repos:include
```

#### Update repo metadata

```
thor repos:update
```

## Misc

See available tasks with `thor list`.
