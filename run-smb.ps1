<#
.SYNOPSIS
Wrapper to execute Set-SMB-Permissions.ps1 remotely on all file servers.

.DESCRIPTION
Reads configuration from servers.json and calls the SMB permissions script
per server with proper arguments, logs, and error handling.

#>

[CmdletBinding()]
param(
    [string]$ServersJson = ".\inputs\servers.json",
    [string]$SMBScript    = ".\submodules\ntfs-smb-permissions\Set-SMB-Permissions.ps1",
    [string]$Derivatives  = ".\derivatives",
    [string]$TempPath     = "C:\Temp"
)

# --- Validate dependencies ---------------------------------------------------
if (-not (Test-Path $ServersJson)) { throw "servers.json not found: $ServersJson" }
if (-not (Test-Path $SMBScript))   { throw "SMB script not found: $SMBScript" }

# --- Load configuration ------------------------------------------------------
$serversConfig = Get-Content $ServersJson -Raw | ConvertFrom-Json
$fileServers   = $serversConfig.file_servers.PSObject.Properties.Name

# --- Prepare logging directory ----------------------------------------------
$logsDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Force -Path $logsDir | Out-Null }

# --- Loop through servers ----------------------------------------------------
foreach ($server in $fileServers) {
    Write-Host "[$server] Starting SMB share permission configuration..." -ForegroundColor Cyan
    
    try {
        $session = New-PSSession -ComputerName $server -ErrorAction Stop

        $remoteCommand = {
            param($SMBScript, $Derivatives, $TempPath)
            Write-Host "Executing SMB permissions script on $env:COMPUTERNAME..."
            & $SMBScript -Derivatives $Derivatives -TempPath $TempPath -Verbose
        }

        Invoke-Command -Session $session -ScriptBlock $remoteCommand -ArgumentList $SMBScript, $Derivatives, $TempPath -ErrorAction Stop

        Write-Host "[$server] SMB share permissions applied successfully." -ForegroundColor Green
    }
    catch {
        Write-Warning "[$server] Failed to apply SMB share permissions: $_"
    }
    finally {
        if ($session) { Remove-PSSession $session }
    }
}

Write-Host "`nAll servers processed." -ForegroundColor Yellow