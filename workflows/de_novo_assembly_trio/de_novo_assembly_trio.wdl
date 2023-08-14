version 1.0

# Performs de novo assembly on a trio, using parental information and phasing to improve the assembly.
# This workflow will run if `Cohort.run_de_novo_assembly_trio` is set to `true`. The cohort must include at least one valid trio (child, father, and mother).

import "../assembly_structs.wdl"
import "../wdl-common/wdl/tasks/samtools_fasta.wdl" as SamtoolsFasta
import "../assemble_genome/assemble_genome.wdl" as AssembleGenome

workflow de_novo_assembly_trio {
	input {
		Cohort cohort

		ReferenceData reference

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

		call yak_count as yak_count_father {
			input:
				sample_id = father.sample_id,
				reads_fastas = samtools_fasta_father.reads_fasta,
				runtime_attributes = default_runtime_attributes
		}

		scatter (movie_bam in mother.movie_bams) {
			call SamtoolsFasta.samtools_fasta as samtools_fasta_mother {
				input:
					bam = movie_bam,
					runtime_attributes = default_runtime_attributes
			}
		}

		call yak_count as yak_count_mother {
			input:
				sample_id = mother.sample_id,
				reads_fastas = samtools_fasta_mother.reads_fasta,
				runtime_attributes = default_runtime_attributes
		}

		# Father is haplotype 1; mother is haplotype 2
		Map[String, String] haplotype_key_map = {
			"hap1": father.sample_id,
			"hap2": mother.sample_id
		}

		scatter (child_index in family.child_indices) {
			Sample child = cohort.samples[child_index]

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
					reference = reference,
					hifiasm_extra_params = "-c1 -d1",
					father_yak = yak_count_father.yak,
					mother_yak = yak_count_mother.yak,
					backend = backend,
					default_runtime_attributes = default_runtime_attributes,
					on_demand_runtime_attributes = on_demand_runtime_attributes
			}
		}
	}

	output {
		Array[Map[String, String]] haplotype_key = haplotype_key_map
		Array[Array[File]] assembly_noseq_gfas = flatten(assemble_genome.assembly_noseq_gfas)
		Array[Array[File]] assembly_lowQ_beds = flatten(assemble_genome.assembly_lowQ_beds)
		Array[Array[File]] zipped_assembly_fastas = flatten(assemble_genome.zipped_assembly_fastas)
		Array[Array[File]] assembly_stats = flatten(assemble_genome.assembly_stats)
		Array[IndexData] asm_bams = flatten(assemble_genome.asm_bam)
	}

	parameter_meta {
		cohort: {help: "Sample information for the cohort"}
		reference: {help: "Reference genome data"}
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

		parse_cohort.py \
			--cohort_json ~{cohort_json} \
			--parse_families
	>>>

	output {
		File families_json = "families.json"
	}

	runtime {
		docker: "~{runtime_attributes.container_registry}/parse-cohort@sha256:94444e7e3fd151936c9bbcb8a64b6a5e7d8c59de53b256a83f15c4ea203977b4"
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

task yak_count {
	input {
		String sample_id
		Array[File] reads_fastas

		RuntimeAttributes runtime_attributes
	}

	Int threads = 10

	# Usage up to 140 GB @ 10 threads for Revio samples
	Int mem_gb = 16 * threads
	Int disk_size = ceil(size(reads_fastas, "GB") * 2 + 20)

	command <<<
		set -euo pipefail

		yak count \
			-t ~{threads} \
			-o ~{sample_id}.yak \
			~{sep=' ' reads_fastas}
	>>>

	output {
		File yak = "~{sample_id}.yak"
	}

	runtime {
		docker: "~{runtime_attributes.container_registry}/yak@sha256:45e344d9432cac713159c830a115f439c5daea3eeb732f107f608376f1ea2a6c"
		cpu: threads
		memory: mem_gb + " GB"
		disk: disk_size + " GB"
		disks: "local-disk " + disk_size + " HDD"
		preemptible: runtime_attributes.preemptible_tries
		maxRetries: runtime_attributes.max_retries
		awsBatchRetryAttempts: runtime_attributes.max_retries
		queueArn: runtime_attributes.queue_arn
		zones: runtime_attributes.zones
	}
}
