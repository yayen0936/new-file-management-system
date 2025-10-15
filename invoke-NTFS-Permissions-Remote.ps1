[CmdletBinding()]
param(
    [string]$ServersJson = ".\inputs\servers.json",
    [string]$NTFSScript  = ".\submodules\ntfs-smb-permissions\Set-NTFS-Permissions.ps1",
    [string]$Derivatives = ".\derivatives",
    [string]$TempPath    = "C:\Temp"
)

# --- Validate dependencies ---------------------------------------------------
if (-not (Test-Path $ServersJson)) { throw "servers.json not found: $ServersJson" }
if (-not (Test-Path $NTFSScript))  { throw "NTFS script not found: $NTFSScript" }

# --- Load server configuration ----------------------------------------------
$serversConfig = Get-Content $ServersJson -Raw | ConvertFrom-Json
$fileServers   = $serversConfig.file_servers.PSObject.Properties.Name

# --- Prepare logging directory ----------------------------------------------
$logsDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Force -Path $logsDir | Out-Null }

# --- Prompt for credential once ---------------------------------------------
$Cred = Get-Credential -Message "Enter domain admin credentials (e.g., ITSADLAB\yayen)"

# --- Run NTFS setup per server ----------------------------------------------
foreach ($Server in $fileServers) {

    Write-Host "`n=== Starting NTFS deployment on ${Server} ===" -ForegroundColor Cyan

    $CsvLocal  = Join-Path $Derivatives ("ntfs-permissions__{0}.csv" -f $Server)
    if (-not (Test-Path $CsvLocal)) {
        Write-Warning "CSV not found for ${Server}: $CsvLocal"
        continue
    }

    $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $logFile   = Join-Path $logsDir ("ntfs__{0}__{1}.log" -f $Server, $timestamp)

    try {
        $Session = New-PSSession -ComputerName "${Server}.ad.itsummerlab.local" -Credential $Cred

        # Ensure C:\Temp exists on remote server
        Invoke-Command -Session $Session -ScriptBlock {
            param($TempPath)
            if (-not (Test-Path $TempPath)) { New-Item -ItemType Directory -Path $TempPath -Force | Out-Null }
        } -ArgumentList $TempPath

        # Copy script and CSV
        Copy-Item -Path $NTFSScript -Destination (Join-Path $TempPath "Set-NTFS-Permissions.ps1") -ToSession $Session -Force
        Copy-Item -Path $CsvLocal  -Destination (Join-Path $TempPath (Split-Path $CsvLocal -Leaf)) -ToSession $Session -Force

        # Execute remotely
        Invoke-Command -Session $Session -ScriptBlock {
            param($TempPath, $CsvFile)
            Write-Host "Running NTFS script on $env:COMPUTERNAME..."
            PowerShell.exe -ExecutionPolicy Bypass `
                -File (Join-Path $TempPath "Set-NTFS-Permissions.ps1") `
                -CsvPath (Join-Path $TempPath $CsvFile) `
                -Verbose
        } -ArgumentList $TempPath, (Split-Path $CsvLocal -Leaf) *>&1 | Tee-Object -FilePath $logFile

        Write-Host "=== NTFS deployment completed on ${Server} ===" -ForegroundColor Green

    } catch {
        Write-Warning "Failed to execute NTFS permissions on ${Server}: $($_.Exception.Message)"
    } finally {
        if ($Session) { Remove-PSSession $Session }
    }
}