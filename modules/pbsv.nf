process PBSV_DISCOVER {
    tag "${sample}"
    //container params.pbsv_container

    input:
    tuple val(sample), val(condition), path(bam), path(bai)
    path ref

    output:
    tuple val(sample), val(condition), path("${sample}.svsig.gz"), emit: svsig

    script:
    def tandem = params.tandem_bed ? "--tandem-repeats ${params.tandem_bed}" : ""
    """
    pbsv discover \\
        ${tandem} \\
        ${bam} \\
        ${sample}.svsig.gz
    """
}

process PBSV_CALL {
    tag "${sample}"
    publishDir "${params.outdir}/sv_pbsv/${sample}", mode: 'copy'
    //container params.pbsv_container

    input:
    tuple val(sample), val(condition), path(svsig)
    path ref

    output:
    tuple val(sample), val(condition), path("${sample}.pbsv.vcf.gz"), path("${sample}.pbsv.vcf.gz.tbi"), emit: vcf

    script:
    """
    pbsv call \\
        --hifi \\
        --num-threads ${task.cpus} \\
        ${ref} \\
        ${svsig} \\
        ${sample}.pbsv.vcf

    bgzip ${sample}.pbsv.vcf
    tabix -p vcf ${sample}.pbsv.vcf.gz
    """
}
