# Reference Databases

QIIME 2 reference **sequence + taxonomy** artifacts (`*.qza`) used to *train*
classifiers.

**Only the UNITE (fungal ITS) reference is bundled here**, because UNITE requires
registration/licensing and cannot be auto-downloaded. SILVA and Greengenes2 are
**downloaded on demand** from inside the app, so they are not shipped.

| Database | Bundled here? | How to get it |
|----------|---------------|---------------|
| **UNITE (fungal ITS)** | ✅ yes (`unite-ver7-99-*.qza`) | already present; used by Advanced ITS training |
| SILVA 138 (16S/18S) | ❌ no | EzMAP → Database & Classifiers → **Section 1 → Download** |
| Greengenes2 2024.09 (16S) | ❌ no | EzMAP → Database & Classifiers → **Section 1 → Download** |

Downloaded databases are saved to `~/ezmap2-databases`
(`C:\Users\<you>\ezmap2-databases`).

## When are these needed?

Only if you **train** a classifier (the **Advanced** section of Database &
Classifiers). Most users don't: instead **download a pre-trained classifier**
(Section 2) — full-length SILVA/Greengenes2 classify any 16S region with no
training and no reference database required.

## Notes

- **UNITE version:** the bundled reference is UNITE ver7 (2017). For the latest
  release, download the QIIME 2-formatted dynamic UNITE from
  <https://unite.ut.ee/repository.php> and use **Import** in Section 1.
- **Downloaded filenames:** SILVA is stored as `silva-138.2-ssu-nr99-{seqs,tax}.qza`
  and Greengenes2 as `gg2-2024.09-nb-{seqs,tax}.qza` (EzMAP renames them on
  download).
