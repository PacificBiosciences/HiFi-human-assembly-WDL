# wdl-humanassembly

Workflow for running de novo assembly using human PacBio whole genome sequencing (WGS) data. Written using [Workflow Description Language (WDL)](https://openwdl.org/).

- Docker images used by these workflows are defined [here](https://github.com/PacificBiosciences/wdl-dockerfiles).

- Common tasks that may be reused within or between workflows are defined [here](https://github.com/PacificBiosciences/wdl-common).

# Workflow

The assembly workflow performs _de novo_ assembly on samples and trios.

**Workflow entrypoint**: [workflows/main.wdl](workflows/main.wdl)

- [Blank input template file](workflows/inputs.json)
- [Azure-based inputs](workflows/inputs.azure.json)
- [AWS-based inputs](workflows/inputs.aws.json)
- [GCP-based inputs]((workflows/inputs.gcp.json))

![De novo assembly workflow diagram](workflows/main.graphviz.svg "De novo assembly workflow diagram")

# Reference datasets and associated workflow files

Reference datasets are hosted publicly for use in the pipeline. For data locations, see `workflows/inputs.${backend}.json`.

## Reference data hosted in Azure

To use Azure reference data, add the following line to your `containers-to-mount` file in your Cromwell on Azure installation ([more info here](https://github.com/microsoft/CromwellOnAzure/blob/develop/docs/troubleshooting-guide.md#use-input-data-files-from-an-existing-azure-storage-account-that-my-lab-or-team-is-currently-using)):

`https://datasetpbrarediseases.blob.core.windows.net/dataset?si=public&spr=https&sv=2021-06-08&sr=c&sig=o6OkcqWWlGcGOOr8I8gCA%2BJwlpA%2FYsRz0DMB8CCtCJk%3D`

The [Azure input file template](workflows/inputs.azure.json) has paths to the reference files in this blob storage prefilled.

## Reference data hosted in AWS

AWS reference data is hosted in the `us-west-2` region  in the bucket `s3://dnastack-resources`.

To use AWS reference data, add the following line to the data section of your [`agc-project.yaml`](https://aws.github.io/amazon-genomics-cli/docs/concepts/projects/):

```yaml
data:
  - location: s3://dnastack-resources
    readOnly: true
```

The [AWS input file template](workflows/inputs.aws.json) has paths to the reference files in the blob storage prefilled.

## Reference data hosted in GCP

<TODO>

# Workflow inputs

## [Cohort](workflows/humanwgs_structs.wdl)

A cohort can include one or more samples. Samples need not be related.

| Type | Name | Description | Notes |
| :- | :- | :- | :- |
| String | cohort_id | A unique name for the cohort; used to name outputs | |
| Array[[Sample](#sample)] | samples | The set of samples for the cohort. At least one sample must be defined. | |
| Boolean | run_de_novo_assembly_trio | Run trio binned _de novo_ assembly. | Cohort must contain at least one valid trio (child and both parents present in the cohort) |

### [Sample](workflows/humanwgs_structs.wdl)

Sample information for each sample in the workflow run.

| Type | Name | Description | Notes |
| :- | :- | :- | :- |
| String | sample_id | A unique name for the sample; used to name outputs | |
| Array[[IndexData](https://github.com/PacificBiosciences/wdl-common/blob/main/wdl/structs.wdl)] | movie_bams | The set of unaligned movie BAMs associated with this sample | |
| String? | sex | Sample sex | ["MALE", "FEMALE", "."]. "." or `null` will set sex to unknown. |
| String? | father_id | Paternal `sample_id` | |
| String? | mother_id | Maternal `sample_id` | |
| Boolean | run_de_novo_assembly | If true, run single-sample _de novo_ assembly for this sample | \[true, false\] |

## [ReferenceData](workflows/humanwgs_structs.wdl)

Files associated with the reference genome.

These files are hosted publicly in each of the cloud backends; see `workflows/inputs.${backend}.json`.

| Type | Name | Description | Notes |
| :- | :- | :- | :- |
| String | name | Reference name; used to name outputs (e.g., "GRCh38") | |
| [IndexData](https://github.com/PacificBiosciences/wdl-common/blob/main/wdl/structs.wdl) | fasta | Reference genome and index | |

## Other inputs

| Type | Name | Description | Notes |
| :- | :- | :- | :- |
| String | backend | Backend where the workflow will be executed | \["Azure", "AWS", "GCP"\] |
| String? | zones | Zones where compute will take place; required if backend is set to 'AWS' or 'GCP'. | [Determining available zones in AWS and GCP](#determining-available-zones-in-aws-and-gcp). |
| String? | aws_spot_queue_arn | Queue ARN for the spot batch queue; required if backend is set to 'AWS' and `preemptible` is set to `true` | [Determining the AWS queue ARN](#determining-the-aws-batch-queue-arn) |
| String? | aws_on_demand_queue_arn | Queue ARN for the on demand batch queue; required if backend is set to 'AWS' and `preemptible` is set to `false` | [Determining the AWS queue ARN](#determining-the-aws-batch-queue-arn) |
| Boolean | preemptible | If set to `true`, run tasks preemptibly where possible. On-demand VMs will be used only for tasks that run for >24 hours if the backend is set to GCP. If set to `false`, on-demand VMs will be used for every task. | \[true, false\] |

### Determining available zones in AWS and GCP

#### AWS

To determine available zones in AWS, look for the ZoneName attributes output by the following command:

```bash
aws ec2 describe-availability-zones --region <region>
```
For example, the zones in region us-east-2 are `"us-east-2a us-east-2b us-east-2c"`.

#### GCP

To determine available zones in GCP, run the following; available zones within a region can be found in the first column of the output:

```bash
gcloud compute zones list | grep <region>
```

For example, the zones in region us-central1 are `"us-central1-a us-central1-b us-central1c us-central1f"`.

### Determining the AWS batch queue ARN

**Note that if you are using a `miniwdl` engine, you can skip these steps; workflows run via miniwdl will run exclusively in the job queue to which they are submitted.**

1. Visit [the AWS console](https://console.aws.amazon.com/).
2. Navigate to the Batch service.
3. In the lefthand sidebar, select "Compute environments". Note the name of the compute environment with the provisioning model SPOT (if you have deployed a context using spot instances) and the name of the compute environment with provisioning model "EC2" (if you have deployed a context that does not use spot instances).
4. In the lefthand sidebar, select "Job queues".
5. Clicking into an individual queue will show information about the compute environment ("Compute environment order"). Identify the job queue with the Compute environment name that matches the name you identified for the SPOT compute environment; copy the Amazon Resource Name (ARN) for this job queue. This is the value that should be used for the `aws_spot_queue_arn`. Repeat this process to find the ARN for the `aws_on_demand_queue_arn`.

- If `preemptible = true`, only the `aws_spot_queue_arn` is required.
- If `preemptible = false`, only the `aws_on_demand_queue_arn` is required.

# Workflow outputs

## De novo assembly - sample

These files will be output if `cohort.samples[sample]` is set to `true` for any sample.

| Type | Name | Description | Notes |
| :- | :- | :- | :- |
| Array[Array[File]?] | zipped_assembly_fastas | [_De novo_ dual assembly](http://lh3.github.io/2021/10/10/introducing-dual-assembly) generated by [hifiasm](https://github.com/chhylp123/hifiasm) | |
| Array[Array[File]?] | assembly_noseq_gfas | Assembly graphs in [GFA format](https://github.com/chhylp123/hifiasm/blob/master/docs/source/interpreting-output.rst). | |
| Array[Array[File]?] | assembly_lowQ_beds | Coordinates of low quality regions in BED format. | |
| Array[Array[File]?] | assembly_stats | Assembly size and NG50 stats generated by [calN50](https://github.com/lh3/calN50). | |
| Array[[IndexData](https://github.com/PacificBiosciences/wdl-common/blob/main/wdl/structs.wdl)?] | asm_bam | [minimap2](https://github.com/lh3/minimap2) alignment of assembly to reference. | |
| Array[[IndexData](https://github.com/PacificBiosciences/wdl-common/blob/main/wdl/structs.wdl)?] | htsbox_vcf | Naive pileup variant calling of assembly against reference with [`htsbox`](https://github.com/lh3/htsbox) | |
| Array[File?] | htsbox_vcf_stats | [`bcftools stats`](https://samtools.github.io/bcftools/bcftools.html#stats) summary statistics for `htsbox` variant calls | |

## De novo assembly - trio

These files will be output if `cohort.de_novo_assembly_trio` is set to `true` and there is at least one parent-parent-kid trio in the cohort.

| Type | Name | Description | Notes |
| :- | :- | :- | :- |
| Array[Array[File]]? | trio_zipped_assembly_fastas | [Haplotype-resolved _de novo_ assembly](http://lh3.github.io/2021/10/10/introducing-dual-assembly) of the trio kid generated by [hifiasm](https://github.com/chhylp123/hifiasm) with [trio binning](https://github.com/chhylp123/hifiasm#trio-binning) | |
| Array[Array[File]]? | trio_assembly_noseq_gfas | Assembly graphs in [GFA format](https://github.com/chhylp123/hifiasm/blob/master/docs/source/interpreting-output.rst). | |
| Array[Array[File]]? | trio_assembly_lowQ_beds | Coordinates of low quality regions in BED format. | |
| Array[Array[File]]? | trio_assembly_stats | Assembly size and NG50 stats generated by [calN50](https://github.com/lh3/calN50). | |
| Array[[IndexData](https://github.com/PacificBiosciences/wdl-common/blob/main/wdl/structs.wdl)]? | trio_asm_bams | [minimap2](https://github.com/lh3/minimap2) alignment of assembly to reference. | |
| Array[Map[String, String]]? | haplotype_key | Indication of which haplotype (`hap1`/`hap2`) corresponds to which parent. | |

# Tool versions and Docker images

Docker images definitions used by the human WGS workflow can be found in [the wdl-dockerfiles repository](https://github.com/PacificBiosciences/wdl-dockerfiles/tree/987efde4d614a292fbfe9f3cf146b63005ad6a8a). Images are hosted in PacBio's [quay.io](https://quay.io/organization/pacbio). Docker images used in the workflow are pegged to specific versions by referring to their digests rather than tags.

The Docker image used by a particular step of the workflow can be identified by looking at the `docker` key in the `runtime` block for the given task. Images can be referenced in the following table by looking for the name after the final `/` character and before the `@sha256:...`. For example, the image referred to here is "align_hifiasm":
> ~{runtime_attributes.container_registry}/**align_hifiasm**@sha256:3968cb<...>b01f80fe

| Image | Major tool versions | Links |
| :- | :- | :- |
| align_hifiasm | <ul><li>[minimap2 2.17](https://github.com/lh3/minimap2/releases/tag/v2.17)</li><li>[samtools 1.14](https://github.com/samtools/samtools/releases/tag/1.14)</li></ul> | [Dockerfile](https://github.com/PacificBiosciences/wdl-dockerfiles/tree/987efde4d614a292fbfe9f3cf146b63005ad6a8a/docker/align_hifiasm) |
| bcftools | <ul><li>[bcftools 1.14](https://github.com/samtools/bcftools/releases/tag/1.14)</li></ul> | [Dockerfile](https://github.com/PacificBiosciences/wdl-dockerfiles/tree/987efde4d614a292fbfe9f3cf146b63005ad6a8a/docker/bcftools) |
| gfatools | <ul><li>[gfatools 0.4](https://github.com/lh3/gfatools/releases/tag/v0.4)</li><li>[htslib 1.14](https://github.com/samtools/htslib/releases/tag/1.14)</li><li>[k8 0.2.5](https://github.com/attractivechaos/k8/releases/tag/0.2.5)</li><li>[caln50 01091f2](https://github.com/lh3/calN50/tree/01091f25bc24e17fbf0da3407ea24aa448c489ae)</li></ul> | [Dockerfile](https://github.com/PacificBiosciences/wdl-dockerfiles/tree/987efde4d614a292fbfe9f3cf146b63005ad6a8a/docker/gfatools) |
| hifiasm | <ul><li>[hifiasm 0.19.4](https://github.com/chhylp123/hifiasm/releases/tag/0.19.4)</li></ul> | [Dockerfile](https://github.com/PacificBiosciences/wdl-dockerfiles/tree/987efde4d614a292fbfe9f3cf146b63005ad6a8a/docker/hifiasm) |
| htsbox | <ul><li>[htsbox r346 (6964440)](https://github.com/lh3/htsbox/tree/6964440d791a60a22ca5ff25dc413a362bdc0abe)</li></ul> | [Dockerfile](https://github.com/PacificBiosciences/wdl-dockerfiles/tree/987efde4d614a292fbfe9f3cf146b63005ad6a8a/docker/htsbox) |
| htslib | <ul><li>[htslib 1.14](https://github.com/samtools/htslib/releases/tag/1.14)</li></ul> | [Dockerfile](https://github.com/PacificBiosciences/wdl-dockerfiles/tree/987efde4d614a292fbfe9f3cf146b63005ad6a8a/docker/htslib) |
| parse-cohort | <ul><li>python 3.8.10; custom scripts</li></ul> | [Dockerfile](https://github.com/PacificBiosciences/wdl-dockerfiles/tree/987efde4d614a292fbfe9f3cf146b63005ad6a8a/docker/parse-cohort) |
| samtools | <ul><li>[samtools 1.14](https://github.com/samtools/samtools/releases/tag/1.14)</li></ul> | [Dockerfile](https://github.com/PacificBiosciences/wdl-dockerfiles/tree/987efde4d614a292fbfe9f3cf146b63005ad6a8a/docker/samtools) |
| yak | <ul><li>[yak 0.1](https://github.com/lh3/yak/releases/tag/v0.1)</li></ul> | [Dockerfile](https://github.com/PacificBiosciences/wdl-dockerfiles/tree/987efde4d614a292fbfe9f3cf146b63005ad6a8a/docker/yak) |
