# Test a single devcontainer template with Podman or Docker (Windows PowerShell version)
# Uses devcontainer exec (same as official CI workflow)
#
# Supported environments:
#   - Windows + Podman (Podman Desktop)
#
# Usage: .\scripts\test-template.ps1 <template-name> [option-name=value ...]
# Examples:
#   .\scripts\test-template.ps1 fedora
#   .\scripts\test-template.ps1 fedora imageVariant=42
#   .\scripts\test-template.ps1 podman-in-podman imageVariant=latest
#   .\scripts\test-template.ps1 podman-in-podman imageVariant=latest installBuildah=false
#
# Requirements:
#   - Node.js (with npm)
#   - Podman Desktop (with Podman Machine running)
#   - devcontainer CLI: npm install -g @devcontainers/cli

param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$TemplateName,
    
    [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
    [string[]]$Options = @()
)

$ErrorActionPreference = "Continue"

# Script configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

# Find devcontainer CLI
$devcontainerCmd = "$env:APPDATA\npm\devcontainer.cmd"
if (-not (Test-Path $devcontainerCmd)) {
    $devcontainerCmd = "devcontainer"
}

# ============================================================================
# Logging Functions
# ============================================================================

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# ============================================================================
# Environment Detection
# ============================================================================

function Test-Environment {
    # Check Podman
    $podmanVersion = podman --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Podman not found. Please install Podman Desktop."
        exit 1
    }
    Write-Info "Podman version: $podmanVersion"
    
    # Check devcontainer CLI
    $devcontainerVersion = & $devcontainerCmd --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "devcontainer CLI not found. Install with: npm install -g @devcontainers/cli"
        exit 1
    }
    Write-Info "devcontainer CLI version: $devcontainerVersion"
    
    # Set Docker path for Podman
    $script:DockerPath = "podman"
    Write-Info "Environment: Windows + Podman"
}

# ============================================================================
# Main Script
# ============================================================================

# Check arguments
if (-not $TemplateName) {
    Write-Host "Usage: .\scripts\test-template.ps1 <template-name> [option-name=value ...]"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\scripts\test-template.ps1 fedora"
    Write-Host "  .\scripts\test-template.ps1 fedora imageVariant=42"
    Write-Host "  .\scripts\test-template.ps1 podman-in-podman imageVariant=latest"
    Write-Host "  .\scripts\test-template.ps1 podman-in-podman imageVariant=latest installBuildah=false"
    Write-Host ""
    Write-Host "Available templates:"
    Get-ChildItem -Path "$RootDir\src" -Directory | ForEach-Object { Write-Host "  $($_.Name)" }
    exit 1
}

$TemplateDir = Join-Path $RootDir "src\$TemplateName"
$TestDir = Join-Path $RootDir "test\$TemplateName"

# Validate template exists
if (-not (Test-Path $TemplateDir)) {
    Write-Err "Template '$TemplateName' not found in $RootDir\src\"
    exit 1
}

if (-not (Test-Path $TestDir)) {
    Write-Err "Test directory not found: $TestDir"
    exit 1
}

Write-Info "Testing template: $TemplateName"

# Test environment
Test-Environment

# Create a temporary working directory
$WorkDir = Join-Path $env:TEMP "devcontainer-test-$TemplateName-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

Write-Info "Working directory: $WorkDir"

# Copy template to working directory
Copy-Item -Path "$TemplateDir\*" -Destination $WorkDir -Recurse -Force

# Configure template options
Write-Info "Configuring template options..."
$TemplateJson = Join-Path $WorkDir "devcontainer-template.json"

# Parse command-line option overrides
$OverrideOptions = @{}
foreach ($opt in $Options) {
    if ($opt -match "^(.+?)=(.*)$") {
        $key = $matches[1]
        $value = $matches[2]
        $OverrideOptions[$key] = $value
        Write-Info "  Override: $key = $value"
    }
}

if (Test-Path $TemplateJson) {
    try {
        $templateConfig = Get-Content $TemplateJson | ConvertFrom-Json
        
        if ($templateConfig.options) {
            foreach ($optionName in $templateConfig.options.PSObject.Properties.Name) {
                $optionKey = "`${templateOption:$optionName}"
                
                # Get value (override or default)
                if ($OverrideOptions.ContainsKey($optionName)) {
                    $optionValue = $OverrideOptions[$optionName]
                } else {
                    $optionValue = $templateConfig.options.$optionName.default
                    if (-not $optionValue) {
                        continue
                    }
                }
                
                # Special handling for podman-in-podman: convert 'stable' to 'latest' (defensive)
                # Note: stable should never be used, but handle it if it appears
                if ($TemplateName -eq "podman-in-podman" -and $optionName -eq "imageVariant" -and $optionValue -eq "stable") {
                    $optionValue = "latest"
                }
                
                # Log the value (after conversion)
                if ($OverrideOptions.ContainsKey($optionName)) {
                    Write-Info "  Setting $optionName = $optionValue (override)"
                } else {
                    Write-Info "  Setting $optionName = $optionValue (default)"
                }
                
                # Replace in files
                $files = Get-ChildItem -Path $WorkDir -Include *.json, Dockerfile -Recurse
                foreach ($file in $files) {
                    $content = Get-Content $file.FullName -Raw
                    $content = $content -replace [regex]::Escape($optionKey), $optionValue
                    Set-Content -Path $file.FullName -Value $content -NoNewline
                }
            }
            
            # Special handling for Podman-in-Podman: calculate PODMAN_TAG from imageVariant
            # Note: imageVariant should be 'latest' or a version (e.g., '5.7.1', 'v5.7.1')
            # 'stable' should never be used, but handle it defensively if it appears
            if ($TemplateName -eq "podman-in-podman") {
                $imageVariant = if ($OverrideOptions.ContainsKey("imageVariant")) {
                    $OverrideOptions["imageVariant"]
                } else {
                    $templateConfig.options.imageVariant.default
                }
                
                # Convert 'stable' to 'latest' (defensive - should never happen)
                if ($imageVariant -eq "stable") {
                    $imageVariant = "latest"
                }
                
                if ($imageVariant) {
                    $podmanTag = if ($imageVariant -eq "latest") {
                        "latest"
                    } elseif ($imageVariant -match "^v") {
                        $imageVariant
                    } else {
                        "v$imageVariant"
                    }
                    
                    Write-Info "  Setting PODMAN_TAG = $podmanTag (calculated from imageVariant=$imageVariant)"
                    
                    # Replace PODMAN_TAG in files
                    $files = Get-ChildItem -Path $WorkDir -Include *.json, Dockerfile -Recurse
                    foreach ($file in $files) {
                        $content = Get-Content $file.FullName -Raw
                        $content = $content -replace '\$\{PODMAN_TAG:-latest\}', $podmanTag
                        $content = $content -replace '\$\{PODMAN_TAG\}', $podmanTag
                        Set-Content -Path $file.FullName -Value $content -NoNewline
                    }
                }
            }
        }
    } catch {
        Write-Warn "Failed to parse template options: $_"
    }
}

# Copy test files
Write-Info "Copying test files..."
$TestProjectDir = Join-Path $WorkDir "test-project"
New-Item -ItemType Directory -Path $TestProjectDir -Force | Out-Null
Copy-Item -Path "$TestDir\*" -Destination $TestProjectDir -Recurse -Force

# Build the devcontainer
Write-Info "Building devcontainer..."
$IdLabel = "test-container=$TemplateName-$(Get-Date -Format 'yyyyMMddHHmmss')"

Push-Location $WorkDir

# Build and start the container
Write-Info "Starting devcontainer up..."
$devcontainerArgs = @(
    "up",
    "--id-label", $IdLabel,
    "--workspace-folder", $WorkDir,
    "--docker-path", $script:DockerPath
)

$result = & $devcontainerCmd $devcontainerArgs
if ($LASTEXITCODE -ne 0) {
    Write-Err "Failed to build/start devcontainer"
    Pop-Location
    Remove-Item -Path $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Info "Container started successfully!"

# Get workspace folder name
$WorkspaceName = Split-Path -Leaf $WorkDir
$ContainerWorkspace = "/workspaces/$WorkspaceName"

# Wait a moment for container to be fully ready
Start-Sleep -Seconds 2

# Get container ID and verify it's running
$containerId = podman container ls --filter "label=$IdLabel" --format "{{.ID}}" | Select-Object -First 1
if (-not $containerId) {
    # Try to get stopped container and restart it
    $stoppedContainer = podman container ls -a --filter "label=$IdLabel" --format "{{.ID}}" | Select-Object -First 1
    if ($stoppedContainer) {
        Write-Info "Container found but stopped. Restarting..."
        podman start $stoppedContainer | Out-Null
        Start-Sleep -Seconds 2
        $containerId = $stoppedContainer
    }
}

# Create VS Code server dirs
Write-Info "Setting up test environment..."
Write-Info "Creating VS Code Server stubs..."
$mkdirCmd = 'mkdir -p $HOME/.vscode-server/bin $HOME/.vscode-server/extensions'
& $devcontainerCmd exec --workspace-folder $WorkDir --id-label $IdLabel --docker-path $script:DockerPath /bin/sh -c $mkdirCmd 2>&1 | Out-Null

# Run tests
Write-Info "Running tests..."
Write-Info "Using devcontainer exec (same as official CI workflow)"

# Get container ID
$containerId = podman container ls --filter "label=$IdLabel" --format "{{.ID}}" | Select-Object -First 1

# Copy test files to writable location inside container
if ($containerId) {
    Write-Info "Copying test files to container-local directory..."
    # Copy files and convert CRLF to LF (Windows line ending fix)
    $copyCmd = "cp -r $ContainerWorkspace/test-project /tmp/ && find /tmp/test-project -type f -exec sed -i 's/\r$//' {} \; && chown -R vscode:vscode /tmp/test-project/ && chmod -R 755 /tmp/test-project/"
    podman exec -u root $containerId sh -c $copyCmd 2>&1 | Out-Null
}

# Execute test script
Write-Info "Executing test script..."
# Write command to temporary file to avoid PowerShell escaping issues
$testScriptPath = Join-Path $env:TEMP "test-script-$(Get-Random).sh"
$testScriptContent = @'
#!/bin/sh
set -e
if [ -f "/tmp/test-project/test.sh" ]; then
    cd /tmp/test-project
    bash test.sh
else
    echo "test.sh not found"
    ls -la /tmp/test-project/ 2>/dev/null || echo "test-project dir not found"
fi
'@
# Use UTF8NoBOM encoding and Unix line endings (LF)
[System.IO.File]::WriteAllText($testScriptPath, $testScriptContent, [System.Text.UTF8Encoding]::new($false))

# Copy script to container and execute
if ($containerId) {
    # Copy script to container and ensure LF line endings
    podman cp $testScriptPath "${containerId}:/tmp/run-test.sh" 2>&1 | Out-Null
    podman exec -u root $containerId sh -c "sed -i 's/\r$//' /tmp/run-test.sh && chmod +x /tmp/run-test.sh" 2>&1 | Out-Null
    
    # Execute via devcontainer exec
    & $devcontainerCmd exec --workspace-folder $WorkDir --id-label $IdLabel --docker-path $script:DockerPath /bin/sh /tmp/run-test.sh
    $testResult = $LASTEXITCODE
} else {
    # Fallback: execute directly
    $testCmd = 'set -e && if [ -f "/tmp/test-project/test.sh" ]; then cd /tmp/test-project && bash test.sh; else echo "test.sh not found"; ls -la /tmp/test-project/ 2>/dev/null || echo "test-project dir not found"; fi'
    & $devcontainerCmd exec --workspace-folder $WorkDir --id-label $IdLabel --docker-path $script:DockerPath /bin/sh -c $testCmd
    $testResult = $LASTEXITCODE
}

# Cleanup temp file
Remove-Item -Path $testScriptPath -Force -ErrorAction SilentlyContinue

if ($testResult -eq 0) {
    Write-Info "✅ All tests passed for $TemplateName!"
} else {
    Write-Err "❌ Tests failed for $TemplateName (exit code: $testResult)"
}

# Cleanup
Write-Info "Cleaning up..."
if ($containerId) {
    podman rm -f $containerId 2>&1 | Out-Null
}

Pop-Location
Remove-Item -Path $WorkDir -Recurse -Force -ErrorAction SilentlyContinue

exit $testResult

