#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { PBMM2_ALIGN                    } from './modules/pbmm2'
include { PBSV_DISCOVER; PBSV_CALL       } from './modules/pbsv'
include { SNIFFLES2                      } from './modules/sniffles2'
include { SNIFFLES2_COHORT               } from './modules/sniffles2'
include { SNIFFLES2_MOSAIC; SNIFFLES2_COHORT as SNIFFLES2_COHORT_MOSAIC } from './modules/sniffles2'
include { DEEPVARIANT                    } from './modules/deepvariant'
include { HIPHASE                        } from './modules/hiphase'
include { PB_CPG_TOOLS                   } from './modules/pb_cpg_tools'
include { MODKIT_PILEUP                  } from './modules/modkit'

workflow {

    // ── Parse samplesheet ──────────────────────────────────────────────────
    Channel
        .fromPath(params.samplesheet)
        .splitCsv(header: true)
        .map { row ->
            def bam = file(row.bam)
            def pbi = file("${row.bam}.pbi")
            tuple(row.sample, row.condition, bam, pbi)
        }
        .set { ch_samples }

    // ── Step 1: Align unaligned HiFi BAM to hg38 with pbmm2 ───────────────
    PBMM2_ALIGN(ch_samples, params.ref)

    // ── Step 2: SV calling ─────────────────────────────────────────────────
    // pbsv: discover svsig per sample, then call SVs
    PBSV_DISCOVER(PBMM2_ALIGN.out.bam, params.ref)
    PBSV_CALL(PBSV_DISCOVER.out.svsig, params.ref)

    // Sniffles2: per-sample VCF + .snf for cohort calling
    // process SNIFFLES2 is for germline SV calling; we can also run it in "mosaic" mode for somatic SVs if needed
    SNIFFLES2(PBMM2_ALIGN.out.bam, params.ref)

    // Mosaic mode to obtain somatic and rare SVs
    SNIFFLES2_MOSAIC(PBMM2_ALIGN.out.bam, params.ref)

    // Sniffles2 cohort: collect all .snf files → joint genotyped VCF
    //SNIFFLES2_COHORT(
    //    SNIFFLES2.out.snf.collect(),
    //    params.ref
    //)

    // Sniffles2 cohort: collect all .snf files from mosaic mode → joint genotyped VCF
    //SNIFFLES2_COHORT_MOSAIC(
    //    SNIFFLES2.out.snf.collect(),
    //    params.ref
    //)

    // ── Step 3: SNV/Indel calling with DeepVariant ─────────────────────────
    DEEPVARIANT(PBMM2_ALIGN.out.bam, params.ref)

    // ── Step 4: Joint phasing with HiPhase (SNVs + SVs together) ──────────
    // ── Step 4: Joint phasing with HiPhase ────────────────────────
    // Strip condition from DeepVariant and pbsv channels before joining
    ch_deepvariant = DEEPVARIANT.out.vcf
        .map { sample, condition, vcf, tbi -> tuple(sample, condition, vcf, tbi) }

    ch_pbsv = PBSV_CALL.out.vcf
        .map { sample, condition, vcf, tbi -> tuple(sample, condition, vcf, tbi) }

    HIPHASE(
        PBMM2_ALIGN.out.bam
            .join(DEEPVARIANT.out.vcf.map { sample, cond, vcf, tbi ->
                tuple(sample, vcf, tbi) })
            .join(PBSV_CALL.out.vcf.map { sample, cond, vcf, tbi ->
                tuple(sample, vcf, tbi) })
            .map { sample, cond, bam, bai, snv_vcf, snv_tbi, sv_vcf, sv_tbi ->
                tuple(sample, cond, bam, bai, snv_vcf, snv_tbi, sv_vcf, sv_tbi)
            },
        params.ref
    )

    // ── Step 5: CpG methylation calling ───────────────────────────────────
    // Use haplotagged BAM from HiPhase for phased methylation
    PB_CPG_TOOLS(HIPHASE.out.haplotagged_bam, params.ref)
    // Define ref and fai as separate channels (for modkit as sif cannot see fai )
    ch_ref     = file(params.ref)
    ch_ref_fai = file("${params.ref}.fai")
    MODKIT_PILEUP(HIPHASE.out.haplotagged_bam, 
                file(params.ref),
                file("${params.ref}.fai"))