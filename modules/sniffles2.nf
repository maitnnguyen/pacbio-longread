process SNIFFLES2 {
    tag "${sample}"
    publishDir "${params.outdir}/sv_sniffles/${sample}", mode: 'copy'
    container params.sniffles_container

    input:
    tuple val(sample), val(condition), path(bam), path(bai)
    path ref

    output:
    tuple val(sample), val(condition), path("${sample}.sniffles.vcf.gz"), emit: vcf
    path "${sample}.sniffles.snf",                                        emit: snf

    script:
    """
    sniffles \\
        --input ${bam} \\
        --vcf ${sample}.sniffles.vcf.gz \\
        --snf ${sample}.sniffles.snf \\
        --reference ${ref} \\
        --threads ${task.cpus} \\
        --sample-id ${sample}
    """
}

process SNIFFLES2_COHORT {
    publishDir "${params.outdir}/sv_cohort", mode: 'copy'

    input:
    path snf_files
    path ref

    output:
    path "cohort.sniffles.vcf.gz",     emit: vcf
    path "cohort.sniffles.vcf.gz.tbi", emit: tbi

    script:
    """
    sniffles \\
        --input ${snf_files} \\
        --vcf cohort.sniffles.vcf.gz \\
        --reference ${ref} \\
        --threads ${task.cpus}

    tabix -p vcf cohort.sniffles.vcf.gz
    """
}