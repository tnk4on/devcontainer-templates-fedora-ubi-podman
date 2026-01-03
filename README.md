# Dev Container Templates: Fedora, UBI, Podman-in-Podman

A collection of Dev Container templates for Fedora, UBI, and Podman-in-Podman.

These templates are also intended for contribution to [devcontainers/templates](https://github.com/devcontainers/templates).

## Template List

| Template | Description | Base Image |
|----------|-------------|------------|
| [Fedora](src/fedora) | Fedora Linux-based development container | `registry.fedoraproject.org/fedora` |
| [UBI](src/ubi) | Red Hat Universal Base Image | `registry.access.redhat.com/ubi{8,9,10}` |
| [Podman-in-Podman](src/podman-in-podman) | Nested container operations | Fedora-based (`quay.io/podman/stable`) |

## Directory Structure

```
devcontainer-templates-fedora-ubi-podman/
├── src/                        # Template sources
│   ├── fedora/
│   │   ├── .devcontainer/
│   │   │   ├── devcontainer.json
│   │   │   └── Dockerfile
│   │   ├── devcontainer-template.json
│   │   └── NOTES.md
│   ├── ubi/
│   │   ├── .devcontainer/
│   │   │   ├── devcontainer.json
│   │   │   └── Dockerfile
│   │   ├── devcontainer-template.json
│   │   └── NOTES.md
│   └── podman-in-podman/
│       ├── .devcontainer/
│       │   ├── devcontainer.json
│       │   └── Dockerfile
│       ├── devcontainer-template.json
│       └── NOTES.md
├── test/                       # Test scripts
│   ├── fedora/
│   │   ├── test.sh
│   │   └── test-utils-fedora.sh
│   ├── ubi/
│   │   ├── test.sh
│   │   └── test-utils-ubi.sh
│   └── podman-in-podman/
│       ├── test.sh
│       └── test-utils-fedora.sh
├── scripts/                    # Test scripts
│   ├── test-all-combinations.sh    # Bash script (macOS/Linux)
│   ├── test-all-combinations.ps1   # PowerShell script (Windows)
│   ├── test-template.sh            # Bash script (macOS/Linux)
│   └── test-template.ps1           # PowerShell script (Windows)
├── CONTRIBUTING.md
├── LICENSE
└── README.md
```

## Local Testing

### Prerequisites

- Podman (5.0+) or Docker
- [@devcontainers/cli](https://github.com/devcontainers/cli)
- jq (for test scripts)

```bash
# Install devcontainer CLI
npm install -g @devcontainers/cli

# macOS/Windows: Ensure Podman machine is running
podman machine start
```

### Testing Methods

#### 1. Test Single Template (Recommended)

**macOS/Windows: Ensure Podman machine is running**
```bash
# macOS
podman machine start

# Windows (PowerShell)
podman machine start
```

**macOS/Linux:**
```bash
# Test Fedora template (default options)
./scripts/test-template.sh fedora

# Test Fedora template with specific version
./scripts/test-template.sh fedora imageVariant=42

# Test UBI template
./scripts/test-template.sh ubi

# Test UBI template with specific version and variant
./scripts/test-template.sh ubi ubiVersion=9 variant=ubi-minimal

# Test Podman-in-Podman template (default options)
./scripts/test-template.sh podman-in-podman

# Test Podman-in-Podman with specific Podman version
./scripts/test-template.sh podman-in-podman imageVariant=latest

# Test Podman-in-Podman with custom options
./scripts/test-template.sh podman-in-podman imageVariant=latest installBuildah=false installSkopeo=false
```

**Windows (PowerShell):**
```powershell
# Test Fedora template (default options)
.\scripts\test-template.ps1 fedora

# Test Fedora template with specific version
.\scripts\test-template.ps1 fedora imageVariant=42

# Test UBI template
.\scripts\test-template.ps1 ubi

# Test UBI template with specific version and variant
.\scripts\test-template.ps1 ubi imageVariant=9 variant=ubi-minimal

# Test Podman-in-Podman template (default options)
.\scripts\test-template.ps1 podman-in-podman

# Test Podman-in-Podman with specific Podman version
.\scripts\test-template.ps1 podman-in-podman imageVariant=latest

# Test Podman-in-Podman with custom options
.\scripts\test-template.ps1 podman-in-podman imageVariant=latest installBuildah=false installSkopeo=false
```

**Usage:**
- **macOS/Linux:** `./scripts/test-template.sh <template-name> [option-name=value ...]`
- **Windows:** `.\scripts\test-template.ps1 <template-name> [option-name=value ...]`

**Available Options:**

- **Fedora**: `imageVariant` (e.g., `43`, `42`, `41`, `latest`, `rawhide`)
- **UBI**: `ubiVersion` (e.g., `10`, `9`, `8`), `variant` (e.g., `ubi`, `ubi-minimal`, `ubi-init`)
- **Podman-in-Podman**: 
  - `imageVariant` (e.g., `latest`, `v5.7.1`, `v5.7`, `v5`, `5.7.1`)
  - `installBuildah` (e.g., `true`, `false`)
  - `installSkopeo` (e.g., `true`, `false`)

#### 2. Test All Version and Variant Combinations

Test all supported combinations of versions and variants for each template:

**macOS / Linux (Bash):**
```bash
# Test all combinations
./scripts/test-all-combinations.sh

# Test only specific templates
./scripts/test-all-combinations.sh --skip-ubi --skip-podman  # Fedora only
./scripts/test-all-combinations.sh --skip-fedora              # UBI and Podman only

# Retry only failed tests
./scripts/test-all-combinations.sh --only-failed
```

**Windows (PowerShell):**
```powershell
# Test all combinations
.\scripts\test-all-combinations.ps1

# Test only specific templates
.\scripts\test-all-combinations.ps1 -SkipUbi -SkipPodman  # Fedora only
.\scripts\test-all-combinations.ps1 -SkipFedora            # UBI and Podman only

# Retry only failed tests
.\scripts\test-all-combinations.ps1 -OnlyFailed

# Show help
.\scripts\test-all-combinations.ps1 -Help
```

**Tested Combinations:**
- **Fedora** (5): 43, 42, 41, latest, rawhide
- **UBI** (9): Versions (10, 9, 8) × Variants (ubi, ubi-minimal, ubi-init)
- **Podman-in-Podman** (1): latest

**Total: 15 combinations**

### Manual Testing in VS Code

```bash
# Copy template to project
mkdir -p ~/my-project
cp -r src/fedora/.devcontainer ~/my-project/

# Open in VS Code
code ~/my-project

# Run "Reopen in Container" from command palette
```

### Cross-Platform Testing

The test scripts support multiple environments:

| Environment | Script | Container Runtime |
|-------------|--------|-------------------|
| macOS + Podman | `test-all-combinations.sh` | Podman Machine (libkrun) |
| Linux + Podman | `test-all-combinations.sh` | Rootless Podman |
| Linux + Docker | `test-all-combinations.sh` | Docker Engine |
| Windows + Podman | `test-all-combinations.ps1` | Podman Machine (WSL2) |

**Requirements by Platform:**

- **macOS**: Podman Desktop with Podman Machine, Node.js, devcontainer CLI
- **Linux + Podman**: Podman 5.0+, `podman.socket` enabled, Node.js, devcontainer CLI
- **Linux + Docker**: Docker Engine, Node.js, devcontainer CLI
- **Windows**: Podman Desktop with Podman Machine, Node.js, devcontainer CLI

**Enable Podman Socket on Linux (required for rootless Podman):**
```bash
systemctl --user enable --now podman.socket
```

### Test Script Structure

```
scripts/
├── test-template.sh          # Complete test for single template (Bash)
├── test-all-combinations.sh  # Test all version/variant combinations (Bash)
└── test-all-combinations.ps1 # Test all version/variant combinations (PowerShell)

test/
├── fedora/
│   └── test.sh        # Fedora-specific tests
├── ubi/
│   └── test.sh        # UBI-specific tests
└── podman-in-podman/
    └── test.sh        # Podman-in-Podman-specific tests
```

## Repository Information

**Repository Name**: `devcontainer-templates-fedora-ubi-podman`

This repository provides Dev Container templates for Fedora, UBI, and Podman-in-Podman.

## Contributing to devcontainers/templates

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

### Overview

1. Fork [devcontainers/templates](https://github.com/devcontainers/templates)
2. Copy templates to `src/`
3. Copy tests to `test/`
4. Create a PR

## Related Links

- [Dev Container Specification](https://containers.dev/)
- [devcontainers/templates](https://github.com/devcontainers/templates)
- [devcontainers/features](https://github.com/devcontainers/features)
- [Podman](https://podman.io/)
- [Red Hat UBI](https://www.redhat.com/en/blog/introducing-red-hat-universal-base-image)

## License

MIT License
