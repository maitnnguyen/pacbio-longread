process SNIFFLES2 {
    tag "${sample}"
    publishDir "${params.outdir}/sv_sniffles/${sample}", mode: 'copy'

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
