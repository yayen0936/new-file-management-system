# File Organization PowerShell Inputs
---
This repository contains a Python script and supporting files for automating  
file system access control using **DFS folders** and **Active Directory security groups**.
---
## 📌 Overview 
The script reads a **role-based matrix** (Excel/CSV) containing DFS folders,  
subfolders, and global security group assignments (RO/RW).  

It generates four Excel outputs that map security groups, NTFS ACLs, and SMB shares:  

1. **domainlocal-groups.xlsx**  dddddd
   - Domain Local Groups for each DFS folder/subfolder (RO/RW variants)  
   - Columns: `GroupName`, `Description`, `NestedOUs`dddddddd, `Members`  

2. **global-groups.xlsx**  
   - Global Security Groups detected from role headers  
   - Columns: `GroupName`, `SamAccountName`, `Description`, `OU`, `Members`  
   - Extra columns are left blank for manual population  

3. **ntfs-permissions.xlsx**  
   - NTFS folder permissions matrix  
   - Columns: `FolderPath`, `DomainLocalGroup`, `Permissions`, `AppliesTo`  
   - RO → `ReadAndExecute`, RW → `Modify`  

4. **smb-share-permissions.xlsx**  
   - SMB share permissions for root DFS folders only  
   - Columns: `FolderPath`, `ShareName`, `DomainLocalGroup`, `Permissions`  
   - RO → `Read`, RW → `Change` 
---
## 📂 Repository Structure

```
fileorg-ps-input/
│ 
├─ inputs/ # Excel/CSV input files
│ └─ file-org-folder-permissions-20250812/
│ └─ servers.json
│ 
├─ fileorg-ps-input.py # Main Python script
│ 
├─ outputs/ # Generated Excel outputs
│ └─ ad-domainlocal-groups.csv
│ └─ ad-global-groups.csv
│ └─ ntfs-permissions__ITSRVR-DC01.csv
│ └─ ntfs-permissions__ITSRVR-DC02.csv
│ └─ smb-share-permissions__ITSRVR-DC01.csv
│ └─ smb-share-permissions__ITSRVR-DC02.csv
│ └─ dfs-namespaces.csv
│ └─ dfs-replications.csv
│ 
├─ .gitignore
│ 
└─ README.md
```
---
## 💻 Usage Instructions

Step 1: Open PowerShell. 

Step 2: Change directory to the repository root so that script and input paths resolve correctly.
```bash
PS> cd C:\Users\<replace>\Documents\new-file-management-system\submodules\fileorg-powershell-inputs
```

Step 3: Run the script with your Excel input file:

Multi-line (PowerShell backticks ` for line continuation)
```bash
    python .\fileorg-ps-input.py `
    --config .\inputs\servers.json `
    --input ".\inputs\file-org-folder-permissions-20250812.xlsx" `
    --sheet "Sheet1" `
    --out ".\outputs\ad-global-groups.csv" `
    --out ".\outputs\ad-domainlocal-groups.csv" `
    --out ".\outputs\ntfs-permissions.csv" `
    --out ".\outputs\smb-share-permissions.csv" `
    --out ".\outputs\dfs-namespaces.csv" `
    --out ".\outputs\dfs-replications.csv" `
    --verbose
```
---
⚠️ Troubleshooting
If you encounter missing package errors, install dependencies:
```bash
python -m pip install --upgrade pip
python -m pip install pandas openpyxl
```