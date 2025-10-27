# New File Management System

This repository is a project for automating the provisioning and management of:
 - **Active Directory (AD) security groups**
 - **NTFS and SMB file permissions**
 - **DFS namespaces and replication**

The repo combines input CSV definitions, child repositories as submodules, and a top-level orchestrator script that executes all steps in sequence. 

It follows Microsoft best practices for PowerShell (Verb-Noun naming), and organizes files into inputs, submodules, docs, and logs for clarity.

## 📂 Repository Structure

```
new-file-management-system/
│
├─ derivatives/                     # CSV inputs
│  ├─ ad-domainlocal-groups.csv
│  ├─ ntfs-permissions.csv
│  ├─ smb-share-permissions.csv
│  ├─ dfs-namespaces.csv
│  ├─ dfs-replications.csv
│
├─ inputs/                          # pipeline config
│  └─ pipeline.config.json          # Orchestrator step definitions
│
├─ logs/
│
├─ submodules/                      # child repos
│  ├─ ad-security-groups/
│  ├─ ntfs-smb-permissions/
│  ├─ dfs-namespace-replication/
│  └─ fileorg-powershell-inputs/
│
├─ provision_all.ps1                # orchestrator to execute full pipeline
├─ run-DomainLocal.ps1              # orchestrator to create domain local groups
├─ run-NTFS.ps1                     # orchestrator to apply NTFS permissions
├─ run-SMB.ps1                      # orchestrator to apply SMB share & permissions
├─ run-DFS.ps1                      # orchestrator to apply DFS namespace & replication
|
├─ .gitmodules                      # submodule references
├─ .gitignore
│
└─ README.md
```
---

## 💻 How to run

Step 1: **Navigate to the repository root directory**
```powershell
cd C:\Users\<replace>\Documents\new-file-management-system
```

Step 2: **Generate input CSV files**
```powershell
python .\submodules\fileorg-permissions-generator\generate_csv.py `
  --input ".\inputs\file-org-folder-permissions.xlsx" `
  --config ".\inputs\servers.json" `
  --outdir ".\derivatives" `
  --verbose
```

Step 3: **Create Domain Local Groups**
```powershell
.\run-DomainLocal.ps1 -Verbose
```

Step 4: **Create Folder and Apply NTFS permissions**
```powershell
.\run-NTFS.ps1 -Verbose
```

Step 5: **Share Folder and Apply SMB permissions**
```powershell
.\run-SMB.ps1 -Verbose
```

Step 6: **Create DFS namespace and replication**
```powershell
.\run-DFS.ps1 -Verbose
```

Step 7: **Run orchestrator**
```powershell
.\provision_all.ps1 `
 -Servers ".\inputs\servers.json" `
 -Permissions ".\inputs\file-org-folder-permissions.xlsx" `
 -Verbose
```