[CmdletBinding()]
param(
    [string]$ServersJson   = ".\inputs\servers.json",
    [string]$ReferralScript = ".\submodules\dfs-namespace-replication\Set-DFS-ReferralTargetPriority.ps1",
    [string]$Derivatives   = ".\derivatives",
    [string]$TempPath      = "C:\Temp",

    [Parameter(Mandatory)]
    [PSCredential]$Cred
)

# --- Validate paths ----------------------------------------------------------
if (-not (Test-Path $ServersJson))    { throw "servers.json not found: $ServersJson" }
if (-not (Test-Path $ReferralScript)) { throw "DFS referral script not found: $ReferralScript" }

# --- Load configuration and detect primary DFS root server -------------------
try {
    $serversConfig = Get-Content $ServersJson -Raw | ConvertFrom-Json

    $dfs_root_servers = $serversConfig.dfs_root_servers
    if (-not $dfs_root_servers) { throw "No dfs_root_servers found in $ServersJson" }

    $PrimaryFileServer = $dfs_root_servers | Select-Object -First 1
    if (-not $PrimaryFileServer) { throw "Primary DFS root server not detected in $ServersJson" }
} catch {
    throw "Failed to parse servers.json: $($_.Exception.Message)"
}

Write-Host "`nPrimary DFS Root Server detected: $PrimaryFileServer" -ForegroundColor Cyan

# --- Prepare logging directory ----------------------------------------------
$logsDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Force -Path $logsDir | Out-Null }

# --- Locate DFS referral CSV -------------------------------------------------
$CsvReferral = Join-Path $Derivatives "dfs-referrals.csv"
if (-not (Test-Path $CsvReferral)) { throw "DFS referral CSV not found: $CsvReferral" }

$timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$logFile   = Join-Path $logsDir ("dfs-referrals__{0}__{1}.log" -f $PrimaryFileServer, $timestamp)

# --- Execute DFS referral configuration remotely -----------------------------
Write-Host "`n=== Starting DFS referral target priority configuration on $PrimaryFileServer ===" -ForegroundColor Cyan

try {
    $Session = New-PSSession -ComputerName "${PrimaryFileServer}.ad.itsummerlab.local" -Credential $Cred

    Invoke-Command -Session $Session -ScriptBlock {
        param($TempPath)
        if (-not (Test-Path $TempPath)) {
            New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
        }
    } -ArgumentList $TempPath

    Copy-Item -Path $ReferralScript -Destination (Join-Path $TempPath "Set-DFS-ReferralTargetPriority.ps1") -ToSession $Session -Force
    Copy-Item -Path $CsvReferral    -Destination (Join-Path $TempPath "dfs-referrals.csv") -ToSession $Session -Force

    Invoke-Command -Session $Session -ScriptBlock {
        Write-Host "Running Set-DFS-ReferralTargetPriority.ps1 locally on $env:COMPUTERNAME..."

        & "C:\Temp\Set-DFS-ReferralTargetPriority.ps1" `
            -CsvPath "C:\Temp\dfs-referrals.csv" `
            -Verbose *>&1
    } *>&1 | Tee-Object -FilePath $logFile

    Write-Host "=== DFS referral target priority configuration completed on ${PrimaryFileServer} ===" -ForegroundColor Green

} catch {
    Write-Warning "Failed to configure DFS referral target priority on ${PrimaryFileServer}: $($_.Exception.Message)"
    Add-Content -Path $logFile -Value ("[ERROR] {0} - Execution failed: {1}" -f (Get-Date), $_.Exception.Message)
} finally {
    if ($Session) { Remove-PSSession $Session }
}
