# EzMAP2 — Easy Microbiome Analysis Pipeline v2

[![Java 11+](https://img.shields.io/badge/Java-11%2B-blue)](https://adoptium.net/)
[![QIIME2 2024.10](https://img.shields.io/badge/QIIME2-2024.10-green)](https://qiime2.org/)
[![R Shiny](https://img.shields.io/badge/R-Shiny-orange)](https://shiny.posit.co/)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

**EzMAP2** is a cross-platform GUI application for 16S/ITS amplicon microbiome analysis. It wraps the QIIME 2 pipeline in a step-by-step Java Swing wizard and provides an interactive R Shiny module for downstream statistical analysis and visualization.

EzMAP2 supports **Easy Mode** (one-click pipeline with validated defaults) and **Expert Mode** (full parameter control at every step), making it accessible to both beginners and advanced users.

---

## Table of Contents
- [Features](#features)
- [System Requirements](#system-requirements)
- [Installation](#installation)
  - [Quick Start](#quick-start)
  - [Bundled Reference Data](#bundled-reference-data)
  - [Prerequisites — Detailed Instructions](#prerequisites--detailed-instructions)
  - [macOS Installation](#macos-installation)
  - [Windows Installation](#windows-installation)
- [Building from Source](#building-from-source)
- [Running EzMAP2](#running-ezmap2)
- [Usage Modes](#usage-modes)
- [Pipeline Output](#pipeline-output)
- [Downstream Analysis (Shiny)](#downstream-analysis-shiny)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Features

**Upstream (QIIME 2 Pipeline):**
- Automatic FASTQ detection (paired-end / single-end)
- Intelligent sample ID reconciliation between FASTQ filenames and metadata
- Primer/barcode auto-detection with Cutadapt integration
- DADA2 / Deblur denoising with smart truncation length suggestions
- Taxonomy classification (Naive Bayes, VSEARCH, BLAST) with on-demand classifier training
- Phylogenetic tree construction (MAFFT → FastTree)
- Quality reports at every stage

**Downstream (R Shiny Interactive Analysis):**
- Data filtering with taxonomy-aware controls
- Rarefaction curves and alpha diversity (Shannon, Simpson, Chao1, etc.) with auto-selected parametric / non-parametric tests
- Beta diversity ordination (PCoA, NMDS) with PERMANOVA, custom legend ordering, and decoupled Group / Color-by variables
- Relative abundance bar plots with faceting and custom ordering
- DESeq2 differential abundance analysis (volcano plots; |log2FC| adjustable in Easy mode)
- ANCOM-BC differential abundance analysis (compositional bias correction; |log2FC| adjustable in Easy mode)
- LEfSe linear discriminant analysis effect size
- Random Forest feature importance with hierarchical biomarker analysis
- Combined DESeq2 + RF and ANCOM-BC + RF consensus biomarker modules with publication-quality Venn diagrams
- Co-occurrence network analysis (SparCC, Pearson, Spearman) with bootstrap-CI edge significance and node sizing by hub centrality
- Tax4Fun2 functional prediction (16S → KEGG)
- FunGuild fungal trait annotation (ITS data)
- BugBase organism-level phenotype prediction
- Easy / Expert mode toggle for all modules

---

## System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **Java** | 11 | 17+ (LTS) |
| **RAM** | 8 GB | 16+ GB |
| **Disk** | 10 GB free space | 20+ GB |
| **Screen** | 1366 × 768 | 1440 × 900 or higher |
| **OS** | Ubuntu 20.04+ / macOS 12+ / Windows 10+ (with WSL) | Ubuntu 22.04 LTS |

**Additional requirements for upstream analysis:**
- Conda (Miniconda or Anaconda) — installed automatically by the in-GUI setup
- QIIME 2 2024.10+ — installed automatically by the in-GUI setup

> **Note:** Downstream-only analysis (no QIIME 2) works on any OS with Java and R installed. QIIME 2 upstream analysis requires Linux or WSL on Windows.

---

## Installation

EzMAP2 can be installed in **any directory** on your system — there's no restriction to a specific location.

The installation has two phases:

1. **Prerequisites** (manual): install the **Java runtime** (JRE 11 or newer; provided in the source package) and **R** (≥ 4.2). These are the only tools you need to install yourself.
2. **Pipeline setup** (automated, from inside the GUI): once EzMAP2 is launched, click **"Set up"** in the GUI. This automatically installs Miniconda and the pinned `EzMAP2-qiime2` conda environment (QIIME 2 2024.10). The R / Shiny / Bioconductor packages are installed automatically the first time you launch the downstream Shiny app — this defers the longest install step until you actually need it, so users running only the upstream pipeline don't have to wait for it.

### Quick Start

After downloading and extracting the EzMAP2 package:

**Step 1 — Install prerequisites (all platforms):**
- Install the Java Runtime Environment (JRE). You can download Java 11 or later from Adoptium. [Adoptium (Java 11+)](https://adoptium.net/).
- Install [R 4.2+](https://cran.r-project.org/) (see also [R Shiny](https://shiny.posit.co/)).

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
3. Create the pinned `EzMAP2-qiime2` conda environment with QIIME 2 2024.10
4. Install R (if missing — but does *not* install R packages yet)
5. Verify the installation

**Step 4 — Launch the downstream app (first time):**

When you first open the downstream Shiny module, EzMAP2 detects any missing R / Bioconductor packages and installs them automatically. On Linux, it uses Posit Public Package Manager binaries for fast installs (5–10 minutes). On macOS / Windows, CRAN binaries are used. Subsequent launches are instant.

This step only needs to be done once. On subsequent launches, EzMAP2 will detect the existing environment and skip the setup.

### Bundled Reference Data

The repository download already includes pre-built classifiers and reference databases sufficient for most 16S and ITS analyses, so most users do **not** need to download anything else.

**`classifiers/` — pre-trained naïve-Bayes classifiers (ready to use):**

| File | Region | Use case |
|---|---|---|
| [`silva-16S-V3V4-nb-classifier.qza`] | 16S V3–V4 | Bacterial / archaeal communities (SILVA 138) |
| [`unite-ITS1-nb-classifier.qza`] | ITS1 | Fungal communities (UNITE v7) |

**`db/` — reference sequence and taxonomy files (only needed if training a custom classifier for a non-default amplicon region):**


**Full SILVA /  UNITE reference databases** (multi-GB; needed only if training classifiers for non-default amplicon regions like V1–V2, V4–V5, ITS2, etc.) are not bundled in the main repository to keep the download size manageable. They can be downloaded from the [v2.0.0 release page](https://github.com/gnanibioinfo/EzMAP-v2.0/releases/tag/v2.0.0).

### Prerequisites — Detailed Instructions

EzMAP2 requires **Java** and **R** to be installed on the host system before launching. Conda, QIIME 2, and the R / Bioconductor packages are handled automatically by the GUI's "Set up" step and the downstream Shiny app's first-launch installer — you do not install those manually.

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

Required for downstream analysis. The R / Shiny / Bioconductor packages themselves are installed automatically the first time you launch the downstream Shiny app — you only need a base R installation here.

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

**Linux: install system libraries that R packages depend on**

R packages with C/C++ dependencies (curl, xml2, fontconfig, harfbuzz) need system development headers. On Ubuntu/Debian:

```bash
sudo apt install libcurl4-openssl-dev libssl-dev libxml2-dev \
                 libfontconfig1-dev libharfbuzz-dev libfribidi-dev \
                 libfreetype6-dev libpng-dev libtiff5-dev libjpeg-dev
```

This is typically a one-time install. Skipping these libraries causes the first-launch R-package install to fail.

#### 3. Build EzMAP2 (Linux / macOS only)

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

Once the GUI opens, click **"Set up"** — EzMAP2 will install Miniconda and the `EzMAP2-qiime2` environment automatically. The R packages will install themselves the first time you launch the downstream Shiny app. EzMAP2 uses the native terminal on macOS.

### Windows Installation

EzMAP2 on Windows uses **WSL (Windows Subsystem for Linux)** for QIIME 2 upstream analysis. The Java GUI runs natively on Windows.

1. **Install Java 11+** from [Adoptium](https://adoptium.net/) and add to PATH (or use the runtime bundled in the `java/` folder of the source package).
2. **Install [R for Windows](https://cran.r-project.org/bin/windows/base/)**.
3. **Install WSL + Ubuntu** (required for QIIME 2 upstream analysis):
   ```powershell
   wsl --install -d Ubuntu
   ```
4. **Launch EzMAP2** by double-clicking `EzMAP2.jar` in the extracted folder.
   - Alternatively, double-click `ezmap2.bat`, or run `java -Xmx2g -jar EzMAP2.jar` from a command prompt.
5. **Click "Set up" in the GUI** — EzMAP2 installs Miniconda and the pinned `EzMAP2-qiime2` environment inside WSL automatically. R packages install on first downstream Shiny launch.

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

## Running EzMAP2

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

---

## Usage Modes

### Full Analysis (Upstream + Downstream)
The complete pipeline from raw FASTQ files to interactive visualization:

1. **Welcome** → Select "Full Analysis"
2. **Environment Check** → Detects OS, WSL, QIIME 2
3. **Database Setup** → Configure or train taxonomy classifiers
4. **Mode Selection** → Choose Easy Mode or Expert Mode
5. **Validate Inputs** → Select FASTQ folder, metadata, output directory
6. **Import** → Import sequences into QIIME 2 format
7. **Cutadapt** → Remove primers/barcodes (auto-detected)
8. **Quality Assessment** → Review per-base quality profiles
9. **Denoising** → DADA2 / Deblur with smart truncation suggestions
10. **Taxonomy** → Classify ASVs against reference database
11. **Results Summary** → QC dashboard with denoising stats and file checklist
12. **Downstream** → Launch interactive Shiny analysis

### Downstream Only
Analyze pre-existing data (BIOM table + metadata) without running QIIME 2:

1. **Welcome** → Select "Downstream Only"
2. **Upload** → Select BIOM file, metadata, and (optional) phylogenetic tree
3. **Downstream** → Launch interactive Shiny analysis

### Resume Downstream
Re-open a previous EzMAP2 pipeline output for further analysis:

1. **Welcome** → Select "Full Analysis"
2. Navigate to **Mode Selection** → Click "Resume Downstream"
3. Select your previous output folder → Results load automatically

---

## Pipeline Output

When EzMAP2 runs the full upstream pipeline, it creates the following output structure in your chosen output directory:

```
<your-output-dir>/
├── qza/                        # QIIME 2 artifacts (.qza files)
│   ├── paired-end-demux.qza    # Imported sequences
│   ├── trimmed.qza             # Cutadapt output
│   ├── table.qza               # Feature table (ASV counts)
│   ├── rep-seqs.qza            # Representative sequences
│   ├── taxonomy.qza            # Taxonomy classifications
│   ├── rooted-tree.qza         # Phylogenetic tree
│   └── ...
├── qzv/                        # QIIME 2 visualizations (.qzv files)
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

The `bundle/` directory contains all files needed for downstream analysis. When you click "Open in EzMAP2 Downstream" or select this folder in Downstream Only mode, EzMAP2 auto-detects these files.

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

On the very first launch, the app detects any missing R / Bioconductor packages and installs them automatically. Linux uses Posit Public Package Manager binaries for fast installs; macOS / Windows use CRAN binaries. Subsequent launches are instant.

### Tax4Fun2 Reference Data

Tax4Fun2 functional prediction requires ~3.5 GB of reference data not included in the repository. Download it separately:

```bash
# Download Tax4Fun2 reference data
# Place in: EzMAPv2-downstream/Tax4Fun2_ReferenceData_v2/
```

---

## Troubleshooting

**JAR not found / won't launch:**
- Run `bash build.sh` to compile from source
- Ensure Java 11+ is installed: `java -version`
- Ensure Maven 3.6+ is installed: `mvn -version`

**JAR opens in 7-Zip / WinRAR instead of running (Windows):**
- Right-click the JAR → **Open with** → **Choose another app** → pick **Java(TM) Platform SE binary** → tick "Always use this app".

**"Permission denied" when double-clicking the JAR (Ubuntu / Linux):**
- GNOME's Files refuses files without the executable bit. Set it once:
  ```bash
  chmod +x EzMAP2.jar
  ```

**"Cannot be opened because the developer cannot be verified" (macOS):**
- Right-click the JAR → **Open** → click **Open** in the warning dialog. Or:
  ```bash
  xattr -d com.apple.quarantine EzMAP2.jar
  ```

**QIIME 2 not detected:**
- Verify the conda environment exists: `conda env list | grep EzMAP2`
- Activate and test: `conda activate EzMAP2-qiime2 && qiime --version`
- On Windows, ensure WSL Ubuntu is installed and the environment is set up inside WSL

**R / Shiny packages missing:**
- The downstream Shiny app installs missing R packages automatically the first time it launches. If that fails, run the installer manually:
  ```bash
  Rscript scripts/install_r_packages.R
  ```
- For Bioconductor packages, ensure BiocManager is installed first:
  ```r
  install.packages("BiocManager")
  BiocManager::install(c("phyloseq", "DESeq2", "biomformat"))
  ```
- On Linux, missing system development libraries (libcurl-dev, libssl-dev, libxml2-dev, etc.) are the most common cause of R-package install failures. See the [Linux system libraries](#2-install-r) section above.

**Conda solver fails during in-GUI setup:**
- Network or channel-priority issue. Re-run "Set up" — `install.sh` is idempotent and skips steps that already completed. If the failure persists, run from a terminal:
  ```bash
  bash install.sh
  ```
  to see full conda output.

**Sample IDs don't match between BIOM and metadata (downstream upload):**
- Ensure the first column of your metadata TSV (sample-id) contains exactly the same IDs as the BIOM table column headers
- Watch for hidden whitespace, trailing newlines, or BOM characters in the metadata file

**WSL issues on Windows:**
- DNS resolution failures: Run `wsl --shutdown` in PowerShell, then restart WSL
- Ensure Ubuntu distribution is installed: `wsl --list --verbose`

**Shiny app crashes on launch:**
- Check R package availability: `Rscript -e "library(shiny); library(phyloseq)"`
- The app auto-installs missing R packages on first launch — wait for the install to finish (typically 5–10 minutes on Linux with binary repo, longer on first-ever installs)

**GUI controls hidden off-screen on small laptops:**
- The wizard pages now have horizontal scroll bars when window width is smaller than content. Use the scroll bars or maximize the window. Minimum supported resolution is 1366 × 768.

---

## License

EzMAP2 is distributed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.
