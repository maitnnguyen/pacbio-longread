process DEEPVARIANT {
    tag "${sample}"
    publishDir "${params.outdir}/snv_deepvariant/${sample}", mode: 'copy'

    input:
    tuple val(sample), val(condition), path(bam), path(bai)
    path ref

    output:
    tuple val(sample), val(condition), path("${sample}.deepvariant.vcf.gz"), path("${sample}.deepvariant.vcf.gz.tbi"), emit: vcf
    path "${sample}.deepvariant.g.vcf.gz", emit: gvcf

    script:
    """
    # Index reference if not already indexed
    if [ ! -f ${ref}.fai ]; then
        samtools faidx ${ref}
    fi

    run_deepvariant \\
        --model_type PACBIO \\
        --ref ${ref} \\
        --reads ${bam} \\
        --output_vcf ${sample}.deepvariant.vcf.gz \\
        --output_gvcf ${sample}.deepvariant.g.vcf.gz \\
        --sample_name ${sample} \\
        --num_shards ${task.cpus}

    #tabix -p vcf ${sample}.deepvariant.vcf.gz
    """
}
