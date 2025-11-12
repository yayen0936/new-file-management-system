try {
    $Host.UI.RawUI.BackgroundColor = 'Black'
    $Host.UI.RawUI.ForegroundColor = 'White'
    Clear-Host
} catch {}

function Show-Menu {
    Clear-Host
    Write-Host "=============================================" -ForegroundColor White
    Write-Host "   FILE MANAGEMENT SYSTEM - MAIN MENU" -ForegroundColor White
    Write-Host "=============================================" -ForegroundColor White
    Write-Host "1. Generate CSV File" -ForegroundColor White
    Write-Host "2. Create AD Domain Local Groups" -ForegroundColor White
    Write-Host "3. Apply NTFS Permissions" -ForegroundColor White
    Write-Host "4. Apply SMB Share Permissions" -ForegroundColor White
    Write-Host "5. Configure DFS Namespace and Replication" -ForegroundColor White
    Write-Host "6. Run Full Orchestration (One-Click)" -ForegroundColor White
    Write-Host "7. Exit" -ForegroundColor White
    Write-Host "=============================================" -ForegroundColor White
}

# -------------------------------
# Function: Generate CSV File
# -------------------------------
function Run-GenerateCSV {
    Write-Host "`n[+] Running CSV generation locally..." -ForegroundColor White
    try {
        python .\submodules\fileorg-permissions-generator\generate_csv.py
        Write-Host "CSV generation completed successfully!" -ForegroundColor White
    } catch {
        Write-Host "Error generating CSV files: $_" -ForegroundColor White
    }
    Pause
}

# -------------------------------
# Function: Create AD Domain Local Groups
# -------------------------------
function Run-DomainLocal {
    Write-Host "`n[+] Executing AD Domain Local Groups provisioning..." -ForegroundColor White
    try {
        .\run-DomainLocal.ps1 -Verbose
        Write-Host "AD Domain Local Groups created successfully!" -ForegroundColor White
    } catch {
        Write-Host "Error running Domain Local Groups script: $_" -ForegroundColor White
    }
    Pause
}

# -------------------------------
# Function: Create Folder and Apply NTFS Permissions
# -------------------------------
function Run-NTFS {
    Write-Host "`n[+] Applying NTFS permissions..." -ForegroundColor White
    try {
        .\run-NTFS.ps1 -Verbose
        Write-Host "NTFS permissions applied successfully!" -ForegroundColor White
    } catch {
        Write-Host "Error applying NTFS permissions: $_" -ForegroundColor White
    }
    Pause
}

# -------------------------------
# Function: Share Folder and Apply SMB Share Permissions
# -------------------------------
function Run-SMB {
    Write-Host "`n[+] Applying SMB share permissions..." -ForegroundColor White
    try {
        .\run-SMB.ps1 -Verbose
        Write-Host "SMB share permissions applied successfully!" -ForegroundColor White
    } catch {
        Write-Host "Error applying SMB permissions: $_" -ForegroundColor White
    }
    Pause
}

# -------------------------------
# Function: Configure DFS Namespace and Replication
# -------------------------------
function Run-DFS {
    Write-Host "`n[+] Configuring DFS Namespace and Replication..." -ForegroundColor White
    try {
        .\run-DFS.ps1 -Cred $Cred -Verbose
        Write-Host "DFS Namespace and Replication configured successfully!" -ForegroundColor White
    } catch {
        Write-Host "Error configuring DFS: $_" -ForegroundColor White
    }
    Pause
}

# -------------------------------
# Function: Run Full Orchestration (One-Click)
# -------------------------------
function Run-FullOrchestration {
    Write-Host "`n[+] Starting full orchestration process..." -ForegroundColor White
    try {
        Write-Host "`n--- Step 1: Generate CSV Files ---" -ForegroundColor White
        Run-GenerateCSV
        Write-Host "CSV generation completed successfully!" -ForegroundColor White

        Write-Host "`n--- Step 2: Create AD Domain Local Groups ---" -ForegroundColor White
        Run-DomainLocal
        Write-Host "AD Domain Local Groups created successfully!" -ForegroundColor White

        Write-Host "`n--- Step 3: Apply NTFS Permissions ---" -ForegroundColor White
        Run-NTFS
        Write-Host "NTFS permissions applied successfully!" -ForegroundColor White

        Write-Host "`n--- Step 4: Apply SMB Share Permissions ---" -ForegroundColor White
        Run-SMB
        Write-Host "SMB share permissions applied successfully!" -ForegroundColor White

        Write-Host "`n--- Step 5: Configure DFS Namespace and Replication ---" -ForegroundColor White
        Run-DFS

        Write-Host "DFS Namespace and Replication configured successfully!" -ForegroundColor White
        Write-Host "`nFull orchestration completed successfully!" -ForegroundColor White
    } catch {
        Write-Host "Error during full orchestration: $_" -ForegroundColor White
    }
    Pause
}

# -------------------------------
# Function: Close Program
# -------------------------------
function Exit-Script {
    Write-Host "`nExiting the orchestrator...`n" -ForegroundColor White
    exit
}

# -------------------------------
# Main Loop
# -------------------------------

# Ask for credentials once
$Cred = Get-Credential -Message "Enter domain admin credentials"

do {
    Show-Menu
    $choice = Read-Host "Select an option (1-7)"

    switch ($choice) {
        1 { Run-GenerateCSV }
        2 { Run-DomainLocal }
        3 { Run-NTFS }
        4 { Run-SMB }
        5 { Run-DFS }
        6 { Run-FullOrchestration }
        7 { Exit-Script }
        default {
            Write-Host "Invalid selection. Please choose a valid option (1-7)."
            Pause
        }
    }
} while ($true)
