#!/bin/bash

#SBATCH --cpus-per-task=128
#SBATCH --mem=128G
#SBATCH --job-name=QIIIME2


QIIME_VERSION=2022.8
SILVA_VERSION=silva-138-99-nb-classifier.qza

export qiime="singularity run -B$PWD:$PWD -W$PWD /data/common/tools/qiime/qiime2-core_$QIIME_VERSION.sif qiime"
#export Rscript="singularity run -B$PWD:$PWD -W$PWD ../../pipelines/container-images/r-rmarkdown_4.0.1.sif Rscript"

# QIIME2 ANALYSIS FOR ILLUMINA 16S PROTOCOL

# Custom parameters used for this analysis

# Trim sequence lengths. Note: reads are trimmed based on length after the primers have
# already been removed (~20 bp have already been removed from the start of the reads).
TRIM_FORWARD=250
TRIM_REVERSE=190

ASV_MIN_READS_SUBSAMPLING=1000

# use the following $qiime version: 
# ../../pipelines/container-images/qiime2-core_2022.8.sif
#singularity run -B$PWD:$PWD -W$PWD ../../pipelines/container-images/qiime2-core_2022.8.sif

$qiime tools import \
    --type 'SampleData[PairedEndSequencesWithQuality]' \
    --input-path 16s_paper_analysis__fastman.csv \
    --input-format PairedEndFastqManifestPhred33 \
    --output-path 1-paired-end-demux.qza

$qiime demux summarize \
    --i-data 1-paired-end-demux.qza \
    --o-visualization 1-paired-end-demux-qc.qzv

$qiime tools extract \
        --input-path 1-paired-end-demux-qc.qzv \
        --output-path 1-paired-end-demux-qc/

# Locus-specific primer sequences: See Illumina protocol
# 16S Metagenomic Sequencing Library Preparation
# Part # 15044223 Rev. B
$qiime cutadapt trim-paired \
    --p-front-f "^CCTACGGGNGGCWGCAG" \
    --p-front-r "^GACTACHVGGGTATCTAATCC" \
    --p-discard-untrimmed \
    --i-demultiplexed-sequences 1-paired-end-demux.qza \
    --o-trimmed-sequences 2-paired-end-demux-trimmed.qza


$qiime demux summarize \
    --i-data 2-paired-end-demux-trimmed.qza \
    --o-visualization 2-paired-end-demux-trimmed-qc.qzv

$qiime tools extract \
        --input-path 2-paired-end-demux-trimmed-qc.qzv \
        --output-path 2-paired-end-demux-trimmed-qc/



# R1: Trim a few bases from the end. Original length is 284 after trimming. The last
# nucleotide has an uncertain quality score and should be trimmed.
# R2: The quality is very bad towards the end, and we remove the worst part, still
# keeping a lot of data with bad quality.

    #--p-trunc-len-f 283 \
    #--p-trunc-len-r 260 \
$qiime dada2 denoise-paired \
    --p-n-threads 128 \
    --p-trunc-len-f $TRIM_FORWARD \
    --p-trunc-len-r $TRIM_REVERSE \
    --i-demultiplexed-seqs 2-paired-end-demux-trimmed.qza \
    --o-representative-sequences 3-representative-sequences.qza \
    --o-table 3-table.qza \
    --o-denoising-stats 3-denoising-stats.qza

# Produce QC outputs for DADA2 - three QC reports + three extract commands
$qiime metadata tabulate \
    --m-input-file 3-denoising-stats.qza \
    --o-visualization 3-denoising-stats.qzv
$qiime tools extract \
    --input-path 3-denoising-stats.qzv \
    --output-path 3-denoising-stats/

$qiime feature-table summarize \
    --i-table 3-table.qza \
    --m-sample-metadata-file 16s_paper_analysis__sample-metadata.tsv \
    --o-visualization 3-table.qzv
$qiime tools extract \
    --input-path 3-table.qzv \
    --output-path 3-table/

$qiime feature-table tabulate-seqs \
    --i-data 3-representative-sequences.qza \
    --o-visualization 3-representative-sequences-lengths.qzv
$qiime tools extract \
    --input-path 3-representative-sequences-lengths.qzv \
    --output-path 3-representative-sequences-lengths/



# Feature classifier: Assign taxonomic information
$qiime feature-classifier classify-sklearn --p-n-jobs 128 \
    --i-classifier $SILVA_VERSION \
    --i-reads 3-representative-sequences.qza \
    --o-classification 4-taxonomy.qza


# Produce barplot
$qiime taxa barplot \
    --i-table 3-table.qza \
    --i-taxonomy 4-taxonomy.qza \
    --m-metadata-file 16s_paper_analysis__sample-metadata.tsv \
    --o-visualization 5-taxa-barplot.qzv
$qiime tools extract \
    --input-path 5-taxa-barplot.qzv \
    --output-path 5-taxa-barplot/


# Make a phylogenetic tree
$qiime phylogeny align-to-tree-mafft-fasttree \
    --p-n-threads 128 \
    --i-sequences 3-representative-sequences.qza \
    --o-alignment 6-aligned-seqs.qza \
    --o-masked-alignment 6-masked-aligned-seqs.qza \
    --o-tree 6-unrooted-tree.qza \
    --o-rooted-tree 6-rooted-tree.qza

# Produce diversity metrics based on this tree
$qiime diversity core-metrics-phylogenetic \
     --p-sampling-depth $ASV_MIN_READS_SUBSAMPLING \
     --i-table 3-table.qza \
     --i-phylogeny 6-rooted-tree.qza \
     --m-metadata-file 16s_paper_analysis__sample-metadata.tsv \
     --output-dir 6-diversity-metrics



echo "$QIIME_VERSION" > qiime-version.txt
echo "$SILVA_VERSION" > silva-version.txt
