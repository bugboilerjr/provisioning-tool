# =============================================================
# bootstrap.ps1 - Windows provisioning entry point
# =============================================================
# Loaded over the wire via:
#   iex (irm <BaseUrl>/bootstrap.ps1)
#
# Downloads its companion files (apps.json, policies/*, office/*)
# from the same repo and applies them in order:
#   1. Verify elevation + winget
#   2. Install apps from apps.json via winget
#   3. Apply local security policy (secedit.inf)
#   4. Apply Defender + firewall hardening
#   5. Install Microsoft 365 via the Office Deployment Tool
# =============================================================

[CmdletBinding()]
param(
    [string]$BaseUrl   = 'https://raw.githubusercontent.com/bugboilerjr/provisioning-tool/main',
    [switch]$SkipApps,
    [switch]$SkipPolicies,
    [switch]$SkipOffice
)

$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Workspace + logging ----------------------------------------------------
$WorkDir = "$env:ProgramData\Provisioning"
$LogDir  = Join-Path $WorkDir 'logs'
New-Item -ItemType Directory -Force -Path $WorkDir, $LogDir | Out-Null
$Stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "provision-$Stamp.log"
Start-Transcript -Path $LogFile -Append | Out-Null

function Write-Step($msg) {
    Write-Host ''
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Get-File($relativePath, $localPath) {
    $url = "$BaseUrl/$relativePath"
    Write-Host "    fetch $url"
    Invoke-WebRequest -Uri $url -OutFile $localPath -UseBasicParsing
}

# --- Elevation check --------------------------------------------------------
$identity   = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal  = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin    = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error 'This script must be run from an elevated PowerShell session.'
    Stop-Transcript | Out-Null
    return
}

Write-Step "Provisioning started $Stamp"
Write-Host "    BaseUrl : $BaseUrl"
Write-Host "    WorkDir : $WorkDir"
Write-Host "    Log     : $LogFile"

# --- winget sanity ----------------------------------------------------------
Write-Step 'Verifying winget'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warning 'winget not found. Trying to install App Installer (winget)...'
    try {
        $appInstaller = Join-Path $WorkDir 'AppInstaller.msixbundle'
        Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile $appInstaller -UseBasicParsing
        Add-AppxPackage -Path $appInstaller -ErrorAction Stop
    } catch {
        Write-Error "Could not install winget automatically: $_"
        Write-Error 'Install "App Installer" from the Microsoft Store and re-run.'
        Stop-Transcript | Out-Null
        return
    }
}
winget --version

# --- Apps -------------------------------------------------------------------
if (-not $SkipApps) {
    Write-Step 'Installing applications via winget'
    $appsFile = Join-Path $WorkDir 'apps.json'
    Get-File 'apps.json' $appsFile
    $apps = (Get-Content $appsFile -Raw | ConvertFrom-Json).winget

    foreach ($app in $apps) {
        Write-Host ''
        Write-Host "    install $($app.name) [$($app.id)]" -ForegroundColor Yellow
        & winget install --id $app.id `
                         --source winget `
                         --silent `
                         --accept-package-agreements `
                         --accept-source-agreements `
                         --scope machine
        # Exit code -1978335189 = "already installed", treat as success
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
            Write-Warning "    winget exit $LASTEXITCODE for $($app.id)"
        }
    }
}

# --- Policies ---------------------------------------------------------------
if (-not $SkipPolicies) {
    Write-Step 'Applying local security policy (secedit)'
    $infFile = Join-Path $WorkDir 'secedit.inf'
    $dbFile  = Join-Path $WorkDir 'secedit.sdb'
    Get-File 'policies/secedit.inf' $infFile
    secedit /configure /db $dbFile /cfg $infFile /overwrite /quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "secedit exit $LASTEXITCODE - see $env:windir\security\logs\scesrv.log"
    }

    Write-Step 'Applying Defender settings'
    $defenderScript = Join-Path $WorkDir 'defender.ps1'
    Get-File 'policies/defender.ps1' $defenderScript
    & $defenderScript

    Write-Step 'Applying firewall settings'
    $firewallScript = Join-Path $WorkDir 'firewall.ps1'
    Get-File 'policies/firewall.ps1' $firewallScript
    & $firewallScript
}

# --- Microsoft 365 via Office Deployment Tool -------------------------------
if (-not $SkipOffice) {
    Write-Step 'Installing Microsoft 365 (Office Deployment Tool)'
    $officeDir = Join-Path $WorkDir 'office'
    New-Item -ItemType Directory -Force -Path $officeDir | Out-Null

    $odtSetup = Join-Path $officeDir 'setup.exe'
    $odtCfg   = Join-Path $officeDir 'configuration.xml'

    # The ODT setup.exe should be committed to your repo at office/setup.exe.
    # Download it once from https://aka.ms/ODT, extract, commit setup.exe.
    try {
        Get-File 'office/setup.exe'         $odtSetup
        Get-File 'office/configuration.xml' $odtCfg
    } catch {
        Write-Warning "Could not fetch Office files: $_"
    }

    if (Test-Path $odtSetup) {
        Write-Host '    running ODT (10-20 min)...'
        Push-Location $officeDir
        & .\setup.exe /configure configuration.xml
        Pop-Location
    } else {
        Write-Warning 'Skipping Office install - setup.exe not present.'
    }
}

Write-Step 'Provisioning complete'
Write-Host "    log: $LogFile"
Stop-Transcript | Out-Null
