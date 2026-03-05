process PBSV_DISCOVER {
    tag "${sample}"

    input:
    tuple val(sample), val(condition), path(bam), path(bai)
    path ref

    output:
    tuple val(sample), val(condition), path("${sample}.svsig.gz"), emit: svsig

    script:
    """
    pbsv discover \\
        --tandem-repeats ${params.tandem_bed ?: ""} \\
        ${bam} \\
        ${sample}.svsig.gz
    """
}

process PBSV_CALL {
    tag "${sample}"
    publishDir "${params.outdir}/sv_pbsv/${sample}", mode: 'copy'

    input:
    tuple val(sample), val(condition), path(svsigs)
    path ref

    output:
    tuple val(sample), val(condition), path("${sample}.pbsv.vcf"), emit: vcf

    script:
    """
    pbsv call \\
        --hifi \\
        --num-threads ${task.cpus} \\
        ${ref} \\
        ${svsigs} \\
        ${sample}.pbsv.vcf
    """
}
