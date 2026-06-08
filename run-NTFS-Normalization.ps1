[CmdletBinding()]
param(
    [string]$ServersJson = ".\inputs\servers.json",
    [string]$NormalizationScript = ".\submodules\ntfs-smb-permissions\Normalize-NTFS-ChildPermissions.ps1",
    [string]$Derivatives = ".\derivatives",
    [string]$TempPath = "C:\Temp",

    [Parameter(Mandatory)]
    [PSCredential]$Cred
)

# --- Validate dependencies ---------------------------------------------------
if (-not (Test-Path $ServersJson)) { throw "servers.json not found: $ServersJson" }
if (-not (Test-Path $NormalizationScript)) { throw "Normalization script not found: $NormalizationScript" }

# --- Load server configuration ----------------------------------------------
$serversConfig = Get-Content $ServersJson -Raw | ConvertFrom-Json
$fileServers = $serversConfig.file_servers.PSObject.Properties.Name

# --- Prepare logging directory ----------------------------------------------
$logsDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Force -Path $logsDir | Out-Null }

# --- Run NTFS normalization per server ---------------------------------------
foreach ($Server in $fileServers) {

    Write-Host "`n=== Starting NTFS child permissions normalization on ${Server} ===" -ForegroundColor Cyan

    $CsvLocal = Join-Path $Derivatives ("ntfs-permissions__{0}.csv" -f $Server)
    if (-not (Test-Path $CsvLocal)) {
        Write-Warning "CSV not found for ${Server}: $CsvLocal"
        continue
    }

    $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $logFile = Join-Path $logsDir ("ntfs-normalization__{0}__{1}.log" -f $Server, $timestamp)

    try {
        $Session = New-PSSession -ComputerName "${Server}.ad.calgarycommunities.com" -Credential $Cred

        # Ensure C:\Temp exists on remote server
        Invoke-Command -Session $Session -ScriptBlock {
            param($TempPath)
            if (-not (Test-Path $TempPath)) { New-Item -ItemType Directory -Path $TempPath -Force | Out-Null }
        } -ArgumentList $TempPath

        # Copy script and CSV
        Copy-Item -Path $NormalizationScript -Destination (Join-Path $TempPath "Normalize-NTFS-ChildPermissions.ps1") -ToSession $Session -Force
        Copy-Item -Path $CsvLocal -Destination (Join-Path $TempPath (Split-Path $CsvLocal -Leaf)) -ToSession $Session -Force

        # Execute remotely
        Invoke-Command -Session $Session -ScriptBlock {
            param($TempPath, $CsvFile)

            Write-Host "Running NTFS child permissions normalization on $env:COMPUTERNAME..."

            PowerShell.exe -ExecutionPolicy Bypass `
                -File (Join-Path $TempPath "Normalize-NTFS-ChildPermissions.ps1") `
                -CsvPath (Join-Path $TempPath $CsvFile) `
                -Verbose

        } -ArgumentList $TempPath, (Split-Path $CsvLocal -Leaf) *>&1 | Tee-Object -FilePath $logFile

        Write-Host "=== NTFS child permissions normalization completed on ${Server} ===" -ForegroundColor Green

    } catch {
        Write-Warning "Failed to normalize NTFS child permissions on ${Server}: $($_.Exception.Message)"
        Add-Content -Path $logFile -Value ("[ERROR] {0} - Execution failed: {1}" -f (Get-Date), $_.Exception.Message)
    } finally {
        if ($Session) { Remove-PSSession $Session }
    }
}