version 1.0

# Performs de novo assembly on a trio, using parental information and phasing to improve the assembly.
# This workflow will run if `Cohort.run_de_novo_assembly_trio` is set to `true`. The cohort must include at least one valid trio (child, father, and mother).

import "../assembly_structs.wdl"
import "../wdl-common/wdl/tasks/samtools_fasta.wdl" as SamtoolsFasta
import "../assemble_genome/assemble_genome.wdl" as AssembleGenome
import "../wdl-common/wdl/tasks/zip_index_vcf.wdl" as ZipIndexVcf
import "../wdl-common/wdl/tasks/bcftools_stats.wdl" as BcftoolsStats

workflow de_novo_assembly_trio {
	input {
		Cohort cohort

		Array[ReferenceData] references

		String backend
		RuntimeAttributes default_runtime_attributes
		RuntimeAttributes on_demand_runtime_attributes
	}

	call parse_families {
		input:
			cohort_json = write_json(cohort),
			runtime_attributes = default_runtime_attributes
	}

	Array[FamilySampleIndices] families = read_json(parse_families.families_json)


	# Run de_novo_assembly for each child with mother and father samples present in the cohort
	# Multiple children per family and multiple unrelated families can be included in the cohort and will each produce separate child assemblies
	scatter (family in families) {
		Sample father = cohort.samples[family.father_index]
		Sample mother = cohort.samples[family.mother_index]

		scatter (movie_bam in father.movie_bams) {
			call SamtoolsFasta.samtools_fasta as samtools_fasta_father {
				input:
					bam = movie_bam,
					runtime_attributes = default_runtime_attributes
			}
		}

		scatter (movie_bam in mother.movie_bams) {
			call SamtoolsFasta.samtools_fasta as samtools_fasta_mother {
				input:
					bam = movie_bam,
					runtime_attributes = default_runtime_attributes
			}
		}

		# if parental coverage is low (<15x), keep singleton kmers from parents and use them to bin child reads
		# if parental coverage is high (>=15x), use bloom filter and require that a kmer occur >= 5 times in
		#     one parent and <2 times in the other parent to be used for binning
		# 60GB uncompressed FASTA ~= 10x coverage (this is not robust to big changes in mean read length)
		# memory for 24 threads is 48GB with bloom filter (<=50x coverage) and 65GB without bloom filter (<=30x coverage)
		Boolean low_depth = if ((size(samtools_fasta_father.reads_fasta, "GB") < 90) && (size(samtools_fasta_mother.reads_fasta, "GB") < 90)) then true else false

		String yak_params = if (low_depth) then "-b0" else "-b37"
		Int yak_mem_gb = if (low_depth) then 70 else 50
		String hifiasm_extra_params = if (low_depth) then "-c1 -d1" else "-c2 -d5"

		call AssembleGenome.yak_count as yak_count_father {
			input:
				sample_id = father.sample_id,
				reads_fastas = samtools_fasta_father.reads_fasta,
				yak_params = yak_params,
				mem_gb = yak_mem_gb,
				runtime_attributes = default_runtime_attributes
		}

		call AssembleGenome.yak_count as yak_count_mother {
			input:
				sample_id = mother.sample_id,
				reads_fastas = samtools_fasta_mother.reads_fasta,
				yak_params = yak_params,
				mem_gb = yak_mem_gb,
				runtime_attributes = default_runtime_attributes
		}

		# Father is haplotype 1; mother is haplotype 2
		Map[String, String] haplotype_key_map = {
			"hap1": father.sample_id,
			"hap2": mother.sample_id
		}

		scatter (child_index in family.child_indices) {
			Sample child = cohort.samples[child_index]

			# Count child kmers for the post assembly QV check
			call AssembleGenome.yak_count as yak_count_child {
				input:
					sample_id = child.sample_id,
					reads_fastas = samtools_fasta_mother.reads_fasta,
					yak_params = yak_params,
					mem_gb = yak_mem_gb,
					runtime_attributes = default_runtime_attributes
			}


			scatter (movie_bam in child.movie_bams) {
				call SamtoolsFasta.samtools_fasta as samtools_fasta_child {
					input:
						bam = movie_bam,
						runtime_attributes = default_runtime_attributes
				}
			}

			call AssembleGenome.assemble_genome {
				input:
					sample_id = "~{cohort.cohort_id}.~{child.sample_id}",
					reads_fastas = samtools_fasta_child.reads_fasta,
					references = references,
					hifiasm_extra_params = hifiasm_extra_params,
					father_yak = yak_count_father.yak,
					mother_yak = yak_count_mother.yak,
					backend = backend,
					default_runtime_attributes = default_runtime_attributes,
					on_demand_runtime_attributes = on_demand_runtime_attributes
			}

			scatter (aln in assemble_genome.alignments) {
				ReferenceData ref = aln.left
				IndexData bam = aln.right

				call AssembleGenome.paftools {
					input:
						bam = bam.data,
						sample = child.sample_id,
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
						params = "--samples ~{child.sample_id}",
						reference = ref.fasta.data,
						runtime_attributes = default_runtime_attributes
				}

			}

		}
	}

	output {
		Array[Map[String, String]] haplotype_key = haplotype_key_map
		Array[Array[File]] assembly_noseq_gfas = flatten(assemble_genome.assembly_noseq_gfas)
		Array[Array[File]] assembly_lowQ_beds = flatten(assemble_genome.assembly_lowQ_beds)
		Array[Array[File]] zipped_assembly_fastas = flatten(assemble_genome.zipped_assembly_fastas)
		Array[Array[File]] assembly_stats = flatten(assemble_genome.assembly_stats)

		Array[Array[IndexData]] merged_bams = flatten(assemble_genome.merged_bams)
		Array[Array[IndexData]] paftools_vcfs = flatten(paftools_vcf)
		Array[Array[File]] paftools_vcf_stats = flatten(bcftools_stats.stats)

	}

	parameter_meta {
		cohort: {help: "Sample information for the cohort"}
		references: {help: "Array of Reference genomes data"}
		default_runtime_attributes: {help: "Default RuntimeAttributes; spot if preemptible was set to true, otherwise on_demand"}
		on_demand_runtime_attributes: {help: "RuntimeAttributes for tasks that require dedicated instances"}
	}
}

task parse_families {
	input {
		File cohort_json

		RuntimeAttributes runtime_attributes
	}

	command <<<
		set -euo pipefail

		parse_cohort.py --version

		parse_cohort.py \
			--cohort_json ~{cohort_json} \
			--parse_families
	>>>

	output {
		File families_json = "families.json"
	}

	runtime {
		docker: "~{runtime_attributes.container_registry}/parse-cohort@sha256:e6a8ac24ada706644e62878178790a0006db9a6abec7a312232052bb0666fe8f"
		cpu: 2
		memory: "4 GB"
		disk: "20 GB"
		disks: "local-disk " + "20" + " HDD"
		preemptible: runtime_attributes.preemptible_tries
		maxRetries: runtime_attributes.max_retries
		awsBatchRetryAttempts: runtime_attributes.max_retries
		queueArn: runtime_attributes.queue_arn
		zones: runtime_attributes.zones
	}
}