# EzMAP v2.0 — Easy Microbiome Analysis Pipeline

[![Java 11+](https://img.shields.io/badge/Java-11%2B-blue)](https://adoptium.net/)
[![QIIME2 2024.10](https://img.shields.io/badge/QIIME2-2024.10-green)](https://qiime2.org/)
[![R Shiny](https://img.shields.io/badge/R-Shiny-orange)](https://shiny.posit.co/)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

**EzMAP v2.0** is a cross-platform GUI application for 16S/ITS amplicon microbiome analysis. It wraps the QIIME2 pipeline in a step-by-step Java Swing wizard and provides an interactive R Shiny module for downstream statistical analysis and visualization.

EzMAP v2.0 supports **Easy Mode** (one-click pipeline with validated defaults) and **Expert Mode** (full parameter control at every step), making it accessible to both beginners and advanced users.

---

## Table of Contents

- [Features](#features)
- [System Requirements](#system-requirements)
- [Installation](#installation)
  - [Quick Start](#quick-start)
  - [Prerequisites — Detailed Instructions](#prerequisites--detailed-instructions)
  - [macOS Installation](#macos-installation)
  - [Windows Installation](#windows-installation)
- [Building from Source](#building-from-source)
- [Running EzMAP2](#running-ezmap2)
- [Usage Modes](#usage-modes)
- [Pipeline Output](#pipeline-output)
- [Downstream Analysis (Shiny)](#downstream-analysis-shiny)
- [Optional Packages (install manually)](#optional-packages-install-manually)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Features

**Upstream (QIIME2 Pipeline):**
- Automatic FASTQ detection (paired-end / single-end)
- Intelligent sample ID reconciliation between FASTQ filenames and metadata
- Primer/barcode auto-detection with Cutadapt integration
- DADA2 / Deblur denoising with smart truncation length suggestions
- Taxonomy classification (Naive Bayes, VSEARCH, BLAST) with on-demand classifier training
- Phylogenetic tree construction (MAFFT → FastTree)
- Quality reports at every stage

**Downstream (R Shiny Interactive Analysis):**
- Data filtering with taxonomy-aware controls
- Rarefaction curves and alpha diversity (Shannon, Simpson, Chao1, etc.)
- Beta diversity ordination (PCoA, NMDS) with PERMANOVA
- Relative abundance bar plots with faceting and custom ordering
- DESeq2 differential abundance analysis
- ANCOM-BC differential abundance analysis
- Random Forest feature importance
- Combined DESeq2+RF and ANCOM-BC+RF biomarker discovery
- Network analysis and Tax4Fun2 functional prediction
- FunGuild fungal trait annotation (ITS data)
- Easy/Expert mode toggle for all modules

---

## System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **Java** | 11 | 17+ (LTS) |
| **RAM** | 8 GB | 16+ GB |
| **Disk** | 10 GB free space | 20+ GB |
| **OS** | Ubuntu 20.04+ / macOS 12+ / Windows 10+ (with WSL) | Ubuntu 22.04 LTS |

**Additional requirements for upstream analysis:**
- Conda (Miniconda or Anaconda)
- QIIME2 2024.10+ (installed via conda)

> **Note:** Downstream-only analysis (no QIIME2) works on any OS with Java and R installed. QIIME2 upstream analysis requires Linux or WSL on Windows.

---

## Installation

EzMAP v2.0 can be installed in **any directory** on your system. There is no restriction to a specific location.

The installation has two phases:

1. **Prerequisites** (manual): install the **Java runtime** (provided in the source package) and **R**. These are the only tools you need to install yourself.
2. **Pipeline setup** (automated, from inside the GUI): once EzMAP v2.0 is launched, click **"Set up"** in the GUI. This will automatically install Miniconda, the pinned `EzMAP2-qiime2` conda environment (QIIME2 2024.10), and the required R/Shiny/Bioconductor packages.

### Quick Start

After downloading and extracting the EzMAP v2.0 package:

**Step 1 — Install prerequisites (all platforms):**
- Install the Java runtime included in the `java/` folder of the source package, or download it from [Adoptium (Java 11+)](https://adoptium.net/).
- Install [R 4.0+](https://cran.r-project.org/) (see also [R Shiny](https://shiny.posit.co/)).

**Step 2 — Launch the GUI:**

| Platform | How to launch |
|----------|---------------|
| **Windows** | Double-click `EzMAP2.jar` |
| **Ubuntu / Linux** | Run `bash build.sh` (first time only), then `bash ezmap2.sh` |
| **macOS** | Run `bash build.sh` (first time only), then `bash ezmap2.sh` |

**Step 3 — Run the in-GUI setup:**

Once the GUI opens, click **"Set up"** on the Environment Check / Database Setup screen. EzMAP2 will automatically:
1. Check internet connectivity
2. Install Miniconda (if not already present)
3. Create the pinned `EzMAP2-qiime2` conda environment with QIIME2 2024.10
4. Install R and required Shiny/Bioconductor packages
5. Verify the installation

This step only needs to be done once. On subsequent launches, EzMAP2 will detect the existing environment and skip the setup.

### Prerequisites — Detailed Instructions

EzMAP v2.0 requires **Java** and **R** to be installed on the host system before launching. Conda, QIIME2, and the R/Bioconductor packages are handled automatically by the GUI's "Set up" step — you do not install those manually.

#### 1. Install the Java Runtime

The Java runtime is bundled in the `java/` folder of the EzMAP2 source package. Use that bundled runtime, or install Java 11+ system-wide.

**Ubuntu/Debian (system-wide):**
```bash
sudo apt update && sudo apt install default-jdk maven
```

**Fedora/RHEL (system-wide):**
```bash
sudo dnf install java-17-openjdk maven
```

**macOS (system-wide via Homebrew):**
```bash
brew install openjdk@17 maven
```

**Windows:** install Java 11+ from [Adoptium](https://adoptium.net/) and add to PATH, or use the bundled runtime in the source package.

**Verify:**
```bash
java -version    # Should show 11+
mvn -version     # Should show 3.6+ (only required if you build from source)
```

#### 2. Install R

Required for downstream analysis. The R/Shiny/Bioconductor packages themselves are installed automatically by the GUI's "Set up" step — you only need a base R installation here.

**Ubuntu/Debian:**
```bash
sudo apt install r-base r-base-dev
```

**Fedora/RHEL:**
```bash
sudo dnf install R
```

**macOS:**
```bash
brew install r
```

**Windows:** install [R for Windows](https://cran.r-project.org/bin/windows/base/).

#### 3. Build EzMAP v2.0 (Linux / macOS only)

On Linux and macOS, build the JAR once before first launch:

```bash
bash build.sh
```

This compiles the Java source in `src-build/` using Maven and produces `EzMAP2.jar`.

> On **Windows**, a prebuilt `EzMAP2.jar` is included in the source package — no build step is needed. Just double-click it.

### macOS Installation

```bash
# 1. Install prerequisites (Java + R)
brew install openjdk@17 maven r

# 2. Extract the EzMAP2 package and enter the folder
cd EzMAP2

# 3. Build the GUI (first time only)
bash build.sh

# 4. Launch EzMAP2
bash ezmap2.sh
```

Once the GUI opens, click **"Set up"** — EzMAP2 will install Miniconda, the `EzMAP2-qiime2` environment, and the required R packages automatically. EzMAP2 uses the native terminal on macOS.

### Windows Installation

EzMAP v2.0 on Windows uses **WSL (Windows Subsystem for Linux)** for QIIME2 upstream analysis. The Java GUI runs natively on Windows.

1. **Install Java 11+** from [Adoptium](https://adoptium.net/) and add to PATH (or use the runtime bundled in the `java/` folder of the source package).
2. **Install [R for Windows](https://cran.r-project.org/bin/windows/base/)**.
3. **Install WSL + Ubuntu** (required for QIIME2 upstream analysis):
   ```powershell
   wsl --install -d Ubuntu
   ```
4. **Launch EzMAP v2.0** by double-clicking `EzMAP2.jar` in the extracted folder.
   - Alternatively, double-click `ezmap2.bat`, or run `java -Xmx2g -jar EzMAP2.jar` from a command prompt.
5. **Click "Set up" in the GUI** — EzMAP2 will install Miniconda and the pinned `EzMAP2-qiime2` environment inside WSL, plus the required R packages, automatically.

> **Downstream-only on Windows:** if you only need downstream analysis, you can skip WSL. Just install Java and R, double-click `EzMAP2.jar`, and select "Downstream Only" in the GUI.

---

## Building from Source

EzMAP2 uses Maven to build an uber JAR (all dependencies bundled):

```bash
# From the EzMAP2 root directory
bash build.sh
```

Or manually:
```bash
cd src-build
mvn clean package
cp target/EzMAP2.jar ../EzMAP2.jar
```

**Requirements:** Java 11+ JDK, Maven 3.6+

The build produces `EzMAP2.jar` in the project root — a self-contained JAR that includes the FlatLaf UI theme and all dependencies.

---

## Running EzMAP v2.0

**Linux / macOS:**
```bash
bash ezmap2.sh
# Or directly:
java -Xmx2g -jar EzMAP2.jar
```

**Windows:**
- Double-click `EzMAP2.jar` (recommended)
- Or double-click `ezmap2.bat`
- Or from command prompt: `java -Xmx2g -jar EzMAP2.jar`

**Ubuntu desktop shortcut:**
```bash
bash install-desktop.sh
```

### Does double-click work? (build once, run anywhere)

`EzMAP2.jar` is a self-contained, cross-platform Java application. **You only build it
once** — the same `EzMAP2.jar` runs on Windows, Linux, and macOS (you can even build it
on one OS and copy the jar to another). The only requirement on each machine is **Java
11+**. Rebuilding per operating system is **not** needed.

Double-clicking the jar, however, is only reliable on Windows:

| Platform | Recommended launch | Double-click? |
|----------|--------------------|---------------|
| **Windows** | Double-click `EzMAP2.jar` (or `ezmap2.bat`) | ✅ Works when Java is installed |
| **Linux** | `bash ezmap2.sh`, or install the desktop shortcut (`bash install-desktop.sh`) | ⚠️ Most file managers won't run a `.jar` on double-click |
| **macOS** | `bash ezmap2.sh`, or `java -jar EzMAP2.jar` in Terminal | ⚠️ Gatekeeper blocks unsigned `.jar` files ("unidentified developer") |

**macOS first-launch tip:** if double-clicking shows *"cannot be opened because it is from
an unidentified developer,"* either run it from Terminal with `java -jar EzMAP2.jar`, or
right-click the jar → **Open** → **Open** to approve it once.

> **Reminder:** a portable jar still needs its pipeline dependencies set up per machine.
> On Linux/macOS the upstream pipeline runs QIIME2/R natively, so run the in-GUI **"Set
> up"** step (or `install.sh`) on each computer before the first upstream analysis.

---

## Usage Modes

### Full Analysis (Upstream + Downstream)

The complete pipeline from raw FASTQ files to interactive visualization:

1. **Welcome** → Select "Full Analysis"
2. **Environment Check** → Detects OS, WSL, QIIME2
3. **Database Setup** → Configure or train taxonomy classifiers
4. **Mode Selection** → Choose Easy Mode or Expert Mode
5. **Validate Inputs** → Select FASTQ folder, metadata, output directory
6. **Import** → Import sequences into QIIME2 format
7. **Cutadapt** → Remove primers/barcodes (auto-detected)
8. **Quality Assessment** → Review per-base quality profiles
9. **Denoising** → DADA2/Deblur with smart truncation suggestions
10. **Taxonomy** → Classify ASVs against reference database
11. **Results Summary** → QC dashboard with denoising stats and file checklist
12. **Downstream** → Launch interactive Shiny analysis

### Downstream Only

Analyze pre-existing data (BIOM table + metadata) without running QIIME2:

1. **Welcome** → Select "Downstream Only"
2. **Upload** → Select BIOM file, metadata, and (optional) phylogenetic tree
3. **Downstream** → Launch interactive Shiny analysis

### Resume Downstream

Re-open a previous EzMAP v2.0 pipeline output for further analysis:

1. **Welcome** → Select "Full Analysis"
2. Navigate to **Mode Selection** → Click "Resume Downstream"
3. Select your previous output folder → Results load automatically

---

## Pipeline Output

When EzMAP v2.0 runs the full upstream pipeline, it creates the following output structure in your chosen output directory:

```
<your-output-dir>/
├── qza/                        # QIIME2 artifacts (.qza files)
│   ├── paired-end-demux.qza    # Imported sequences
│   ├── trimmed.qza             # Cutadapt output
│   ├── table.qza               # Feature table (ASV counts)
│   ├── rep-seqs.qza            # Representative sequences
│   ├── taxonomy.qza            # Taxonomy classifications
│   ├── rooted-tree.qza         # Phylogenetic tree
│   └── ...
├── qzv/                        # QIIME2 visualizations (.qzv files)
│   ├── demux-summary.qzv       # Read quality summary
│   ├── denoising-stats.qzv     # Denoising statistics
│   ├── taxa-bar-plots.qzv      # Taxonomy bar plots
│   └── ...
├── bundle/                     # Downstream-ready files (exported from QZA)
│   ├── feature-table-tax.biom  # BIOM table with taxonomy annotations
│   ├── feature-table.biom      # BIOM table (without taxonomy)
│   ├── taxonomy.tsv            # Taxonomy assignments
│   ├── rooted-tree.nwk         # Newick phylogenetic tree
│   ├── rep-seqs.fasta          # Representative sequences (FASTA)
│   ├── metadata.tsv            # Copy of sample metadata
│   ├── denoising-stats.tsv     # Denoising statistics
│   └── parameters.json         # Pipeline parameters used
└── logs/
    └── pipeline.log            # Full pipeline log
```

The `bundle/` directory contains all files needed for downstream analysis. When you click "Open in EzMAP2 Downstream" or select this folder in Downstream Only mode, EzMAP v2.0 auto-detects these files.

---

## Downstream Analysis (Shiny)

The Shiny app can also run standalone without the Java GUI:

```bash
cd EzMAPv2-downstream
Rscript -e "shiny::runApp('.', launch.browser=TRUE)"
```

With auto-loaded files (skip the upload step):

```bash
cd EzMAPv2-downstream
EZMAP2_BIOM=/path/to/feature-table-tax.biom \
EZMAP2_METADATA=/path/to/metadata.tsv \
EZMAP2_TREE=/path/to/rooted-tree.nwk \
Rscript -e "shiny::runApp('.', launch.browser=TRUE)"
```

### Tax4Fun2 Reference Data

Tax4Fun2 functional prediction requires ~3.5 GB of reference data not included in the repository. Download it separately:

```bash
# Download Tax4Fun2 reference data
# Place in: EzMAPv2-downstream/Tax4Fun2_ReferenceData_v2/
```

---

## Optional Packages (install manually)

A few downstream features rely on packages that **EzMAP cannot install reliably on your
behalf** — they are hosted on GitHub and **compile from source**, so they need a build
toolchain that isn't always present. EzMAP's first-launch setup attempts them and silently
skips any it can't build; the affected panels then fall back or stay disabled. **For full
functionality, please install these yourself before using EzMAP.** (The same guidance is
shown in the GUI's **About** page.)

| Package | Needed for | Install via |
|---------|-----------|-------------|
| **themetagenomics** | Tax4Fun2 functional prediction | R (GitHub) |
| **SpiecEasi** | SPIEC-EASI co-occurrence networks (Network panel) | R (GitHub) |
| **FUNGuildR** + **FUNGuild** | Fungal functional guilds (ITS data only) | R + Python |

### Step 1 — install a compiler toolchain

These packages build from source, so install the platform build tools first:

- **Windows:** install [Rtools](https://cran.r-project.org/bin/windows/Rtools/) (match it to your R version).
- **macOS:** `xcode-select --install` (installs the compilers; `gfortran` may also be required for SpiecEasi).
- **Ubuntu/Debian:** `sudo apt install build-essential gfortran`

### Step 2 — install the R packages

Run in R (or RStudio):

```r
install.packages("remotes")
remotes::install_github("EESI/themetagenomics")   # Tax4Fun2 functional prediction
remotes::install_github("zdk123/SpiecEasi")        # SPIEC-EASI network inference
install.packages("FUNGuildR")                       # fungal guilds (ITS data)
```

### Step 3 — FUNGuild (Python script, ITS/fungal data only)

```bash
git clone https://github.com/UMNFuN/FUNGuild
pip install requests
python FUNGuild/Guilds_v1.1.py -h
```

**Resources:**

- themetagenomics — https://github.com/EESI/themetagenomics
- SpiecEasi — https://github.com/zdk123/SpiecEasi
- FUNGuild — https://github.com/UMNFuN/FUNGuild

> **These are optional.** Without them EzMAP still runs and every other downstream panel
> works normally — the Network panel falls back to Pearson/Spearman correlation, and the
> Tax4Fun2 and FUNGuild features simply remain unavailable until the packages are installed.

---

## Troubleshooting

**JAR not found / won't launch:**
- Run `bash build.sh` to compile from source
- Ensure Java 11+ is installed: `java -version`
- Ensure Maven 3.6+ is installed: `mvn -version`

**QIIME2 not detected:**
- Verify the conda environment exists: `conda env list | grep EzMAP2`
- Activate and test: `conda activate EzMAP2-qiime2 && qiime --version`
- On Windows, ensure WSL Ubuntu is installed and the environment is set up inside WSL

**R/Shiny packages missing:**
- Run: `Rscript scripts/install_r_packages.R`
- For Bioconductor packages, ensure BiocManager is installed first:
  ```r
  install.packages("BiocManager")
  BiocManager::install(c("phyloseq", "DESeq2", "biomformat"))
  ```

**WSL issues on Windows:**
- DNS resolution failures: Run `wsl --shutdown` in PowerShell, then restart WSL
- Ensure Ubuntu distribution is installed: `wsl --list --verbose`

**Shiny app crashes on launch:**
- Check R package availability: `Rscript -e "library(shiny); library(phyloseq)"`
- The Java GUI auto-installs missing R packages on first launch

---

## License

EzMAP v2.0 is distributed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.
