# New File Management System

This repository is a project for automating the provisioning and management of:
 - **Active Directory (AD) Domain Local security groups**
 - **NTFS and SMB permissions across file servers (LOUIE and DEWEY)**
 - **DFS Namespaces and DFS Replication**

It uses a combination of:
- **Input files (Excel/CSV)**
- **Python-based CSV generator**
- **PowerShell submodules**
- **A main menu–driven orchestrator (main.ps1)**

## 📂 Repository Structure

```
new-file-management-system/
│
├─ derivatives/                     # Auto-generated CSV outputs
│  ├─ ad-domainlocal-groups.csv
│  │  ├─ group-membership/          # Validates/adds/removes Global Group membership in Domain Local Groups
│  │  │  ├─ validate-DomainLocal-Members.ps1
│  │  │  ├─ add-DomainLocal-Members.ps1
│  │  │  └─ remove-DomainLocal-Members.ps1
│  ├─ ntfs-permissions__SERVER.csv
│  ├─ smb-share-permissions__SERVER.csv
│  ├─ dfs-namespaces.csv
│  ├─ dfs-replications.csv
│
├─ inputs/                          # Input & config files
│  ├─ file-org-folder-permissions.xlsx
│  ├─ servers.json                  # File servers, DFS root servers, share suffix
│
├─ audit/                           # Validation reports and group membership action logs
│  ├─ DomainLocal-Members-<timestamp>.csv
│  ├─ Added-Members-<timestamp>.txt
│  └─ Removed-Members-<timestamp>.txt
│
├─ submodules/                      # Independent modules (Git submodules)
│  ├─ ad-security-groups/           # Creates AD Domain Local groups
│  ├─ ntfs-smb-permissions/         # Sets NTFS & SMB permissions
│  ├─ dfs-namespace-replication/    # DFS namespaces & replication config
│  └─ fileorg-permissions-generator/# Python CSV generator
│
├─ run-DomainLocal.ps1              # Individual AD group creation
├─ run-NTFS.ps1                     # Individual NTFS permission provisioning
├─ run-SMB.ps1                      # Individual SMB share provisioning
├─ run-DFS.ps1                      # Individual DFS namespace/replication
├─ run-GroupMembership.ps1          # Group membership assignment submenu
├─ main.ps1                         # NEW main menu-based orchestrator
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
cd C:\Users\<your-name>\Documents\new-file-management-system
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
7. Group Membership Assignment
8. Exit
=============================================
Select an option (1-8):

## 👥 Group Membership Assignment Menu

Option 7 opens the Group Membership Assignment submenu.

```powershell
=============================================
    GROUP MEMBERSHIP ASSIGNMENT
=============================================
1. Validate Domain Local Group Members
2. Add Members
3. Remove Members
4. Return to Main Menu
=============================================
Select an option (1-4):
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
| **7**             | Opens the Group Membership Assignment submenu      | Executes remotely on DC |
| **8**             | Exits the program                                  | — |
```