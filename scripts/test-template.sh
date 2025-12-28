#!/bin/bash
# Test a single devcontainer template with Podman
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

# Check for devcontainer CLI
if ! command -v devcontainer &> /dev/null; then
    log_error "devcontainer CLI not found. Install with: npm install -g @devcontainers/cli"
    exit 1
fi

# Check for Podman
if ! command -v podman &> /dev/null; then
    log_error "Podman not found. Please install Podman first."
    exit 1
fi

# Check Podman machine is running (for macOS/Windows)
if [[ "$(uname)" == "Darwin" ]] || [[ "$(uname)" =~ MINGW|MSYS|CYGWIN ]]; then
    if ! podman machine list --format '{{.Running}}' | grep -q "true"; then
        log_warn "Podman machine may not be running. Starting..."
        podman machine start || true
    fi
fi

log_info "Podman version: $(podman --version)"
log_info "devcontainer CLI version: $(devcontainer --version)"

# Create a temporary working directory
WORK_DIR=$(mktemp -d)
OVERRIDE_FILE=$(mktemp)
trap "rm -rf ${WORK_DIR}; rm -f ${OVERRIDE_FILE}" EXIT

log_info "Working directory: ${WORK_DIR}"

# Copy template to working directory
cp -r "${TEMPLATE_DIR}/." "${WORK_DIR}/"

# Configure template options (replace ${templateOption:xxx} with defaults or provided values)
log_info "Configuring template options..."
TEMPLATE_JSON="${WORK_DIR}/devcontainer-template.json"

# Parse command-line option overrides (format: optionName=value)
# Store overrides in a temporary file to avoid using associative arrays (bash 3.x compatibility)
# OVERRIDE_FILE is already created above

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

# Make test files executable on host (before container starts)
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

# Use Podman socket
export DOCKER_HOST="unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null || echo '/var/run/docker.sock')"
log_info "DOCKER_HOST=${DOCKER_HOST}"

cd "${WORK_DIR}"

# Build and start the container
log_info "Starting devcontainer up..."
if ! devcontainer up --id-label "${ID_LABEL}" --workspace-folder "${WORK_DIR}"; then
    log_error "Failed to build/start devcontainer"
    exit 1
fi

log_info "Container started successfully!"

# Get the workspace folder name inside container
WORKSPACE_NAME=$(basename "${WORK_DIR}")
CONTAINER_WORKSPACE="/workspaces/${WORKSPACE_NAME}"

# Stub out VS Code server directories for test compatibility
log_info "Setting up test environment..."

# Get container ID to run commands as root
CONTAINER_ID=$(podman container ls -f "label=${ID_LABEL}" -q 2>/dev/null | head -1)
log_info "Container ID: ${CONTAINER_ID}"

if [ -n "${CONTAINER_ID}" ]; then
    # Fix permissions using podman directly (as root)
    log_info "Fixing workspace permissions..."
    podman exec -u root "${CONTAINER_ID}" chown -R vscode:vscode "${CONTAINER_WORKSPACE}" 2>/dev/null || true
    podman exec -u root "${CONTAINER_ID}" chmod -R 755 "${CONTAINER_WORKSPACE}" 2>/dev/null || true
    
    # Determine test user and create VS Code server dirs accordingly
    TEST_USER="vscode"
    if [ -f "${TEMPLATE_DIR}/.devcontainer/devcontainer.json" ]; then
        REMOTE_USER=$(grep '"remoteUser"' "${TEMPLATE_DIR}/.devcontainer/devcontainer.json" | grep -v '^\s*//' | sed -E 's/^[^"]*"remoteUser"[^"]*"([^"]+)".*/\1/' | head -1)
        if [ -n "${REMOTE_USER}" ]; then
            TEST_USER="${REMOTE_USER}"
        fi
    fi
    
    # Create VS Code server dirs for the test user
    if [ "${TEST_USER}" = "root" ]; then
        podman exec "${CONTAINER_ID}" mkdir -p /root/.vscode-server/bin /root/.vscode-server/extensions 2>/dev/null || true
    else
        podman exec "${CONTAINER_ID}" mkdir -p /home/${TEST_USER}/.vscode-server/bin /home/${TEST_USER}/.vscode-server/extensions 2>/dev/null || true
    fi
fi

# Run tests
log_info "Running tests..."
log_info "Workspace inside container: ${CONTAINER_WORKSPACE}"

# First, list what's in the workspace to debug
if [ -n "${CONTAINER_ID}" ]; then
    podman exec "${CONTAINER_ID}" ls -la "${CONTAINER_WORKSPACE}/" 2>&1 || echo "Cannot list workspace"
    podman exec "${CONTAINER_ID}" ls -la "${CONTAINER_WORKSPACE}/test-project/" 2>&1 || echo "test-project not found"
fi

if [ -n "${CONTAINER_ID}" ]; then
    log_info "Executing test script..."
    # Determine test user from original devcontainer.json (before sed replacement)
    # Read from template directory to avoid issues with sed-replaced values
    # Note: devcontainer.json may contain comments (JSONC), so use grep instead of jq
    TEST_USER="vscode"
    if [ -f "${TEMPLATE_DIR}/.devcontainer/devcontainer.json" ]; then
        # Extract remoteUser value using grep (handles JSONC with comments)
        # Exclude commented lines (starting with //) and get the first uncommented match
        REMOTE_USER=$(grep '"remoteUser"' "${TEMPLATE_DIR}/.devcontainer/devcontainer.json" | grep -v '^\s*//' | sed -E 's/^[^"]*"remoteUser"[^"]*"([^"]+)".*/\1/' | head -1)
        if [ -n "${REMOTE_USER}" ] && [ "${REMOTE_USER}" != "vscode" ]; then
            TEST_USER="${REMOTE_USER}"
        fi
    fi
    log_info "Running tests as user: ${TEST_USER}"
    podman exec -u "${TEST_USER}" "${CONTAINER_ID}" /bin/bash -c \
        "cd ${CONTAINER_WORKSPACE}/test-project && bash test.sh" 2>&1
    TEST_RESULT=$?
    
    if [ ${TEST_RESULT} -eq 0 ]; then
        log_info "✅ All tests passed for ${TEMPLATE_NAME}!"
    else
        log_error "❌ Tests failed for ${TEMPLATE_NAME} (exit code: ${TEST_RESULT})"
    fi
else
    log_error "Container not found!"
    TEST_RESULT=1
fi

# Cleanup
log_info "Cleaning up..."
CONTAINER_ID=$(podman container ls -f "label=${ID_LABEL}" -q 2>/dev/null || true)
if [ -n "${CONTAINER_ID}" ]; then
    podman rm -f "${CONTAINER_ID}" 2>/dev/null || true
fi

exit ${TEST_RESULT}


