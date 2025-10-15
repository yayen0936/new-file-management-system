## 📋 Overview

PowerShell script automates provisioning of DFS Namespaces, DFS Folders, and DFS Replication using CSV manifests. It simplifies setup, ensures consistency, and reduces manual configuration errors.

---
## 📂 Repository Structure
```
DFS-Namespace-Replication/   ← Root folder
|
├─ DFS-Namespace-And-Replication.ps1
|
├─ .gitignore
└── README.md
```

---
## 💻 Usage Instructions

a) Prepare the required input CSV files under the `inputs/` folder in the meta repo:
   - `inputs/dfs-namespaces.csv`    
   - `inputs/dfs-replications.csv`

b) Change directory

Change directory to the repository root so that script and input paths resolve correctly

```powershell
PS> cd "C:\Users\ccrodua\Documents\New-File-System-Structure"
```

c) Run the PowerShell script

```powershell
PS> .\repos\DFS-Namespace-Replication\Create-DFS-Namespace-Replication.ps1 -CsvPath .\inputs\dfs-namespaces.csv -FoldersCsvPath .\inputs\dfs-replications.csv -Verbose
```