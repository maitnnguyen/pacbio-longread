# 🧬 PacBio HiFi Long-Read Sequencing Pipeline

> Nextflow DSL2 pipeline for structural variant calling and CpG methylation profiling from PacBio HiFi whole genome sequencing data.  
> Designed for the CVID multi-omic study — 20 patients + 50 controls, BAMs stored on CSC Allas (S3).

---

## Table of Contents

- [Overview](#overview)
- [Pipeline Structure](#pipeline-structure)
- [Requirements](#requirements)
- [Allas S3 Setup](#allas-s3-setup)
- [Samplesheet](#samplesheet)
- [Running the Pipeline](#running-the-pipeline)
- [Modules](#modules)
- [Output Structure](#output-structure)
- [Downstream Analysis](#downstream-analysis)
- [References](#references)

---

## Overview

This pipeline processes PacBio HiFi BAM files to extract three analytical layers:

| Layer | Tools | Notes |
|-------|-------|-------|
| Structural Variants (SVs) | `pbsv`, `Sniffles2` | Per-sample + cohort-level joint calling |
| CpG Methylation | `pb-CpG-tools`, `modkit` | Genome-wide 5mC from MM:/ML: tags |
| Phased Methylation | `ccsmeth` | Haplotype-resolved allele-specific methylation |

> ⚠️ **Prerequisite:** BAM files must contain `MM:` and `ML:` kinetics tags for methylation calling.  
> Verify with: `samtools view your.bam | head -5 | tr '\t' '\n' | grep -E '^MM:|^ML:'`

---

## Pipeline Structure

```
.
├── main.nf
├── nextflow.config
├── samplesheet.csv
└── modules/
    ├── pbsv.nf
    ├── sniffles2.nf
    ├── pb_cpg_tools.nf
    └── modkit.nf
```

---

## Requirements

- [Nextflow](https://www.nextflow.io/) >= 23.04
- Singularity (on CSC Puhti/Mahti — Docker not available on HPC)
- Access to CSC Allas with S3 credentials
- Reference genome: `hg38.fa` + `.fai` index

---

## Allas S3 Setup

BAM files are read directly from Allas via S3 — no pre-download needed.

**Step 1 — Authenticate:**
```bash
module load allas
allas-conf --mode s3cmd
```

**Step 2 — Export credentials:**
```bash
export AWS_ACCESS_KEY_ID=$(grep access_key ~/.s3cfg | awk '{print $3}')
export AWS_SECRET_ACCESS_KEY=$(grep secret_key ~/.s3cfg | awk '{print $3}')
```

**Step 3 — Verify bucket access:**
```bash
s5cmd --endpoint-url https://a3s.fi ls s3://your-bucket/
```

> ⚠️ Allas credentials expire after ~8 hours. Use `-resume` so completed processes are not re-run after re-authentication.

The S3 endpoint is configured in `nextflow.config`:
```groovy
aws {
    client {
        endpoint          = "https://a3s.fi"
        s3PathStyleAccess = true
    }
    region = "regionOne"
}
```

---

## Samplesheet

Provide a CSV file with the following columns:

```csv
sample,condition,bam
CVID_01,CVID,s3://your-bucket/pacbio/CVID_01.bam
CVID_02,CVID,s3://your-bucket/pacbio/CVID_02.bam
CTRL_01,control,s3://your-bucket/pacbio/CTRL_01.bam
CTRL_02,control,s3://your-bucket/pacbio/CTRL_02.bam
```

- `sample` — unique sample ID
- `condition` — `CVID` or `control`
- `bam` — full S3 path to HiFi BAM on Allas (BAI index expected at `<bam>.bai`)

---

## Running the Pipeline

```bash
nextflow run main.nf \
    --samplesheet samplesheet.csv \
    --ref /path/to/hg38.fa \
    --outdir results \
    -profile slurm \
    -resume
```

### Key parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--samplesheet` | Path to CSV samplesheet | `samplesheet.csv` |
| `--ref` | Path to hg38 reference FASTA | required |
| `--outdir` | Output directory | `results` |
| `--tandem_bed` | Tandem repeat BED for pbsv (optional but recommended) | `null` |

---

## Modules

### `pbsv` — Structural Variant Calling (PacBio native)

Two-step process:

```
pbsv discover  →  per-sample .svsig.gz
pbsv call      →  per-sample VCF
```

- Container: `quay.io/pacbio/pbsv:2.9.0_1.14_build1`
- Recommended: provide `--tandem_bed` (PacBio human tandem repeat BED) for improved SV breakpoint accuracy

---

### `sniffles2` — Structural Variant Calling (alternative + cohort)

```
sniffles --input  →  per-sample VCF + .snf file
sniffles --snf    →  joint cohort VCF (all 70 samples)
```

- Container: `quay.io/biocontainers/sniffles:2.4--pyhdfd78af_0`
- The `.snf` file per sample is retained for cohort-level joint calling — do not delete intermediate outputs
- Joint calling across all 70 samples produces a fully genotyped multi-sample VCF

---

### `pb_cpg_tools` — CpG Methylation Calling (primary)

```
aligned_bam_to_cpg_scores  →  bedMethyl per sample
```

- Container: `docker.io/mgibio/pb-cpg-tools:latest`
- Uses PacBio deep learning model (`--model DeepLearning`) for improved accuracy
- Minimum coverage: `--min-coverage 10`
- Output: `sample.combined.bed.gz` (merged strands), `sample.hap1.bed.gz`, `sample.hap2.bed.gz`

---

### `modkit` — CpG Methylation (validation + flexible manipulation)

```
modkit pileup  →  bedMethyl per sample
```

- Container: `quay.io/biocontainers/ont-modkit:0.4.3--hcdda2d0_0`
- Flags: `--preset traditional --combine-strands --cpg`
- Complements pb-CpG-tools — use both for cross-validation of methylation calls
- Also useful for downstream filtering, subsetting, and format conversion

---

## Output Structure

```
results/
├── sv_pbsv/
│   └── <sample>/
│       └── <sample>.pbsv.vcf
├── sv_sniffles/
│   └── <sample>/
│       ├── <sample>.sniffles.vcf.gz
│       └── <sample>.sniffles.snf          ← retain for cohort calling
├── sv_cohort/
│   └── cohort.sniffles.vcf.gz             ← joint VCF (all samples)
├── methylation/
│   └── <sample>/
│       ├── <sample>.combined.bed.gz
│       ├── <sample>.hap1.bed.gz
│       └── <sample>.hap2.bed.gz
└── methylation_modkit/
    └── <sample>/
        ├── <sample>.modkit.bed.gz
        └── <sample>.modkit.log
```

---

## Downstream Analysis

### 1. Structural Variant Analysis

**Merge pbsv + Sniffles2 calls (high-confidence SV set):**
```bash
# Install SURVIVOR
SURVIVOR merge sample_vcfs.txt 1000 2 1 1 0 50 merged.vcf
```

**Annotate SVs against CVID-relevant loci:**
```bash
# Intersect with gene BED (IgH, NFKB1, AICDA, TNFRSF13B, IKBKG)
bedtools intersect -a merged.vcf -b cvid_genes.bed -header > svs_at_cvid_loci.vcf
```

**Population-level comparison in R:**
```r
library(VariantAnnotation)
library(ggplot2)

# Load cohort VCF
vcf <- readVcf("results/sv_cohort/cohort.sniffles.vcf.gz", "hg38")

# Compare SV burden CVID vs control
sv_counts <- data.frame(
  sample    = samples(header(vcf)),
  condition = c(rep("CVID", 20), rep("control", 50)),
  n_sv      = colSums(geno(vcf)$GT != "0/0", na.rm = TRUE)
)
ggplot(sv_counts, aes(condition, n_sv, fill = condition)) +
  geom_boxplot() +
  labs(title = "SV burden: CVID vs control")
```

---

### 2. CpG Methylation Analysis

**Differential methylation with DSS (R):**
```r
library(DSS)
library(bsseq)

# Load bedMethyl files for all samples
# (cols: chr, start, end, coverage, methylated_count)
cvid_samples    <- lapply(cvid_files,    read_bedmethyl)
control_samples <- lapply(control_files, read_bedmethyl)

bs <- makeBSseqData(c(cvid_samples, control_samples),
                    sampleNames = c(cvid_ids, control_ids))

# DML test
dml_test <- DMLtest(bs,
                    group1 = cvid_ids,
                    group2 = control_ids,
                    smoothing = TRUE)

# Call DMRs
dmrs <- callDMR(dml_test, p.threshold = 0.05)
```

**Prioritise DMRs at regulatory regions:**
```bash
# Overlap DMRs with B cell enhancers (ENCODE / Blueprint)
bedtools intersect \
    -a dmrs.bed \
    -b bcell_enhancers_hg38.bed \
    -wo > dmrs_at_bcell_enhancers.bed

# Overlap with CVID gene promoters (±2kb TSS)
bedtools intersect \
    -a dmrs.bed \
    -b cvid_gene_promoters.bed \
    -wo > dmrs_at_cvid_promoters.bed
```

**Haplotype-phased methylation (allele-specific):**
```bash
# Run ccsmeth phasing mode (requires HP-tagged BAM)
ccsmeth call_mods \
    --input sample.bam \
    --ref hg38.fa \
    --output sample_ccsmeth

ccsmeth call_freqb \
    --input_bam sample_ccsmeth.bam \
    --ref hg38.fa \
    --output sample_freq \
    --bed \
    --call_phasedcpg
```

Use phased output to investigate whether LOH regions show allele-specific methylation silencing on the remaining allele.

---

### 3. Integration: SVs × Methylation

Link structural events to epigenetic changes at the same loci:

```bash
# Find samples with SV at a locus AND DMR at the same region
bedtools intersect \
    -a dmrs_at_cvid_loci.bed \
    -b svs_at_cvid_loci.vcf \
    -wo > sv_methylation_overlap.bed
```

**Key biological question:** In CVID patients with LOH at a gene (e.g. NFKB1), is the remaining allele epigenetically silenced by hypermethylation? This would represent a two-hit epigenetic mechanism.

---

### 4. Recommended R Packages for Downstream Analysis

| Task | Package |
|------|---------|
| Differential methylation | `DSS`, `methylKit` |
| DMR calling | `DSS` + `bsseq` |
| SV annotation | `VariantAnnotation`, `StructuralVariantAnnotation` |
| Genomic overlaps | `GenomicRanges`, `bedtools` |
| Visualisation | `ggplot2`, `ComplexHeatmap`, `Gviz` |
| Allele-specific analysis | `AllelicImbalance` |

---

## References

| Tool | Citation |
|------|----------|
| **pbsv** | PacBio — https://github.com/PacificBiosciences/pbsv |
| **Sniffles2** | Smolka et al., *Nat Biotechnol* 2024. doi:10.1038/s41587-023-02024-y |
| **pb-CpG-tools** | PacBio — https://github.com/PacificBiosciences/pb-CpG-tools |
| **ccsmeth** | Ni et al., *Nat Commun* 2023. doi:10.1038/s41467-023-39784-9 |
| **modkit** | Oxford Nanopore — https://github.com/nanoporetech/modkit |
| **DSS** | Feng et al., *Nucleic Acids Res* 2014. doi:10.1093/nar/gku154 |

---

*CVID Multi-Omic Study — CSC Finland | PacBio HiFi WGS pipeline*
