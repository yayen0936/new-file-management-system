[CmdletBinding()]
param(
    [string]$ServersJson   = ".\inputs\servers.json",
    [string]$ADGroupScript = ".\submodules\ad-security-groups\Create-AD-DomainLocal-Groups.ps1",
    [string]$Derivatives   = ".\derivatives",
    [string]$TempPath      = "C:\Temp",

    [Parameter(Mandatory)]
    [PSCredential]$Cred
)

# --- Validate paths ----------------------------------------------------------
if (-not (Test-Path $ServersJson))   { throw "servers.json not found: $ServersJson" }
if (-not (Test-Path $ADGroupScript)) { throw "AD group script not found: $ADGroupScript" }

# --- Load server configuration ----------------------------------------------
try {
    $serversConfig = Get-Content $ServersJson -Raw | ConvertFrom-Json
    $PrimaryDC     = $serversConfig.primary_member
    if (-not $PrimaryDC) { throw "primary_member not found in $ServersJson" }
} catch {
    throw "Failed to read or parse servers.json: $($_.Exception.Message)"
}

Write-Host "`nPrimary Domain Controller detected: $PrimaryDC" -ForegroundColor Cyan

# --- Prepare logging directory ----------------------------------------------
$logsDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Force -Path $logsDir | Out-Null }

# --- Validate AD module locally ---------------------------------------------
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    throw "ActiveDirectory module not available. Run this on a domain-joined system with RSAT tools."
}

# --- Locate the CSV manifest ------------------------------------------------
$CsvLocal = Join-Path $Derivatives "ad-domainlocal-groups.csv"
if (-not (Test-Path $CsvLocal)) {
    throw "CSV not found for primary domain controller: $CsvLocal"
}

$timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$logFile   = Join-Path $logsDir ("domainlocal__{0}__{1}.log" -f $PrimaryDC, $timestamp)

# --- Begin deployment -------------------------------------------------------
Write-Host "`n=== Starting Domain Local Group deployment on $PrimaryDC ===" -ForegroundColor Cyan

try {
    # Establish a remote session to the primary DC
    $Session = New-PSSession -ComputerName "${PrimaryDC}.ad.itsummerlab.local" -Credential $Cred

    # Ensure C:\Temp exists remotely
    Invoke-Command -Session $Session -ScriptBlock {
        param($TempPath)
        if (-not (Test-Path $TempPath)) {
            New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
        }
    } -ArgumentList $TempPath

    # Copy the script and CSV to the remote Domain Controller
    Copy-Item -Path $ADGroupScript -Destination (Join-Path $TempPath "Create-AD-DomainLocal-Groups.ps1") -ToSession $Session -Force
    Copy-Item -Path $CsvLocal     -Destination (Join-Path $TempPath (Split-Path $CsvLocal -Leaf)) -ToSession $Session -Force

    # Execute remotely on primary DC
    Invoke-Command -Session $Session -ScriptBlock {
        param($TempPath, $CsvFile)
        Write-Host "Running Create-AD-DomainLocal-Groups.ps1 on $env:COMPUTERNAME..."
        PowerShell.exe -ExecutionPolicy Bypass `
            -File (Join-Path $TempPath "Create-AD-DomainLocal-Groups.ps1") `
            -CsvPath (Join-Path $TempPath $CsvFile) `
            -Verbose
    } -ArgumentList $TempPath, (Split-Path $CsvLocal -Leaf) *>&1 | Tee-Object -FilePath $logFile

    Write-Host "=== Domain Local Group deployment completed on ${PrimaryDC} ===" -ForegroundColor Green

} catch {
    Write-Warning "Execution failed on ${PrimaryDC}: $($_.Exception.Message)"
    Add-Content -Path $logFile -Value ("[ERROR] {0} - {1}" -f (Get-Date), $_.Exception.Message)
} finally {
    if ($Session) { Remove-PSSession $Session }
}
