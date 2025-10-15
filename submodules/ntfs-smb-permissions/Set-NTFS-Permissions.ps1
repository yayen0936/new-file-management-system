<#
.SYNOPSIS
    Automates NTFS permissions for folders using a CSV manifest.

.DESCRIPTION
    Reads a CSV file containing folder paths, groups, permissions, and inheritance settings.
    - Creates missing folders.
    - Breaks inheritance and removes inherited permissions.
    - Grants Full Control to key admin accounts and CREATOR OWNER.
    - Adds or updates custom permissions per CSV entries with correct inheritance/propagation flags.

.PARAMETER CsvPath
    Path to the CSV file with NTFS permission definitions.
    CSV must include: FolderPath, DomainLocalGroup, Permissions, AppliesTo.

.EXAMPLE
    # Step 1: Navigate to the repo root
    cd "C:\Users\YAYEN\Documents\new-file-management-system"

    # Step 2: Execute the NTFS permissions script
    .\submodules\ntfs-permissions\Set-NTFS-Permissions.ps1 `
        -CsvPath ".\derivatives\ntfs-permissions.csv" `
        -Verbose

.NOTES
    Author: Clarence Crodua
    Date: 2025-10-08
    Version: 1.8

.LINK
    * Windows Server Documentation
    1) NTFS overview
       https://learn.microsoft.com/en-us/windows-server/storage/file-server/ntfs-overview
    2) Access control overview
       https://learn.microsoft.com/en-us/windows/security/identity-protection/access-control/access-control
    3) Well-known SIDs (includes CREATOR OWNER)
       https://learn.microsoft.com/en-us/windows/win32/secauthz/well-known-sids
    4) Managing Permissions
       https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/cc770962(v=ws.11)](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/cc770962(v=ws.11)
    5) Best practices for assigning permissions on Active Directory objects
       https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2003/cc786285(v=ws.10)?redirectedfrom=MSDN](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2003/cc786285(v=ws.10)?redirectedfrom=MSDN
    6) Access control in Active Directory
       https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2003/cc785913(v=ws.10)](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2003/cc785913(v=ws.10)
    7) Active Directory Best practices
       https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2003/cc778219(v=ws.10)](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2003/cc778219(v=ws.10)

    * PowerShell cmdlet reference
    1) Get-Acl
       https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-acl?view=powershell-7.5
    2) Set-Acl
       https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-acl?view=powershell-7.5
    3) New-Item
       https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-item?view=powershell-7.5
    4) Import-Csv
       https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/import-csv?view=powershell-7.5
    5) Group-Object
       https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/group-object?view=powershell-7.5
    6) Test-Path
       https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/test-path?view=powershell-7.5
#>
param (
    [Parameter(Mandatory)]
    [string]$CsvPath
)

# --- Admin accounts (Full Control) -------------------------------------------
# Principals granted FullControl at the root with inheritance to children.
$AdminAccounts = @(
    'BUILTIN\Administrators',
    'Domain Admins',
    'NT AUTHORITY\SYSTEM'
)

# --- Permission map -----------------------------------------------------------
# CSV "Permissions" must match one of these keys; otherwise the row is skipped.
$accessMap = @{
    "FullControl"      = [System.Security.AccessControl.FileSystemRights]::FullControl
    "Modify"           = [System.Security.AccessControl.FileSystemRights]::Modify
    "ReadAndExecute"   = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
    "ListDirectory"    = [System.Security.AccessControl.FileSystemRights]::ListDirectory
    "Read"             = [System.Security.AccessControl.FileSystemRights]::Read
    "Write"            = [System.Security.AccessControl.FileSystemRights]::Write
}

# --- Helper: map AppliesTo -> inheritance/propagation -------------------------
# Returns: [ InheritanceFlags, PropagationFlags ]
function Get-InheritanceAndPropagation {
    param ($appliesTo)
    switch ($appliesTo) {
        "ThisFolderOnly"            { return @('None', 'None') }                           # Affect folder only
        "ThisFolderSubfoldersFiles" { return @('ContainerInherit,ObjectInherit', 'None') } # Folder + all children
        "ThisFolderSubfolders"      { return @('ContainerInherit', 'None') }               # Folder + subfolders
        "ThisFolderFiles"           { return @('ObjectInherit', 'None') }                  # Folder + files
        "SubfoldersFilesOnly"       { return @('ContainerInherit,ObjectInherit', 'InheritOnly') } # Children only
        "SubfoldersOnly"            { return @('ContainerInherit', 'InheritOnly') }        # Subfolders only
        "FilesOnly"                 { return @('ObjectInherit', 'InheritOnly') }           # Files only
        default                     { return @('ContainerInherit,ObjectInherit', 'None') } # Sensible default
    }
}

# --- Import CSV manifest ------------------------------------------------------
# Expected columns: FolderPath, DomainLocalGroup, Permissions, AppliesTo
$entries = Import-Csv -Path $CsvPath

# --- Group rows by folder -----------------------------------------------------
# Build and write one ACL per folder for efficiency and consistency.
$folders = $entries | Group-Object -Property FolderPath

foreach ($folder in $folders) {
    $folderPath = $folder.Name

    # --- Ensure folder exists -------------------------------------------------
    if (-Not (Test-Path -Path $folderPath)) {
        New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
        Write-Host "Created: $folderPath"
    } else {
        Write-Host "Exists: $folderPath"
    }

    # --- Load current ACL -----------------------------------------------------
    $acl = Get-Acl -Path $folderPath

    # --- Reset inheritance & clear ACEs --------------------------------------
    # Disable inheritance (do not preserve inherited ACEs) and remove existing explicit ACEs.
    $acl.SetAccessRuleProtection($true, $false)
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }

    # --- Admin Full Control ---------------------------------------------------
    # Apply FullControl to admins on folder and all children.
    $adminFlags   = Get-InheritanceAndPropagation 'ThisFolderSubfoldersFiles'
    $adminInherit = $adminFlags[0]
    $adminProp    = $adminFlags[1]
    foreach ($acct in $AdminAccounts) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $acct, 'FullControl', $adminInherit, $adminProp, 'Allow'
        )
        $acl.AddAccessRule($rule)
    }

    # --- CREATOR OWNER (children only) ---------------------------------------
    # Owners get FullControl on objects they create under this folder (not on the root itself).
    $creatorFlags   = Get-InheritanceAndPropagation 'SubfoldersFilesOnly'
    $creatorInherit = $creatorFlags[0]
    $creatorProp    = $creatorFlags[1]
    $creatorRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'CREATOR OWNER', 'FullControl', $creatorInherit, $creatorProp, 'Allow'
    )
    $acl.AddAccessRule($creatorRule)

    # --- Apply CSV-defined permissions ---------------------------------------
    foreach ($row in $folder.Group) {
        $group     = $row.DomainLocalGroup   # Domain Local group per AGDLP/RBAC
        $perm      = $row.Permissions        # Must exist in $accessMap
        $appliesTo = $row.AppliesTo          # Scope of inheritance/propagation

        # Validate permission name
        if (-not $accessMap.ContainsKey($perm)) {
            Write-Warning "Invalid permission: $perm for $group on $folderPath"
            continue
        }

        # Resolve inheritance/propagation flags and add the ACE
        $flags   = Get-InheritanceAndPropagation $appliesTo
        $inherit = $flags[0]
        $prop    = $flags[1]

        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $group, $accessMap[$perm], $inherit, $prop, 'Allow'
        )
        $acl.AddAccessRule($rule)
        Write-Host "Set $perm for $group on $folderPath (AppliesTo: $appliesTo)"
    }

    # --- Commit ACL -----------------------------------------------------------
    # Apply the composed ACL to the folder (requires appropriate privileges).
    Set-Acl -Path $folderPath -AclObject $acl
    Write-Host "Permissions applied on: $folderPath"
}