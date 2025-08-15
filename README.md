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

```
# Build for all distributions, releases, and architectures
thor build:bake:gen # Creates docker-bake.hcl
thor build:bake

# Build for specific targets
thor build:bake:gen --targets debian-trixie-amd64 debian-forky-amd64
thor build:bake

# Build specific package(s) only
thor build:bake:gen --packages xlibre-server xserver-xlibre-input-libinput
thor build:bake

# Build single target without bake file
thor build:target debian-sid-amd64 # [--packages]

# List targets
thor build:list-targets
```

The build results will be stored in the `output/` directory.

### Manage repos
#### Requirements

- thor (ruby-thor)
- apt-utils
- devscripts
- xv
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
