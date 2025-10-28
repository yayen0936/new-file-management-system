function Show-Menu {
    Clear-Host
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "   FILE MANAGEMENT SYSTEM - MAIN MENU" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "1. Generate CSV File" -ForegroundColor Yellow
    Write-Host "2. Create AD Domain Local Groups" -ForegroundColor Yellow
    Write-Host "3. Apply NTFS Permissions" -ForegroundColor Yellow
    Write-Host "4. Apply SMB Share Permissions" -ForegroundColor Yellow
    Write-Host "5. Configure DFS Namespace and Replication" -ForegroundColor Yellow
    Write-Host "6. Run Full Orchestration (One-Click)" -ForegroundColor Yellow
    Write-Host "7. Exit" -ForegroundColor Yellow
    Write-Host "=============================================" -ForegroundColor Cyan
}

# -------------------------------
# Function: Generate CSV File
# -------------------------------
function Run-GenerateCSV {
    Write-Host "`n[+] Running CSV generation locally..." -ForegroundColor Cyan
    try {
        python .\submodules\fileorg-permissions-generator\generate_csv.py
        Write-Host "CSV generation completed successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Error generating CSV files: $_" -ForegroundColor Red
    }
    Pause
}

# -------------------------------
# Function: Create AD Domain Local Groups
# -------------------------------
function Run-DomainLocal {
    Write-Host "`n[+] Executing AD Domain Local Groups provisioning..." -ForegroundColor Cyan
    try {
        .\run-DomainLocal.ps1 -Verbose
        Write-Host "AD Domain Local Groups created successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Error running Domain Local Groups script: $_" -ForegroundColor Red
    }
    Pause
}

# -------------------------------
# Function: Create Folder and Apply NTFS Permissions
# -------------------------------
function Run-NTFS {
    Write-Host "`n[+] Applying NTFS permissions..." -ForegroundColor Cyan
    try {
        .\run-NTFS.ps1 -Verbose
        Write-Host "NTFS permissions applied successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Error applying NTFS permissions: $_" -ForegroundColor Red
    }
    Pause
}

# -------------------------------
# Function: Share Folder and Apply SMB Share Permissions
# -------------------------------
function Run-SMB {
    Write-Host "`n[+] Applying SMB share permissions..." -ForegroundColor Cyan
    try {
        .\run-SMB.ps1 -Verbose
        Write-Host "SMB share permissions applied successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Error applying SMB permissions: $_" -ForegroundColor Red
    }
    Pause
}

# -------------------------------
# Function: Configure DFS Namespace and Replication
# -------------------------------
function Run-DFS {
    Write-Host "`n[+] Configuring DFS Namespace and Replication..." -ForegroundColor Cyan
    try {
        .\run-DFS.ps1 -Verbose
        Write-Host "DFS Namespace and Replication configured successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Error configuring DFS: $_" -ForegroundColor Red
    }
    Pause
}

# -------------------------------
# Function: Run Full Orchestration (One-Click)
# -------------------------------
function Run-FullOrchestration {
    Write-Host "`n[+] Starting full orchestration process..." -ForegroundColor Cyan
    try {
        Write-Host "`n--- Step 1: Generate CSV Files ---" -ForegroundColor Magenta
        python .\submodules\fileorg-permissions-generator\generate_csv.py
        Write-Host "CSV generation completed successfully!" -ForegroundColor Green

        Write-Host "`n--- Step 2: Create AD Domain Local Groups ---" -ForegroundColor Magenta
        .\run-DomainLocal.ps1 -Verbose
        Write-Host "AD Domain Local Groups created successfully!" -ForegroundColor Green

        Write-Host "`n--- Step 3: Apply NTFS Permissions ---" -ForegroundColor Magenta
        .\run-NTFS.ps1 -Verbose
        Write-Host "NTFS permissions applied successfully!" -ForegroundColor Green

        Write-Host "`n--- Step 4: Apply SMB Share Permissions ---" -ForegroundColor Magenta
        .\run-SMB.ps1 -Verbose
        Write-Host "SMB share permissions applied successfully!" -ForegroundColor Green

        Write-Host "`n--- Step 5: Configure DFS Namespace and Replication ---" -ForegroundColor Magenta
        .\run-DFS.ps1 -Verbose
        Write-Host "DFS Namespace and Replication configured successfully!" -ForegroundColor Green

        Write-Host "`nFull orchestration completed successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Error during full orchestration: $_" -ForegroundColor Red
    }
    Pause
}

# -------------------------------
# Function: Close Program
# -------------------------------
function Exit-Script {
    Write-Host "`nExiting the orchestrator...`n" -ForegroundColor Magenta
    exit
}

# -------------------------------
# Main Loop
# -------------------------------
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
            Write-Host "Invalid selection. Please choose a valid option (1-7)." -ForegroundColor Red
            Pause
        }
    }
} while ($true)