#!/bin/bash
# Test all version and variant combinations for all templates
#
# Supported environments:
#   - macOS + Podman (local podman machine)
#   - Linux + Podman (rootless podman)
#   - Linux + Docker (Docker Engine)
#
# For Windows + Podman (Podman Desktop):
#   Use the PowerShell script: .\scripts\test-all-combinations.ps1
#
# Usage: ./scripts/test-all-combinations.sh [--skip-fedora] [--skip-ubi] [--skip-podman] [--only-failed]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source nvm if devcontainer is not in PATH (common on Linux servers)
if ! command -v devcontainer &> /dev/null; then
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        . "$NVM_DIR/nvm.sh"
    elif [ -s "$HOME/.nvm/nvm.sh" ]; then
        export NVM_DIR="$HOME/.nvm"
        . "$NVM_DIR/nvm.sh"
    fi
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_test() { echo -e "${BLUE}[TEST]${NC} $1"; }
log_env() { echo -e "${CYAN}[ENV]${NC} $1"; }

# ============================================================================
# Environment Detection
# ============================================================================

detect_environment() {
    # Detect OS
    case "$(uname -s)" in
        Linux)
            OS_TYPE="Linux"
            ;;
        Darwin)
            OS_TYPE="macOS"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            OS_TYPE="Windows"
            ;;
        *)
            OS_TYPE="Unknown"
            ;;
    esac

    # Detect container runtime
    CONTAINER_RUNTIME=""
    
    if command -v podman &> /dev/null; then
        CONTAINER_RUNTIME="Podman"
        RUNTIME_VERSION=$(podman --version 2>/dev/null | head -1 || echo "unknown")
    elif command -v docker &> /dev/null; then
        # Check if docker is actually podman
        if docker --version 2>&1 | grep -qi podman; then
            CONTAINER_RUNTIME="Podman"
            RUNTIME_VERSION=$(docker --version 2>/dev/null | head -1 || echo "unknown")
        else
            CONTAINER_RUNTIME="Docker"
            RUNTIME_VERSION=$(docker --version 2>/dev/null | head -1 || echo "unknown")
        fi
    else
        log_error "No container runtime found. Please install Podman or Docker."
        exit 1
    fi

    # Get devcontainer CLI version
    if command -v devcontainer &> /dev/null; then
        DEVCONTAINER_VERSION=$(devcontainer --version 2>/dev/null || echo "unknown")
    else
        log_error "devcontainer CLI not found. Install with: npm install -g @devcontainers/cli"
        exit 1
    fi

    # Display environment info
    log_info "=========================================="
    log_info "Environment Information"
    log_info "=========================================="
    log_env "OS: ${OS_TYPE}"
    log_env "Container Runtime: ${CONTAINER_RUNTIME}"
    log_env "Runtime Version: ${RUNTIME_VERSION}"
    log_env "devcontainer CLI: ${DEVCONTAINER_VERSION}"
    
    # Show kernel/OS details
    if [ "${OS_TYPE}" = "Linux" ]; then
        if [ -f /etc/os-release ]; then
            DISTRO=$(grep -E "^PRETTY_NAME=" /etc/os-release | cut -d'"' -f2)
            log_env "Distribution: ${DISTRO}"
        fi
        log_env "Kernel: $(uname -r)"
    elif [ "${OS_TYPE}" = "macOS" ]; then
        log_env "macOS Version: $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
    fi
    
    echo ""
}

# Parse arguments
SKIP_FEDORA=false
SKIP_UBI=false
SKIP_PODMAN=false
ONLY_FAILED=false

for arg in "$@"; do
    case $arg in
        --skip-fedora)
            SKIP_FEDORA=true
            shift
            ;;
        --skip-ubi)
            SKIP_UBI=true
            shift
            ;;
        --skip-podman)
            SKIP_PODMAN=true
            shift
            ;;
        --only-failed)
            ONLY_FAILED=true
            shift
            ;;
        *)
            log_error "Unknown option: $arg"
            echo "Usage: $0 [--skip-fedora] [--skip-ubi] [--skip-podman] [--only-failed]"
            echo ""
            echo "Supported environments:"
            echo "  - macOS + Podman"
            echo "  - Windows + Podman"
            echo "  - Linux + Podman"
            echo "  - Linux + Docker"
            exit 1
            ;;
    esac
done

# Results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
FAILED_LIST=()

# Test result file
RESULT_FILE="${ROOT_DIR}/.test-results.txt"
LOG_DIR="${ROOT_DIR}/.test-logs"
mkdir -p "${LOG_DIR}"

# Function to run a single test
run_test() {
    local template=$1
    shift
    local options=("$@")
    local test_name="${template}"
    local option_str=""
    
    for opt in "${options[@]}"; do
        option_str="${option_str} ${opt}"
        test_name="${test_name}-${opt//=/}"
    done
    
    # Sanitize test name for filename
    test_name=$(echo "${test_name}" | tr ' ' '-' | tr '=' '-' | sed 's/--/-/g' | sed 's/[^a-zA-Z0-9-]//g')
    local log_file="${LOG_DIR}/test-${test_name}.log"
    
    log_test "Testing: ${template}${option_str}"
    
    # For UBI, show the actual values being used
    if [ "${template}" = "ubi" ]; then
        image_variant=""
        variant_value=""
        for opt in "${options[@]}"; do
            if echo "${opt}" | grep -q "imageVariant="; then
                image_variant=$(echo "${opt}" | cut -d'=' -f2-)
            elif echo "${opt}" | grep -q "variant="; then
                variant_value=$(echo "${opt}" | cut -d'=' -f2-)
            fi
        done
        if [ -n "${image_variant}" ] && [ -n "${variant_value}" ]; then
            log_info "   → UBI_VERSION=${image_variant}, VARIANT=${variant_value}"
            log_info "   → Image: registry.access.redhat.com/ubi${image_variant}/${variant_value}:latest"
        fi
    fi
    
    if "${SCRIPT_DIR}/test-template.sh" "${template}" "${options[@]}" > "${log_file}" 2>&1; then
        log_info "✅ PASSED: ${template}${option_str}"
        # Use file-based counter for parallel execution safety
        echo "PASS" >> "${LOG_DIR}/.test-counter"
        return 0
    else
        log_error "❌ FAILED: ${template}${option_str}"
        log_error "   Log: ${log_file}"
        # Use file-based counter for parallel execution safety
        echo "FAIL" >> "${LOG_DIR}/.test-counter"
        echo "${template}${option_str}" >> "${RESULT_FILE}"
        return 1
    fi
}

# Function to test Fedora combinations
test_fedora() {
    if [ "${SKIP_FEDORA}" = true ]; then
        log_warn "Skipping Fedora tests"
        return
    fi
    
    log_info "=========================================="
    log_info "Testing Fedora template"
    log_info "=========================================="
    
    local versions=("43" "42" "41" "latest" "rawhide")
    
    for version in "${versions[@]}"; do
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        run_test "fedora" "imageVariant=${version}"
    done
}

# Function to test UBI combinations
test_ubi() {
    if [ "${SKIP_UBI}" = true ]; then
        log_warn "Skipping UBI tests"
        return
    fi
    
    log_info "=========================================="
    log_info "Testing UBI template"
    log_info "=========================================="
    
    local versions=("10" "9" "8")
    local variants=("ubi" "ubi-minimal" "ubi-init")
    
    log_info "UBI versions to test: ${versions[*]}"
    log_info "UBI variants to test: ${variants[*]}"
    log_info "Total UBI combinations: $((${#versions[@]} * ${#variants[@]}))"
    echo ""
    
    for version in "${versions[@]}"; do
        for variant in "${variants[@]}"; do
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
            log_test "UBI ${version} variant=${variant} (imageVariant=${version} variant=${variant})"
            run_test "ubi" "imageVariant=${version}" "variant=${variant}"
        done
    done
}

# Function to test Podman-in-Podman combinations
test_podman() {
    if [ "${SKIP_PODMAN}" = true ]; then
        log_warn "Skipping Podman-in-Podman tests"
        return
    fi
    
    log_info "=========================================="
    log_info "Testing Podman-in-Podman template"
    log_info "=========================================="
    
    # Test latest only
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    run_test "podman-in-podman" "imageVariant=latest"
}

# Function to retry failed tests
retry_failed() {
    if [ ! -f "${RESULT_FILE}" ] || [ ! -s "${RESULT_FILE}" ]; then
        log_warn "No failed tests to retry"
        return
    fi
    
    log_info "=========================================="
    log_info "Retrying failed tests"
    log_info "=========================================="
    
    local retry_count=0
    while IFS= read -r line; do
        if [ -z "$line" ]; then
            continue
        fi
        
        # Parse the failed test line
        # Format: "template option1=value1 option2=value2"
        local template=$(echo "$line" | awk '{print $1}')
        local options_str=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
        
        # Convert options string to array
        local options=()
        for opt in ${options_str}; do
            options+=("${opt}")
        done
        
        retry_count=$((retry_count + 1))
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        log_test "Retrying (${retry_count}): ${template} ${options_str}"
        
        if run_test "${template}" "${options[@]}"; then
            # Remove from failed list
            grep -v "^${line}$" "${RESULT_FILE}" > "${RESULT_FILE}.tmp" && mv "${RESULT_FILE}.tmp" "${RESULT_FILE}"
        fi
    done < "${RESULT_FILE}"
}

# Main execution
main() {
    log_info "=========================================="
    log_info "Testing All Template Combinations"
    log_info "=========================================="
    log_info "Start time: $(date)"
    echo ""
    
    # Detect environment first
    detect_environment
    
    # Clear previous results
    > "${RESULT_FILE}"
    rm -rf "${LOG_DIR}"
    mkdir -p "${LOG_DIR}"
    
    # Run tests
    if [ "${ONLY_FAILED}" = true ]; then
        retry_failed
    else
        test_fedora
        echo ""
        test_ubi
        echo ""
        test_podman
        echo ""
    fi
    
    # Count results from counter file
    if [ -f "${LOG_DIR}/.test-counter" ]; then
        PASSED_TESTS=$(grep -c "^PASS$" "${LOG_DIR}/.test-counter" 2>/dev/null || echo "0")
        FAILED_TESTS=$(grep -c "^FAIL$" "${LOG_DIR}/.test-counter" 2>/dev/null || echo "0")
    fi
    
    # Print summary
    log_info "=========================================="
    log_info "Test Summary"
    log_info "=========================================="
    log_env "Environment: ${OS_TYPE} + ${CONTAINER_RUNTIME}"
    log_info "Total tests: ${TOTAL_TESTS}"
    log_info "Passed: ${GREEN}${PASSED_TESTS}${NC}"
    log_info "Failed: ${RED}${FAILED_TESTS}${NC}"
    log_info "End time: $(date)"
    echo ""
    
    if [ "${FAILED_TESTS}" -gt 0 ] 2>/dev/null; then
        log_error "Failed tests:"
        for failed in "${FAILED_LIST[@]}"; do
            log_error "  - ${failed}"
        done
        echo ""
        log_info "Failed test results saved to: ${RESULT_FILE}"
        log_info "To retry failed tests, run: $0 --only-failed"
        echo ""
        exit 1
    else
        log_info "✅ All tests passed!"
        rm -f "${RESULT_FILE}"
        echo ""
        exit 0
    fi
}

# Run main function
main
