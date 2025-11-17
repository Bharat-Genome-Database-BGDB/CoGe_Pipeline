#!/usr/bin/env bash
set -euo pipefail

############################################
#     GENOME PIPELINE (SEQUENTIAL VERSION)
#     Requires conda env: genome-pipeline
############################################

ENV_NAME="genome-pipeline"
THREADS=6
MAIN_DIR="results"

echo "====================================="
echo "     GENOME PIPELINE"
echo "====================================="

# ------------------------------------------------------
# 1. Load conda and activate environment
# ------------------------------------------------------
if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
elif [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
    source "$HOME/anaconda3/etc/profile.d/conda.sh"
else
    echo "❌ ERROR: conda.sh not found!"
    exit 1
fi

conda activate "$ENV_NAME" || {
    echo "❌ ERROR: Unable to activate conda env '$ENV_NAME'"
    exit 1
}

echo "✔ Activated conda environment: $ENV_NAME"
echo

mkdir -p "$MAIN_DIR/logs"

# ------------------------------------------------------
# 2. Detect FASTQ files
# ------------------------------------------------------
shopt -s nullglob
R1_FILES=( *_R1*.fastq.gz *_1*.fastq.gz )
shopt -u nullglob

if [[ ${#R1_FILES[@]} -eq 0 ]]; then
    echo "❌ No paired-end FASTQ files found."
    exit 1
fi

# ------------------------------------------------------
# 3. Loop through samples
# ------------------------------------------------------
for R1 in "${R1_FILES[@]}"; do

    if [[ "$R1" == *_R1* ]]; then
        R2="${R1/_R1/_R2}"
        SAMPLE=$(basename "$R1" | sed 's/_R1.*//')
    else
        R2="${R1/_1/_2}"
        SAMPLE=$(basename "$R1" | sed 's/_1.*//')
    fi

    if [[ ! -f "$R2" ]]; then
        echo "⚠️  Skipping sample ${SAMPLE} — missing $R2"
        continue
    fi

    echo "====================================="
    echo "      PROCESSING SAMPLE: $SAMPLE"
    echo "====================================="

    SAMPLE_DIR="${MAIN_DIR}/${SAMPLE}"
    mkdir -p "${SAMPLE_DIR}/fastqc_raw" \
             "${SAMPLE_DIR}/fastp_output" \
             "${SAMPLE_DIR}/fastqc_trimmed" \
             "${SAMPLE_DIR}/spades_output" \
             "${SAMPLE_DIR}/quast_output" \
             "${SAMPLE_DIR}/prokka_output" \
             "${SAMPLE_DIR}/antismash_output"

    LOG_DIR="${MAIN_DIR}/logs"

    # ------------------------------------------------------
    # FastQC Raw
    # ------------------------------------------------------
    echo "[1/7] FastQC (raw)"
    fastqc "$R1" "$R2" \
        -o "${SAMPLE_DIR}/fastqc_raw" \
        2>&1 | tee "${LOG_DIR}/${SAMPLE}_fastqc_raw.log"

    # ------------------------------------------------------
    # fastp Trimming
    # ------------------------------------------------------
    echo "[2/7] fastp trimming"
    fastp \
        -i "$R1" -I "$R2" \
        -o "${SAMPLE_DIR}/fastp_output/${SAMPLE}_R1_trimmed.fastq.gz" \
        -O "${SAMPLE_DIR}/fastp_output/${SAMPLE}_R2_trimmed.fastq.gz" \
        -h "${SAMPLE_DIR}/fastp_output/fastp_report.html" \
        -j "${SAMPLE_DIR}/fastp_output/fastp_report.json" \
        -q 20 -u 30 -n 5 -l 50 -w 4 \
        2>&1 | tee "${LOG_DIR}/${SAMPLE}_fastp.log"

    # ------------------------------------------------------
    # FastQC Trimmed
    # ------------------------------------------------------
    echo "[3/7] FastQC (trimmed)"
    fastqc \
        "${SAMPLE_DIR}/fastp_output/${SAMPLE}_R1_trimmed.fastq.gz" \
        "${SAMPLE_DIR}/fastp_output/${SAMPLE}_R2_trimmed.fastq.gz" \
        -o "${SAMPLE_DIR}/fastqc_trimmed" \
        2>&1 | tee "${LOG_DIR}/${SAMPLE}_fastqc_trimmed.log"

    # ------------------------------------------------------
    # SPAdes
    # ------------------------------------------------------
    echo "[4/7] SPAdes assembly"
    spades.py \
        -1 "${SAMPLE_DIR}/fastp_output/${SAMPLE}_R1_trimmed.fastq.gz" \
        -2 "${SAMPLE_DIR}/fastp_output/${SAMPLE}_R2_trimmed.fastq.gz" \
        -o "${SAMPLE_DIR}/spades_output" \
        -t ${THREADS} --isolate \
        2>&1 | tee "${LOG_DIR}/${SAMPLE}_spades.log"

    ASSEMBLY="${SAMPLE_DIR}/spades_output/contigs.fasta"
    if [[ ! -f "$ASSEMBLY" ]]; then
        echo "❌ Assembly missing for $SAMPLE — skipping remaining steps."
        continue
    fi

    # ------------------------------------------------------
    # QUAST
    # ------------------------------------------------------
    echo "[5/7] QUAST"
    quast "$ASSEMBLY" \
        -o "${SAMPLE_DIR}/quast_output" \
        -t ${THREADS} \
        2>&1 | tee "${LOG_DIR}/${SAMPLE}_quast.log"

    # ------------------------------------------------------
    # Prokka
    # ------------------------------------------------------
    echo "[6/7] Prokka annotation"
    prokka "$ASSEMBLY" \
        --outdir "${SAMPLE_DIR}/prokka_output" \
        --prefix "$SAMPLE" \
        --cpus ${THREADS} \
        --kingdom Bacteria \
        --compliant \
        --centre X \
        --force \
        --fast \
        2>&1 | tee "${LOG_DIR}/${SAMPLE}_prokka.log"

    GBK="${SAMPLE_DIR}/prokka_output/${SAMPLE}.gbk"
    if [[ ! -f "$GBK" ]]; then
        echo "❌ Prokka failed for $SAMPLE — skipping antiSMASH"
        continue
    fi

    # ------------------------------------------------------
    # antiSMASH
    # ------------------------------------------------------
    echo "[7/7] antiSMASH"
    antismash "$GBK" \
        --databases "$HOME/antismash_db" \
        --output-dir "${SAMPLE_DIR}/antismash_output" \
        --genefinding-tool none \
        --taxon bacteria \
        --cpus ${THREADS} \
        --cb-general --cb-subclusters --cb-knownclusters \
        --asf --pfam2go \
        2>&1 | tee "${LOG_DIR}/${SAMPLE}_antismash.log"

    echo "✔ Finished sample: ${SAMPLE}"
    echo

done

echo "====================================="
echo " ALL SAMPLES PROCESSED SUCCESSFULLY!"
echo " Results in: $MAIN_DIR/"
echo "====================================="
