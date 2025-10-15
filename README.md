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
├─ inputs/                   # CSV inputs & pipeline config
│  ├─ ad-domainlocal-groups.csv
│  ├─ ntfs-permissions.csv
│  ├─ smb-share-permissions.csv
│  ├─ dfs-namespaces.csv
│  ├─ dfs-replications.csv
│  └─ pipeline.config.json   # Orchestrator step definitions
│
├─ submodules/                    # Submodules (child repos)
│  ├─ ad-security-groups/
│  ├─ ntfs-smb-permissions/
│  └─ dfs-namespace-replication/
│  └─ fileorg-powershell-inputs/
│
├─ Run-All.ps1               # Orchestrator to execute full pipeline
|
├─ .gitmodules               # Submodule references
├─ .gitignore
│
└─ README.md
```
---

## 💻 Usage Instructions

**Run-All.ps1 uses inputs\pipeline.config.json to know which scripts to run and which CSVs to pass.**

a) **Prepare the required input CSV files under the `inputs/` folder:**

1. **Create AD Domain Local Groups**  
   - `inputs/ad-domainlocal-groups.csv` → Defines AD **Domain Local Security Groups** to be created.  

2. **Set NTFS Permissions**  
   - `inputs/ntfs-permissions.csv` → Defines NTFS folder and file permissions to be applied.  

3. **Set SMB Share Permissions**  
   - `inputs/smb-share-permissions.csv` → Defines SMB share-level permissions to be applied.  

4. **Create DFS Namespace and Replication**  
   - `inputs/dfs-namespaces.csv` → Defines DFS namespaces to be created.  
   - `inputs/dfs-replications.csv` → Defines DFS replication groups and replicated folders.  


b) **Run via Orchestrator**  

> First, change directory to the repository root so that script and input paths resolve correctly:

```powershell
PS> cd C:\Users\<replace>\Documents\new-file-management-system
```

```powershell
PS> .\Run-All.ps1 -Verbose
```
Logs are written to .\logs\pipeline-<timestamp>.log