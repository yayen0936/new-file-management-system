#!/usr/bin/env python3
r"""
Examples
--------
# Step 1: Navigate to the repo root
cd "C:\Users\YAYEN\Documents\new-file-management-system"

# Step 2: Execute the CSV generator script
python .\submodules\fileorg-permissions-generator\generate_csv.py `
  --input ".\inputs\file-org-folder-permissions.xlsx" `
  --config ".\inputs\servers.json" `
  --outdir ".\derivatives" `
  --verbose
"""
from __future__ import annotations

import argparse
import json
import logging
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import pandas as pd

# =========================
# Global Constants
# =========================
# Column names expected in the file and folder organization permissions excel file
COL_DFS = "DFS Folder"
COL_SUB = "Subfolder"

# Only these permission tokens are accepted in role columns
PERM_TOKENS = ("RO", "RW")

# For joining multiple role names into the Members column
MEMBERS_JOIN = "; "

# Output column orders (kept centralized to avoid drift)
COLS_AD_DLG = ["GroupName", "Description", "NestedOUs", "Members"]
COLS_NTFS   = ["FolderPath", "DomainLocalGroup", "Permissions", "AppliesTo"]
COLS_SMB    = ["FolderPath", "ShareName", "DomainLocalGroup", "Permissions"]
COLS_DFS_NS = ["NamespaceServer", "NamespaceName"]
COLS_DFS_REP= ["Namespace", "Folder", "Server", "SMBShare", "ReplicationLocalPath"]

# Naming / text fragments
ROOT_SEGMENT = "Root"                              # used when Subfolder is blank
APPLIES_TO_DEFAULT = "ThisFolderSubfoldersFiles"  # standard inheritance scope for NTFS
NESTED_OUS_DEFAULT = "Resources"                  # example OU path (logical grouping)
DLG_NAME_FMT = "{dfs}-{sub}-L-{perm}"             # canonical DLG naming pattern
DESC_PREFIX = {"RO": "Read-only access for", "RW": "Read/Write access for"}
DESC_WHERE_ROOT = "Root Folder"
DESC_WHERE_SUB_FMT = "{sub} SubFolder"

# Permission mappings for downstream PowerShell scripts
NTFS_PERM_MAP = {"RO": "ReadAndExecute", "RW": "Modify"}
SMB_PERM_MAP  = {"RO": "Read", "RW": "Change"}

# Keep group/share name segments alphanumeric for safety
SANITIZE_RE = re.compile(r"[^A-Za-z0-9]")

# Keys used in servers.json
CFG_SERVERS           = "file_servers"
CFG_NAMESPACE_SERVERS = "dfs_root_servers"
CFG_SHARE_SUFFIX      = "share_suffix"
CFG_DRIVE_ROOT        = "drive_root"
CFG_FOLDER_PREFIX     = "folder_prefix"

# =========================
# Repo-aware Paths
# =========================
# Determine repo root based on this file's location:
# this script lives under submodules/fileorg-permissions-generator/, so go up twice.
SCRIPT_PATH = Path(__file__).resolve()
REPO_ROOT   = SCRIPT_PATH.parents[2]
DEFAULT_CONFIG_JSON = REPO_ROOT / "inputs" / "servers.json"  # default config file
DEFAULT_OUTDIR      = REPO_ROOT / "derivatives"              # default output directory

# =========================
# Logging
# =========================
def setup_logging(verbose: bool) -> None:
    """Configure console logging. INFO if --verbose else WARNING."""
    level = logging.INFO if verbose else logging.WARNING
    logging.basicConfig(level=level, format="%(levelname)s: %(message)s")

# =========================
# Helpers
# =========================
def sanitize(segment: Optional[str]) -> str:
    """Strip to alphanumerics; used for DLG names and SMB share names."""
    return SANITIZE_RE.sub("", str(segment)) if segment else ""

def norm_cell(val) -> str:
    """Normalize a role cell to '', 'RO', or 'RW' (uppercase, trims whitespace)."""
    if pd.isna(val):
        return ""
    s = str(val).strip().upper()
    return s if s in PERM_TOKENS else ""

def norm_drive_root(path: str) -> str:
    """Normalize drive roots to Windows style with trailing backslash, e.g., 'D:\\'."""
    return path.replace("/", "\\").rstrip("\\") + "\\"

def make_description(dfs_folder: str, subfolder: Optional[str], perm: str) -> str:
    """Compose a human-readable description for a DLG."""
    where = DESC_WHERE_SUB_FMT.format(sub=subfolder) if subfolder and str(subfolder).strip() else DESC_WHERE_ROOT
    return f"{DESC_PREFIX[perm]} {dfs_folder} {where}"

def roots_from_df(df: pd.DataFrame) -> List[str]:
    """Return all DFS root names (rows where Subfolder is blank)."""
    roots = []
    for _, r in df.iterrows():
        dfs = str(r.get(COL_DFS, "")).strip()
        sub = str(r.get(COL_SUB, "")).strip()
        if dfs and (not sub or sub.lower() == "nan"):
            roots.append(dfs)
    return sorted(set(roots))

# =========================
# Loaders
# =========================
def load_cfg(path: Path) -> Dict:
    """Load and parse servers.json; exit with a helpful message on failure."""
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        sys.exit(f"[ERROR] Failed to read servers.json: {e}")

def load_table(path: Path, sheet: Optional[str]) -> pd.DataFrame:
    """
    Load the input matrix from CSV or Excel.
    - CSV: simple pd.read_csv
    - Excel: select openpyxl for .xlsx/.xlsm, xlrd for .xls
    """
    if not path.exists():
        sys.exit(f"[ERROR] Input not found: {path}")

    ext = path.suffix.lower()

    # Fast path for CSV
    if ext == ".csv":
        return pd.read_csv(path)

    # Excel engine selection
    engine = None
    if ext in (".xlsx", ".xlsm"):
        engine = "openpyxl"
    elif ext == ".xls":
        engine = "xlrd"
    else:
        sys.exit("[ERROR] Unsupported input type (use .xlsx, .xlsm, .xls, or .csv)")

    # Read Excel with the chosen engine and clear guidance if it's missing
    try:
        return pd.read_excel(path, sheet_name=sheet or 0, engine=engine)
    except ImportError:
        needed = "openpyxl" if engine == "openpyxl" else "xlrd"
        sys.exit(
            f"[ERROR] Missing Excel engine '{needed}'. "
            f"Install it with: py -m pip install --user {needed}"
        )
    except ValueError as ve:
        sys.exit(
            f"[ERROR] {ve}\n"
            f"Hint: This file is '{ext}'. We tried engine='{engine}'. "
            f"If this isn't a real Excel file, export as .xlsx or .csv."
        )
    except Exception as e:
        sys.exit(f"[ERROR] Failed to read Excel file '{path.name}': {e}")

# =========================
# Config helpers
# =========================
def server_list(cfg: Dict) -> List[Tuple[str, str, str]]:
    """
    Expand servers.json into a list of (server_name, drive_root, folder_prefix).
    for file servers only. DFS root servers may not appear here if they are DC-only.
    """
    out: List[Tuple[str, str, str]] = []
    file_servers = cfg.get(CFG_SERVERS) or {}
    if not file_servers:
        sys.exit("[ERROR] No file_servers defined in servers.json")

    for name, s in file_servers.items():
        drive_root = s.get(CFG_DRIVE_ROOT)
        folder_prefix = s.get(CFG_FOLDER_PREFIX, "")

        if not drive_root:
            sys.exit(f"[ERROR] Server '{name}' missing drive_root in servers.json")

        out.append((name, drive_root, folder_prefix))
    return out

def combine_root(drive_root: str, prefix: str) -> str:
    r"""
    Build a base path like:  D:\Data\   (if prefix='Data')  or  D:\   (if prefix='')
    Ensures proper backslashes and trailing slash.
    """
    base = norm_drive_root(drive_root)
    pref = str(prefix or "").replace("/", "\\").strip("\\")
    return base + (pref + "\\" if pref else "")

def get_namespace_servers(cfg: Dict) -> List[str]:
    """
    Return the list of namespace servers.
    Requires explicit 'dfs_root_servers' list in servers.json.
    """
    ns_servers = cfg.get(CFG_NAMESPACE_SERVERS)
    if not isinstance(ns_servers, list) or not ns_servers:
        sys.exit("[ERROR] Missing or empty 'dfs_root_servers' in servers.json")
    return [str(s).strip() for s in ns_servers]

# =========================
# Builders
# =========================
def build_domainlocal_groups(df: pd.DataFrame) -> pd.DataFrame:
    """
    Build AD Domain Local Groups per DFS/Sub path for both RO and RW.
    'Members' lists the role headers that requested that permission for that row.
    """
    # Validate required columns early with a clear message
    if {COL_DFS, COL_SUB} - set(df.columns):
        raise ValueError(f'Missing required columns: "{COL_DFS}", "{COL_SUB}"')

    # Role columns = all columns except the two structural ones
    role_cols = [c for c in df.columns if c not in (COL_DFS, COL_SUB)]
    if not role_cols:
        raise ValueError("No role columns detected (e.g., 'Executive Director').")

    # Normalize text columns to keep comparisons predictable
    df = df.copy()
    df[COL_DFS] = df[COL_DFS].astype(str).str.strip().replace({"nan": ""})
    df[COL_SUB] = df[COL_SUB].astype(str).str.strip().replace({"nan": ""})

    rows: List[Tuple[str, str, str, str]] = []
    for _, r in df.iterrows():
        dfs_disp = r[COL_DFS]
        if not dfs_disp:
            continue  # skip empty DFS rows
        sub_disp = r[COL_SUB] if r[COL_SUB] else ""

        # Prepare sanitized name segments for safe DLG/Share naming
        seg1 = sanitize(dfs_disp)
        seg2 = sanitize(sub_disp) if sub_disp else ROOT_SEGMENT

        # Emit both RO and RW variants (even if Members ends up blank)
        for perm in PERM_TOKENS:
            members = [str(col).strip() for col in role_cols if norm_cell(r.get(col, "")) == perm]
            rows.append((
                DLG_NAME_FMT.format(dfs=seg1, sub=seg2, perm=perm),
                make_description(dfs_disp, sub_disp or None, perm),
                NESTED_OUS_DEFAULT,
                MEMBERS_JOIN.join(members)
            ))
    return pd.DataFrame(rows, columns=COLS_AD_DLG)

def build_ntfs(df: pd.DataFrame, drive_root: str, prefix: str) -> pd.DataFrame:
    """
    Build NTFS ACL rows for every DFS/Sub path on a specific server.
    Two entries per path: one for RO, one for RW.
    """
    if {COL_DFS, COL_SUB} - set(df.columns):
        raise ValueError(f'Missing required columns: "{COL_DFS}", "{COL_SUB}"')

    df = df.copy()
    df[COL_DFS] = df[COL_DFS].astype(str).str.strip().replace({"nan": ""})
    df[COL_SUB] = df[COL_SUB].astype(str).str.strip().replace({"nan": ""})

    base = combine_root(drive_root, prefix)  # e.g., "D:\Data\"
    rows: List[Tuple[str, str, str, str]] = []

    for _, r in df.iterrows():
        dfs_disp = r[COL_DFS]
        if not dfs_disp:
            continue
        sub_disp = r[COL_SUB] if r[COL_SUB] else ""

        # Build absolute target path for ACLs
        folder_path = f"{base}{dfs_disp}" if not sub_disp else f"{base}{dfs_disp}\\{sub_disp}"
        folder_path = folder_path.replace("\\\\", "\\")  # collapse accidental doubles

        # Group name components
        seg1 = sanitize(dfs_disp)
        seg2 = sanitize(sub_disp) if sub_disp else ROOT_SEGMENT

        for perm in PERM_TOKENS:
            rows.append((
                folder_path,
                DLG_NAME_FMT.format(dfs=seg1, sub=seg2, perm=perm),
                NTFS_PERM_MAP[perm],
                APPLIES_TO_DEFAULT
            ))
    return pd.DataFrame(rows, columns=COLS_NTFS)

def build_smb_roots(df: pd.DataFrame, drive_root: str, prefix: str, share_suffix: str) -> pd.DataFrame:
    """
    Build SMB share rows for DFS roots (Subfolder blank) on a specific server.
    Two entries per root: one for RO, one for RW (permissions on the share).
    """
    if {COL_DFS, COL_SUB} - set(df.columns):
        raise ValueError(f'Missing required columns: "{COL_DFS}", "{COL_SUB}"')

    df = df.copy()
    df[COL_DFS] = df[COL_DFS].astype(str).str.strip().replace({"nan": ""})
    df[COL_SUB] = df[COL_SUB].astype(str).str.strip().replace({"nan": ""})

    base = combine_root(drive_root, prefix)
    rows: List[Tuple[str, str, str, str]] = []

    for dfs_disp in roots_from_df(df):
        folder_path = f"{base}{dfs_disp}".replace("\\\\", "\\")
        seg1 = sanitize(dfs_disp)
        share_name = f"{seg1}{share_suffix}"  # e.g., "Finance$"

        for perm in PERM_TOKENS:
            rows.append((
                folder_path,
                share_name,
                DLG_NAME_FMT.format(dfs=seg1, sub=ROOT_SEGMENT, perm=perm),
                SMB_PERM_MAP[perm]
            ))
    return pd.DataFrame(rows, columns=COLS_SMB)

def build_dfs_namespaces(df: pd.DataFrame, cfg: Dict) -> pd.DataFrame:
    """
    Emit (NamespaceServer, NamespaceName) rows derived from the permissions input file.
    Supports multiple namespaces for future-proofing.
    """
    servers = get_namespace_servers(cfg)

    # Detect namespaces dynamically from the input file
    # Prefer explicit "Namespace" column if present
    if "Namespace" in df.columns:
        namespaces = sorted(df["Namespace"].dropna().unique())
    else:
        # Fallback: derive from DFS Folder if structured as "\\Domain\\Namespace\\Share"
        namespaces = sorted(set(str(x).split("\\")[0] for x in df[COL_DFS] if isinstance(x, str) and x.strip()))

    if not namespaces:
        sys.exit("[ERROR] No namespaces detected in permissions input file.")

    rows = []
    for ns in namespaces:
        for s in servers:
            rows.append({"NamespaceServer": s, "NamespaceName": ns})

    return pd.DataFrame(rows, columns=COLS_DFS_NS)

def build_dfs_replications(df: pd.DataFrame, cfg: Dict, share_suffix: str) -> pd.DataFrame:
    """
    Emit (Namespace, Folder, Server, SMBShare, ReplicationLocalPath)
    for every DFS root folder on every *file server*.
    DFS root servers (DC-only) host the namespace but do not contain replicated data.
    """
    dfs_root_servers = cfg.get(CFG_NAMESPACE_SERVERS, [])
    file_servers_cfg = cfg.get(CFG_SERVERS) or {}

    records: List[Dict[str, str]] = []

    # Prefer explicit "Namespace" column if present; otherwise, fallback to a default.
    if "Namespace" in df.columns:
        namespaces = sorted(df["Namespace"].dropna().unique())
    else:
        namespaces = ["DFS"]

    if not namespaces:
        sys.exit("[ERROR] No namespaces detected in permissions input file.")

    # --- Generate replication rows ---
    for ns_name in namespaces:
        for folder in roots_from_df(df):
            share = f"{sanitize(folder)}{share_suffix}"

            # Replication targets → file servers only
            for server, drive_root, prefix in server_list(cfg):
                base = combine_root(drive_root, prefix)
                records.append({
                    "Namespace": ns_name,
                    "Folder": folder,
                    "Server": server,
                    "SMBShare": share,
                    "ReplicationLocalPath": f"{base}{folder}".replace("\\\\", "\\")
                })

        # Informational: DFS root servers that are not file servers
        for dfs_root in dfs_root_servers:
            if dfs_root not in file_servers_cfg:
                logging.info(
                    f"DFS root server '{dfs_root}' hosts DFS namespace '{ns_name}' only "
                    f"(no local replication path)."
                )

    return pd.DataFrame(records, columns=COLS_DFS_REP)

# =========================
# Main
# =========================
def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate AD/NTFS/SMB/DFS CSVs from Excel/CSV + servers.json (repo-aware)."
    )
    # Require explicit input so runs are deterministic and auditable
    parser.add_argument("--input",  required=True, help="Path to .xlsx/.xls/.csv (explicit)")
    parser.add_argument("--sheet",  default=None, help="Excel sheet name (ignored for CSV)")
    parser.add_argument("--config", required=True, help="Path to servers.json")
    parser.add_argument("--outdir", required=True, help="Output directory")
    parser.add_argument("--share-suffix", default=None, help='Share name suffix (default: servers.json "share_suffix" or "$")')
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    setup_logging(args.verbose)

    # Resolve all paths early and create output directory if missing
    permissions = Path(args.input).resolve()
    servers   = Path(args.config).resolve()
    outdir     = Path(args.outdir).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    logging.info(f"Input:  {permissions}")
    logging.info(f"Config: {servers}")
    logging.info(f"Outdir: {outdir}")

    # Load config and matrix
    cfg = load_cfg(servers)
    df  = load_table(permissions, args.sheet)

    # Role columns (anything except the DFS/Subfolder structure columns)
    role_cols = [c for c in df.columns if c not in (COL_DFS, COL_SUB)]
    if not role_cols:
        sys.exit("[ERROR] No role columns detected (e.g., 'Executive Director').")

    # Log some context to help diagnose input issues
    servers = [s for s, _, _ in server_list(cfg)]
    logging.info(f"Servers: {', '.join(servers) if servers else '(none)'}")
    logging.info(f"Columns: {list(df.columns)}")
    logging.info(f"Role columns detected: {role_cols}")

    # Share suffix precedence: CLI > config > default "$"
    share_suffix = (
        args.share_suffix
        or cfg.get(CFG_SHARE_SUFFIX)
        or "$"
    )

    if not share_suffix:
        sys.exit("[ERROR] No share_suffix defined (provide --share-suffix or set in servers.json)")

    logging.info(f"Share suffix: {share_suffix!r}")

    # --- AD Domain Local Groups
    dlg = build_domainlocal_groups(df)
    dlg_path = outdir / "ad-domainlocal-groups.csv"
    dlg.to_csv(dlg_path, index=False, columns=COLS_AD_DLG)
    logging.info(f"Wrote {dlg_path} ({len(dlg)} rows)")

    # --- NTFS per server
    for server, drive_root, prefix in server_list(cfg):
        ntfs = build_ntfs(df, drive_root, prefix)
        ntfs_path = outdir / f"ntfs-permissions__{server}.csv"
        ntfs.to_csv(ntfs_path, index=False, columns=COLS_NTFS)
        logging.info(f"Wrote {ntfs_path} ({len(ntfs)} rows)")

    # --- SMB per server (roots only)
    for server, drive_root, prefix in server_list(cfg):
        smb = build_smb_roots(df, drive_root, prefix, share_suffix)
        smb_path = outdir / f"smb-share-permissions__{server}.csv"
        smb.to_csv(smb_path, index=False, columns=COLS_SMB)
        logging.info(f"Wrote {smb_path} ({len(smb)} rows)")

    # --- DFS namespaces
    dfs_ns = build_dfs_namespaces(df, cfg)
    dfs_ns_path = outdir / "dfs-namespaces.csv"
    dfs_ns.to_csv(dfs_ns_path, index=False, columns=COLS_DFS_NS)
    logging.info(f"Wrote {dfs_ns_path} ({len(dfs_ns)} rows)")

    # --- DFS replications
    dfs_rep = build_dfs_replications(df, cfg, share_suffix)
    dfs_rep_path = outdir / "dfs-replications.csv"
    dfs_rep.to_csv(dfs_rep_path, index=False, columns=COLS_DFS_REP)
    logging.info(f"Wrote {dfs_rep_path} ({len(dfs_rep)} rows)")

    # Final friendly summary for humans
    print("[DONE] CSVs written to:", outdir)
    print(" -", dlg_path.name)
    for server in servers:
        print(" -", f"ntfs-permissions__{server}.csv")
    for server in servers:
        print(" -", f"smb-share-permissions__{server}.csv")
    print(" -", dfs_ns_path.name)
    print(" -", dfs_rep_path.name)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        # Make Ctrl+C exits clear and consistent in CI logs
        print("\nInterrupted.", file=sys.stderr)
        sys.exit(130)
    except Exception as e:
        # Ensure we always get a readable error even if logging isn't configured yet
        logging.basicConfig(level=logging.ERROR, format="%(levelname)s: %(message)s")
        logging.error(e)
        sys.exit(1)