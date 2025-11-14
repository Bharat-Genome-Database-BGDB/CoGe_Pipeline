#!/bin/bash

# Prompt for accession list and output folder
echo "Enter the path to accession list (e.g. accessions.txt):"
read acc_file

echo "Enter the main output folder path:"
read main_outdir

# Create main output directory if it doesn't exist
mkdir -p "$main_outdir"

# Loop through each accession in the file
while read acc; do
  # Skip empty lines
  [[ -z "$acc" ]] && continue

  echo "==============================================="
  echo "Starting pipeline for accession: $acc"
  echo "==============================================="

  outdir="$main_outdir/$acc"
  mkdir -p "$outdir/fasterqdump_results" "$outdir/fastqc_result" \
           "$outdir/fastp_results" "$outdir/spades_result" \
           "$outdir/quast_result" "$outdir/prokka_result" "$outdir/diamond_results"

  echo "---------------------------------------------"
  echo "Running fasterq-dump for accession: $acc"
  echo "---------------------------------------------"

  /home/tmp_data/ngs/sra/bin/fasterq-dump "$acc" -O "$outdir/fasterqdump_results" || { echo "fasterq-dump failed for $acc"; continue; }

  echo "---------------------------------------------"
  echo "Running FastQC..."
  echo "---------------------------------------------"

  /home/tmp_data/ngs/FastQC/fastqc "$outdir/fasterqdump_results/${acc}_1.fastq" "$outdir/fasterqdump_results/${acc}_2.fastq" -o "$outdir/fastqc_result"
  echo "---------------------------------------------"
  echo "Running fastp..."
  echo "---------------------------------------------"

  /home/tmp_data/ngs/fastp \
    -i "$outdir/fasterqdump_results/${acc}_1.fastq" \
    -I "$outdir/fasterqdump_results/${acc}_2.fastq" \
    -o "$outdir/fastp_results/clean_1.fastq" \
    -O "$outdir/fastp_results/clean_2.fastq" \
    -h "$outdir/fastp_results/fastp_report.html" \
    -j "$outdir/fastp_results/fastp_report.json" \
    --thread 12 || { echo "fastp failed for $acc"; continue; }

  /home/tmp_data/ngs/FastQC/fastqc "$outdir/fastp_results/clean_1.fastq" "$outdir/fastp_results/clean_2.fastq" -o "$outdir/fastqc_result"

  echo "---------------------------------------------"
  echo "Running SPAdes..."
  echo "---------------------------------------------"

  /home/tmp_data/ngs/SPAdes-4.2.0-Linux/bin/spades.py \
    -1 "$outdir/fastp_results/clean_1.fastq" \
    -2 "$outdir/fastp_results/clean_2.fastq" \
    -o "$outdir/spades_result" \
    --threads 12 \
    --memory 12 \
    --careful || { echo "SPAdes failed for $acc"; continue; }

  echo "---------------------------------------------"
  echo "Running QUAST..."
  echo "---------------------------------------------"

  /home/tmp_data/ngs/quast/quast.py \
    "$outdir/spades_result/contigs.fasta" \
    -o "$outdir/quast_result" \
    -t 12 || { echo "QUAST failed for $acc"; continue; }

  echo "---------------------------------------------"
  echo "Running Prokka..."
  echo "---------------------------------------------"

  prokka \
    "$outdir/spades_result/contigs.fasta" \
    --outdir "$outdir/prokka_result" --force \
    --prefix prokka_annotated || { echo "Prokka failed for $acc"; continue; }

  echo "---------------------------------------------"
  echo "Running DIAMOND BLASTp..."
  echo "---------------------------------------------"

  /home/tmp_data/ngs/diamond blastp \
    -d "/home/tmp_data/group4/uniprot_sprot" \
    -q "$outdir/prokka_result/prokka_annotated.faa" \
    -o "$outdir/diamond_results/diamond_results.csv" \
    --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore stitle \
    --max-target-seqs 1 \
    --evalue 1e-5 \
    --threads 12 || { echo "DIAMOND failed for $acc"; continue; }

  echo "Pipeline completed successfully for: $acc"
  echo "Results stored in: $outdir"
  echo "---------------------------------------------"

done < "$acc_file"

echo "All genomes processed successfully!"
