version 1.0

# Assemble a genome using hifiasm. Can be used for single-sample or trio-based assembly.

import "../assembly_structs.wdl"

workflow assemble_genome {
	input {
		String sample_id
		Array[File] reads_fastas

		Array[ReferenceData] references

		String? hifiasm_extra_params
		File? father_yak
		File? mother_yak

		RuntimeAttributes default_runtime_attributes
	}

	call hifiasm_assemble {
		input:
			sample_id = sample_id,
			reads_fastas = reads_fastas,
			extra_params = hifiasm_extra_params,
			father_yak = father_yak,
			mother_yak = mother_yak,
			runtime_attributes = default_runtime_attributes
	}

	scatter (gfa in hifiasm_assemble.assembly_hap_gfas) {
		call gfa2fa {
			input:
				gfa = gfa,
				runtime_attributes = default_runtime_attributes 
		}
	}


	scatter (ref in references) {
		scatter (hap in gfa2fa.zipped_fasta) {
			call align_hifiasm {
				input:
					sample_id = sample_id,
					query_sequences = hap,
					reference = ref.fasta.data,
					reference_name = ref.name,
					runtime_attributes = default_runtime_attributes
			}

			IndexData sample_aligned_bam = {
				"data": align_hifiasm.asm_bam,
				"data_index": align_hifiasm.asm_bam_index
			}

			Pair[ReferenceData,IndexData] align_data = (ref, sample_aligned_bam)
		}

		Array[File] bamlist = align_hifiasm.asm_bam

		call merge_haps {
			input:
				sample_id = sample_id,
				bams = bamlist,
				refname = ref.name,
				runtime_attributes = default_runtime_attributes
		}


	}
	output {
		Array[File] assembly_noseq_gfas = hifiasm_assemble.assembly_noseq_gfas
		Array[File] assembly_lowQ_beds = hifiasm_assemble.assembly_lowQ_beds
		Array[File] zipped_assembly_fastas = gfa2fa.zipped_fasta
		Array[File] assembly_stats = gfa2fa.assembly_stats
		Array[IndexData] asm_bams = flatten(sample_aligned_bam)
		Array[IndexData] merged_bams = merge_haps.merged_bam
		Array[Pair[ReferenceData,IndexData]] alignments = flatten(align_data)
	}

	parameter_meta {
		sample_id: {help: "Sample ID; used for naming files"}
		reads_fastas: {help: "Reads in fasta format to be used for assembly; one for each movie bam to be used in assembly. Reads fastas from one or more sample may be combined to use in the assembly"}
		references: {help: "Array of Reference genomes data"}
		hiiasm_extra_params: {help: "[OPTIONAL] Additional parameters to pass to hifiasm assembly"}
		father_yak: {help: "[OPTIONAL] kmer counts for the father; required if running trio-based assembly"}
		mother_yak: {help: "[OPTIONAL] kmer counts for the mother; required if running trio-based assembly"}
		default_runtime_attributes: {help: "Default RuntimeAttributes; spot if preemptible was set to true, otherwise on_demand"}
		on_demand_runtime_attributes: {help: "RuntimeAttributes for tasks that require dedicated instances"}
	}
}

# Note that this task will run ~25% faster on intel vs. AMD processors
task hifiasm_assemble {
	input {
		String sample_id
		Array[File] reads_fastas

		String? extra_params
		File? father_yak
		File? mother_yak

		RuntimeAttributes runtime_attributes
	}

	String prefix = "~{sample_id}.asm"
	Int threads = 48
	Int mem_gb = threads * 6
	Int disk_size = ceil(size(reads_fastas, "GB") * 4 + 20)

	command <<<
		set -euo pipefail

		echo "hifiasm version: $(hifiasm --version)"

		hifiasm \
			-o ~{prefix} \
			-t ~{threads} \
			~{extra_params} \
			~{"-1 " + father_yak} \
			~{"-2 " + mother_yak} \
			~{sep=' ' reads_fastas}
	>>>

	output {
		Array[File] assembly_hap_gfas = glob("~{prefix}.*.hap[12].p_ctg.gfa")
		Array[File] assembly_noseq_gfas = flatten([
			glob("~{prefix}.*.hap[12].p_ctg.noseq.gfa"),
			glob("~{prefix}.dip.[pr]_utg.noseq.gfa")
		])
		Array[File] assembly_lowQ_beds = flatten([
			glob("~{prefix}.*.hap[12].p_ctg.lowQ.bed"),
			glob("~{prefix}.dip.[pr]_utg.lowQ.bed")
		])
	}

	runtime {
		docker: "~{runtime_attributes.container_registry}/hifiasm@sha256:434c2aa706fd67fa0f2f5b7c6c16eb897c736a5a17a7aae9a3501a2ee06dd405"
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

task gfa2fa {
	input {
		File gfa

		RuntimeAttributes runtime_attributes
	}

	String gfa_basename = basename(gfa, ".gfa")
	Int disk_size = ceil(size(gfa, "GB") * 3 + 20)
	Int threads = 2

	command <<<
		set -euo pipefail

		echo "gfatools version: $(gfatools version)"

		gfatools gfa2fa \
			~{gfa} \
		> ~{gfa_basename}.fasta

		bgzip --version

		bgzip \
			--threads ~{threads} \
			--stdout \
			~{gfa_basename}.fasta \
		> ~{gfa_basename}.fasta.gz

		echo "calN50.js version: $(k8 /opt/calN50/calN50.js -v)"

		# Calculate assembly stats
		k8 \
			/opt/calN50/calN50.js \
			-L3.1g \
			~{gfa_basename}.fasta.gz \
		> ~{gfa_basename}.fasta.stats.txt
	>>>



	output {
		File zipped_fasta = "~{gfa_basename}.fasta.gz"
		File assembly_stats = "~{gfa_basename}.fasta.stats.txt"
	}

	runtime {
		docker: "~{runtime_attributes.container_registry}/gfatools@sha256:5b68ed45a3dfce62936db039d2fe775866a5de9ed9e2e590d6af38c2ebcffd92"
		cpu: threads
		memory: "4 GB"
		disk: disk_size + " GB"
		disks: "local-disk " + disk_size + " HDD"
		preemptible: runtime_attributes.preemptible_tries
		maxRetries: runtime_attributes.max_retries
		awsBatchRetryAttempts: runtime_attributes.max_retries
		queueArn: runtime_attributes.queue_arn
		zones: runtime_attributes.zones
	}
}

task align_hifiasm {
	input {
		String sample_id
		File query_sequences

		File reference
		String reference_name

		RuntimeAttributes runtime_attributes
	}

	Int threads = 16
	Int mem_gb = threads * 8
	Int disk_size = ceil((size(query_sequences, "GB") + size(reference, "GB")) * 2 + 20)

	command <<<


		echo "minimap2 version: $(minimap2 --version)"
		haplotype=$(basename ~{query_sequences} | sed -n 's/.*\(hap.\).*/\1/p')
		echo "$haplotype" > hap.txt

		samtools --version

		minimap2 \
			-t ~{threads - 4} \
			-L \
			--secondary=no \
			--eqx \
			--cs \
			-a \
			-x asm5 \
			-R "@RG\\tID:~{sample_id}_hifiasm\\tSM:~{sample_id}" \
			~{reference} \
			~{query_sequences} \
		| samtools sort \
			-@ 3 \
			-T ./TMP \
			-m 8G \
			-O BAM \
			-o "~{sample_id}.$haplotype.asm.~{reference_name}.bam"

		samtools index "~{sample_id}.$haplotype.asm.~{reference_name}.bam"
	>>>

	output {
		File asm_bam = glob("*.bam")[0]
		File asm_bam_index = glob("*.bam.bai")[0]
	}

	runtime {
		docker: "~{runtime_attributes.container_registry}/align_hifiasm@sha256:0e8ad680b0e89376eb94fa8daa1a0269a4abe695ba39523a5c56a59d5c0e3953"
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

task merge_haps {
	input {
		Array[File] bams
		String sample_id
		String refname
		
		RuntimeAttributes runtime_attributes
	}

	Int threads = 3
	Int disk_size = 20
	Int mem_gb = threads * 8
	
	command <<<

		samtools merge \
			-@3 \
			-o ~{sample_id}.asm.~{refname}.bam \
			~{sep=' ' bams} 

		samtools index ~{sample_id}.asm.~{refname}.bam


	>>>

	output {
		IndexData merged_bam = {"data": "~{sample_id}.asm.~{refname}.bam",
								"data_index": "~{sample_id}.asm.~{refname}.bam.bai"}
	}

	runtime {
		docker: "~{runtime_attributes.container_registry}/align_hifiasm@sha256:0e8ad680b0e89376eb94fa8daa1a0269a4abe695ba39523a5c56a59d5c0e3953"
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

task paftools {
	input {
		File bam
		File bam_index

		File reference

		String sample

		RuntimeAttributes runtime_attributes
	}

	String bam_basename = basename(bam, ".bam")
	Int threads = 2
	Int disk_size = ceil((size(bam, "GB") + size(reference, "GB")) * 3 + 20)
	Int mem_gb = threads * 8

	command <<<
		set -euo pipefail

		k8 /opt/minimap2-2.17/misc/paftools.js version

		samtools view -h ~{bam} | \
		k8 /opt/minimap2-2.17/misc/paftools.js sam2paf - | \
		sort -k6,6 -k8,8n | \
		k8 /opt/minimap2-2.17/misc/paftools.js call \
			-L5000 \
			-f ~{reference} \
			-s ~{sample} \
			- \
			> ~{bam_basename}.paftools.vcf

	>>>

	output {
		File paftools_vcf = "~{bam_basename}.paftools.vcf"
	}

	runtime {
		docker: "~{runtime_attributes.container_registry}/align_hifiasm@sha256:0e8ad680b0e89376eb94fa8daa1a0269a4abe695ba39523a5c56a59d5c0e3953"
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
