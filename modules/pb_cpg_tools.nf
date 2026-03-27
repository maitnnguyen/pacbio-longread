process PB_CPG_TOOLS {
    tag "${sample}"
    publishDir "${params.outdir}/methylation/${sample}", mode: 'copy'

    container params.pb_cpg_container

    input:
    tuple val(sample), val(condition), path(bam), path(bai)
    path ref

    output:
    tuple val(sample), val(condition), path("${sample}.combined.bed.gz"), emit: bedmethyl
    path "${sample}.hap1.bed.gz", optional: true
    path "${sample}.hap2.bed.gz", optional: true

    script:
    """
    aligned_bam_to_cpg_scores \\
        --bam ${bam} \\
        --output-prefix ${sample} \\
        --ref ${ref} \\
        --threads ${task.cpus} \\
        --min-coverage 5 --min-mapq 20
    """
}
