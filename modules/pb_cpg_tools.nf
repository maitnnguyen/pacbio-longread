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
    MODEL_PATH="/opt/pb-CpG-tools-v2.3.2-x86_64-unknown-linux-gnu/models/pileup_calling_model.v1.tflite"
    
    aligned_bam_to_cpg_scores \\
        --bam ${bam} \\
        --output-prefix ${sample} \\
        --model \${MODEL_PATH} \\
        --ref ${ref} \\
        --threads ${task.cpus} \\
        --min-coverage 5 --min-mapq 20
    """
}
