# EzMAP-v2.0
**EzMAP v2.0 – An Integrated Platform for Microbiome Data Analysis**
EzMAP v2.0 (Easy Microbiome Analysis Pipeline) is a user-friendly, end-to-end platform designed for processing, analyzing, and visualizing amplicon-based microbiome datasets. The tool integrates sequence preprocessing, taxonomic profiling, statistical analysis, machine learning, and co-occurrence network inference into a single streamlined workflow. EzMAP v2.0 provides an intuitive graphical interface and supports advanced modules for functional prediction, diversity analysis, differential abundance testing, and network construction.

This repository contains the full EzMAP v2.0 source code, documentation, example datasets, and step-by-step tutorials for installation and use. The tool is designed for both beginners and experienced researchers seeking a comprehensive and reproducible microbiome analysis framework.

**EzMAP v2.0 – Installation Requirements**

EzMAP v2.0 is designed as a fully automated pipeline. Users **do not need** to manually install QIIME2, Conda, or any supporting tools. **EzMAP v2.0 will automatically install and configure the required environments on first use.**

**Required only for users:**
Windows Users

**Windows Subsystem for Linux (WSL)**
Required to run QIIME2 and Linux-based commands.
Installation instructions:

wsl --install

(Restart required after installation.)

**MacOS and Linux Users**

No additional system requirements.

**Required for all platforms**

**Java Runtime Environment (JRE)**
https://www.java.com/en/download/

**EzMAP v2.0 – Installation Steps**
**1. Download EzMAP v2.0**

Download the EzMAP v2.0 release ZIP from GitHub and extract it.
You will obtain a folder:

**EzMAP-v2.0/**

**2. Prepare the required folders**

Move the following to your Desktop:

EzMAP folder (contains build/, dist/, Downstream/, etc.)

EzMAP_Analysis folder (contains manifest, metadata, raw_data)

EzMAP.jar (launcher file)

Your Desktop should look like this:

~/Desktop/
    EzMAP/
    EzMAP_Analysis/
    EzMAP.jar

**3. Launch EzMAP v2.0**

Double-click EzMAP.jar to open the EzMAP interface.

On the first launch:

EzMAP v2.0 will automatically install QIIME2 and Miniconda inside its own environment.

No user involvement is required; installation runs in the background.

After installation completes, the tool is ready for use.

**Working With EzMAP v2.0**
A. Upstream Analysis (QIIME2 Pipeline)

Open EzMAP using EzMAP.jar

Click Start Analysis

Select Run QIIME2 Analysis

Provide:

Working directory (EzMAP_Analysis)

Manifest file

Metadata file

Select read type: Paired-end

Enter primer sequence

Import sequences

Run Cutadapt trimming

Choose trimming/truncation parameters

Select denoising method (DADA2)

Assign taxonomy (SILVA, Greengenes, or UNITE)

Build phylogenetic tree

**EzMAP generates a complete analysis folder including:**

Feature table

Taxonomy

Representative sequences

Phylogenetic tree

table-w-tax-meta.biom

Use this BIOM file for downstream analysis.

**B. Downstream Analysis (Shiny R Interface)**

Open EzMAP → Run Downstream Analysis
(RStudio launches automatically.)

In the EzMAP Shiny App:

Upload table-w-tax-meta.biom

Upload the phylogenetic tree

EzMAP creates a phyloseq object and displays dataset summary.

Available Modules:

Alpha Diversity

Beta Diversity (PCoA, PERMANOVA)

Differential Abundance (DESeq2)

Functional Prediction

Random Forest Classification

Network Analysis
