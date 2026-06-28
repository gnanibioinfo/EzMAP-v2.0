# Uninstalling EzMAP2

EzMAP2 installs several components and can download large reference files, so a
full removal frees up considerable disk space (the QIIME2 environment alone is
~5 GB, and classifiers/databases can add several more GB). This guide removes
everything EzMAP2 creates. Follow the section for your operating system.

> **Tip:** If you only want to reclaim space from downloaded data but keep the
> software, you can just delete the `ezmap2-classifiers` and `ezmap2-databases`
> folders (see step 2 below) and skip the rest.

---

## What EzMAP2 installs / creates

| Component | Location | Approx. size |
|-----------|----------|--------------|
| QIIME2 conda environment (`EzMAP2-qiime2`, includes R + all packages) | inside your conda installation, e.g. `~/miniconda3/envs/EzMAP2-qiime2` | ~5–7 GB |
| Pre-trained / trained classifiers | `ezmap2-classifiers/` in your home folder | 0.1–2 GB |
| Reference databases | `ezmap2-databases/` in your home folder | 0.1–1 GB |
| Package-check lock file | `~/.ezmap2_packages_ok` | tiny |
| Application files (JAR + scripts) | the folder where you placed EzMAP2 | ~30 MB |
| Miniconda (only if EzMAP2 installed it for you) | `~/miniconda3` | ~0.5 GB |
| Desktop shortcut (Linux only) | `~/.local/share/applications/ezmap2.desktop`, `~/Desktop/EzMAP2.desktop` | tiny |

---

## Windows (WSL)

On Windows, the app runs natively while QIIME2 and R live inside WSL (Ubuntu).
The downloaded classifiers/databases are stored in your **Windows** user folder.

**1. Remove the conda environment and lock file (inside WSL).** Open a terminal:

```powershell
wsl -d Ubuntu -- bash -lc "source ~/miniconda3/etc/profile.d/conda.sh 2>/dev/null; conda env remove -n EzMAP2-qiime2 -y; rm -f ~/.ezmap2_packages_ok"
```

**2. Delete the downloaded classifiers and databases (Windows side):**

```powershell
rmdir /s /q "%USERPROFILE%\ezmap2-classifiers"
rmdir /s /q "%USERPROFILE%\ezmap2-databases"
```

**3. Delete the EzMAP2 application folder** (where `EzMAP2.jar` lives) — just
delete it in File Explorer.

**4. (Optional) Remove Miniconda** — only if EzMAP2 installed it and you don't
use conda for anything else:

```powershell
wsl -d Ubuntu -- bash -lc "rm -rf ~/miniconda3"
```

**5. (Optional) Remove WSL/Ubuntu entirely** — only if you installed Ubuntu
solely for EzMAP2 (this deletes the whole Linux environment):

```powershell
wsl --unregister Ubuntu
```

---

## Linux

Everything lives in your home folder.

```bash
# 1. Remove the conda environment + lock file
source ~/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda env remove -n EzMAP2-qiime2 -y
rm -f ~/.ezmap2_packages_ok

# 2. Remove downloaded classifiers and databases
rm -rf ~/ezmap2-classifiers ~/ezmap2-databases

# 3. Remove desktop shortcuts
rm -f ~/.local/share/applications/ezmap2.desktop ~/Desktop/EzMAP2.desktop

# 4. Remove the application folder (adjust the path to where you installed it)
rm -rf ~/EzMAP2

# 5. (Optional) Remove Miniconda — only if EzMAP2 installed it and you don't
#    use conda for anything else
rm -rf ~/miniconda3
```

---

## macOS

Same as Linux, but there are no `.desktop` shortcuts:

```bash
source ~/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda env remove -n EzMAP2-qiime2 -y
rm -f ~/.ezmap2_packages_ok
rm -rf ~/ezmap2-classifiers ~/ezmap2-databases
rm -rf ~/EzMAP2          # adjust to your install path
rm -rf ~/miniconda3      # optional, only if EzMAP2 installed it
```

---

## Verifying removal

To confirm the conda environment is gone:

```bash
conda env list          # 'EzMAP2-qiime2' should no longer be listed
```

That's it — EzMAP2 leaves nothing else on your system.
