# EzMAP2 — Example Dataset

A small, **real** 16S rRNA dataset for trying out EzMAP2 end-to-end. It is a
subsample of a rice-rhizosphere study comparing **Control vs. Drought**, kept
deliberately small so the whole workflow runs in a few minutes on a laptop while
still producing real, SILVA-classifiable taxonomy (so every downstream panel,
including functional prediction, works).

## Source

Raw reads are a subsample of a publicly available rice-rhizosphere 16S rRNA study
(NGDC/CRA accessions `CRR1325537`–`CRR1325623`). The full study contains 156
samples (four conditions × thirteen time points × three replicates); this example
uses **6 samples** (Control and Drought at the first time point), each subsampled
to **10,000 read pairs**, to keep it lightweight.

> *Citation / BioProject:* _add the study citation and accession here._

## Samples

| Accession | Condition | Replicate |
|-----------|-----------|-----------|
| CRR1325537 | Control | 1 |
| CRR1325541 | Control | 2 |
| CRR1325545 | Control | 3 |
| CRR1325615 | Drought | 1 |
| CRR1325619 | Drought | 2 |
| CRR1325623 | Drought | 3 |

`condition` (Control vs Drought) is the grouping variable for all comparisons.

## Layout

The dataset is split so you can test **either stage independently**:

```
example-data/
├── upstream/      ← raw reads — test the full pipeline (import → taxonomy)
│   ├── raw/       ← paired-end FASTQ files (CRR…_r1/_r2.fq.gz)
│   └── metadata.tsv
└── downstream/    ← processed outputs — test Downstream Analysis directly
    ├── feature-table-tax.biom   ← ASV table WITH taxonomy
    ├── rooted-tree.nwk
    └── metadata.tsv
```

---

## Option A — Test the full pipeline (upstream → downstream)

1. Launch EzMAP2 and finish **Environment Setup** (QIIME2 + R).
2. On **Database & Classifiers**, make a 16S classifier available: in **Section 2
   (Pre-trained)** click **Download** for *SILVA 138 — Full-length* (a one-time
   ~150 MB download that classifies V3–V4 and any other 16S region). Training your
   own (Advanced) is optional and only needed for non-standard primers.
3. Choose **Easy Mode** (or Expert Mode):
   - **Import** the FASTQ files in `upstream/raw/` (paired-end) and select
     `upstream/metadata.tsv` as the sample metadata.
   - Amplicon: **16S-V3V4** (primers 341F `CCTACGGGNGGCWGCAG` / 805R
     `GACTACHVGGGTATCTAATCC`); keep other settings at their defaults.
   - Run. The pipeline performs cutadapt → DADA2 → SILVA taxonomy → phylogeny and
     writes a `bundle/` folder containing `feature-table-tax.biom`,
     `rooted-tree.nwk`, and `metadata.tsv`.
4. Open **Downstream Analysis** and load that `bundle/` folder (see Option B).

On these 6 small samples the whole run takes only a few minutes.

---

## Option B — Test downstream only (skip upstream)

1. Open **Downstream Analysis**.
2. In the **Bundle** card, select the `downstream/` folder — EzMAP2 auto-detects
   `feature-table-tax.biom` (required), `metadata.tsv` (required), and
   `rooted-tree.nwk` (optional, for UniFrac).
3. Click **Launch**, choose **Easy Mode** or **Expert Mode**, and start on the
   **Data** tab.

**Tip:** when a panel asks for a grouping variable, choose **`condition`**
(Control vs Drought). `Sample` is unique per sample and is not a grouping variable.

### What each downstream panel produces

| Panel | Expected result on this dataset |
|-------|---------------------------------|
| **Data** | Phyloseq object built; metadata shows `condition` / `time` / `replicate` for 6 samples |
| **Filtering** | Chloroplast/mitochondria and low-prevalence ASVs removed; most ASVs retained |
| **Relative Abundance** | Stacked bar plots by Phylum/Genus, Control vs Drought |
| **Rarefaction** | Rarefaction curves per sample/group |
| **Alpha Diversity** | Shannon / Chao1 / Simpson boxplots compared between groups |
| **Beta Diversity** | PCoA ordination + PERMANOVA, Control vs Drought (colour by `condition`) |
| **LEfSe** | LDA effect-size differential-abundance ranking |
| **DESeq2** | Per-ASV differential abundance with volcano plot |
| **ANCOM-BC** | Compositional (bias-corrected) differential abundance |
| **Random Forest** | Control-vs-Drought classifier with feature-importance ranking |
| **DESeq2 + RF / ANCOM-BC + RF** | Intersection of statistical and machine-learning biomarkers |
| **Network** | Co-occurrence network built per group |
| **Tax4Fun** | KEGG functional (KO/pathway) prediction — works, using the real SILVA taxonomy |
| **BugBase** | Phenotype prediction (Gram stain, oxygen tolerance, etc.) |
| **FunGuild** | Not applicable here — FunGuild is for fungal ITS data; this is a 16S bacterial dataset |

> This is a compact 3-replicates-per-group demonstration subset, designed to let
> you exercise the entire EzMAP2 workflow quickly. Every panel runs and produces
> output. For a fully powered statistical analysis, use a larger dataset (for
> example, the complete study).

---

## Important

The `downstream/` table must be **`feature-table-tax.biom`** (the taxonomy-merged
BIOM), not the plain `feature-table.biom`. Only the taxonomy-merged file lets the
Relative Abundance, Tax4Fun, and BugBase panels work.
