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
    Write-Host "6. Exit" -ForegroundColor White
    Write-Host "=============================================" -ForegroundColor White
}

# -------------------------------
# Function: Generate CSV File
# -------------------------------
function Run-GenerateCSV {
    Write-Host "`n[+] Running CSV generation locally..." -ForegroundColor DarkGray
    try {
        $repoRoot = $PSScriptRoot

        $input  = Join-Path $repoRoot "inputs\file-org-folder-permissions.xlsx"
        $config = Join-Path $repoRoot "inputs\servers.json"
        $outdir = Join-Path $repoRoot "derivatives"
        $script = Join-Path $repoRoot "submodules\fileorg-permissions-generator\generate_csv.py"

        if (-not (Test-Path $input)) {
            Write-Host "[!] Input file not found: $input" -ForegroundColor Red
            return
        }

        if (-not (Test-Path $config)) {
            Write-Host "[!] Config file not found: $config" -ForegroundColor Red
            return
        }

        if (-not (Test-Path $script)) {
            Write-Host "[!] CSV generator script not found: $script" -ForegroundColor Red
            return
        }

        # Ensure output directory exists
        if (-not (Test-Path $outdir)) {
            New-Item -ItemType Directory -Path $outdir | Out-Null
        }

        # Call Python with the required arguments
        & python $script `
            --input  $input `
            --config $config `
            --outdir $outdir `
            --verbose

        if ($LASTEXITCODE -eq 0) {
            Write-Host "CSV generation completed successfully!" -ForegroundColor Green
        } else {
            Write-Host "[!] CSV generation script exited with code $LASTEXITCODE" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Error generating CSV files: $_" -ForegroundColor Red
    }
    Pause
}

# -------------------------------
# Function: Create AD Domain Local Groups
# -------------------------------
function Run-DomainLocal {
    Write-Host "`n[+] Executing AD Domain Local Groups provisioning..." -ForegroundColor DarkGray
    try {
        .\run-DomainLocal.ps1 -Cred $Cred -Verbose
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
    Write-Host "`n[+] Applying NTFS permissions..." -ForegroundColor DarkGray
    try {
        .\run-NTFS.ps1 -Cred $Cred -Verbose
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
    Write-Host "`n[+] Applying SMB share permissions..." -ForegroundColor DarkGray
    try {
        .\run-SMB.ps1 -Cred $Cred -Verbose
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
    Write-Host "`n[+] Configuring DFS Namespace and Replication..." -ForegroundColor DarkGray
    try {
        .\run-DFS.ps1 -Cred $Cred -Verbose
        Write-Host "DFS Namespace and Replication configured successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Error configuring DFS: $_" -ForegroundColor Red
    }
    Pause
}

# -------------------------------
# Function: Close Program
# -------------------------------
function Exit-Script {
    Write-Host "`nExiting the orchestrator...`n" -ForegroundColor DarkGray
    exit
}

# -------------------------------
# Main Loop
# -------------------------------

# Ask for credentials once
$Cred = Get-Credential -Message "Enter domain admin credentials"

do {
    Show-Menu
    $choice = Read-Host "Select an option (1-6)"

    switch ($choice) {
        1 { Run-GenerateCSV }
        2 { Run-DomainLocal }
        3 { Run-NTFS }
        4 { Run-SMB }
        5 { Run-DFS }
        6 { Exit-Script }
        default {
            Write-Host "Invalid selection. Please choose a valid option (1-6)."
            Pause
        }
    }
} while ($true)