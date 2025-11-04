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

Step 2: **Launch the Main Orchestrator Menu**
```powershell
.\main.ps1
```

```powershell
=============================================
   FILE MANAGEMENT SYSTEM - MAIN MENU
=============================================
1. Generate CSV File
2. Create AD Domain Local Groups
3. Apply NTFS Permissions
4. Apply SMB Share Permissions
5. Configure DFS Namespace and Replication
6. Run Full Orchestration (One-Click)
7. Exit
=============================================
Select an option (1-7):
```

```
Each option executes a corresponding task:

| Menu Option       | Action                                             | Execution Context |
|--------------     |---------                                           |------------------ |
| **1**             | Generates new CSV files using the Python generator | Runs locally on Client |
| **2**             | Creates Domain Local Groups in AD                  | Executes remotely on DC |
| **3**             | Applies NTFS permissions                           | Executes remotely on each file server |
| **4**             | Applies SMB share permissions                      | Executes remotely on each file server |
| **5**             | Configures DFS namespace and replication           | Executes remotely on DC |
| **6**             | Runs the full pipeline (1–5 sequentially)          | Orchestrates full remote provisioning |
| **7**             | Exits the program                                  | — |
```
