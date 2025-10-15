<#
.SYNOPSIS
    Creates Domain Local security groups from a CSV manifest and optionally adds members (global group).

.DESCRIPTION
    Reads a CSV and, for each row:
      - Resolves the target OU from "NestedOUs" (accepts full DN or relative path under -BaseOU).
      - Verifies the OU exists.
      - Skips creation if a same-name group already exists at that OU (one-level check).
      - Creates a Security Group - Domain Local with the provided Description (or a timestamped default).
      - Adds members listed in "Members" (delimiters supported: ';' '|' ',') by resolving sAMAccountName or CN.
    Emits a console summary table and returns result objects for automation.

.PARAMETER CsvPath
    Path to the CSV file with columns:
      GroupName, Description, NestedOUs, Members
    - Members may contain multiple principals separated by ';' '|' ','.
    - NestedOUs may be a full DN (contains OU=... and DC=...) or a relative path like "Resources/Apps".

.PARAMETER BaseOU
    Base distinguished name used when NestedOUs is a relative path.
    Example: "OU=LAB Groups,DC=ad,DC=itsummerlab,DC=local"

.EXAMPLE
    # Step 1: Navigate to the repository root directory
    cd "C:\Users\YAYEN\Documents\new-file-management-system"

    # Step 2: Run the provisioning script to create Domain Local security groups from the CSV manifest
    .\submodules\ad-security-groups\Create-AD-DomainLocal-Groups.ps1 `
        -CsvPath ".\derivatives\ad-domainlocal-groups.csv" `
        -Verbose

    # If you encounter an error such as:
    #   "Import-Module : The specified module 'ActiveDirectory' was not loaded..."
    #   this indicates the Active Directory module (RSAT) is missing.
    #
    # Install it using the following command (requires Administrator privileges):
    #
    Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
    #
    # After installation, open a new PowerShell window and re-run the script.

.NOTES
    Author: Clarence Crodua
    Date: 2025-10-8
    Version: 1.6

.LINK
    * Windows Server Documentation
    1) Active Directory security groups
       https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/understand-security-groups
    2) Active Directory Domain Services (AD DS) overview
       https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/active-directory-domain-services

    * PowerShell cmdlet reference
    1) Add-ADGroupMember
       https://learn.microsoft.com/en-us/powershell/module/activedirectory/add-adgroupmember?view=windowsserver2025-ps
    2) New-ADGroup
       https://learn.microsoft.com/en-us/powershell/module/activedirectory/new-adgroup?view=windowsserver2025-ps
    3) Get-ADGroup
       https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adgroup?view=windowsserver2025-ps
    4) Get-ADOrganizationalUnit
       https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adorganizationalunit?view=windowsserver2025-ps
    5) Get-ADDomain
       https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-addomain?view=windowsserver2025-ps
    6) Get-ADObject
       https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adobject?view=windowsserver2025-ps
    7) Import-Csv
       https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/import-csv
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath,

    # Base container for your branch (e.g., "OU=LAB Groups,DC=ad,DC=itsummerlab,DC=local")
    # Used when the CSV "NestedOUs" value is given as a relative path.
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$BaseOU = "OU=LAB Groups,DC=ad,DC=itsummerlab,DC=local"
)

# ---------------- AD module ---------------------------------------------------
# Load the AD module and stop immediately if unavailable (prevents partial runs without AD cmdlets).
Import-Module ActiveDirectory -ErrorAction Stop

# ---------------- Helpers -----------------------------------------------------

# Verify an OU exists by DN
function Test-ADOUExists {
    param([Parameter(Mandatory)][string]$DistinguishedName)
    # Attempt to read the OU; success returns $true, failure (throws) returns $false.
    try { Get-ADOrganizationalUnit -Identity $DistinguishedName -ErrorAction Stop | Out-Null; $true }
    catch { $false }
}

# Check if a group with CN = GroupName exists directly in a given OU
function Test-ADGroupExistsInOU {
    param(
        [Parameter(Mandatory)][string]$GroupName,
        [Parameter(Mandatory)][string]$OuDn
    )
    # Escape single quotes for the LDAP filter string.
    $nameEsc = $GroupName.Replace("'", "''")
    # OneLevel scope ensures we only check the specified OU, not its children.
    $g = Get-ADGroup -Filter "Name -eq '$nameEsc'" -SearchBase $OuDn -SearchScope OneLevel -ErrorAction SilentlyContinue
    return [bool]$g
}

# Convert a relative path like "Resources" or "Apps/ShareX" to a full DN under BaseOU
function Convert-NestedOUsToDistinguishedName {
    param(
        [Parameter(Mandatory)][string]$NestedOUs,
        [Parameter(Mandatory)][string]$BaseOU
    )
    # Accept full DN as-is (if someone provided one)
    if ($NestedOUs -match '(^|\b)OU=' -and $NestedOUs -match 'DC=') { return $NestedOUs.Trim() }

    # Split on "\" or "/" and build DN leaf-first (child -> parent -> BaseOU)
    $parts = $NestedOUs -split '[\\/]' | Where-Object { $_ -and $_.Trim() -ne '' } | ForEach-Object { "OU=$($_.Trim())" }
    [array]::Reverse($parts)
    return (@($parts) + $BaseOU) -join ','
}

# Resolve a principal by sAMAccountName or CN across the domain; return DN if found, else $null
function Resolve-PrincipalDn {
    param([Parameter(Mandatory)][string]$Identity)

    $id = $Identity.Trim()
    if (-not $id) { return $null }

    # --- Escape LDAP special characters (manual fallback for RSAT clients)
    $escapedId = $id -replace '([\\\*\(\)])', '\\$1'

    # 1) Try sAMAccountName exact match
    try {
        $domainDn = (Get-ADDomain).DistinguishedName
    } catch {
        $domainDn = "DC=ad,DC=itsummerlab,DC=local"
    }

    $obj = Get-ADObject -LDAPFilter "(samAccountName=$escapedId)" -SearchBase $domainDn -SearchScope Subtree -ErrorAction SilentlyContinue
    if ($obj) { return $obj.DistinguishedName }

    # 2) Try CN exact match (for global groups or names with spaces)
    $obj = Get-ADObject -LDAPFilter "(cn=$escapedId)" -SearchBase $domainDn -SearchScope Subtree -ErrorAction SilentlyContinue
    if ($obj) { return $obj.DistinguishedName }

    Write-Warning "Member not found in AD: $id"
    return $null
}

# ---------------- Load CSV ----------------------------------------------------
try {
    # Attempt to import the CSV manifest; fail fast with a clear error if unreadable.
    $rows = Import-Csv -Path $CsvPath
} catch {
    Write-Error "Failed to read CSV: $($_.Exception.Message)"
    exit 1
}

# Validate required headers exist
$requiredHeaders = 'GroupName','Description','NestedOUs','Members'
# Check the first row's properties as a quick schema validation.
$missing = $requiredHeaders | Where-Object { $_ -notin $rows[0].PsObject.Properties.Name }
if ($missing) {
    Write-Error "CSV missing required column(s): $($missing -join ', ')"
    exit 1
}

# ---------------- Process rows -----------------------------------------------
# Collect per-row outcomes for a human-readable summary and machine consumption.
$results = New-Object System.Collections.Generic.List[object]

foreach ($row in $rows) {
    # Pull/trim values
    $GroupName  = ([string]$row.GroupName).Trim()
    $Desc       = ([string]$row.Description).Trim()
    $NestedOUs  = ([string]$row.NestedOUs).Trim()
    $MembersRaw = ([string]$row.Members)

    # Basic validation per row with actionable warnings.
    if (-not $GroupName)  { Write-Warning "Skipping row with empty GroupName."; continue }
    if (-not $NestedOUs)  { Write-Warning "Skipping '$GroupName' — NestedOUs is empty."; continue }

    # Resolve OU DN from NestedOUs under BaseOU
    $targetOuDn = Convert-NestedOUsToDistinguishedName -NestedOUs $NestedOUs -BaseOU $BaseOU

    # Ensure the target OU exists; do not auto-create OUs here.
    if (-not (Test-ADOUExists -DistinguishedName $targetOuDn)) {
        Write-Warning "OU path does not exist for '$GroupName': $targetOuDn"
        $results.Add([pscustomobject]@{ GroupName=$GroupName; OU=$targetOuDn; Created=$false; AddedMembers=0; SkippedMembers=''; Message='OU not found' })
        continue
    }

    # Skip if group already exists in that OU
    if (Test-ADGroupExistsInOU -GroupName $GroupName -OuDn $targetOuDn) {
        Write-Warning "Group already exists in OU. Skipping: $GroupName  [$targetOuDn]"
        $results.Add([pscustomobject]@{ GroupName=$GroupName; OU=$targetOuDn; Created=$false; AddedMembers=0; SkippedMembers=''; Message='Exists' })
        continue
    }

    # Create Domain Local Security group
    try {
        # Use CSV Description when provided; otherwise add a timestamped default.
        $descToUse = if ($Desc) { $Desc } else { "Created by script on $(Get-Date -Format 'yyyy-MM-dd')" }
        New-ADGroup -Name $GroupName -GroupScope DomainLocal -GroupCategory Security -Path $targetOuDn -Description $descToUse
        Write-Host "Created Domain Local group: $GroupName  Path: $targetOuDn" -ForegroundColor Green
        $created = $true
    } catch {
        # Capture error message and move on to next row (keeps the batch going).
        Write-Error "Failed to create group '$GroupName': $($_.Exception.Message)"
        $results.Add([pscustomobject]@{ GroupName=$GroupName; OU=$targetOuDn; Created=$false; AddedMembers=0; SkippedMembers=''; Message=$_.Exception.Message })
        continue
    }

    # Add members from CSV (supports ; | , separators)
    $added = 0; $skipped = @()
    if ($MembersRaw) {
        # Split into tokens, trim each one, and discard empties.
        $memberTokens = $MembersRaw -split '[;|,]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        if ($memberTokens.Count -gt 0) {
            # Resolve the newly created group DN (Identity can be DN or sAM; we use DN for clarity)
            $newGroup = Get-ADGroup -Filter "Name -eq '$($GroupName.Replace("'", "''"))'" -SearchBase $targetOuDn -SearchScope OneLevel
            $targetGroupDn = $newGroup.DistinguishedName

            foreach ($m in $memberTokens) {
                # Try to resolve each principal by sAM or CN; if not found, record as skipped.
                $memberDn = Resolve-PrincipalDn -Identity $m
                if (-not $memberDn) { $skipped += $m; continue }
                try {
                    # Use DN for Identity and Members to avoid ambiguity.
                    Add-ADGroupMember -Identity $targetGroupDn -Members $memberDn -ErrorAction Stop
                    $added++
                    Write-Host "  + Added member: $m" -ForegroundColor DarkGreen
                } catch {
                    # Preserve the error per member for post-run triage.
                    $skipped += "$m (err: $($_.Exception.Message))"
                }
            }
        }
    }

    # Persist outcome for this row into the result list.
    $results.Add([pscustomobject]@{
        GroupName     = $GroupName
        OU            = $targetOuDn
        Created       = $created
        AddedMembers  = $added
        SkippedMembers= ($skipped -join '; ')
        Message       = 'Created'
    })
}

# ---------------- Summary -----------------------------------------------------
# Print a concise summary table for operators…
"`n==== Summary ===="
$results | Select-Object GroupName,OU,Created,AddedMembers,SkippedMembers,Message | Format-Table -AutoSize
# Also return objects for automation use (e.g., Export-Csv, logging, tests).
$results