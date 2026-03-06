#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { PBSV_DISCOVER; PBSV_CALL   } from './modules/pbsv'
include { SNIFFLES2                   } from './modules/sniffles2'
include { PB_CPG_TOOLS                } from './modules/pb_cpg_tools'
include { MODKIT_PILEUP               } from './modules/modkit'

// Parameters
params.genome  = "/home/arkku/group/ics/tools/refdata-gex-GRCh38-2024-A"
params.outdir         = "${projectDir}/pacbio_results"

// Container paths
params.container_cache      = '/home/arkku/group/ics/tools/singularity_cache'
params.pbsv_container       = "${params.container_cache}/pbsv_2.9.0.sif"
params.sniffles2_container  = "${params.container_cache}/sniffles_2.4.sif"
params.pb_cpg_container     = "${params.container_cache}/pb_cpg_tools_2.3.2.sif"
params.modkit_container     = "${params.container_cache}/modkit_0.4.3.sif"


workflow {

    // Parse samplesheet
    Channel
        .fromPath(params.samplesheet)
        .splitCsv(header: true)
        .map { row ->
            def bam_file = file(row.bam)
            def bai_file = file("${row.bam}.bai")
            tuple(row.sample, row.condition, bam_file, bai_file)
        }
        .set { ch_samples }

    // SV calling - pbsv (2 steps)
    PBSV_DISCOVER(ch_samples, params.ref)
    PBSV_CALL(
        PBSV_DISCOVER.out.svsig
            .groupTuple(by: [0,1]),   // group by sample+condition
        params.ref
    )

    // SV calling - Sniffles2 (alternative/complementary)
    SNIFFLES2(ch_samples, params.ref)

    // Methylation calling - pb-CpG-tools
    PB_CPG_TOOLS(ch_samples, params.ref)

    // Methylation manipulation - modkit
    MODKIT_PILEUP(ch_samples, params.ref)
}
