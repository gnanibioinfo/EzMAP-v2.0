
# Reference Databases

This folder holds the QIIME 2 reference **sequence + taxonomy** artifacts
(`*.qza`) that EzMAP v2.0 uses to train classifiers and assign taxonomy.

**The `.qza` files are not tracked in Git** (roughly 0.6–93 MB each), so only
this README is committed. EzMAP downloads them on demand to your home folder
(`~/ezmap2-databases`, i.e. `C:\Users\<you>\ezmap2-databases`).

## Option A — get them from inside EzMAP (recommended)

Launch EzMAP → **Database & Classifier Setup** → **Section 1 (Reference
Databases)** → **Download**. Files are saved to `~/ezmap2-databases`.

## Option B — download manually

Save the files into this folder (or `~/ezmap2-databases`) using these exact
names that EzMAP expects:

| Database | Files (sequences, taxonomy) | Source |
|----------|------------------------------|--------|
| SILVA 138 (16S/18S) | `silva-138.2-ssu-nr99-seqs.qza`, `silva-138.2-ssu-nr99-tax.qza` | https://data.qiime2.org/2024.10/common/silva-138-99-seqs.qza · https://data.qiime2.org/2024.10/common/silva-138-99-tax.qza |
| Greengenes2 2024.09 (16S) | `gg2-2024.09-nb-seqs.qza`, `gg2-2024.09-nb-tax.qza` | http://ftp.microbio.me/greengenes_release/2024.09/2024.09.backbone.full-length.fna.qza · http://ftp.microbio.me/greengenes_release/2024.09/2024.09.backbone.tax.qza |
| UNITE 10.0 (fungal ITS) | `unite-ver10-seqs-dynamic.qza`, `unite-ver10-tax-dynamic.qza` | Manual download (licensing): https://unite.ut.ee/repository.php |

## Notes

- **Filenames:** the QIIME 2 SILVA download is named `silva-138-99-seqs.qza` /
  `-tax.qza` at the source, but EzMAP stores it as `silva-138.2-ssu-nr99-*.qza`.
  If you download manually, rename to the names in the table above (EzMAP does
  this automatically when it downloads).
- **UNITE** requires registration and a license agreement, so it cannot be
  auto-downloaded. Get the QIIME 2-formatted dynamic release (ver 10.0) from
  unite.ut.ee, then use the **Import** button in Section 1 to place it here.
- **Which to use:** SILVA is the most widely used for bacteria/archaea (16S/18S);
  Greengenes2 is a 16S alternative with an updated phylogeny; UNITE is required
  for fungal ITS studies.
- These databases are only needed if you **train** a classifier (Section 3). If
  you use a pre-trained classifier (see `../classifier/`), you don't need them.
