<#
.SYNOPSIS
    Creates or updates SMB shares from a CSV manifest and applies share-level permissions.

.DESCRIPTION
    For each row in the CSV, this script:
      - Ensures the SMB share exists (creates it if missing with admin FullAccess).
      - Removes the default 'Everyone' share permission (if present).
      - Removes existing share access for the specified Domain Local group (if present).
      - Grants the requested share-level permission (Read, Change/Modify, or Full Control).

.PARAMETER CsvPath
    Path to the CSV file containing share definitions.
    Required columns (exact names):
      - ShareName
      - FolderPath
      - DomainLocalGroup
      - Permissions   (Accepts: Read | Change | Modify | Full | FullControl)

.EXAMPLE
    # usage instructions for running sripts from repo root
    cd "C:\Users\Administrator\Documents\PowerShell Scripts\FileShares-NTFS-SMBShare-Permissions"

    .\scripts\Set-SMB-Share-Permissions.ps1 -CsvPath .\inputs\smb-share-permissions.csv -Verbose

.NOTES
    Author: Clarence Crodua
    Date: 2025-07-29
    Version: 1.6

.LINK
    * Windows Server Documentation
    1) SMB overview
       https://learn.microsoft.com/en-us/windows-server/storage/file-server/file-server-smb-overview
    2) SMB security enhancements
       https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-security
    3) SMB signing overview
       https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-signing-overview
    4) Secure SMB traffic
       https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-secure-traffic

    * PowerShell cmdlet reference
    1) New-SmbShare
       https://learn.microsoft.com/en-us/powershell/module/smbshare/new-smbshare?view=windowsserver2025-ps
    2) Get-SmbShare
       https://learn.microsoft.com/en-us/powershell/module/smbshare/get-smbshare?view=windowsserver2025-ps
    3) Grant-SmbShareAccess
       https://learn.microsoft.com/en-us/powershell/module/smbshare/grant-smbshareaccess?view=windowsserver2025-ps
    4) Revoke-SmbShareAccess
       https://learn.microsoft.com/en-us/powershell/module/smbshare/revoke-smbshareaccess?view=windowsserver2025-ps
    5) Import-Csv
       https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/import-csv?view=powershell-7.5
#>

param (
    [Parameter(Mandatory)]
    [string]$CsvPath
)

# --- Admin accounts (Full Control) -------------------------------------------
# These principals will receive FullAccess when creating a new share.
$AdminAccounts = @(
    'BUILTIN\Administrators',
    'Domain Admins'
)

# --- Import CSV manifest ------------------------------------------------------
$shares = Import-Csv -Path $CsvPath

# --- Iterate shares -----------------------------------------------------------
foreach ($entry in $shares) {
    $shareName        = $entry.ShareName
    $folderPath       = $entry.FolderPath
    $domainLocalGroup = $entry.DomainLocalGroup
    $permission       = $entry.Permissions

    # --- Ensure SMB share exists ---------------------------------------------
    $share = Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue
    if (-not $share) {
        New-SmbShare -Name $shareName -Path $folderPath -FullAccess $AdminAccounts | Out-Null
        Write-Host "Created SMB share: $shareName ($folderPath)"
    } else {
        Write-Host "Share exists: $shareName"
    }

    # --- Remove 'Everyone' access (if present) --------------------------------
    try {
        Revoke-SmbShareAccess -Name $shareName -AccountName "Everyone" -Force
        Write-Host "Removed 'Everyone' from $shareName"
    } catch {}

    # --- Reset group's share access before grant ------------------------------
    try {
        Revoke-SmbShareAccess -Name $shareName -AccountName $domainLocalGroup -Force
        Write-Host "Removed existing share-level access for: $domainLocalGroup"
    } catch {}

    # --- Grant requested access ------------------------------------------------
    if ($permission -eq "Change" -or $permission -eq "Modify") {
        Grant-SmbShareAccess -Name $shareName -AccountName $domainLocalGroup -AccessRight Change -Force
        Write-Host "Granted Change (Share) to $domainLocalGroup on $shareName"
    } elseif ($permission -eq "Read") {
        Grant-SmbShareAccess -Name $shareName -AccountName $domainLocalGroup -AccessRight Read -Force
        Write-Host "Granted Read (Share) to $domainLocalGroup on $shareName"
    } elseif ($permission -eq "FullControl" -or $permission -eq "Full") {
        Grant-SmbShareAccess -Name $shareName -AccountName $domainLocalGroup -AccessRight Full -Force
        Write-Host "Granted Full Control (Share) to $domainLocalGroup on $shareName"
    } else {
        Write-Warning "Unknown permission: $permission for $domainLocalGroup on $shareName"
    }
}