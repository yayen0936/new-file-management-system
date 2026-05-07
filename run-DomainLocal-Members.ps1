[CmdletBinding()]
param(
    [string]$ServersJson = ".\inputs\servers.json",
    [string]$ReconcileScript = ".\submodules\ad-security-groups\Reconcile-DomainLocal-Members.ps1",
    [string]$Derivatives = ".\derivatives",
    [string]$TempPath = "C:\Temp",

    [Parameter(Mandatory)]
    [PSCredential]$Cred
)

if (-not (Test-Path $ServersJson)) {
    throw "servers.json not found: $ServersJson"
}

if (-not (Test-Path $ReconcileScript)) {
    throw "Reconciliation script not found: $ReconcileScript"
}

$serversConfig = Get-Content $ServersJson -Raw | ConvertFrom-Json
$PrimaryDC = $serversConfig.primary_member

if (-not $PrimaryDC) {
    throw "primary_member not found in $ServersJson"
}

$CsvLocal = Join-Path $Derivatives "ad-domainlocal-groups.csv"

if (-not (Test-Path $CsvLocal)) {
    throw "CSV file not found: $CsvLocal"
}

$auditDir = Join-Path $PSScriptRoot "audit"

if (-not (Test-Path $auditDir)) {
    New-Item -Path $auditDir -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $auditDir "domainlocal-members-reconciliation__$PrimaryDC__$timestamp.log"

Write-Host ""
Write-Host "=== Starting Domain Local Group members reconciliation on $PrimaryDC ===" -ForegroundColor Cyan

$Session = $null

try {
    $Session = New-PSSession -ComputerName "$PrimaryDC.ad.itsummerlab.local" -Credential $Cred

    Invoke-Command -Session $Session -ScriptBlock {
        param($TempPath)

        if (-not (Test-Path $TempPath)) {
            New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
        }
    } -ArgumentList $TempPath

    $RemoteScript = Join-Path $TempPath "Reconcile-DomainLocal-Members.ps1"
    $RemoteCsv = Join-Path $TempPath "ad-domainlocal-groups.csv"

    Copy-Item -Path $ReconcileScript -Destination $RemoteScript -ToSession $Session -Force
    Copy-Item -Path $CsvLocal -Destination $RemoteCsv -ToSession $Session -Force

    Invoke-Command -Session $Session -ScriptBlock {
        param($TempPath)

        $ScriptPath = Join-Path $TempPath "Reconcile-DomainLocal-Members.ps1"
        $CsvPath = Join-Path $TempPath "ad-domainlocal-groups.csv"

        Write-Host "Running Reconcile-DomainLocal-Members.ps1 on $env:COMPUTERNAME..."

        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

        & $ScriptPath -CsvPath $CsvPath

    } -ArgumentList $TempPath 2>&1 | Tee-Object -FilePath $logFile

    Write-Host "=== Domain Local Group members reconciliation completed on $PrimaryDC ===" -ForegroundColor Green
    Write-Host "Audit log saved to: $logFile" -ForegroundColor DarkGray
}
catch {
    Write-Host "Error running Domain Local Group members reconciliation on ${PrimaryDC}: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally {
    if ($Session) {
        Remove-PSSession $Session
    }
}