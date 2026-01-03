#!/bin/bash
# Test a single devcontainer template with Podman or Docker
# Uses devcontainer exec (same as official CI workflow)
# 
# Supported environments:
#   - macOS + Podman (local podman machine)
#   - Windows + Podman (Podman Desktop)
#   - Linux + Podman (rootless podman)
#   - Linux + Docker (Docker Engine)
#
# Usage: ./scripts/test-template.sh <template-name> [option-name=value ...]
# Examples:
#   ./scripts/test-template.sh fedora
#   ./scripts/test-template.sh fedora imageVariant=42
#   ./scripts/test-template.sh podman-in-podman imageVariant=v5.7.1
#   ./scripts/test-template.sh podman-in-podman imageVariant=v5.7.1 installBuildah=false

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================================
# Environment Detection
# ============================================================================

detect_environment() {
    # Detect OS
    case "$(uname -s)" in
        Linux)
            OS_TYPE="linux"
            ;;
        Darwin)
            OS_TYPE="macos"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            OS_TYPE="windows"
            ;;
        *)
            OS_TYPE="unknown"
            ;;
    esac

    # Detect container runtime
    CONTAINER_RUNTIME=""
    DOCKER_PATH=""
    
    if command -v podman &> /dev/null; then
        CONTAINER_RUNTIME="podman"
        DOCKER_PATH="podman"
    elif command -v docker &> /dev/null; then
        # Check if docker is actually podman (some systems alias docker to podman)
        if docker --version 2>&1 | grep -qi podman; then
            CONTAINER_RUNTIME="podman"
            DOCKER_PATH="docker"  # Use docker command but it's podman
        else
            CONTAINER_RUNTIME="docker"
            DOCKER_PATH="docker"
        fi
    fi

    # Log detected environment
    log_info "Environment: ${OS_TYPE} + ${CONTAINER_RUNTIME}"
}

# ============================================================================
# Container Runtime Setup
# ============================================================================

setup_container_runtime() {
    case "${CONTAINER_RUNTIME}" in
        podman)
            setup_podman
            ;;
        docker)
            setup_docker
            ;;
        *)
            log_error "No container runtime found. Please install Podman or Docker."
            exit 1
            ;;
    esac
}

setup_podman() {
    case "${OS_TYPE}" in
        macos)
            # macOS: Podman runs in a VM via podman machine
            if ! podman machine list --format '{{.Running}}' 2>/dev/null | grep -q "true"; then
                log_warn "Podman machine may not be running. Attempting to start..."
                podman machine start 2>/dev/null || true
                sleep 2
            fi
            
            # Get socket path from podman machine
            SOCKET_PATH=$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null || echo "")
            if [ -n "${SOCKET_PATH}" ]; then
                export DOCKER_HOST="unix://${SOCKET_PATH}"
            else
                log_warn "Could not get podman machine socket path, using default"
                export DOCKER_HOST="unix:///var/run/docker.sock"
            fi
            ;;
            
        windows)
            # Windows: Podman Desktop uses named pipe or socket
            # The DOCKER_HOST is typically set by Podman Desktop
            if [ -z "${DOCKER_HOST}" ]; then
                # Try common Windows Podman socket paths
                if [ -S "/run/podman/podman.sock" ]; then
                    export DOCKER_HOST="unix:///run/podman/podman.sock"
                elif [ -S "${HOME}/.local/share/containers/podman/machine/podman.sock" ]; then
                    export DOCKER_HOST="unix://${HOME}/.local/share/containers/podman/machine/podman.sock"
                fi
            fi
            ;;
            
        linux)
            # Linux: Native rootless podman uses user socket
            # Check if podman socket is available
            USER_SOCKET="/run/user/$(id -u)/podman/podman.sock"
            
            if [ -S "${USER_SOCKET}" ]; then
                export DOCKER_HOST="unix://${USER_SOCKET}"
            else
                # Try to enable podman socket
                if command -v systemctl &> /dev/null; then
                    systemctl --user start podman.socket 2>/dev/null || true
                    sleep 1
                fi
                
                if [ -S "${USER_SOCKET}" ]; then
                    export DOCKER_HOST="unix://${USER_SOCKET}"
                else
                    log_warn "Podman socket not found at ${USER_SOCKET}"
                    log_warn "Try: systemctl --user enable --now podman.socket"
                fi
            fi
            ;;
    esac
    
    log_info "Podman version: $(podman --version 2>/dev/null || echo 'unknown')"
    log_info "DOCKER_HOST=${DOCKER_HOST:-<not set>}"
}

setup_docker() {
    # Docker typically uses the default socket
    if [ -z "${DOCKER_HOST}" ]; then
        if [ -S "/var/run/docker.sock" ]; then
            export DOCKER_HOST="unix:///var/run/docker.sock"
        fi
    fi
    
    log_info "Docker version: $(docker --version 2>/dev/null || echo 'unknown')"
    log_info "DOCKER_HOST=${DOCKER_HOST:-<default>}"
}

# ============================================================================
# Get devcontainer options based on environment
# ============================================================================

get_devcontainer_options() {
    DEVCONTAINER_OPTS=()
    
    # Linux + Podman: Disable UID update to avoid buildx/podman compatibility issues
    # The docker-container driver in buildx can't access local images for the UID update build
    if [ "${OS_TYPE}" = "linux" ] && [ "${CONTAINER_RUNTIME}" = "podman" ]; then
        DEVCONTAINER_OPTS+=(--update-remote-user-uid-default off)
        log_info "Using --update-remote-user-uid-default off (Linux+Podman compatibility)"
    fi
}

# ============================================================================
# Main Script
# ============================================================================

# Check arguments
if [ -z "$1" ]; then
    echo "Usage: $0 <template-name> [option-name=value ...]"
    echo ""
    echo "Examples:"
    echo "  $0 fedora"
    echo "  $0 fedora imageVariant=42"
    echo "  $0 podman-in-podman imageVariant=v5.7.1"
    echo "  $0 podman-in-podman imageVariant=v5.7.1 installBuildah=false"
    echo ""
    echo "Supported environments:"
    echo "  - macOS + Podman"
    echo "  - Windows + Podman"
    echo "  - Linux + Podman"
    echo "  - Linux + Docker"
    echo ""
    echo "Available templates:"
    ls -1 "${ROOT_DIR}/src/"
    exit 1
fi

TEMPLATE_NAME="$1"
shift  # Remove template name from arguments
TEMPLATE_DIR="${ROOT_DIR}/src/${TEMPLATE_NAME}"
TEST_DIR="${ROOT_DIR}/test/${TEMPLATE_NAME}"

# Validate template exists
if [ ! -d "${TEMPLATE_DIR}" ]; then
    log_error "Template '${TEMPLATE_NAME}' not found in ${ROOT_DIR}/src/"
    exit 1
fi

if [ ! -d "${TEST_DIR}" ]; then
    log_error "Test directory not found: ${TEST_DIR}"
    exit 1
fi

log_info "Testing template: ${TEMPLATE_NAME}"

# Detect and setup environment
detect_environment
setup_container_runtime
get_devcontainer_options

# Check for devcontainer CLI
if ! command -v devcontainer &> /dev/null; then
    log_error "devcontainer CLI not found. Install with: npm install -g @devcontainers/cli"
    exit 1
fi
log_info "devcontainer CLI version: $(devcontainer --version)"

# Create a temporary working directory
WORK_DIR=$(mktemp -d)
chmod 755 "${WORK_DIR}"  # Make accessible from inside container (bind mount)

# Set SELinux context for container access (required on Fedora/RHEL with SELinux enforcing)
if command -v chcon &> /dev/null && [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
    chcon -Rt container_file_t "${WORK_DIR}" 2>/dev/null || true
fi

OVERRIDE_FILE=$(mktemp)
trap "rm -rf ${WORK_DIR}; rm -f ${OVERRIDE_FILE}" EXIT

log_info "Working directory: ${WORK_DIR}"

# Copy template to working directory
cp -r "${TEMPLATE_DIR}/." "${WORK_DIR}/"

# Configure template options (replace ${templateOption:xxx} with defaults or provided values)
log_info "Configuring template options..."
TEMPLATE_JSON="${WORK_DIR}/devcontainer-template.json"

# Parse command-line option overrides (format: optionName=value)
for arg in "$@"; do
    if echo "${arg}" | grep -q "="; then
        option_name=$(echo "${arg}" | cut -d'=' -f1)
        option_value=$(echo "${arg}" | cut -d'=' -f2-)
        echo "${option_name}=${option_value}" >> "${OVERRIDE_FILE}"
        log_info "  Override: ${option_name} = ${option_value}"
    fi
done

# Function to get override value (bash 3.x compatible)
get_override() {
    local option_name="$1"
    grep "^${option_name}=" "${OVERRIDE_FILE}" 2>/dev/null | cut -d'=' -f2- || echo ""
}

if [ -f "${TEMPLATE_JSON}" ]; then
    optionProp=$(jq -r '.options' "${TEMPLATE_JSON}")
    
    if [ "${optionProp}" != "" ] && [ "${optionProp}" != "null" ]; then
        options=$(jq -r '.options | keys[]' "${TEMPLATE_JSON}")
        
        for option in ${options}; do
            option_key="\${templateOption:${option}}"
            
            # Check if override is provided, otherwise use default
            override_value=$(get_override "${option}")
            if [ -n "${override_value}" ]; then
                option_value="${override_value}"
                log_info "  Setting ${option} = ${option_value} (override)"
            else
                option_value=$(jq -r ".options.${option}.default" "${TEMPLATE_JSON}")
                if [ "${option_value}" != "" ] && [ "${option_value}" != "null" ]; then
                    log_info "  Setting ${option} = ${option_value} (default)"
                else
                    continue
                fi
            fi
            
            # Escape special characters for sed
            option_value_escaped=$(printf '%s\n' "${option_value}" | sed -e 's/[\/&]/\\&/g')
            find "${WORK_DIR}" -type f \( -name "*.json" -o -name "Dockerfile" \) -exec \
                sed -i.bak "s/\${templateOption:${option}}/${option_value_escaped}/g" {} \;
        done
        
        # Special handling for Podman-in-Podman: calculate PODMAN_TAG from imageVariant
        if [ "${TEMPLATE_NAME}" = "podman-in-podman" ]; then
            image_variant=$(get_override "imageVariant")
            if [ -z "${image_variant}" ]; then
                image_variant=$(jq -r '.options.imageVariant.default' "${TEMPLATE_JSON}")
            fi
            
            if [ -n "${image_variant}" ] && [ "${image_variant}" != "null" ]; then
                podman_tag=""
                
                if [ "${image_variant}" = "stable" ] || [ "${image_variant}" = "latest" ]; then
                    podman_tag="latest"
                elif echo "${image_variant}" | grep -q "^v"; then
                    podman_tag="${image_variant}"
                else
                    podman_tag="v${image_variant}"
                fi
                
                log_info "  Setting PODMAN_TAG = ${podman_tag} (calculated from imageVariant=${image_variant})"
                podman_tag_escaped=$(printf '%s\n' "${podman_tag}" | sed -e 's/[\/&]/\\&/g')
                find "${WORK_DIR}" -type f \( -name "*.json" -o -name "Dockerfile" \) -exec \
                    sed -i.bak "s/\${PODMAN_TAG:-latest}/${podman_tag_escaped}/g" {} \; 2>/dev/null || true
                find "${WORK_DIR}" -type f \( -name "*.json" -o -name "Dockerfile" \) -exec \
                    sed -i.bak "s/\${PODMAN_TAG}/${podman_tag_escaped}/g" {} \; 2>/dev/null || true
            fi
        fi
    fi
fi

# Copy test files
log_info "Copying test files..."
mkdir -p "${WORK_DIR}/test-project"
cp -r "${TEST_DIR}/." "${WORK_DIR}/test-project/"

# Make test files readable and executable on host (before container starts)
chmod -R 755 "${WORK_DIR}/test-project/" 2>/dev/null || true
chmod +x "${WORK_DIR}/test-project/"*.sh 2>/dev/null || true

# Create test-utils.sh if not exists (simplified version)
if [ ! -f "${WORK_DIR}/test-project/test-utils.sh" ]; then
    cat > "${WORK_DIR}/test-project/test-utils.sh" << 'EOF'
#!/bin/bash
# Simplified test utilities for local testing

FAILED=()

check() {
    LABEL=$1
    shift
    echo -e "\n🧪 Testing $LABEL"
    if "$@"; then 
        echo "✅  Passed!"
        return 0
    else
        echo "❌ $LABEL check failed." >&2
        FAILED+=("$LABEL")
        return 1
    fi
}

reportResults() {
    if [ ${#FAILED[@]} -ne 0 ]; then
        echo -e "\n💥  Failed tests: ${FAILED[@]}" >&2
        exit 1
    else 
        echo -e "\n💯  All passed!"
        exit 0
    fi
}
EOF
fi

# Build the devcontainer
log_info "Building devcontainer..."
ID_LABEL="test-container=${TEMPLATE_NAME}-$(date +%s)"

cd "${WORK_DIR}"

# Build and start the container
log_info "Starting devcontainer up..."
if ! devcontainer up --id-label "${ID_LABEL}" --workspace-folder "${WORK_DIR}" "${DEVCONTAINER_OPTS[@]}"; then
    log_error "Failed to build/start devcontainer"
    exit 1
fi

log_info "Container started successfully!"

# Get the workspace folder name inside container
WORKSPACE_NAME=$(basename "${WORK_DIR}")
CONTAINER_WORKSPACE="/workspaces/${WORKSPACE_NAME}"

# Stub out VS Code server directories for test compatibility
log_info "Setting up test environment..."

# Create VS Code server dirs using devcontainer exec (same as official CI)
log_info "Creating VS Code Server stubs..."
devcontainer exec --workspace-folder "${WORK_DIR}" --id-label "${ID_LABEL}" --docker-path "${DOCKER_PATH}" /bin/sh -c \
    "mkdir -p \$HOME/.vscode-server/bin \$HOME/.vscode-server/extensions" 2>/dev/null || true

# Run tests using devcontainer exec (same as official CI)
log_info "Running tests..."
log_info "Using devcontainer exec (same as official CI workflow)"

# Get container ID to fix permissions if needed
CONTAINER_ID=""
if [ "${CONTAINER_RUNTIME}" = "podman" ]; then
    CONTAINER_ID=$(podman container ls -f "label=${ID_LABEL}" -q 2>/dev/null | head -1)
else
    CONTAINER_ID=$(docker container ls -f "label=${ID_LABEL}" -q 2>/dev/null | head -1)
fi

# Copy test files to a writable location inside container and execute
log_info "Copying test files to container-local directory..."
if [ -n "${CONTAINER_ID}" ]; then
    if [ "${CONTAINER_RUNTIME}" = "podman" ]; then
        podman exec -u root "${CONTAINER_ID}" sh -c "cp -r ${CONTAINER_WORKSPACE}/test-project /tmp/ && chown -R vscode:vscode /tmp/test-project/ && chmod -R 755 /tmp/test-project/" 2>/dev/null || true
    else
        docker exec -u root "${CONTAINER_ID}" sh -c "cp -r ${CONTAINER_WORKSPACE}/test-project /tmp/ && chown -R vscode:vscode /tmp/test-project/ && chmod -R 755 /tmp/test-project/" 2>/dev/null || true
    fi
fi

# Execute test script using devcontainer exec (same as official CI)
log_info "Executing test script..."
devcontainer exec --workspace-folder "${WORK_DIR}" --id-label "${ID_LABEL}" --docker-path "${DOCKER_PATH}" /bin/sh -c \
    'set -e && if [ -f "/tmp/test-project/test.sh" ]; then cd /tmp/test-project && bash test.sh; else echo "test.sh not found"; ls -la /tmp/test-project/ 2>/dev/null || echo "test-project dir not found"; fi' 2>&1
TEST_RESULT=$?

if [ ${TEST_RESULT} -eq 0 ]; then
    log_info "✅ All tests passed for ${TEMPLATE_NAME}!"
else
    log_error "❌ Tests failed for ${TEMPLATE_NAME} (exit code: ${TEST_RESULT})"
fi

# Cleanup
log_info "Cleaning up..."
if [ "${CONTAINER_RUNTIME}" = "podman" ]; then
    CONTAINER_ID=$(podman container ls -f "label=${ID_LABEL}" -q 2>/dev/null || true)
    if [ -n "${CONTAINER_ID}" ]; then
        podman rm -f "${CONTAINER_ID}" 2>/dev/null || true
    fi
else
    CONTAINER_ID=$(docker container ls -f "label=${ID_LABEL}" -q 2>/dev/null || true)
    if [ -n "${CONTAINER_ID}" ]; then
        docker rm -f "${CONTAINER_ID}" 2>/dev/null || true
    fi
fi

exit ${TEST_RESULT}
