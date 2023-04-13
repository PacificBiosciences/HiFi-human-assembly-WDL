version 1.0

import "wdl-common/wdl/structs.wdl"

struct ReferenceData {
	String name
	IndexData fasta
}

struct Sample {
	String sample_id
	Array[File] movie_bams

	String? sex

	String? father_id
	String? mother_id

	Boolean run_de_novo_assembly
}

struct Cohort {
	String cohort_id
	Array[Sample] samples

	Boolean run_de_novo_assembly_trio
}

struct FamilySampleIndices {
	Array[Int] child_indices
	Int father_index
	Int mother_index
}
