# Test all version and variant combinations for all templates (Windows PowerShell version)
#
# Supported environments:
#   - Windows + Podman (Podman Desktop)
#
# Usage: .\scripts\test-all-combinations.ps1 [-SkipFedora] [-SkipUbi] [-SkipPodman] [-OnlyFailed]
#
# Requirements:
#   - Node.js (with npm)
#   - Podman Desktop (with Podman Machine running)
#   - devcontainer CLI: npm install -g @devcontainers/cli

param(
    [switch]$SkipFedora,
    [switch]$SkipUbi,
    [switch]$SkipPodman,
    [switch]$OnlyFailed,
    [switch]$Help
)

# Script configuration
$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

# Find devcontainer CLI
$devcontainerCmd = "$env:APPDATA\npm\devcontainer.cmd"
if (-not (Test-Path $devcontainerCmd)) {
    $devcontainerCmd = "devcontainer"
}

# Log directories
$LogDir = Join-Path $RootDir ".test-logs"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$SummaryLogFile = Join-Path $LogDir "test-summary-$Timestamp.log"
$ResultFile = Join-Path $RootDir ".test-results.txt"

# Results tracking
$script:TotalTests = 0
$script:PassedTests = 0
$script:FailedTests = 0
$script:FailedList = @()

# ============================================================================
# Logging Functions
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Color = "White"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$ts] [$Level] $Message"
    Write-Host $logMsg -ForegroundColor $Color
    Add-Content -Path $SummaryLogFile -Value $logMsg -ErrorAction SilentlyContinue
}

function Write-Info { param([string]$msg) Write-Log $msg "INFO" "Green" }
function Write-Warn { param([string]$msg) Write-Log $msg "WARN" "Yellow" }
function Write-Err { param([string]$msg) Write-Log $msg "ERROR" "Red" }
function Write-Test { param([string]$msg) Write-Log $msg "TEST" "Blue" }
function Write-Env { param([string]$msg) Write-Log $msg "ENV" "Cyan" }

# ============================================================================
# Environment Detection
# ============================================================================

function Get-EnvironmentInfo {
    Write-Info "=========================================="
    Write-Info "Environment Information"
    Write-Info "=========================================="
    
    # OS Information
    $osInfo = Get-CimInstance Win32_OperatingSystem
    $arch = (Get-CimInstance Win32_ComputerSystem).SystemType
    Write-Env "OS: $($osInfo.Caption)"
    Write-Env "OS Version: $($osInfo.Version)"
    Write-Env "Architecture: $arch"
    
    # Container Runtime
    $podmanVersion = podman --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Env "Container Runtime: Podman"
        Write-Env "Runtime Version: $podmanVersion"
    } else {
        Write-Err "Podman not found. Please install Podman Desktop."
        exit 1
    }
    
    # devcontainer CLI
    $devcontainerVersion = & $devcontainerCmd --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Env "devcontainer CLI: $devcontainerVersion"
    } else {
        Write-Err "devcontainer CLI not found. Install with: npm install -g @devcontainers/cli"
        exit 1
    }
    
    # Node.js
    $nodeVersion = node --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Env "Node.js: $nodeVersion"
    }
    
    Write-Host ""
}

# ============================================================================
# Cleanup Functions
# ============================================================================

function Invoke-PodmanCleanup {
    Write-Info "Cleaning up Podman environment..."
    
    # Stop all running containers
    $runningContainers = podman ps -q 2>&1
    if ($runningContainers -and $LASTEXITCODE -eq 0 -and $runningContainers.Trim()) {
        Write-Host "  Stopping running containers..." -ForegroundColor Gray
        podman stop $runningContainers 2>&1 | Out-Null
    }
    
    # Remove all containers
    Write-Host "  Removing all containers..." -ForegroundColor Gray
    podman container prune -f 2>&1 | Out-Null
    
    # Remove unused images (but keep base images for faster subsequent tests)
    Write-Host "  Removing test-generated images..." -ForegroundColor Gray
    $testImages = podman images --filter "label=devcontainer.metadata" -q 2>&1
    if ($testImages -and $LASTEXITCODE -eq 0 -and $testImages.Trim()) {
        podman rmi $testImages 2>&1 | Out-Null
    }
    
    # Remove unused volumes
    Write-Host "  Removing unused volumes..." -ForegroundColor Gray
    podman volume prune -f 2>&1 | Out-Null
    
    Write-Host "  Cleanup complete" -ForegroundColor Gray
}

# ============================================================================
# Test Functions
# ============================================================================

function Invoke-TemplateTest {
    param(
        [string]$Template,
        [hashtable]$Options = @{}
    )
    
    $script:TotalTests++
    
    # Build test name
    $testName = $Template
    foreach ($key in $Options.Keys) {
        $testName += "-$key$($Options[$key])"
    }
    
    # Sanitize test name for filename
    $testName = $testName -replace '[^a-zA-Z0-9-]', ''
    $logFile = Join-Path $LogDir "test-$testName.log"
    
    $optionsDisplay = ($Options.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join " "
    Write-Test "Testing: $Template $optionsDisplay"
    
    # Show additional info for UBI
    if ($Template -eq "ubi" -and $Options.ContainsKey("imageVariant") -and $Options.ContainsKey("variant")) {
        $imageVariant = $Options["imageVariant"]
        $variant = $Options["variant"]
        Write-Info "   -> UBI_VERSION=$imageVariant, VARIANT=$variant"
        Write-Info "   -> Image: registry.access.redhat.com/ubi$imageVariant/${variant}:latest"
    }
    
    # Create test workspace
    $templateDir = Join-Path (Join-Path $RootDir "src") $Template
    $testDir = Join-Path (Join-Path $RootDir "test") $Template
    $testWorkspace = Join-Path $env:TEMP "devcontainer-test-$Template-$(Get-Random)"
    
    $startTime = Get-Date
    
    try {
        Add-Content -Path $logFile -Value "=== Test Start ===" -ErrorAction SilentlyContinue
        Add-Content -Path $logFile -Value "Template: $Template" -ErrorAction SilentlyContinue
        Add-Content -Path $logFile -Value "Options: $optionsDisplay" -ErrorAction SilentlyContinue
        Add-Content -Path $logFile -Value "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ErrorAction SilentlyContinue
        Add-Content -Path $logFile -Value "" -ErrorAction SilentlyContinue
        
        # Validate template exists
        if (-not (Test-Path $templateDir)) {
            throw "Template directory not found: $templateDir"
        }
        
        # Create test workspace and copy template
        New-Item -ItemType Directory -Path $testWorkspace -Force | Out-Null
        Copy-Item -Path "$templateDir\*" -Destination $testWorkspace -Recurse -Force
        
        Add-Content -Path $logFile -Value "=== Template copied to $testWorkspace ===" -ErrorAction SilentlyContinue
        
        # Replace template options in files
        $devcontainerJsonPath = Join-Path $testWorkspace ".devcontainer\devcontainer.json"
        $dockerfilePath = Join-Path $testWorkspace ".devcontainer\Dockerfile"
        $templateJsonPath = Join-Path $testWorkspace "devcontainer-template.json"
        
        # Read template.json to get option defaults
        $templateConfig = @{}
        if (Test-Path $templateJsonPath) {
            $templateJson = Get-Content $templateJsonPath -Raw | ConvertFrom-Json
            if ($templateJson.options) {
                $templateJson.options.PSObject.Properties | ForEach-Object {
                    $optName = $_.Name
                    $optDefault = $_.Value.default
                    if ($Options.ContainsKey($optName)) {
                        $templateConfig[$optName] = $Options[$optName]
                    } elseif ($optDefault) {
                        $templateConfig[$optName] = $optDefault
                    }
                }
            }
        }
        
        # Apply template options to files
        $filesToProcess = @()
        if (Test-Path $devcontainerJsonPath) { $filesToProcess += $devcontainerJsonPath }
        if (Test-Path $dockerfilePath) { $filesToProcess += $dockerfilePath }
        
        foreach ($file in $filesToProcess) {
            $content = Get-Content $file -Raw
            foreach ($optName in $templateConfig.Keys) {
                $placeholder = "`${templateOption:$optName}"
                $value = $templateConfig[$optName]
                $content = $content -replace [regex]::Escape($placeholder), $value
            }
            Set-Content -Path $file -Value $content -NoNewline
        }
        
        # Special handling for Podman-in-Podman: calculate PODMAN_TAG from imageVariant
        if ($Template -eq "podman-in-podman" -and $templateConfig.ContainsKey("imageVariant")) {
            $imageVariant = $templateConfig["imageVariant"]
            $podmanTag = ""
            
            # Note: 'stable' should never be used, but handle it defensively if it appears
            if ($imageVariant -eq "stable" -or $imageVariant -eq "latest") {
                $podmanTag = "latest"
            } elseif ($imageVariant.StartsWith("v")) {
                $podmanTag = $imageVariant
            } else {
                $podmanTag = "v$imageVariant"
            }
            
            Add-Content -Path $logFile -Value "  PODMAN_TAG = $podmanTag (calculated from imageVariant=$imageVariant)" -ErrorAction SilentlyContinue
            
            foreach ($file in $filesToProcess) {
                $content = Get-Content $file -Raw
                $content = $content -replace [regex]::Escape('${PODMAN_TAG:-latest}'), $podmanTag
                $content = $content -replace [regex]::Escape('${PODMAN_TAG}'), $podmanTag
                Set-Content -Path $file -Value $content -NoNewline
            }
        }
        
        Add-Content -Path $logFile -Value "=== Template options applied ===" -ErrorAction SilentlyContinue
        $templateConfig.GetEnumerator() | ForEach-Object {
            Add-Content -Path $logFile -Value "  $($_.Key) = $($_.Value)" -ErrorAction SilentlyContinue
        }
        
        # Copy test files
        if (Test-Path $testDir) {
            $testProjectDir = Join-Path $testWorkspace "test-project"
            New-Item -ItemType Directory -Path $testProjectDir -Force | Out-Null
            Copy-Item -Path "$testDir\*" -Destination $testProjectDir -Recurse -Force
        }
        
        # Create unique ID label
        $idLabel = "test-container=$Template-$([DateTimeOffset]::Now.ToUnixTimeSeconds())"
        
        Add-Content -Path $logFile -Value "`n=== Devcontainer Up ===" -ErrorAction SilentlyContinue
        
        # Run devcontainer up
        $upArgs = @(
            "up",
            "--id-label", $idLabel,
            "--workspace-folder", $testWorkspace,
            "--docker-path", "podman"
        )
        
        $upOutput = & $devcontainerCmd @upArgs 2>&1
        $upExitCode = $LASTEXITCODE
        
        Add-Content -Path $logFile -Value ($upOutput | Out-String) -ErrorAction SilentlyContinue
        Add-Content -Path $logFile -Value "Exit Code: $upExitCode" -ErrorAction SilentlyContinue
        
        $duration = ((Get-Date) - $startTime).TotalSeconds
        
        if ($upExitCode -eq 0 -or ($upOutput -join "`n") -match '"outcome":\s*"success"') {
            Write-Info "PASSED: $Template $optionsDisplay ($([math]::Round($duration, 2))s)"
            $script:PassedTests++
            Add-Content -Path $logFile -Value "`nResult: PASSED" -ErrorAction SilentlyContinue
        } else {
            throw "devcontainer up failed with exit code $upExitCode"
        }
    }
    catch {
        $duration = ((Get-Date) - $startTime).TotalSeconds
        Write-Err "FAILED: $Template $optionsDisplay"
        Write-Err "   Log: $logFile"
        Write-Err "   Error: $_"
        $script:FailedTests++
        $script:FailedList += "$Template $optionsDisplay"
        Add-Content -Path $ResultFile -Value "$Template $optionsDisplay" -ErrorAction SilentlyContinue
        Add-Content -Path $logFile -Value "`nResult: FAILED`nError: $_" -ErrorAction SilentlyContinue
    }
    finally {
        # Cleanup container
        try {
            Write-Host "  Stopping container..." -ForegroundColor Gray
            
            # Try to stop containers with the label
            $containers = podman ps -a --filter "label=$idLabel" -q 2>&1
            if ($containers -and $LASTEXITCODE -eq 0 -and $containers.Trim()) {
                podman rm -f $containers 2>&1 | Out-Null
            }
            
            # Also try devcontainer down
            & $devcontainerCmd down --workspace-folder $testWorkspace 2>&1 | Out-Null
        }
        catch { }
        
        # Remove test workspace
        if (Test-Path $testWorkspace) {
            Remove-Item -Path $testWorkspace -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-Fedora {
    if ($SkipFedora) {
        Write-Warn "Skipping Fedora tests"
        return
    }
    
    Write-Info "=========================================="
    Write-Info "Testing Fedora template"
    Write-Info "=========================================="
    
    $versions = @("43", "42", "41", "latest", "rawhide")
    
    foreach ($version in $versions) {
        Invoke-TemplateTest -Template "fedora" -Options @{ "imageVariant" = $version }
    }
}

function Test-Ubi {
    if ($SkipUbi) {
        Write-Warn "Skipping UBI tests"
        return
    }
    
    Write-Info "=========================================="
    Write-Info "Testing UBI template"
    Write-Info "=========================================="
    
    $versions = @("10", "9", "8")
    $variants = @("ubi", "ubi-minimal", "ubi-init")
    
    Write-Info "UBI versions to test: $($versions -join ', ')"
    Write-Info "UBI variants to test: $($variants -join ', ')"
    Write-Info "Total UBI combinations: $($versions.Count * $variants.Count)"
    Write-Host ""
    
    foreach ($version in $versions) {
        foreach ($variant in $variants) {
            Invoke-TemplateTest -Template "ubi" -Options @{ 
                "imageVariant" = $version
                "variant" = $variant 
            }
        }
    }
}

function Test-Podman {
    if ($SkipPodman) {
        Write-Warn "Skipping Podman-in-Podman tests"
        return
    }
    
    Write-Info "=========================================="
    Write-Info "Testing Podman-in-Podman template"
    Write-Info "=========================================="
    
    Invoke-TemplateTest -Template "podman-in-podman" -Options @{ "imageVariant" = "latest" }
}

function Invoke-FailedRetry {
    if (-not (Test-Path $ResultFile) -or (Get-Content $ResultFile -ErrorAction SilentlyContinue).Count -eq 0) {
        Write-Warn "No failed tests to retry"
        return
    }
    
    Write-Info "=========================================="
    Write-Info "Retrying failed tests"
    Write-Info "=========================================="
    
    $failedTests = Get-Content $ResultFile
    $retryCount = 0
    
    foreach ($line in $failedTests) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        
        $retryCount++
        $parts = $line -split ' '
        $template = $parts[0]
        $options = @{}
        
        for ($i = 1; $i -lt $parts.Count; $i++) {
            if ($parts[$i] -match '(.+)=(.+)') {
                $options[$matches[1]] = $matches[2]
            }
        }
        
        Write-Test "Retrying ($retryCount): $line"
        Invoke-TemplateTest -Template $template -Options $options
    }
}

# ============================================================================
# Main Execution
# ============================================================================

function Show-Help {
    Write-Host @"
Test all version and variant combinations for devcontainer templates (Windows)

Usage: .\test-all-combinations.ps1 [options]

Options:
    -SkipFedora     Skip Fedora template tests
    -SkipUbi        Skip UBI template tests
    -SkipPodman     Skip Podman-in-Podman template tests
    -OnlyFailed     Only retry previously failed tests
    -Help           Show this help message

Examples:
    .\test-all-combinations.ps1                    # Run all tests
    .\test-all-combinations.ps1 -SkipFedora        # Skip Fedora tests
    .\test-all-combinations.ps1 -OnlyFailed        # Retry failed tests

Requirements:
    - Podman Desktop with running Podman Machine
    - Node.js and npm
    - devcontainer CLI (npm install -g @devcontainers/cli)
"@
    exit 0
}

function Main {
    if ($Help) {
        Show-Help
    }
    
    # Create log directory first (before any logging)
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    
    Write-Info "=========================================="
    Write-Info "Testing All Template Combinations"
    Write-Info "=========================================="
    Write-Info "Start time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host ""
    
    # Detect environment
    Get-EnvironmentInfo
    
    # Clear previous results (unless retrying)
    if (-not $OnlyFailed) {
        if (Test-Path $ResultFile) { Remove-Item $ResultFile -Force }
        Get-ChildItem -Path $LogDir -Filter "test-*.log" -ErrorAction SilentlyContinue | Remove-Item -Force
    }
    
    # Initial cleanup
    Invoke-PodmanCleanup
    Write-Host ""
    
    # Run tests
    if ($OnlyFailed) {
        Invoke-FailedRetry
    } else {
        Test-Fedora
        Write-Host ""
        Test-Ubi
        Write-Host ""
        Test-Podman
        Write-Host ""
    }
    
    # Final cleanup
    Write-Info "=========================================="
    Write-Info "Final Cleanup"
    Write-Info "=========================================="
    Invoke-PodmanCleanup
    Write-Host ""
    
    # Print summary
    Write-Info "=========================================="
    Write-Info "Test Summary"
    Write-Info "=========================================="
    Write-Env "Environment: Windows + Podman"
    Write-Info "Total tests: $script:TotalTests"
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Passed: $script:PassedTests" -ForegroundColor Green
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Failed: $script:FailedTests" -ForegroundColor $(if ($script:FailedTests -gt 0) { "Red" } else { "Green" })
    Write-Info "End time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host ""
    
    if ($script:FailedTests -gt 0) {
        Write-Err "Failed tests:"
        foreach ($failed in $script:FailedList) {
            Write-Err "  - $failed"
        }
        Write-Host ""
        Write-Info "Failed test results saved to: $ResultFile"
        Write-Info "To retry failed tests, run: .\test-all-combinations.ps1 -OnlyFailed"
        Write-Host ""
        Write-Info "Log files saved to: $LogDir"
        Write-Info "Summary log: $SummaryLogFile"
        exit 1
    } else {
        Write-Info "All tests passed!"
        if (Test-Path $ResultFile) { Remove-Item $ResultFile -Force }
        Write-Host ""
        Write-Info "Log files saved to: $LogDir"
        Write-Info "Summary log: $SummaryLogFile"
        exit 0
    }
}

# Run main function
Main
