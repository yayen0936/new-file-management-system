[CmdletBinding()]
param(
    [string]$ServersJson = ".\inputs\servers.json",
    [string]$DFSscript   = ".\submodules\dfs-namespace-replication\Create-DFS-Namespace-Replication.ps1",
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
if (-not (Test-Path $DFSscript))   { throw "DFS script not found: $DFSscript" }

# --- Load server configuration ----------------------------------------------
$serversConfig = Get-Content $ServersJson -Raw | ConvertFrom-Json
$dfsRootServers = $serversConfig.dfs_root_servers
if (-not $dfsRootServers) { throw "No DFS root servers defined in servers.json." }

# --- Prepare logging directory ----------------------------------------------
$logsDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Force -Path $logsDir | Out-Null }

# --- Prompt for credential once ---------------------------------------------
$Cred = Get-Credential -Message "Enter domain admin credentials (e.g., ITSADLAB\yayen)"

# --- Locate CSVs -------------------------------------------------------------
$NamespacesCsv   = Join-Path $Derivatives "dfs-namespaces.csv"
$ReplicationCsv  = Join-Path $Derivatives "dfs-replications.csv"

if (-not (Test-Path $NamespacesCsv))  { throw "Missing CSV: $NamespacesCsv" }
if (-not (Test-Path $ReplicationCsv)) { throw "Missing CSV: $ReplicationCsv" }

# --- Loop through DFS root servers ------------------------------------------
foreach ($Server in $dfsRootServers) {

    Write-Host "`n=== Starting DFS namespace and replication deployment on ${Server} ===" -ForegroundColor Cyan
    $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $logFile   = Join-Path $logsDir ("dfs__{0}__{1}.log" -f $Server, $timestamp)

    try {
        # Establish remote PowerShell session
        $fqdn = "${Server}.ad.itsummerlab.local"
        $Session = New-PSSession -ComputerName $fqdn -Credential $Cred -ErrorAction Stop

        # Ensure C:\Temp exists remotely
        Invoke-Command -Session $Session -ScriptBlock {
            param($TempPath)
            if (-not (Test-Path $TempPath)) {
                New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
            }
        } -ArgumentList $TempPath

        # Copy DFS script and CSVs to remote server
        Copy-Item -Path $DFSscript -Destination (Join-Path $TempPath "Create-DFS-Namespace-Replication.ps1") -ToSession $Session -Force
        Copy-Item -Path $NamespacesCsv  -Destination (Join-Path $TempPath "dfs-namespaces.csv")  -ToSession $Session -Force
        Copy-Item -Path $ReplicationCsv -Destination (Join-Path $TempPath "dfs-replications.csv") -ToSession $Session -Force

        # --- Execute remotely ------------------------------------------------
        Invoke-Command -Session $Session -ScriptBlock {
            param($TempPath)
            Write-Host "Running DFS Namespace and Replication script on $env:COMPUTERNAME..."
            PowerShell.exe -ExecutionPolicy Bypass `
                -File (Join-Path $TempPath "Create-DFS-Namespace-Replication.ps1") `
                -CsvPath (Join-Path $TempPath "dfs-namespaces.csv") `
                -FoldersCsvPath (Join-Path $TempPath "dfs-replications.csv") `
                -Verbose
        } -ArgumentList $TempPath *>&1 | Tee-Object -FilePath $logFile

        Write-Host "=== DFS deployment completed on ${Server} ===" -ForegroundColor Green

    } catch {
        Write-Warning "Failed to execute DFS namespace and replication on ${Server}: $($_.Exception.Message)"
        Add-Content -Path $logFile -Value ("[ERROR] {0} - Execution failed: {1}" -f (Get-Date), $_.Exception.Message)
    } finally {
        if ($Session) { Remove-PSSession $Session }
    }
}

Write-Host "`nAll DFS root servers processed." -ForegroundColor Yellow