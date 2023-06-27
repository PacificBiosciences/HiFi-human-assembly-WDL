Either `miniwdl` or `Cromwell` can be used to run workflows on the HPC.

# Installing and configuring `miniwdl`

## Requirements

- [`miniwdl`](https://github.com/chanzuckerberg/miniwdl) >= 1.9.0
- [`miniwdl-slurm`](https://github.com/miniwdl-ext/miniwdl-slurm)

## Configuring

An [example miniwdl.cfg file](miniwdl.cfg) is provided here. This should be placed at `~/.config/miniwdl.cfg` and edited to match your slurm configuration. This allows running workflows using a basic SLURM setup.

# Installing and configuring `Cromwell`

Cromwell supports a number of different HPC backends; see [Cromwell's documentation](https://cromwell.readthedocs.io/en/stable/backends/HPC/) for more information on configuring each of the backends.

# Configuring and running the workflow

## Filling out workflow inputs

Fill out any information missing in [the inputs file](inputs.hpc.json). Once you have downloaded the reference data bundle, ensure that you have replaced the `<local_path_prefix>` in the input template file with the local path to the reference datasets on your HPC.

See [the inputs section of the main README](../../README.md#workflow-inputs) for more information on the structure of the inputs.json file.

## Running the workflow

### Running via miniwdl

`miniwdl run workflows/main.wdl -i <inputs_json_file>`

### Running via Cromwell

`cromwell run workflows/main.wdl -i <inputs_json_file>`

### Running via Workbench

1. [Register the engine in Workbench](https://docs.dnastack.com/docs/connecting-to-a-workflow-engine)
2. [Follow the instructions in the README to run the workflow via Workbench](../../README.md#run-using-workbench)

# Reference data bundle

![https://doi.org/10.5281/zenodo.7922357](https://zenodo.org/badge/DOI/10.5281/zenodo.7922357.svg)

Reference data is hosted on Zenodo at [10.5281/zenodo.7922357](https://zenodo.org/record/7922357).  Download the reference data bundle and extract it to a location on your HPC, then update the input template file with the path to the reference data.

```bash
# download the reference data bundle
wget https://zenodo.org/record/7922357/files/wdl-humanwgs.v1.0.0.resources.tgz

# extract the reference data bundle and rename as dataset
tar -xzf wdl-humanwgs.v1.0.0.resources.tgz && mv static_resources dataset
```
