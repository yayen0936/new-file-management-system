<#
.SYNOPSIS
    Orchestrates end-to-end provisioning of AD, NTFS, SMB, and DFS.

.DESCRIPTION
    Script Workflow:
      1) Pre-flight validation:
         - Checks administrator privileges, servers.json, inputs, Python runtime, and logging setup.
      2) Generates CSV into .\derivatives using the Python script (generate_csv.py):
         - ad-domainlocal-groups.csv
         - ntfs-permissions__*.csv
         - smb-share-permissions__*.csv
         - dfs-namespaces.csv
         - dfs-replications.csv
      3) Executes provisioning steps via PowerShell submodules:
         - Create-AD-DomainLocal-Groups.ps1
         - Set-NTFS-Permissions.ps1
         - Set-SMB-Share-Permissions.ps1
         - Create-DFS-Namespace-Replication.ps1

.PARAMETER Servers
    Path to the servers.json configuration file (default: .\inputs\servers.json)

.PARAMETER Permissions
    Path to the Excel or CSV file and folder permissions (default: .\inputs\file-org-folder-permissions.xlsx)

.PARAMETER DerivativeDir
    Output directory for generated CSVs (default: .\derivatives)

.OUTPUTS
    Console and transcript log files stored (default: .\logs)

.NOTES
    Author: Clarence Crodua
    Date: 2025-10-06
    Version: 2.8

    Variable Naming:
    - Using PascalCase consistently for all script parameters: (e.g. $Servers, $Permissions, $DerivativeDir)
    - PowerShell is case-insensitive, but consistent casing improves readability.

.EXAMPLE
    PS> .\provision_all.ps1 -Verbose
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Servers = ".\inputs\servers.json",

    [Parameter(Mandatory=$true)]
    [string]$Permissions = ".\inputs\file-org-folder-permissions.xlsx",

    [Parameter(Mandatory=$false)]
    [string]$DerivativeDir = ".\derivatives",

    [Parameter(Mandatory=$false)]
    [string]$DLGroupsCsv = ".\derivatives\ad-domainlocal-groups.csv",

    [Parameter(Mandatory=$false)]
    [string]$NtfsCsv = ".\derivatives",

    [Parameter(Mandatory=$false)]
    [string]$SmbCsv = ".\derivatives",

    [Parameter(Mandatory=$false)]
    [string]$DfsNamespaceCsv = ".\derivatives\dfs-namespaces.csv",

    [Parameter(Mandatory=$false)]
    [string]$DfsReplicationCsv = ".\derivatives\dfs-replications.csv"
)

# Force all errors to be treated as terminating errors
$ErrorActionPreference = 'Stop'

# Ensure the script always runs from its own directory
if (-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
Set-Location -Path $PSScriptRoot

# -----------------------------
# Function: Write-Section
# -----------------------------
# Define a function to print a section header in the console for readability
function Write-Section{
    param([string]$Message)
    Write-Host ('-' * 72)
    Write-Host $Message
    Write-Host ('-' * 72)
}

# -----------------------------
# Function: Pre-flight Checks
# -----------------------------
function Test-Preflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Servers,
        [Parameter(Mandatory=$true)][string]$Permissions
    )
    Write-Section "Pre-flight Validation"
    
    # 1) Check admin privileges
    Write-Host "Checking administrator privileges..."
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        throw "Administrator rights required. Run PowerShell or VS Code as Administrator."
    }

    # Log current user and host (for debugging)
    $CurrentUser = $env:USERNAME
    $CurrentHost = $env:COMPUTERNAME
    Write-Verbose "Current user: $CurrentUser"
    Write-Verbose "Current host: $CurrentHost"

    # 2) Validate config file (servers.json)
    if (-not (Test-Path $Servers -PathType Leaf)) {
        throw "Missing configuration file: $Servers"
    }
    Write-Verbose "Configuration file found: $Servers"

    try {
        $serversConfig = Get-Content $Servers -Raw | ConvertFrom-Json -ErrorAction Stop

    # a. File Servers
    if (-not $serversConfig.file_servers) { 
        throw "No file_servers defined in servers.json"
    }
    Write-Verbose "File servers defined: $($serversConfig.file_servers.PSObject.Properties.Name -join ', ')"

    # b. DFS Root Servers
    if (-not $serversConfig.dfs_root_servers) { 
        throw "No dfs_root_servers defined in servers.json"
    }
    Write-Verbose "DFS root servers: $($serversConfig.dfs_root_servers -join ', ')"

    # c. Share Sufffix
    if (-not $serversConfig.share_suffix) { 
        throw "No share_suffix defined in servers.json"
    }
    Write-Verbose "Share suffix: $($serversConfig.share_suffix)"
    
    # d. Drive Root and Folder Prefix
    foreach ($server in $serversConfig.file_servers.PSObject.Properties) {
        $serverName = $server.Name
        $serverData = $server.Value

        if (-not $serverData.drive_root) {
            throw "File server '$serverName' missing drive_root property."
        }
        if (-not $serverData.PSObject.Properties.Name -contains 'folder_prefix') {
            throw "File server '$serverName' missing folder_prefix property."
        }
        Write-Verbose ("Validated file server '{0}' → DriveRoot={1}, FolderPrefix='{2}'" -f $serverName, $serverData.drive_root, $serverData.folder_prefix)
    }

    # e. DFS Root Server Membership
    $fileServerNames = $serversConfig.file_servers.PSObject.Properties.Name

    foreach ($dfsServer in $serversConfig.dfs_root_servers) {
        if ($fileServerNames -contains $dfsServer) {
            Write-Host "DFS root server '$dfsServer' also acts as a file server (hybrid configuration)." -ForegroundColor Yellow
        }
        else {
            Write-Host "DFS root server '$dfsServer' is separate from file servers — expected for DC-only roles." -ForegroundColor Green
        }
    }
    catch {
        throw "Invalid servers.json: $($_.Exception.Message)"
    }

    # 3) Logging setup
    $logsDir = Join-Path -Path $PSScriptRoot -ChildPath 'logs'
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
    }
    $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $logPath   = Join-Path $logsDir -ChildPath ("pipeline-{0}.log" -f $timestamp)
    Start-Transcript -Path $logPath -Force | Out-Null
    Write-Host "Logging initialized at: $logPath"

    # 4) Input files
    if (-not (Test-Path $Permissions -PathType Leaf)) {
        throw "Input file not found: $Permissions"
    }
    Write-Host "Input file found: $Permissions"

    # 5) Python runtime
    $pythonCmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        throw "Python not found in PATH. Please install Python 3.x."
    }
    $pythonVersion = & $pythonCmd.Source --version 2>&1
    Write-Verbose "Python version detected: $pythonVersion"
}

# -----------------------------
# Function: Generate-CSV
# -----------------------------
function Generate-CSV {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Servers,
        [Parameter(Mandatory=$true)][string]$Permissions,
        [Parameter(Mandatory=$true)][string]$DerivativeDir
    )

    Write-Section "Generate CSV"

    $pythonScript = Join-Path $PSScriptRoot "submodules\fileorg-permissions-generator\generate_csv.py"
    if (-not (Test-Path $pythonScript)) {
        throw "Required Python script not found: $pythonScript"
    }

    & python.exe $pythonScript `
        --input "`"$Permissions`"" `
        --config "`"$Servers`"" `
        --DerivativeDir "`"$DerivativeDir`"" `
        --verbose

    if ($LASTEXITCODE -ne 0) {
        throw "Python CSV generation failed."
    }
    Write-Host "CSV successfully generated in: $DerivativeDir"
}

# -----------------------------
# Function: Provision-Step
# -----------------------------
function Provision-Step {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$StepName,
        [Parameter(Mandatory=$true)][string]$ScriptPath,
        [string[]]$Args
    )

    Write-Section "Running Step: $StepName"

    if (-not (Test-Path $ScriptPath)) {
        throw "Script not found: $ScriptPath"
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Args -Verbose
    if ($LASTEXITCODE -ne 0) {
        throw "Step '$StepName' failed with exit code $LASTEXITCODE."
    }
}

# -----------------------------
# Function: Provision-Orchestrator
# -----------------------------
function Provision-Orchestrator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Servers,
        [Parameter(Mandatory=$true)][string]$Permissions,
        [Parameter(Mandatory=$true)][string]$DerivativeDir,
        [string]$DLGroupsCsv,
        [string]$NtfsCsv,
        [string]$SmbCsv,
        [string]$DfsNamespaceCsv,
        [string]$DfsReplicationCsv
    )

    Write-Section "Starting Provisioning Orchestrator"
    Write-Host ("Started at: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))

    Test-Preflight -Servers $Servers -Permissions $Permissions
    Generate-CSV -Servers $Servers -Permissions $Permissions -DerivativeDir $DerivativeDir

    # Step 1: Create AD Domain Local Groups
    Provision-Step -StepName "Create-AD-DomainLocal-Groups" `
        -ScriptPath ".\submodules\ad-security-groups\Create-AD-DomainLocal-Groups.ps1" `
        -Args @("-CsvPath", "`"$DLGroupsCsv`"")

    # Step 2: Apply NTFS Permissions per file server
    $serversConfig = Get-Content $Servers -Raw | ConvertFrom-Json
    foreach ($server in $serversConfig.file_servers.PSObject.Properties.Name) {
        $ntfsPath = Join-Path $NtfsCsv ("ntfs-permissions__{0}.csv" -f $server)
        if (Test-Path $ntfsPath) {
            Provision-Step -StepName "Set-NTFS-Permissions ($server)" `
                -ScriptPath ".\submodules\ntfs-smb-permissions\Set-NTFS-Permissions.ps1" `
                -Args @("-CsvPath", "`"$ntfsPath`"")
        }
    } 

    # Step 3: Apply SMB Share Permissions per file server
    $serversConfig = Get-Content $Servers -Raw | ConvertFrom-Json
    foreach ($server in $serversConfig.file_servers.PSObject.Properties.Name) {
        $smbPath = Join-Path $SmbCsv ("smb-share-permissions__{0}.csv" -f $server)
        if (Test-Path $smbPath) {
            Provision-Step -StepName "Set-SMB-Share-Permissions ($server)" `
                -ScriptPath ".\submodules\ntfs-smb-permissions\Set-SMB-Share-Permissions.ps1" `
                -Args @("-CsvPath", "`"$smbPath`"")
        }
    }

    # Step 4: Create DFS Namespace and Replication
    Provision-Step -StepName "Create-DFS-Namespace-Replication" `
        -ScriptPath ".\submodules\dfs-namespace-replication\Create-DFS-Namespace-Replication.ps1" `
        -Args @(
            "-CsvPath", "`"$DfsNamespaceCsv`"",
            "-FoldersCsvPath", "`"$DfsReplicationCsv`""
        )
   
    Write-Section "Pipeline execution completed successfully"
    Write-Host ("Completed at: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
}
# -----------------------------
# MAIN EXECUTION
# -----------------------------
try {
    Provision-Orchestrator `
        -Servers $Servers `
        -Permissions $Permissions `
        -DerivativeDir $DerivativeDir `
        -DLGroupsCsv $DLGroupsCsv `
        -NtfsCsv $NtfsCsv `
        -SmbCsv $SmbCsv `
        -DfsNamespaceCsv $DfsNamespaceCsv `
        -DfsReplicationCsv $DfsReplicationCsv   
}
catch {
    Write-Section "Pipeline failed"
    Write-Error ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $_.Exception.Message)
    exit 1
}
finally {
    try {
        Stop-Transcript | Out-Null
    } catch {
        Write-Warning "Transcript could not be stopped cleanly."
    }
}