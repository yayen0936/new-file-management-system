<#
.SYNOPSIS
    Automates provisioning of DFS Namespaces, DFS folders, and DFS Replication using CSV manifest.

.DESCRIPTION
    This script:
      • Ensures required DFS roles are present on target servers.
      • Creates DFS Namespace roots and adds multiple servers as root targets.
      • Enables Access-Based Enumeration (ABE) on each DFS Namespace for improved security.
      • Creates DFS folders and adds folder targets.
      • Configures DFS Replication with a full mesh topology using folder membership data.

    All server, folder, and replication data are imported from user-supplied CSV files.

    Requires elevated privileges. Run on a system with DFSN and DFSR PowerShell modules.
    Access-Based Enumeration (ABE) is automatically enabled for each DFS Namespace.

.PARAMETER CsvPath
    Path to the dfs-namespaces CSV file specifying namespace root servers.
    > Filename: dfs-namespaces.csv
    > Purpose: Lists each DFS Namespace and its corresponding servers that will host the namespace root.

.PARAMETER FoldersCsvPath
    Path to the dfs-replications CSV file specifying folders, SMB shares, target servers, and replication paths.
    > Filename: dfs-replications.csv
    > Purpose: Defines each folder within a namespace, its associated SMB share name, target server, and replication path.

.EXAMPLE
    # usage instructions for running sripts from repo root
    cd "C:\Users\Administrator\Documents\Automation\New-File-System-Structure"

    .\repos\DFS-Namespace-Replication\Create-DFS-Namespace-Replication.ps1 -CsvPath .\inputs\dfs-namespaces.csv -FoldersCsvPath .\inputs\dfs-replications.csv -Verbose

.NOTES
    Author: Clarence Crodua
    Date: 2025-08-28
    Version: 1.7

.LINK
    * Windows Server Documentation
    1) DFS Namespaces overview
       https://learn.microsoft.com/en-us/windows-server/storage/dfs-namespaces/dfs-overview
    2) DFS Replication overview
       https://learn.microsoft.com/en-us/windows-server/storage/dfs-replication/dfs-replication-overview
    3) Install or uninstall roles, role services, or features
       https://learn.microsoft.com/en-us/windows-server/administration/server-manager/install-or-uninstall-roles-role-services-or-features

    * PowerShell cmdlet reference
    1) DFSN module (Get/New-DfsnRoot, Get/New-DfsnRootTarget, Get/New-DfsnFolder, Get/New-DfsnFolderTarget)
       https://learn.microsoft.com/en-us/powershell/module/dfsn/?view=windowsserver2025-ps
    2) DFSR module (New/Get-DfsReplicationGroup, New/Get-DfsReplicatedFolder, Add-DfsrMember, Add/Get-DfsrConnection, Set-DfsrMembership)
       https://learn.microsoft.com/en-us/powershell/module/dfsr/?view=windowsserver2025-ps
    3) Get-WindowsFeature / Install-WindowsFeature
       https://learn.microsoft.com/en-us/powershell/module/servermanager/get-windowsfeature
       https://learn.microsoft.com/en-us/powershell/module/servermanager/install-windowsfeature
    4) Invoke-Command
       https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/invoke-command
    5) New-SmbShare / Get-SmbShare / Grant-SmbShareAccess
       https://learn.microsoft.com/en-us/powershell/module/smbshare/new-smbshare
       https://learn.microsoft.com/en-us/powershell/module/smbshare/get-smbshare
       https://learn.microsoft.com/en-us/powershell/module/smbshare/grant-smbshareaccess
    6) Test-Connection
       https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/test-connection
    7) Import-Csv
       https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/import-csv
#>

# --- PARAMETERS ---------------------------------------------------------------
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CsvPath,               # Path to CSV listing DFS namespaces and their servers

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$FoldersCsvPath         # Path to CSV listing folders, SMB shares, and replication paths
)

# --- SETTINGS -----------------------------------------------------------------
$NamespaceType       = 'DomainV2'   # Use Domain-based namespace with enhanced features
$RoleNameNamespace   = 'FS-DFS-Namespace'
$RoleNameReplication = 'FS-DFS-Replication'
$DefaultSharePerms   = @{ AccountName='Everyone'; Access='Read' }  # Default share permissions

# --- ENV / FEATURE PREP -------------------------------------------------------
function Test-IsServer {
    try { Get-Command Get-WindowsFeature -ErrorAction Stop | Out-Null; return $true } catch { return $false }
}

function Ensure-DfsManagementTools {
    if (Test-IsServer) {
        foreach ($f in @($RoleNameNamespace, $RoleNameReplication)) {
            $feature = Get-WindowsFeature -Name $f
            if ($feature -and -not $feature.Installed) {
                Write-Verbose "Installing Windows feature $f ..."
                Install-WindowsFeature -Name $f -IncludeManagementTools -ErrorAction Stop | Out-Null
            }
        }
    } else {
        # Client OS (Win10/11): ensure RSAT DFS tools are installed
        $caps = @('Rsat.Dfs.Mgmt.Tools~~~~0.0.1.0')
        foreach ($c in $caps) {
            $cap = Get-WindowsCapability -Online -Name $c -ErrorAction SilentlyContinue
            if ($cap -and $cap.State -ne 'Installed') {
                Write-Verbose "Installing Windows capability $c ..."
                Add-WindowsCapability -Online -Name $c -ErrorAction Stop | Out-Null
            }
        }
    }
}

# Ensure tools exist BEFORE importing modules
Ensure-DfsManagementTools

Import-Module DFSN -ErrorAction Stop
Import-Module DFSR -ErrorAction Stop

# --- FUNCTIONS ----------------------------------------------------------------

# Ensure DFS Namespace / Replication roles are installed locally.
function Ensure-DfsRole {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FS-DFS-Namespace','FS-DFS-Replication')]
        [string]$FeatureName
    )
    if (Test-IsServer) {
        Write-Verbose "Checking for DFS role $FeatureName..."
        $feature = Get-WindowsFeature -Name $FeatureName
        if (-not $feature) { throw "Feature $FeatureName not recognized on this server." }
        if (-not $feature.Installed) {
            Write-Verbose "Installing DFS role $FeatureName (may require reboot)..."
            Install-WindowsFeature -Name $FeatureName -IncludeManagementTools -ErrorAction Stop | Out-Null
        } else {
            Write-Verbose "DFS role $FeatureName already installed."
        }
    }
}

# Quick reachability check to avoid long timeouts during remote operations.
function Test-ServerReachability {
    param([string]$ComputerName)
    Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction SilentlyContinue
}

# Ensure a root SMB share exists on a remote server (idempotent).
function Ensure-ServerSmbShare {
    param(
        [string]$Server,
        [string]$ShareName,
        [string]$FolderPath
    )
    Write-Verbose "Ensuring SMB share '$ShareName' on server $Server (Path: $FolderPath)..."
    Invoke-Command -ComputerName $Server -ErrorAction Stop -ScriptBlock {
        param($ShareName,$FolderPath,$DefaultSharePerms)
        if (-not (Test-Path $FolderPath)) {
            New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null
        }
        if (-not (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
            New-SmbShare -Name $ShareName -Path $FolderPath -FullAccess 'BUILTIN\Administrators' | Out-Null
            Grant-SmbShareAccess -Name $ShareName -AccountName $DefaultSharePerms.AccountName -AccessRight $DefaultSharePerms.Access -Force | Out-Null
        }
    } -ArgumentList $ShareName,$FolderPath,$DefaultSharePerms
}

# Add a namespace root target on a server if missing (robust + retries; ignore if exists)
function Ensure-dfs-namespacesRootTarget {
    param([string]$NamespacePath, [string]$Server)

    $shareName = ($NamespacePath -split '\\')[-1]
    $target    = "\\$Server\$shareName"

    if (Get-DfsnRootTarget -Path $NamespacePath -TargetPath $target -ErrorAction SilentlyContinue) {
        Write-Verbose "Namespace root target already present: $target"
        return
    }

    $maxAttempts = 6
    for ($i=1; $i -le $maxAttempts; $i++) {
        Write-Verbose "Adding namespace root target (attempt $i/$maxAttempts): $target"
        try {
            New-DfsnRootTarget -Path $NamespacePath -TargetPath $target -ErrorAction Stop | Out-Null
            Write-Verbose "Successfully added root target: $target"
            return
        }
        catch {
            $msg = $_.Exception.Message
            if ($msg -match 'could not be found' -or $msg -match 'cannot find the file' -or $msg -match 'The system cannot find the file') {
                Write-Warning "Namespace not visible on this DC yet (AD replication delay). Waiting 15s then retrying..."
                Start-Sleep -Seconds 15
                continue
            }
            if ($msg -match 'already exists' -or $msg -match 'object already exists') {
                Write-Verbose "Root target already exists (reported by API): $target"
                return
            }
            if ($i -lt $maxAttempts) { Write-Warning "Failed to add root target: $msg"; Start-Sleep -Seconds 15; continue }
            throw
        }
    }
}

# Ensure DFS folder and target exist in the namespace; validates remote SMB share first.
# Idempotent and non-fatal if the SMB share isn't ready (warn & continue).
function Ensure-DfsFolderAndTarget {
    param(
        [string]$NamespacePath,
        [string]$SMBName,
        [string]$TargetServer
    )

    $dfsFolderPath = Join-Path $NamespacePath $SMBName
    Write-Verbose "Ensuring DFS folder $dfsFolderPath for $TargetServer"

    # Validate remote SMB share; if missing, warn and skip (non-fatal for your test runs)
    $SmbShareExists = Invoke-Command -ComputerName $TargetServer -ErrorAction SilentlyContinue -ScriptBlock {
        param($SMBName)
        return [bool](Get-SmbShare -Name $SMBName -ErrorAction SilentlyContinue)
    } -ArgumentList $SMBName

    if (-not $SmbShareExists) {
        Write-Warning "SMB Share '$SMBName' does not exist on $TargetServer. Skipping DFS folder/target for this server."
        return
    }

    # Ensure DFS folder exists
    if (-not (Get-DfsnFolder -Path $dfsFolderPath -ErrorAction SilentlyContinue)) {
        Write-Verbose "Creating DFS folder: $dfsFolderPath"
        try {
            New-DfsnFolder -Path $dfsFolderPath -TargetPath "\\$TargetServer\$SMBName" -ErrorAction Stop | Out-Null
        } catch {
            if ($_.Exception.Message -match 'already exists') {
                Write-Verbose "DFS folder already exists: $dfsFolderPath"
            } else { throw }
        }
    } else {
        Write-Verbose "DFS folder already present: $dfsFolderPath"
    }

    # Ensure folder target exists
    if (-not (Get-DfsnFolderTarget -Path $dfsFolderPath -TargetPath "\\$TargetServer\$SMBName" -ErrorAction SilentlyContinue)) {
        Write-Verbose "Adding folder target: $TargetServer\$SMBName → $dfsFolderPath"
        try {
            New-DfsnFolderTarget -Path $dfsFolderPath -TargetPath "\\$TargetServer\$SMBName" -ErrorAction Stop | Out-Null
        } catch {
            if ($_.Exception.Message -match 'already exists') {
                Write-Verbose "DFS folder target already exists: \\$TargetServer\$SMBName"
            } else { throw }
        }
    } else {
        Write-Verbose "Folder target already present: $TargetServer\$SMBName"
    }
}

# Configure DFS Replication with full-mesh topology; idempotent and skip-if-exists.
function Ensure-DfsReplication {
    param(
        [string]$FolderName,
        [string[]]$Members,
        [hashtable]$ContentPaths,
        [string]$DfsnPath,
        [string]$Namespace,
        [string]$Domain
    )

    $groupName = "${Domain}\${Namespace}\${FolderName}"
    $primary   = $Members[0]

    Write-Host "Processing Replication Group '$groupName'"

    # Replication Group
    if (-not (Get-DfsReplicationGroup -GroupName $groupName -ErrorAction SilentlyContinue)) {
        Write-Verbose "Creating DFS Replication Group: $groupName"
        try {
            New-DfsReplicationGroup -GroupName $groupName -DomainName $env:USERDNSDOMAIN -ErrorAction Stop | Out-Null
        } catch {
            if ($_.Exception.Message -match 'already exists') {
                Write-Verbose "Replication group already exists: $groupName"
            } else { throw }
        }
    } else {
        Write-Verbose "Replication group already present: $groupName"
    }

    # Replicated Folder
    if (-not (Get-DfsReplicatedFolder -GroupName $groupName -FolderName $FolderName -ErrorAction SilentlyContinue)) {
        Write-Verbose "Creating replicated folder '$FolderName'"
        try {
            New-DfsReplicatedFolder -GroupName $groupName -FolderName $FolderName -DfsnPath $DfsnPath | Out-Null
        } catch {
            if ($_.Exception.Message -match 'already exists') {
                Write-Verbose "Replicated folder already exists: $FolderName"
            } else { throw }
        }
    } else {
        Write-Verbose "Replicated folder already present: $FolderName"
    }

    # Members
    foreach ($srv in $Members) {
        if (-not (Get-DfsrMember -GroupName $groupName -ComputerName $srv -ErrorAction SilentlyContinue)) {
            Write-Verbose "Adding DFSR Membership for $srv"
            try {
                Add-DfsrMember -GroupName $groupName -ComputerName $srv | Out-Null
            } catch {
                if ($_.Exception.Message -match 'already exists') {
                    Write-Verbose "Membership already exists for $srv"
                } else { throw }
            }
        } else {
            Write-Verbose "Membership already present for $srv"
        }
    }

    # Full-mesh connections
    foreach ($src in $Members) {
        foreach ($dst in ($Members | Where-Object { $_ -ne $src })) {
            if (-not (Get-DfsrConnection -GroupName $groupName -SourceComputerName $src -DestinationComputerName $dst -ErrorAction SilentlyContinue)) {
                Write-Verbose "Adding replication connection from $src to $dst"
                try {
                    Add-DfsrConnection -GroupName $groupName -SourceComputerName $src -DestinationComputerName $dst | Out-Null
                } catch {
                    if ($_.Exception.Message -match 'already exists') {
                        Write-Verbose "Connection already exists: $src -> $dst"
                    } else { throw }
                }
            } else {
                Write-Verbose "Connection already present: $src -> $dst"
            }
        }
    }

    # Membership settings (safe to re-apply)
    foreach ($srv in $Members) {
        $isPrimaryMember = ($primary -eq $srv)
        $path            = $ContentPaths[$srv]
        if (-not $path) {
            Write-Warning ("No ContentPath for {0}; skipping membership path update." -f $srv)
            continue
        }
        Write-Verbose ("Setting DFSR Membership for {0} (Primary: {1}, Path: {2})" -f $srv, $isPrimaryMember, $path)
        try {
            Set-DfsrMembership -GroupName $groupName -FolderName $FolderName -ComputerName $srv -ContentPath $path -PrimaryMember $isPrimaryMember -Force | Out-Null
        } catch {
            Write-Warning ("Failed to set membership for {0}: {1}" -f $srv, $_.Exception.Message)
        }
    }
}

# Create a new DFS Namespace across specified servers and enable ABE (idempotent).
function New-dfs-namespaces {
    param([string]$NamespaceName, [string[]]$NamespaceServers)

    $domainDns     = $env:USERDNSDOMAIN
    $namespacePath = "\\$domainDns\$NamespaceName"

    foreach ($srv in $NamespaceServers) {
        if (-not (Test-ServerReachability $srv)) {
            Write-Warning "Server '$srv' unreachable; skipping namespace '$NamespaceName' on this server."
            continue
        }
        Ensure-DfsRole -FeatureName $RoleNameNamespace
        Ensure-DfsRole -FeatureName $RoleNameReplication

        $nsRootPath = "C:\DFSRoots\$NamespaceName"
        Ensure-ServerSmbShare -Server $srv -ShareName $NamespaceName -FolderPath $nsRootPath
    }

    # Namespace root (create if missing; otherwise no-op)
    if (-not (Get-DfsnRoot -Path $namespacePath -ErrorAction SilentlyContinue)) {
        Write-Host "Creating DFS namespace: $namespacePath"
        try {
            New-DfsnRoot -Path $namespacePath -TargetPath "\\$($NamespaceServers[0])\$NamespaceName" -Type $NamespaceType -EnableAccessBasedEnumeration $true | Out-Null
            Start-Sleep -Seconds 10  # brief settle before adding more root targets
        } catch {
            if ($_.Exception.Message -match 'already exists') {
                Write-Verbose "DFS namespace already exists: $namespacePath"
            } else { throw }
        }
    } else {
        Write-Verbose "DFS namespace already present: $namespacePath"
    }

    # Additional root targets (idempotent; retries inside)
    foreach ($srv in ($NamespaceServers | Select-Object -Unique | Select-Object -Skip 1)) {
        Ensure-dfs-namespacesRootTarget -NamespacePath $namespacePath -Server $srv
    }
}

# Add DFS folders and configure replication for a specific namespace (idempotent).
function Add-DfsFolder {
    param([string]$NamespaceName)

    $domainDns     = $env:USERDNSDOMAIN.ToLower()
    $namespacePath = "\\$domainDns\$NamespaceName"

    Write-Verbose "Add-DfsFolder from: $FoldersCsvPath"

    $folders = Import-Csv -Path $FoldersCsvPath | Where-Object { $_.Namespace -eq $NamespaceName }
    if (-not $folders) {
        Write-Verbose "No folder rows found for namespace '$NamespaceName'; skipping."
        return
    }

    # Ensure folders and targets
    foreach ($f in $folders) {
        if (-not $f.Namespace -or -not $f.Folder -or -not $f.SMBShare -or -not $f.Server -or -not $f.ReplicationLocalPath) {
            Write-Warning "Skipping row with missing value: $($f | ConvertTo-Json -Compress)"
            continue
        }
        Ensure-DfsFolderAndTarget -NamespacePath $namespacePath -SMBName $f.SMBShare -TargetServer $f.Server
    }

    # Configure replication (safe if already configured)
    foreach ($folderGroup in $folders | Group-Object -Property Folder) {
        $members = $folderGroup.Group.Server
        $contentPaths = @{}
        foreach ($f in $folderGroup.Group) {
            $contentPaths[$f.Server] = $f.ReplicationLocalPath
        }

        Ensure-DfsReplication -FolderName $folderGroup.Name `
            -Members $members `
            -ContentPaths $contentPaths `
            -DfsnPath (Join-Path $namespacePath $folderGroup.name) `
            -Namespace $NamespaceName `
            -Domain $domainDns
    }
}

# --- MAIN --------------------------------------------------------------------
# Import DFS namespaces from CSV and process each group (idempotent overall).
try {
    $nsRows = Import-Csv -Path $CsvPath
} catch {
    throw "Failed to read CSV '$CsvPath': $($_.Exception.Message)"
}

foreach ($g in $nsRows | Group-Object NamespaceName) {
    try {
        New-dfs-namespaces -NamespaceName $g.Name -NamespaceServers ($g.Group.NamespaceServer | Select-Object -Unique)
        Add-DfsFolder -NamespaceName $g.Name
    }
    catch {
        # Non-fatal: log and continue so other steps (AD/NTFS/SMB) can still be tested
        Write-Warning ("DFS step encountered an error but will continue: {0}" -f $_.Exception.Message)
    }
}

Write-Host "DFS namespace, folder, and replication provisioning complete (idempotent; existing objects are ignored)."