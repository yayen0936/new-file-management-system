[CmdletBinding()]
param(
    [string]$ServersJson = ".\inputs\servers.json",
    [string]$DFSScript   = ".\submodules\dfs-namespace-replication\Create-DFS-Namespace-Replication.ps1",
    [string]$Derivatives = ".\derivatives",
    [string]$TempPath    = "C:\Temp",

    [Parameter(Mandatory)]
    [PSCredential]$Cred
)

# --- Validate paths ----------------------------------------------------------
if (-not (Test-Path $ServersJson)) { throw "servers.json not found: $ServersJson" }
if (-not (Test-Path $DFSScript))  { throw "DFS script not found: $DFSScript" }

# --- Load configuration and detect primary file server -----------------------
try {
    $serversConfig = Get-Content $ServersJson -Raw | ConvertFrom-Json

    # Pick the first file server as primary (e.g., LAB-LOUIE)
    $dfs_root_servers = $serversConfig.dfs_root_servers
    # $FileServers = $serversConfig.file_servers.PSObject.Properties.Name
    if (-not $dfs_root_servers) { throw "No file_servers found in $ServersJson" }
    $PrimaryFileServer = $dfs_root_servers | Select-Object -First 1

    if (-not $PrimaryFileServer) { throw "Primary file server not detected in $ServersJson" }
} catch {
    throw "Failed to parse servers.json: $($_.Exception.Message)"
}

Write-Host "`nPrimary File Server detected: $PrimaryFileServer" -ForegroundColor Cyan

# --- Prepare logging directory ----------------------------------------------
$logsDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Force -Path $logsDir | Out-Null }

# --- Locate DFS CSV manifests -----------------------------------------------
$CsvNamespace = Join-Path $Derivatives "dfs-namespaces.csv"
$CsvFolders   = Join-Path $Derivatives "dfs-replications.csv"
$CsvAbe   = Join-Path $Derivatives "dfs-abe.csv"

if (-not (Test-Path $CsvNamespace)) { throw "DFS Namespace CSV not found: $CsvNamespace" }
if (-not (Test-Path $CsvFolders))   { throw "DFS Replication CSV not found: $CsvFolders" }

$timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$logFile   = Join-Path $logsDir ("dfs__{0}__{1}.log" -f $PrimaryFileServer, $timestamp)

# --- Execute DFS provisioning remotely --------------------------------------
Write-Host "`n=== Starting DFS Namespace & Replication deployment on $PrimaryFileServer ===" -ForegroundColor Cyan

try {
    # Create PowerShell remoting session
    $Session = New-PSSession -ComputerName "${PrimaryFileServer}.ad.itsummerlab.local" -Credential $Cred

    # Ensure temp directory exists remotely
    Invoke-Command -Session $Session -ScriptBlock {
        param($TempPath)
        if (-not (Test-Path $TempPath)) {
            New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
        }
    } -ArgumentList $TempPath

    # Copy DFS script and CSV files to the remote file server
    Copy-Item -Path $DFSScript     -Destination (Join-Path $TempPath "Create-DFS-Namespace-Replication.ps1") -ToSession $Session -Force
    Copy-Item -Path $CsvNamespace  -Destination (Join-Path $TempPath (Split-Path $CsvNamespace -Leaf)) -ToSession $Session -Force
    Copy-Item -Path $CsvFolders    -Destination (Join-Path $TempPath (Split-Path $CsvFolders -Leaf)) -ToSession $Session -Force
    Copy-Item -Path $CsvAbe        -Destination (Join-Path $TempPath (Split-Path $CsvAbe -Leaf)) -ToSession $Session -Force

    # Execute the DFS provisioning script remotely
    Invoke-Command -Session $Session -ScriptBlock {
        # param($Cred)

        Write-Host "Running Create-DFS-Namespace-Replication.ps1 locally on $env:COMPUTERNAME..."

        # Run DFS script in a local logon on the server
        & "C:\Temp\Create-DFS-Namespace-Replication.ps1" `
            -CsvPath  "C:\Temp\dfs-namespaces.csv" `
            -FoldersCsvPath "C:\Temp\dfs-replications.csv" `
            -AbeCsvPath "C:\Temp\dfs-abe.csv" `
            -Cred $Using:Cred `
            -Verbose *>&1
    } *>&1 | Tee-Object -FilePath $logFile

    Write-Host "=== DFS Namespace and Replication deployment completed on ${PrimaryFileServer} ===" -ForegroundColor Green

} catch {
    Write-Warning "Failed to execute DFS namespace and replication on ${Server}: $($_.Exception.Message)"
    Add-Content -Path $logFile -Value ("[ERROR] {0} - Execution failed: {1}" -f (Get-Date), $_.Exception.Message)
} finally {
    if ($Session) { Remove-PSSession $Session }
}

Write-Host "`nAll DFS root servers processed." -ForegroundColor Yellow
