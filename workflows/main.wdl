version 1.0

import "assembly_structs.wdl"
import "wdl-common/wdl/workflows/backend_configuration/backend_configuration.wdl" as BackendConfiguration
import "de_novo_assembly_sample/de_novo_assembly_sample.wdl" as DeNovoAssemblySample
import "de_novo_assembly_trio/de_novo_assembly_trio.wdl" as DeNovoAssemblyTrio


workflow de_novo_assembly {
	input {
		Cohort cohort

		ReferenceData reference

		# Backend configuration
		String backend
		String? zones
		String? aws_spot_queue_arn
		String? aws_on_demand_queue_arn
		String? container_registry

		Boolean preemptible
	}

	call BackendConfiguration.backend_configuration {
		input:
			backend = backend,
			zones = zones,
			aws_spot_queue_arn = aws_spot_queue_arn,
			aws_on_demand_queue_arn = aws_on_demand_queue_arn,
			container_registry = container_registry
	}

	RuntimeAttributes default_runtime_attributes = if preemptible then backend_configuration.spot_runtime_attributes else backend_configuration.on_demand_runtime_attributes

	scatter (sample in cohort.samples) {
		if (sample.run_de_novo_assembly) {
			call DeNovoAssemblySample.de_novo_assembly_sample {
				input:
					sample = sample,
					reference = reference,
					backend = backend,
					default_runtime_attributes = default_runtime_attributes,
					on_demand_runtime_attributes = backend_configuration.on_demand_runtime_attributes
			}
		}
	}

	if (length(cohort.samples) > 1) {
		if (cohort.run_de_novo_assembly_trio) {
			call DeNovoAssemblyTrio.de_novo_assembly_trio {
				input:
					cohort = cohort,
					reference = reference,
					backend = backend,
					default_runtime_attributes = default_runtime_attributes,
					on_demand_runtime_attributes = backend_configuration.on_demand_runtime_attributes
			}
		}
	}

	output {
		# de_novo_assembly_sample output
		Array[Array[File]?] assembly_noseq_gfas = de_novo_assembly_sample.assembly_noseq_gfas
		Array[Array[File]?] assembly_lowQ_beds = de_novo_assembly_sample.assembly_lowQ_beds
		Array[Array[File]?] zipped_assembly_fastas = de_novo_assembly_sample.zipped_assembly_fastas
		Array[Array[File]?] assembly_stats = de_novo_assembly_sample.assembly_stats
		Array[IndexData?] asm_bam = de_novo_assembly_sample.asm_bam
		Array[IndexData?] htsbox_vcf = de_novo_assembly_sample.htsbox_vcf
		Array[File?] htsbox_vcf_stats = de_novo_assembly_sample.htsbox_vcf_stats

		# de_novo_assembly_trio output
		Array[Map[String, String]]? haplotype_key = de_novo_assembly_trio.haplotype_key
		Array[Array[File]]? trio_assembly_noseq_gfas = de_novo_assembly_trio.assembly_noseq_gfas
		Array[Array[File]]? trio_assembly_lowQ_beds = de_novo_assembly_trio.assembly_lowQ_beds
		Array[Array[File]]? trio_zipped_assembly_fastas = de_novo_assembly_trio.zipped_assembly_fastas
		Array[Array[File]]? trio_assembly_stats = de_novo_assembly_trio.assembly_stats
		Array[IndexData]? trio_asm_bams = de_novo_assembly_trio.asm_bams
	}

	parameter_meta {
		cohort: {help: "Sample information for the cohort"}
		reference: {help: "Reference genome data"}
		backend: {help: "Backend where the workflow will be executed ['GCP', 'Azure', 'AWS']"}
		zones: {help: "Zones where compute will take place; required if backend is set to 'AWS' or 'GCP'"}
		aws_spot_queue_arn: {help: "Queue ARN for the spot batch queue; required if backend is set to 'AWS'"}
		aws_on_demand_queue_arn: {help: "Queue ARN for the on demand batch queue; required if backend is set to 'AWS'"}
		container_registry: {help: "Container registry where workflow images are hosted. If left blank, PacBio's public Quay.io registry will be used."}
		preemptible: {help: "Where possible, run tasks preemptibly"}
	}
}
