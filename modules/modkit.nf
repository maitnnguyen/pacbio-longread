process MODKIT_PILEUP {
    tag "${sample}"
    publishDir "${params.outdir}/methylation_modkit/${sample}", mode: 'copy'

    input:
    tuple val(sample), val(condition), path(bam), path(bai)
    path ref

    output:
    tuple val(sample), val(condition), path("${sample}.modkit.bed.gz"), emit: bedmethyl
    path "${sample}.modkit.log",                                        emit: log

    script:
    """
    modkit pileup \\
        ${bam} \\
        ${sample}.modkit.bed \\
        --ref ${ref} \\
        --threads ${task.cpus} \\
        --preset traditional \\
        --log-filepath ${sample}.modkit.log \\
        --combine-strands \\
        --cpg

    bgzip ${sample}.modkit.bed
    """
}
