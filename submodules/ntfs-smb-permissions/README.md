# PowerShell Automation for NTFS Permissions and SMB Share & Permissions 

## 📋 Overview

PowerShell scripts that automate the creation of folders, assignment of NTFS permissions to folders and files, and provisioning of SMB shares with proper share-level permissions—all driven by structured CSV manifest files. Designed for Windows Server environments, these scripts help standardize and simplify the setup and management of secure shared folders.

---
## 📂 Repository Structure
```
FileShares-NTFS-SMBShare-Permissions/   ← Root folder
├── docs/         ← NTFS permission references
|
├─ Set-NTFS-Permissions.ps1
├─ Set-SMBShare-Permissions.ps1
|
├─ .gitignore
└── README.md
```

---
## 💻 Usage Instructions

a) Prepare the required input CSV files under the `inputs/` folder in the meta repo:
   - `inputs/ntfs-permissions.csv`    
   - `inputs/smb-share-permissions.csv`

Example: ntfs-permissions.csv

| FolderPath             | DomainLocalGroup          | Permissions    | AppliesTo                 |
| ---------------------- | ------------------------- | -------------- | ------------------------- |
| D:\GoodSpot            | GoodSpot-L-RW             | Modify         | ThisFolderSubfoldersFiles |
| D:\GoodSpot            | GoodSpot-L-RO             | ReadAndExecute | ThisFolderSubfoldersFiles |
| D:\GoodSpot\Consulting | GoodSpotConsulting-L-RW   | Modify         | ThisFolderSubfoldersFiles |
| D:\GoodSpot\Consulting | GoodSpotConsulting-L-RO   | ReadAndExecute | ThisFolderSubfoldersFiles |
| D:\GoodSpot\Projects   | GoodSpotDemoProjects-L-RW | Modify         | ThisFolderSubfoldersFiles |
| D:\GoodSpot\Projects   | GoodSpotDemoProjects-L-RO | ReadAndExecute | ThisFolderSubfoldersFiles |

Example: smb-share-permissions.csv

| FolderPath  | ShareName  | DomainLocalGroup | Permissions |
| ----------- | ---------- | ---------------- | ----------- |
| D:\GoodSpot | GoodSpot\$ | GoodSpot-L-RW    | Change      |
| D:\GoodSpot | GoodSpot\$ | GoodSpot-L-RO    | Read        |

b) Change directory
Change directory to the repository root so that script and input paths resolve correctly

```powershell
PS> cd "C:\Users\ccrodua\Documents\New-File-System-Structure"
```

c) Run the PowerShell script

**NTFS Permissions:**
```powershell
PS> .\repos\FileShares-NTFS-SMBShare-Permissions\Set-NTFS-Permissions.ps1 -CsvPath .\inputs\ntfs-permissions.csv -Verbose
```

**SMB Permissions:**
```powershell
PS> .\repos\FileShares-NTFS-SMBShare-Permissions\Set-SMBShare-Permissions.ps1 -CsvPath .\inputs\smb-share-permissions.csv -Verbose
```

---
🛡️ Best Practices
- Assign NTFS permissions first before configuring SMB share permissions.
- Use security groups instead of individual users where possible.
- Use hidden shares ($) for administrative or sensitive shares.
- Disable inheritance at the root of each share if needed for security.

