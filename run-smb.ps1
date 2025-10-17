[CmdletBinding()]
param(
    [string]$ServersJson = ".\inputs\servers.json",
    [string]$SMBScript   = ".\submodules\ntfs-smb-permissions\Set-SMB-Share-Permissions.ps1",
    [string]$Derivatives = ".\derivatives",
    [string]$TempPath    = "C:\Temp"
)

# --- Ensure user can run scripts ---------------------------------------------
try {
    $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
    if ($currentPolicy -ne 'RemoteSigned') {
        Write-Host "Current user execution policy is '$currentPolicy'. Updating to 'RemoteSigned'..." -ForegroundColor Yellow
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
        Write-Host "Execution policy updated to 'RemoteSigned' for user $env:USERNAME." -ForegroundColor Green
    } else {
        Write-Host "Execution policy already set to 'RemoteSigned' for current user." -ForegroundColor Green
    }
} catch {
    Write-Warning "Unable to set execution policy automatically. Run PowerShell as administrator if required."
}

# --- Validate dependencies ---------------------------------------------------
if (-not (Test-Path $ServersJson)) { throw "servers.json not found: $ServersJson" }
if (-not (Test-Path $SMBScript))   { throw "SMB script not found: $SMBScript" }

# --- Load server configuration ----------------------------------------------
$serversConfig = Get-Content $ServersJson -Raw | ConvertFrom-Json
$fileServers   = $serversConfig.file_servers.PSObject.Properties.Name

# --- Prepare logging directory ----------------------------------------------
$logsDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Force -Path $logsDir | Out-Null }

# --- Prompt for credential once ---------------------------------------------
$Cred = Get-Credential -Message "Enter domain admin credentials (e.g., ITSADLAB\yayen)"

# --- Loop through servers ----------------------------------------------------
foreach ($Server in $fileServers) {

    Write-Host "`n=== Starting SMB share permission deployment on ${Server} ===" -ForegroundColor Cyan
    $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $logFile   = Join-Path $logsDir ("smb__{0}__{1}.log" -f $Server, $timestamp)

    try {
        # Create remote PowerShell session
        $fqdn = "${Server}.ad.itsummerlab.local"
        $Session = New-PSSession -ComputerName $fqdn -Credential $Cred -ErrorAction Stop

        # Ensure C:\Temp exists remotely
        Invoke-Command -Session $Session -ScriptBlock {
            param($TempPath)
            if (-not (Test-Path $TempPath)) {
                New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
            }
        } -ArgumentList $TempPath

        # Copy the SMB script to remote Temp
        Copy-Item -Path $SMBScript -Destination (Join-Path $TempPath "Set-SMB-Share-Permissions.ps1") -ToSession $Session -Force

        # Locate the per-server CSV file
        $CsvLocal = Join-Path $Derivatives ("smb-share-permissions__{0}.csv" -f $Server)
        if (-not (Test-Path $CsvLocal)) {
            Write-Warning "CSV not found for ${Server}: $CsvLocal"
            continue
        }

        # Copy CSV file to remote server
        Copy-Item -Path $CsvLocal -Destination (Join-Path $TempPath (Split-Path $CsvLocal -Leaf)) -ToSession $Session -Force

        # --- Execute remotely ------------------------------------------------
        # Microsoft guidance: use -ExecutionPolicy Bypass for one-time automation
        Invoke-Command -Session $Session -ScriptBlock {
            param($TempPath, $CsvFile)
            Write-Host "Running SMB Share Permissions script on $env:COMPUTERNAME..."
            PowerShell.exe -ExecutionPolicy Bypass `
                -File (Join-Path $TempPath "Set-SMB-Share-Permissions.ps1") `
                -CsvPath (Join-Path $TempPath $CsvFile) `
                -Verbose
        } -ArgumentList $TempPath, (Split-Path $CsvLocal -Leaf) *>&1 | Tee-Object -FilePath $logFile

        Write-Host "=== SMB deployment completed on ${Server} ===" -ForegroundColor Green

    } catch {
        Write-Warning "Failed to execute SMB permissions on ${Server}: $($_.Exception.Message)"
        Add-Content -Path $logFile -Value ("[ERROR] {0} - Execution failed: {1}" -f (Get-Date), $_.Exception.Message)
    } finally {
        if ($Session) { Remove-PSSession $Session }
    }
}
Write-Host "`nAll servers processed." -ForegroundColor Yellow