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

# --- Import AD module -------------------------------------------------------
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    throw "ActiveDirectory module not available. Please run this script on a domain-joined system with RSAT tools."
}

# --- Run NTFS setup per server ----------------------------------------------
foreach ($Server in $fileServers) {

    Write-Host "`n=== Starting NTFS deployment on ${Server} ===" -ForegroundColor Cyan

    $CsvLocal = Join-Path $Derivatives ("ntfs-permissions__{0}.csv" -f $Server)
    if (-not (Test-Path $CsvLocal)) {
        Write-Warning "CSV not found for ${Server}: $CsvLocal"
        continue
    }

    $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $logFile   = Join-Path $logsDir ("ntfs__{0}__{1}.log" -f $Server, $timestamp)

    # --- Validate Domain Local Groups ----------------------------------------
    Write-Host "Validating domain local groups for ${Server}..." -ForegroundColor Yellow
    try {
        $CsvData = Import-Csv $CsvLocal
        if (-not $CsvData) { throw "CSV file is empty or unreadable: $CsvLocal" }

        # Adjust the column name below if your CSV uses a different field (e.g., 'Group', 'ADGroup', etc.)
        if (-not ($CsvData | Get-Member -Name 'DomainLocalGroup')) {
            throw "CSV does not contain the required 'DomainLocalGroup' column."
        }

        $Groups = $CsvData | Select-Object -ExpandProperty 'DomainLocalGroup' -Unique
        $MissingGroups = @()

        foreach ($Group in $Groups) {
            try {
                if (-not (Get-ADGroup -Identity $Group -ErrorAction Stop)) {
                    $MissingGroups += $Group
                }
            } catch {
                $MissingGroups += $Group
            }
        }

        if ($MissingGroups.Count -gt 0) {
            $msg = "The following domain local groups do not exist in AD: $($MissingGroups -join ', ')"
            Write-Error $msg
            Add-Content -Path $logFile -Value ("[ERROR] {0} - {1}" -f (Get-Date), $msg)
            Write-Warning "Skipping ${Server} due to missing groups."
            continue
        } else {
            Write-Host "All domain local groups verified successfully." -ForegroundColor Green
        }

    } catch {
        Write-Error "Group validation failed on ${Server}: $($_.Exception.Message)"
        Add-Content -Path $logFile -Value ("[ERROR] {0} - Validation failed: {1}" -f (Get-Date), $_.Exception.Message)
        continue
    }

    # --- Proceed with remote NTFS setup --------------------------------------
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
        Add-Content -Path $logFile -Value ("[ERROR] {0} - Execution failed: {1}" -f (Get-Date), $_.Exception.Message)
    } finally {
        if ($Session) { Remove-PSSession $Session }
    }
}
