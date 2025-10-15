## 🎯 Purpose

This PowerShell automation simplifies the bulk creation of Active Directory Security Domain Local Groups using data from a CSV manifest.
It validates the OU structure, prevents duplicate groups, and reduces manual work while ensuring accuracy and consistency.

---

## 📂 Repository Structure
```
AD-Security-DomainLocal-Groups/   ← Root folder
├─ Create-AD-DomainLocal-Groups.ps1
|
├─ .gitignore
└── README.md
```
---
## 💻 Usage Instructions

a) Prepare the required input CSV files under the `inputs/` folder in the meta repo:
   - `inputs/ad-domainlocal-groups.csv` → Defines AD **Domain Local Security Groups** to be created.  

b) Change directory
Change directory to the repository root so that script and input paths resolve correctly

```powershell
PS> cd "C:\Users\ccrodua\Documents\New-File-System-Structure"
```
c) Run the PowerShell script

```powershell
PS> .\repos\AD-Security-DomainLocal-Groups\Create-AD-DomainLocal-Groups.ps1 -CsvPath .\inputs\ad-domainlocal-groups.csv -Verbose
```