[CmdletBinding()]
param(
    [string]$ValidateScript = ".\submodules\ad-security-groups\group-membership\validate-DomainLocal-Members.ps1",
    [string]$AddScript      = ".\submodules\ad-security-groups\group-membership\add-DomainLocal-Members.ps1",
    [string]$RemoveScript   = ".\submodules\ad-security-groups\group-membership\remove-DomainLocal-Members.ps1",

    [Parameter(Mandatory)]
    [PSCredential]$Cred
)

# --- Validate paths ----------------------------------------------------------
if (-not (Test-Path $ValidateScript)) { throw "Validation script not found: $ValidateScript" }
if (-not (Test-Path $AddScript))      { throw "Add member script not found: $AddScript" }
if (-not (Test-Path $RemoveScript))   { throw "Remove member script not found: $RemoveScript" }

function Show-GroupMembersMenu {
    Clear-Host
    Write-Host "=============================================" -ForegroundColor White
    Write-Host "    GROUP MEMBERSHIP ASSIGNMENT" -ForegroundColor White
    Write-Host "=============================================" -ForegroundColor White
    Write-Host "1. Validate Domain Local Group Members" -ForegroundColor White
    Write-Host "2. Add Members" -ForegroundColor White
    Write-Host "3. Remove Members" -ForegroundColor White
    Write-Host "4. Return to Main Menu" -ForegroundColor White
    Write-Host "=============================================" -ForegroundColor White

}
function Run-ValidateDomainLocalMembers {
    Write-Host "`n[+] Validating Domain Local Group members..." -ForegroundColor DarkGray
    try {
        & $ValidateScript
    }
    catch {
        Write-Host "Error validating Domain Local Group members: $_" -ForegroundColor Red
    }
    Pause
}

function Run-AddDomainLocalMembers {
    Write-Host "`n[+] Adding missing Global Groups members to Domain Local Groups..." -ForegroundColor DarkGray
    try {
        & $AddScript
    }
    catch {
        Write-Host "Error adding Global Groups members to Domain Local Groups: $_" -ForegroundColor Red
    }
    Pause
}
function Run-RemoveDomainLocalMembers {
    Write-Host "`n[+] Removing extra Global Groups members from Domain Local Groups..." -ForegroundColor DarkGray
    try {
        & $RemoveScript
    }
    catch {
        Write-Host "Error removing Global Groups members from Domain Local Groups: $_" -ForegroundColor Red
    }
    Pause
}

do {
    Show-GroupMembersMenu
    $choice = Read-Host "Select an option (1-4)"

    switch ($choice) {
        1 { Run-ValidateDomainLocalMembers }
        2 { Run-AddDomainLocalMembers }
        3 { Run-RemoveDomainLocalMembers }
        4 { return }
        default {
            Write-Host "Invalid selection. Please choose a valid option (1-4)." -ForegroundColor Yellow
            Pause
        }
    }
} while ($true)