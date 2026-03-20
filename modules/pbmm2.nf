process PBMM2_ALIGN {
    tag "${sample}"
    publishDir "${params.outdir}/aligned/${sample}", mode: 'copy'
    //container params.pbmm2_container

    input:
    tuple val(sample), val(condition), path(bam), path(pbi)
    path ref

    output:
    tuple val(sample), val(condition), path("${sample}.aligned.bam"), path("${sample}.aligned.bam.bai"), emit: bam

    script:
    """
    pbmm2 align \\
        --preset CCS \\
        --sort \\
        --unmapped \\
        -j ${task.cpus} \\
        ${ref} \\
        ${bam} \\
        ${sample}.aligned.bam

    samtools index ${sample}.aligned.bam
    """
}
//    --rg "@RG\\tID:${sample}\\tSM:${sample}\\tPL:PACBIO" \\
    