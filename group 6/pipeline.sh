#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -------------------------
# CONFIGURATION (edit as needed)
# -------------------------
DIAMOND_DB=DIAMOND_DB="/home/staicy/miniconda3/lib/python3.13/site-packages/app/_db/protein.db"
           # your Diamond database
TMHMM_BIN_DIR="$HOME/tmhmm-2.0c/bin"      # TMHMM executable
SIGNALP_VENV_BIN="$HOME/signalp6_fast/signalp-6-package/venv/bin" # SignalP binary folder
AMRFINDER_ENV="amrfinder_env"             # conda env for AMRFinder
PROKKA_BIN="/usr/bin/prokka"
THREADS=4
# -------------------------

# -------------------------
# INPUT FILE (required)
# -------------------------
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 path/to/genome.fastq[.gz]"
    exit 1
fi

INPUT_FILE="$1"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: file '$INPUT_FILE' not found!"
    exit 1
fi

# Genome name and directory
BASENAME="$(basename "$INPUT_FILE")"
GENOME="${BASENAME%%.*}"
GENOME_DIR="$(dirname "$INPUT_FILE")/$GENOME"

# Create genome folder and tool subfolders
mkdir -p "$GENOME_DIR"/{fastqc,fastp,multiqc,spades,quast,prokka,diamond,signalp,tmhmm,amrfinder}

echo "=== Processing genome: $GENOME ==="

# -------------------------
# 1) FastQC
# -------------------------
echo "Running FastQC..."
fastqc -o "$GENOME_DIR/fastqc" -t "$THREADS" "$INPUT_FILE"

# -------------------------
# 2) fastp (trimming)
# -------------------------
echo "Running fastp..."
TRIMMED="$GENOME_DIR/fastp/${GENOME}_trimmed.fastq"
fastp -i "$INPUT_FILE" -o "$TRIMMED" -h "$GENOME_DIR/fastp/${GENOME}_fastp.html" \
      -j "$GENOME_DIR/fastp/${GENOME}_fastp.json" -w "$THREADS"

# -------------------------
# 3) MultiQC
# -------------------------
echo "Running MultiQC..."
(cd "$GENOME_DIR" && multiqc -o multiqc . || true)

# -------------------------
# 4) SPAdes assembly
# -------------------------
echo "Running SPAdes..."
SPADES_OUT="$GENOME_DIR/spades"
spades.py -s "$TRIMMED" -o "$SPADES_OUT" --threads "$THREADS" --isolate
CONTIGS="$SPADES_OUT/contigs.fasta"
if [ ! -f "$CONTIGS" ]; then
    echo "SPAdes failed for $GENOME. Exiting."
    exit 1
fi

# -------------------------
# 5) QUAST
# -------------------------
echo "Running QUAST..."
quast.py "$CONTIGS" -o "$GENOME_DIR/quast" --threads "$THREADS" || true

# -------------------------
# 6) PROKKA
# -------------------------
echo "Running Prokka..."
PROKKA_OUT="$GENOME_DIR/prokka"
prokka --outdir "$PROKKA_OUT" --prefix "$GENOME" --cpus "$THREADS" --force "$CONTIGS"
PROKKA_FAA="$PROKKA_OUT/${GENOME}.faa"

# -------------------------
# 7) DIAMOND
# -------------------------
echo "Running DIAMOND..."
if [ -f "${DIAMOND_DB}.dmnd" ] || [ -f "$DIAMOND_DB" ]; then
    diamond blastp -d "$DIAMOND_DB" -q "$PROKKA_FAA" \
                   -o "$GENOME_DIR/diamond/${GENOME}_diamond.tsv" \
                   -f 6 qseqid sseqid pident length evalue bitscore stitle \
                   --threads "$THREADS"
else
    echo "DIAMOND DB not found. Skipping DIAMOND."
fi

# -------------------------
# 8) SignalP
# -------------------------
echo "Running SignalP..."
if [ -x "$SIGNALP_VENV_BIN/signalp6" ]; then
    "$SIGNALP_VENV_BIN/signalp6" -fasta "$PROKKA_FAA" \
                                 -format txt \
                                 -prefix "$GENOME_DIR/signalp/${GENOME}_signalp" || true
else
    echo "SignalP binary not found. Skipping."
fi

# -------------------------
# 9) TMHMM
# -------------------------
echo "Running TMHMM..."
if [ -x "$TMHMM_BIN_DIR/tmhmm" ]; then
    "$TMHMM_BIN_DIR/tmhmm" "$PROKKA_FAA" > "$GENOME_DIR/tmhmm/${GENOME}_tmhmm.txt" || true
else
    echo "TMHMM not found. Skipping."
fi

# -------------------------
# 10) AMRFinderPlus
# -------------------------
echo "Running AMRFinderPlus..."
if conda env list | grep -q "$AMRFINDER_ENV"; then
    source "$(conda info --base)/etc/profile.d/conda.sh"
    conda activate "$AMRFINDER_ENV"
    amrfinder -p "$PROKKA_FAA" -o "$GENOME_DIR/amrfinder/${GENOME}_amrfinder.tsv" \
              --organism "Staphylococcus_aureus" || true
    conda deactivate
else
    echo "AMRFinder env not found. Skipping."
fi

echo "=== Finished genome: $GENOME ==="
