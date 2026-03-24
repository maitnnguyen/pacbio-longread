process HIPHASE {
    tag "${sample}"
    publishDir "${params.outdir}/phased/${sample}", mode: 'copy'
    //container params.hiphase_container

    input:
    tuple val(sample), val(condition),
          path(bam), path(bai),
          path(snv_vcf), path(snv_tbi),
          path(sv_vcf),  path(sv_tbi)
    path ref

    output:
    tuple val(sample), val(condition),
          path("${sample}.haplotagged.bam"),
          path("${sample}.haplotagged.bam.bai"),     emit: haplotagged_bam
    tuple val(sample), val(condition),
          path("${sample}.phased.snv.vcf.gz"),
          path("${sample}.phased.snv.vcf.gz.tbi"),   emit: phased_snv_vcf
    tuple val(sample), val(condition),
          path("${sample}.phased.sv.vcf.gz"),
          path("${sample}.phased.sv.vcf.gz.tbi"),    emit: phased_sv_vcf
    path "${sample}.hiphase.stats.tsv",               emit: stats
    path "${sample}.hiphase.blocks.tsv",              emit: blocks
    path "${sample}.hiphase.haplotag.tsv",              emit: haplotag

    script:
    """
    hiphase \\
        --threads ${task.cpus} \\
        --reference ${ref} \\
        --bam ${bam} \\
        --vcf ${snv_vcf} \\
        --vcf ${sv_vcf} \\
        --output-vcf ${sample}.phased.snv.vcf.gz \\
        --output-vcf ${sample}.phased.sv.vcf.gz \\
        --output-bam ${sample}.haplotagged.bam \\
        --stats-file ${sample}.hiphase.stats.tsv \\
        --blocks-file ${sample}.hiphase.blocks.tsv \\
        --haplotag-file ${sample}.hiphase.haplotag.tsv \\
        --summary-file ${sample}.hiphase.summary.tsv \\
        --min-vcf-qual 10 

    samtools index ${sample}.haplotagged.bam
    #tabix -p vcf ${sample}.phased.snv.vcf.gz
    #tabix -p vcf ${sample}.phased.sv.vcf.gz
    """
}
