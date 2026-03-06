# 🧬 PacBio HiFi Long-Read Sequencing Pipeline

> Nextflow DSL2 pipeline for alignment, SNV/indel calling, structural variant calling, haplotype phasing, and CpG methylation profiling from PacBio HiFi whole genome sequencing data.  
> Designed for the CVID multi-omic study — 20 CVID patients + 50 controls.  
> Platform: **CSC Puhti** | Executor: **SLURM** | Containers: **Singularity**

---

## Table of Contents

- [Overview](#overview)
- [Pipeline Structure](#pipeline-structure)
- [Requirements](#requirements)
- [Samplesheet](#samplesheet)
- [Configuration](#configuration)
- [Running the Pipeline](#running-the-pipeline)
- [Modules](#modules)
- [Output Structure](#output-structure)
- [Downstream Analysis](#downstream-analysis)
- [Containers](#containers)
- [References](#references)

---

## Overview

This pipeline takes **unaligned PacBio HiFi BAMs** (straight from instrument demultiplexing) and processes them through five sequential stages:

```
Unaligned HiFi BAM  (.bam + .bam.pbi)
        │
        ▼
 [1] pbmm2          →  Aligned + sorted BAM (hg38)
        │
        ├──────────────────────┐
        ▼                      ▼
 [2a] pbsv                  Sniffles2      →  SV calls per sample
      pbsv discover                           + cohort joint VCF
      pbsv call
        │
        ▼
 [2b] DeepVariant (PACBIO)  →  SNV/Indel VCF per sample
        │
        ▼
 [3]  HiPhase               →  Jointly phased SNV + SV VCFs
                               + HP-tagged haplotagged BAM
        │
        ▼
 [4]  pb-CpG-tools          →  Genome-wide CpG methylation (bedMethyl)
      modkit pileup             Hap1 / Hap2 methylation (phased)
```

---

## Pipeline Structure

```
.
├── main.nf
├── nextflow.config
├── samplesheet.csv
└── modules/
    ├── pbmm2.nf
    ├── pbsv.nf
    ├── sniffles2.nf
    ├── deepvariant.nf
    ├── hiphase.nf
    ├── pb_cpg_tools.nf
    └── modkit.nf
```

---

## Requirements

- [Nextflow](https://www.nextflow.io/) >= 23.04
- Singularity/Apptainer (available on Puhti via `module load singularity-apptainer`)
- CSC Puhti project account (`project_2xxxxxxx`)
- Reference genome: `hg38.fa` + `hg38.fa.fai` (samtools faidx)
- Optional: PacBio human tandem repeat BED for improved pbsv accuracy

> ⚠️ **Input BAMs must be unaligned HiFi CCS BAMs** with kinetics tags (`MM:`/`ML:`) preserved for methylation calling.  
> Verify: `samtools view your.bam | head -5 | tr '\t' '\n' | grep -E '^MM:|^ML:'`

---

## Samplesheet

Create `samplesheet.csv` with local paths to unaligned BAMs on Puhti scratch:

```csv
sample,condition,bam
CVID_01,CVID,/scratch/project_2xxxxxxx/data/CVID_01/m64145_240117_141650.bcAd1056T--bcAd1056T.bam
CVID_02,CVID,/scratch/project_2xxxxxxx/data/CVID_02/m84212_240222_154443_s4.hifi_reads.bcAd1023T.bam
CTRL_01,control,/scratch/project_2xxxxxxx/data/CTRL_01/sample.bam
CTRL_02,control,/scratch/project_2xxxxxxx/data/CTRL_02/sample.bam
```

- `sample` — unique sample ID (used for all output filenames)
- `condition` — `CVID` or `control`
- `bam` — absolute path to unaligned HiFi BAM (`.bam.pbi` index expected at same location)

> **Note:** When data is moved to Allas S3, replace local paths with `s3://your-bucket/path/sample.bam`  
> and uncomment the `aws` block in `nextflow.config`.

---

## Configuration

Edit `nextflow.config` before running:

| Field | Where | What to change |
|-------|-------|----------------|
| `project_2xxxxxxx` | all `clusterOptions` | Replace with your CSC project number |
| `params.ref` | `params` block | Absolute path to `hg38.fa` on scratch |
| `singularity.cacheDir` | singularity block | Path to your Singularity image cache |
| `workDir` | bottom of config | Nextflow work directory on scratch |
| `params.tandem_bed` | `params` block | Optional: path to PacBio tandem repeat BED |

---

## Running the Pipeline

```bash
# Load required modules on Puhti
module load nextflow
module load singularity-apptainer

# Launch pipeline
nextflow run main.nf \
    --samplesheet samplesheet.csv \
    --ref /scratch/project_2xxxxxxx/${USER}/ref/hg38.fa \
    --outdir results \
    -resume
```

Use `-resume` to restart from the last successful step if a job fails or times out.

### Run as a SLURM batch job (recommended for full cohort)

```bash
#!/bin/bash
#SBATCH --job-name=cvid_pacbio
#SBATCH --account=project_2xxxxxxx
#SBATCH --partition=small
#SBATCH --time=72:00:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G

module load nextflow
module load singularity-apptainer

nextflow run main.nf \
    --samplesheet samplesheet.csv \
    --ref /scratch/project_2xxxxxxx/${USER}/ref/hg38.fa \
    --outdir results \
    -resume
```

---

## Modules

### `pbmm2` — Alignment
Maps unaligned HiFi BAM to hg38 using the `CCS` preset. Preserves all PacBio-specific tags including `MM:`/`ML:` kinetics for downstream methylation calling.

- Container: `quay.io/pacbio/pbmm2:1.13.0_build1`
- Key flag: `--unmapped` retains unmapped reads in output BAM

---

### `pbsv` — SV Calling (PacBio native)
Two-step process: `discover` builds a per-sample signature file (`.svsig.gz`), `call` genotypes SVs into VCF.

- Container: `quay.io/pacbio/pbsv:2.9.0_1.14_build1`
- Provide `--tandem_bed` for significantly improved accuracy at repetitive regions

---

### `sniffles2` — SV Calling (cohort-aware)
Per-sample calling produces both a VCF and a `.snf` snapshot file. All `.snf` files are then merged in `SNIFFLES2_COHORT` to produce a fully genotyped multi-sample VCF across all 70 samples.

- Container: `quay.io/biocontainers/sniffles:2.4--pyhdfd78af_0`
- The `.snf` intermediate files are retained — do not delete before cohort step completes

---

### `deepvariant` — SNV/Indel Calling
Uses the `PACBIO` model specifically trained on HiFi reads. Outputs both a VCF and gVCF per sample.

- Container: `google/deepvariant:1.6.1`
- gVCF output enables joint genotyping across cohort if needed downstream

---

### `hiphase` — Joint Phasing
Takes the aligned BAM + DeepVariant SNV VCF + pbsv SV VCF simultaneously and phases them together into haplotype-resolved calls. Outputs:
- Phased SNV VCF
- Phased SV VCF
- HP-tagged haplotagged BAM (required for phased methylation in pb-CpG-tools)

- Container: `quay.io/pacbio/hiphase:1.5.0_build1`
- Key advantage over WhatsHap: jointly phases SNVs + SVs in a single step

---

### `pb_cpg_tools` — CpG Methylation (primary)
Calls 5mC methylation using PacBio's deep learning model directly from the HP-tagged haplotagged BAM. Produces haplotype-separated bedMethyl files (hap1/hap2) enabling allele-specific methylation analysis.

- Container: `quay.io/pacbio/pb-cpg-tools:3.0.0_build1`
- Minimum coverage: `--min-coverage 10`

---

### `modkit` — CpG Methylation (validation)
Independent methylation calling using ONT modkit (compatible with PacBio MM:/ML: tags). Used to cross-validate pb-CpG-tools calls.

- Container: `quay.io/biocontainers/ont-modkit:0.4.3--hcdda2d0_0`

---

## Output Structure

```
results/
├── aligned/
│   └── <sample>/
│       ├── <sample>.aligned.bam
│       └── <sample>.aligned.bam.bai
├── sv_pbsv/
│   └── <sample>/
│       ├── <sample>.pbsv.vcf.gz
│       └── <sample>.pbsv.vcf.gz.tbi
├── sv_sniffles/
│   └── <sample>/
│       ├── <sample>.sniffles.vcf.gz
│       └── <sample>.sniffles.snf          ← keep for cohort step
├── sv_cohort/
│   ├── cohort.sniffles.vcf.gz             ← joint VCF all samples
│   └── cohort.sniffles.vcf.gz.tbi
├── snv_deepvariant/
│   └── <sample>/
│       ├── <sample>.deepvariant.vcf.gz
│       ├── <sample>.deepvariant.vcf.gz.tbi
│       └── <sample>.deepvariant.g.vcf.gz
├── phased/
│   └── <sample>/
│       ├── <sample>.haplotagged.bam       ← HP-tagged, used for methylation
│       ├── <sample>.haplotagged.bam.bai
│       ├── <sample>.phased.snv.vcf.gz
│       ├── <sample>.phased.sv.vcf.gz
│       ├── <sample>.hiphase.stats.tsv
│       └── <sample>.hiphase.blocks.tsv
├── methylation/
│   └── <sample>/
│       ├── <sample>.combined.bed.gz       ← merged strands
│       ├── <sample>.hap1.bed.gz           ← haplotype 1
│       └── <sample>.hap2.bed.gz           ← haplotype 2
├── methylation_modkit/
│   └── <sample>/
│       ├── <sample>.modkit.bed.gz
│       └── <sample>.modkit.log
└── reports/
    ├── pipeline_report.html
    ├── timeline.html
    └── dag.html
```

---

## Downstream Analysis

### 1. SNV/Indel Analysis

**Filter PASS variants and annotate:**
```bash
# Filter PASS only
bcftools view -f PASS sample.deepvariant.vcf.gz -O z -o sample.pass.vcf.gz

# Annotate with VEP or ANNOVAR against known CVID genes
# Key genes: TNFRSF13B, NFKB1, IKBKG, AICDA, PIK3CD, PIK3R1, CARD11
bcftools view sample.pass.vcf.gz chr4 chr12 chr14 chr17 chrX \
    -O z -o sample.cvid_loci.vcf.gz
```

**LOH detection in R:**
```r
library(ASCAT)
# Use phased SNV VCF B-allele frequencies to detect LOH regions
# Compare CVID vs control allele imbalance at known CVID gene loci
```

---

### 2. Structural Variant Analysis

**Merge pbsv + Sniffles2 for high-confidence SVs:**
```bash
SURVIVOR merge sample_vcfs.txt 1000 2 1 1 0 50 sample.merged.vcf
```

**Annotate against CVID-relevant loci:**
```bash
# IgH locus (chr14:105,583,000-106,879,000), NFKB1 (chr4), AICDA (chr12)
bedtools intersect \
    -a sample.merged.vcf \
    -b cvid_genes.bed -header \
    > sample.svs_cvid_loci.vcf
```

**Cohort-level comparison (R):**
```r
library(VariantAnnotation)
library(ggplot2)

vcf <- readVcf("results/sv_cohort/cohort.sniffles.vcf.gz", "hg38")
sv_burden <- data.frame(
  sample    = samples(header(vcf)),
  condition = c(rep("CVID", 20), rep("control", 50)),
  n_sv      = colSums(geno(vcf)$GT != "0/0", na.rm = TRUE)
)
ggplot(sv_burden, aes(condition, n_sv, fill = condition)) +
  geom_boxplot() +
  labs(title = "SV burden: CVID vs control")
```

---

### 3. Haplotype Phasing QC

```bash
# Check phase block statistics from HiPhase output
# Key metrics: NG50 phase block length, % genome phased, % genes fully phased
awk 'NR>1 {sum+=$5; count++} END {print "Mean block length:", sum/count}' \
    sample.hiphase.blocks.tsv
```

---

### 4. CpG Methylation Analysis

**Differential methylation (CVID vs control) in R:**
```r
library(DSS)
library(bsseq)

# Load bedMethyl per sample (cols: chr, start, end, coverage, methylated)
read_bedmethyl <- function(f) {
  df <- read.table(f, header=FALSE, sep="\t")
  data.frame(chr=df$V1, pos=df$V2, N=df$V5, X=round(df$V5 * df$V10/100))
}

cvid_data    <- lapply(cvid_bedmethyl_files, read_bedmethyl)
control_data <- lapply(control_bedmethyl_files, read_bedmethyl)

bs <- makeBSseqData(
  c(cvid_data, control_data),
  sampleNames = c(cvid_ids, control_ids)
)

# DML test + DMR calling
dml  <- DMLtest(bs, group1 = cvid_ids, group2 = control_ids, smoothing = TRUE)
dmrs <- callDMR(dml, p.threshold = 0.05, minLen = 50, minCG = 3)
```

**Prioritise DMRs at B cell regulatory regions:**
```bash
# Overlap DMRs with B cell enhancers (ENCODE Blueprint)
bedtools intersect -a dmrs.bed -b bcell_enhancers_hg38.bed -wo \
    > dmrs_bcell_enhancers.bed

# Overlap with CVID gene promoters (±2kb TSS)
bedtools intersect -a dmrs.bed -b cvid_promoters_2kb.bed -wo \
    > dmrs_cvid_promoters.bed
```

**Allele-specific methylation (hap1 vs hap2):**
```r
# Compare hap1 vs hap2 bedMethyl at LOH regions
# If one allele shows >20% methylation difference → allele-specific silencing
hap1 <- read_bedmethyl("sample.hap1.bed.gz")
hap2 <- read_bedmethyl("sample.hap2.bed.gz")
asm  <- merge(hap1, hap2, by=c("chr","pos"), suffixes=c(".h1",".h2"))
asm$delta <- abs(asm$methylation.h1 - asm$methylation.h2)
asm_hits  <- asm[asm$delta > 0.20, ]
```

---

### 5. Multi-Layer Integration

**Link SNV/LOH → Methylation → Expression:**
```bash
# Find DMRs co-occurring with LOH regions
bedtools intersect -a dmrs_cvid_promoters.bed -b loh_regions.bed -wo \
    > loh_with_methylation.bed
```

Key biological question: in CVID patients with LOH at a gene locus, does the remaining allele show hypermethylation (allele-specific methylation from hap1/hap2 bedMethyl)? This two-hit epigenetic mechanism would be a strong mechanistic finding.

**Recommended R packages:**

| Task | Package |
|------|---------|
| Differential methylation | `DSS`, `methylKit` |
| DMR calling | `DSS` + `bsseq` |
| SNV annotation | `VariantAnnotation`, `VEP` |
| SV annotation | `StructuralVariantAnnotation` |
| Genomic overlaps | `GenomicRanges`, `bedtools` |
| Allele-specific analysis | `AllelicImbalance` |
| Visualisation | `ggplot2`, `ComplexHeatmap`, `Gviz` |

---

## Containers

| Tool | Container | Registry |
|------|-----------|----------|
| pbmm2 | `quay.io/pacbio/pbmm2:1.13.0_build1` | quay.io/pacbio |
| pbsv | `quay.io/pacbio/pbsv:2.9.0_1.14_build1` | quay.io/pacbio |
| Sniffles2 | `quay.io/biocontainers/sniffles:2.4--pyhdfd78af_0` | BioContainers |
| DeepVariant | `google/deepvariant:1.6.1` | Docker Hub |
| HiPhase | `quay.io/pacbio/hiphase:1.5.0_build1` | quay.io/pacbio |
| pb-CpG-tools | `quay.io/pacbio/pb-cpg-tools:3.0.0_build1` | quay.io/pacbio |
| modkit | `quay.io/biocontainers/ont-modkit:0.4.3--hcdda2d0_0` | BioContainers |

> All PacBio official tools are hosted at `https://quay.io/organization/pacbio` — check there for latest tags.  
> Singularity images are pulled and cached automatically by Nextflow on first run.

---

## References

| Tool | Citation |
|------|----------|
| **pbmm2** | PacBio — https://github.com/PacificBiosciences/pbmm2 |
| **pbsv** | PacBio — https://github.com/PacificBiosciences/pbsv |
| **Sniffles2** | Smolka et al., *Nat Biotechnol* 2024. doi:10.1038/s41587-023-02024-y |
| **DeepVariant** | Poplin et al., *Nat Biotechnol* 2018. doi:10.1038/nbt.4235 |
| **HiPhase** | Holt et al., *Bioinformatics* 2024. doi:10.1093/bioinformatics/btae042 |
| **pb-CpG-tools** | PacBio — https://github.com/PacificBiosciences/pb-CpG-tools |
| **ccsmeth** | Ni et al., *Nat Commun* 2023. doi:10.1038/s41467-023-39784-9 |
| **modkit** | Oxford Nanopore — https://github.com/nanoporetech/modkit |
| **DSS** | Feng et al., *Nucleic Acids Res* 2014. doi:10.1093/nar/gku154 |

---

*CVID Multi-Omic Study — CSC Puhti | PacBio HiFi WGS pipeline*
