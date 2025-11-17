#!/usr/bin/env bash
set -euo pipefail

############################################
#     GENOME PIPELINE (PARALLEL VERSION)
#     Requires conda env: genome-pipeline
############################################

ENV_NAME="genome-pipeline"
THREADS=6
PARALLEL_JOBS=2   # Number of genomes to process in parallel
MAIN_DIR="results_parallel"
DB_DIR="$HOME/.antismash"


echo "====================================="
echo "     GENOME PIPELINE (PARALLEL)"
echo "====================================="

# ------------------------------------------------------
# 1. Load conda
# ------------------------------------------------------
if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
else
    echo "❌ ERROR: conda.sh not found!"
    exit 1
fi

# ------------------------------------------------------
# 2. Activate environment
# ------------------------------------------------------
conda activate "$ENV_NAME" || {
    echo "❌ ERROR: Cannot activate conda environment '$ENV_NAME'"
    exit 1
}

echo "✔ Activated conda environment: $ENV_NAME"
echo

mkdir -p "$MAIN_DIR/logs"

# ------------------------------------------------------
# 3. Detect FASTQ files
# ------------------------------------------------------
shopt -s nullglob
R1_FILES=( *_R1*.fastq.gz *_1*.fastq.gz )
shopt -u nullglob

if [[ ${#R1_FILES[@]} -eq 0 ]]; then
    echo "❌ No paired-end FASTQ files found."
    exit 1
fi

# ------------------------------------------------------
# 4. Define function to process one sample
# ------------------------------------------------------
run_sample() {
    R1="$1"
    R2="$2"
    SAMPLE="$3"
    SAMPLE_DIR="$4"
    LOG_DIR="$5"
    THREADS="$6"

    echo "====================================="
    echo "    STARTING SAMPLE: $SAMPLE"
    echo "====================================="

    mkdir -p "${SAMPLE_DIR}/fastqc_raw" \
             "${SAMPLE_DIR}/fastp_output" \
             "${SAMPLE_DIR}/fastqc_trimmed" \
             "${SAMPLE_DIR}/spades_output" \
             "${SAMPLE_DIR}/quast_output" \
             "${SAMPLE_DIR}/prokka_output" \
             "${SAMPLE_DIR}/antismash_output"

    # 1. FastQC raw
    fastqc "$R1" "$R2" -o "${SAMPLE_DIR}/fastqc_raw" \
        2>&1 | tee "${LOG_DIR}/${SAMPLE}_fastqc_raw.log"

    # 2. fastp trimming
    fastp \
        -i "$R1" -I "$R2" \
        -o "${SAMPLE_DIR}/fastp_output/${SAMPLE}_R1_trimmed.fastq.gz" \
        -O "${SAMPLE_DIR}/fastp_output/${SAMPLE}_R2_trimmed.fastq.gz" \
        -h "${SAMPLE_DIR}/fastp_output/${SAMPLE}_fastp.html" \
        -j "${SAMPLE_DIR}/fastp_output/${SAMPLE}_fastp.json" \
        -q 20 -u 30 -n 5 -l 50 -w 4 \
        2>&1 | tee "${LOG_DIR}/${SAMPLE}_fastp.log"

    # 3. FastQC trimmed
    fastqc \
        "${SAMPLE_DIR}/fastp_output/${SAMPLE}_R1_trimmed.fastq.gz" \
        "${SAMPLE_DIR}/fastp_output/${SAMPLE}_R2_trimmed.fastq.gz" \
        -o "${SAMPLE_DIR}/fastqc_trimmed" \
        2>&1 | tee "${LOG_DIR}/${SAMPLE}_fastqc_trimmed.log"

    # 4. SPAdes assembly
    spades.py \
        -1 "${SAMPLE_DIR}/fastp_output/${SAMPLE}_R1_trimmed.fastq.gz" \
        -2 "${SAMPLE_DIR}/fastp_output/${SAMPLE}_R2_trimmed.fastq.gz" \
        -o "${SAMPLE_DIR}/spades_output" \
        -t ${THREADS} --isolate \
        2>&1 | tee "${LOG_DIR}/${SAMPLE}_spades.log"

    ASSEMBLY="${SAMPLE_DIR}/spades_output/contigs.fasta"
    if [[ ! -f "$ASSEMBLY" ]]; then
        echo "❌ Assembly missing for $SAMPLE — skipping remaining steps."
        return
    fi

    # 5. QUAST
    quast "$ASSEMBLY" \
        -o "${SAMPLE_DIR}/quast_output" \
        -t ${THREADS} \
        2>&1 | tee "${LOG_DIR}/${SAMPLE}_quast.log"

    # 6. Prokka
    prokka "$ASSEMBLY" \
        --outdir "${SAMPLE_DIR}/prokka_output" \
        --prefix "$SAMPLE" \
        --cpus ${THREADS} \
        --kingdom Bacteria \
        --complaint\
        --fast \
        --force \
        2>&1 | tee "${LOG_DIR}/${SAMPLE}_prokka.log"

    GBK="${SAMPLE_DIR}/prokka_output/${SAMPLE}.gbk"
    if [[ ! -f "$GBK" ]]; then
        echo "❌ Prokka failed for $SAMPLE — skipping antiSMASH"
        return
    fi

    # 7. antiSMASH
    antismash "$GBK" \
        --databases "$DB_DIR" \
        --output-dir "${SAMPLE_DIR}/antismash_output" \
        --genefinding-tool none \
        --taxon bacteria \
        --cpus ${THREADS} \
        --cb-general --cb-subclusters --cb-knownclusters \
        --asf --pfam2go \
        2>&1 | tee "${LOG_DIR}/${SAMPLE}_antismash.log"

    echo "✔ COMPLETED SAMPLE: $SAMPLE"
}

export -f run_sample

# ------------------------------------------------------
# 5. Build parallel job list
# ------------------------------------------------------
JOB_FILE="parallel_jobs.txt"
rm -f "$JOB_FILE"

for R1 in "${R1_FILES[@]}"; do
    if [[ "$R1" == *_R1* ]]; then
        R2="${R1/_R1/_R2}"
        SAMPLE=$(basename "$R1" | sed 's/_R1.*//')
    else
        R2="${R1/_1/_2}"
        SAMPLE=$(basename "$R1" | sed 's/_1.*//')
    fi

    [[ -f "$R2" ]] || continue

    echo "$R1 $R2 $SAMPLE $MAIN_DIR/$SAMPLE $MAIN_DIR/logs $THREADS" >> "$JOB_FILE"
done

# ------------------------------------------------------
# 6. Run samples in parallel
# ------------------------------------------------------
echo
echo "==========================================="
echo " RUNNING ${PARALLEL_JOBS} SAMPLES IN PARALLEL"
echo "==========================================="
echo

parallel --colsep ' ' -j "$PARALLEL_JOBS" run_sample :::: "$JOB_FILE"

echo
echo "====================================="
echo " ALL SAMPLES PROCESSED SUCCESSFULLY!"
echo " RESULTS IN: $MAIN_DIR/"
echo "====================================="
