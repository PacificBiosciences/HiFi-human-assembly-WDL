version 1.0

# Assembles a single genome. This workflow is run if `Sample.run_de_novo_assembly` is set to `true`. Each sample can be independently assembled in this way.

import "../assembly_structs.wdl"
import "../wdl-common/wdl/tasks/samtools_fasta.wdl" as SamtoolsFasta
import "../assemble_genome/assemble_genome.wdl" as AssembleGenome
import "../wdl-common/wdl/tasks/zip_index_vcf.wdl" as ZipIndexVcf
import "../wdl-common/wdl/tasks/bcftools_stats.wdl" as BcftoolsStats

workflow de_novo_assembly_sample {
	input {
		Sample sample

		Array[ReferenceData] references

		RuntimeAttributes default_runtime_attributes
	}

	scatter (movie_bam in sample.movie_bams) {
		call SamtoolsFasta.samtools_fasta {
			input:
				bam = movie_bam,
				runtime_attributes = default_runtime_attributes
		}
	}

	call AssembleGenome.assemble_genome {
		input:
			sample_id = sample.sample_id,
			reads_fastas = samtools_fasta.reads_fasta,
			references = references,
			default_runtime_attributes = default_runtime_attributes
	}

	scatter (aln in assemble_genome.alignments) {
		ReferenceData ref = aln.left
		IndexData bam = aln.right

		call AssembleGenome.paftools {
			input:
				bam = bam.data,
				sample = sample.sample_id,
				bam_index = bam.data_index,
				reference = ref.fasta.data,
				runtime_attributes = default_runtime_attributes
		}


		call ZipIndexVcf.zip_index_vcf {
			input:
				vcf = paftools.paftools_vcf,
				runtime_attributes = default_runtime_attributes
		}

		IndexData paftools_vcf = {
			"data": zip_index_vcf.zipped_vcf, 
			"data_index": zip_index_vcf.zipped_vcf_index
		}

		call BcftoolsStats.bcftools_stats {
			input:
				vcf = zip_index_vcf.zipped_vcf,
				params = "--samples ~{sample.sample_id}",
				reference = ref.fasta.data,
				runtime_attributes = default_runtime_attributes
		}

	}

	
	output {
		Array[File] assembly_noseq_gfas = assemble_genome.assembly_noseq_gfas
		Array[File] assembly_lowQ_beds = assemble_genome.assembly_lowQ_beds
		Array[File] zipped_assembly_fastas = assemble_genome.zipped_assembly_fastas
		Array[File] assembly_stats = assemble_genome.assembly_stats
		Array[IndexData] merged_bams = assemble_genome.merged_bams

		Array[IndexData] paftools_vcfs = paftools_vcf
		Array[File] paftools_vcf_stats = bcftools_stats.stats
	}

	parameter_meta {
		sample: {help: "Sample information and associated data files"}
		references: {help: "Array of Reference genomes data"}
		default_runtime_attributes: {help: "Default RuntimeAttributes; spot if preemptible was set to true, otherwise on_demand"}
	}
}