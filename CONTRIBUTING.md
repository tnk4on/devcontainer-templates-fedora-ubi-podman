# Contribution Plan for devcontainers/templates

## Overview

This document describes the process for adding Fedora, UBI, and Podman-in-Podman templates to the official [devcontainers/templates](https://github.com/devcontainers/templates) repository.

## Pre-check

According to the official repository's [README](https://github.com/devcontainers/templates#contributing-to-this-repository):

> This repository will accept improvement and bug fix contributions related to the current set of maintained templates.

For adding new templates, the following approaches are recommended:

1. **Host in your own repository**: Use [devcontainers/template-starter](https://github.com/devcontainers/template-starter)
2. **PR to official repository**: Improvements and bug fixes to existing templates

## Option 1: Host in Your Own Repository (Recommended)

### Steps

1. Create a new repository using [template-starter](https://github.com/devcontainers/template-starter) as a template

2. Copy templates:
```bash
cp -r /path/to/devcontainer-templates-fedora-ubi-podman/src/* src/
cp -r /path/to/devcontainer-templates-fedora-ubi-podman/test/* test/
```

3. Release via GitHub Actions (automatically configured)

4. After publishing, available at (repository name: `devcontainer-templates-fedora-ubi-podman`):
```
ghcr.io/<your-username>/devcontainer-templates-fedora-ubi-podman/fedora:latest
ghcr.io/<your-username>/devcontainer-templates-fedora-ubi-podman/ubi:latest
ghcr.io/<your-username>/devcontainer-templates-fedora-ubi-podman/podman-in-podman:latest
```

### Benefits

- Full control
- Immediate publication
- No waiting for official review

## Option 2: PR to Official Repository

### Steps

1. Fork & clone:
```bash
gh repo fork devcontainers/templates --clone
cd templates
git checkout -b add-fedora-ubi-podman
```

2. Copy templates:
```bash
cp -r /path/to/devcontainer-templates-fedora-ubi-podman/src/* src/
cp -r /path/to/devcontainer-templates-fedora-ubi-podman/test/* test/
```

3. Run tests:
```bash
# Build & test each template
cd src/fedora && devcontainer build --workspace-folder . && cd ../..
cd src/ubi && devcontainer build --workspace-folder . && cd ../..
cd src/podman-in-podman && devcontainer build --workspace-folder . && cd ../..
```

4. Commit & push:
```bash
git add src/fedora src/ubi src/podman-in-podman
git add test/fedora test/ubi test/podman-in-podman
git commit -m "feat: Add Fedora, UBI, and Podman-in-Podman templates"
git push origin add-fedora-ubi-podman
```

5. Create PR

### PR Description Template

```markdown
## Description

This PR adds three new templates to expand support for Red Hat ecosystem and Podman workflows.

### New Templates

#### 1. Fedora
- Fedora Linux-based development container
- Versions: 43, 42, 41, latest, rawhide
- Uses Dev Container Features for common utilities

#### 2. Red Hat UBI (Universal Base Image)
- Freely redistributable RHEL-compatible base
- UBI 10, 9, and 8 support
- Variants: ubi, ubi-minimal, ubi-init

#### 3. Podman-in-Podman
- Daemonless alternative to Docker-in-Docker
- Includes Buildah and Skopeo
- Supports both Fedora and UBI base images

## Motivation

1. **Fedora**: Popular development platform with no existing template
2. **UBI**: Enterprise developers need RHEL-compatible, freely redistributable containers
3. **Podman-in-Podman**: Growing demand for Docker-in-Docker alternatives

## Testing

- [ ] Tested on Linux with Podman
- [ ] Tested on macOS with Podman Desktop
- [ ] Tested on Windows with Podman Desktop
- [ ] Tested with Docker

## Checklist

- [x] Template structure follows existing patterns
- [x] Uses Dev Container Features where appropriate
- [x] Includes NOTES.md for documentation
- [x] Includes test scripts
- [x] Multi-architecture support (amd64, arm64)
```

## Related Issues

Before creating a PR, check/create related issues:

- [ ] Create a feature request Issue to gauge community interest
- [ ] Reference existing related issues if any

## Template Specification Checklist

Ensure each template meets the following:

### devcontainer-template.json

- [x] `id`: Unique identifier
- [x] `version`: Semantic version
- [x] `name`: Display name
- [x] `description`: Description
- [x] `documentationURL`: Documentation URL
- [x] `publisher`: Publisher name
- [x] `licenseURL`: License URL
- [x] `options`: Template options
- [x] `platforms`: Supported platforms
- [x] `optionalPaths`: Optional files

### .devcontainer/devcontainer.json

- [x] Use of template options (`${templateOption:xxx}`)
- [x] Utilization of Dev Container Features
- [x] Appropriate comments

### Dockerfile

- [x] Multi-architecture support
- [x] ARG for option input
- [x] Minimal installation

### NOTES.md

- [x] Usage instructions
- [x] Option descriptions
- [x] Podman compatibility notes

### test/

- [x] test.sh
- [x] test-utils-xxx.sh
