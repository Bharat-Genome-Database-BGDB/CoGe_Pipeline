#!/bin/bash
set -e

################################################################################
# 🔹 SECTION 1 — INSTALL ALL REQUIRED TOOLS AUTOMATICALLY (RUNS ONLY IF NEEDED)
################################################################################
echo "===================================================="
echo " 🔧 Checking & Installing Dependencies"
echo "===================================================="

# Update system
sudo apt update -y

# Install core dependencies
sudo apt install -y \
  fastqc \
  fastp \
  spades \
  quast \
  abricate \
  python3-biopython \
  unzip wget git

# Install Prokka if missing
if ! command -v prokka &> /dev/null; then
  echo "⚙ Installing Prokka..."
  sudo apt install -y prokka
else
  echo "✔ Prokka already installed"
fi

# Update Abricate database
echo "🔃 Updating Abricate database..."
abricate --setupdb

echo "===================================================="
echo " 🔥 Tools Installed Successfully"
echo "===================================================="


################################################################################
# 🔹 SECTION 2 — AUTOMATED GENOME PIPELINE
################################################################################
WORKDIR="/mnt/d/automated_pipeline"
cd "$WORKDIR"

echo "===================================================="
echo " 🚀 STARTING / RESUMING GENOME PIPELINE"
echo " Working directory: $WORKDIR"
echo "===================================================="

for FWD in *_R1_001.fastq.gz; do
    SAMPLE=$(basename "$FWD" _R1_001.fastq.gz)
    REV="${SAMPLE}_R2_001.fastq.gz"

    echo "----------------------------------------------------"
    echo " Processing sample: $SAMPLE"
    echo "----------------------------------------------------"


    # 1️⃣ FASTQC
    if [[ ! -d "${SAMPLE}_fastqc" ]]; then
        echo "[1/6] Running FastQC..."
        mkdir -p "${SAMPLE}_fastqc"
        fastqc "$FWD" "$REV" -o "${SAMPLE}_fastqc"
    else
        echo "✔ FastQC already done"
    fi


    # 2️⃣ fastp
    if [[ ! -f "${SAMPLE}_trimmed_R1.fastq" ]]; then
        echo "[2/6] Running fastp trimming..."
        fastp -i "$FWD" -I "$REV" \
              -o "${SAMPLE}_trimmed_R1.fastq" \
              -O "${SAMPLE}_trimmed_R2.fastq" \
              -h "${SAMPLE}_fastp.html" \
              -j "${SAMPLE}_fastp.json"
    else
        echo "✔ fastp already done"
    fi


    # 3️⃣ SPAdes — Assembly
    if [[ ! -f "${SAMPLE}_spades_output/contigs.fasta" ]]; then
        echo "[3/6] Running SPAdes..."
        mkdir -p "${SAMPLE}_spades_output"
        spades.py --isolate \
          -1 "${SAMPLE}_trimmed_R1.fastq" \
          -2 "${SAMPLE}_trimmed_R2.fastq" \
          -o "${SAMPLE}_spades_output"
    else
        echo "✔ SPAdes already done"
    fi


    # 4️⃣ QUAST — Assembly evaluation
    if [[ ! -d "${SAMPLE}_quast" ]]; then
        echo "[4/6] Running QUAST..."
        quast.py "${SAMPLE}_spades_output/contigs.fasta" \
          -o "${SAMPLE}_quast"
    else
        echo "✔ QUAST already done"
    fi


    # 5️⃣ PROKKA — Annotation
    if [[ ! -f "${SAMPLE}_prokka/${SAMPLE}.fna" ]]; then
        echo "[5/6] Running PROKKA..."
        mkdir -p "${SAMPLE}_prokka"
        prokka --outdir "${SAMPLE}_prokka" \
               --prefix "$SAMPLE" \
               "${SAMPLE}_spades_output/contigs.fasta"
    else
        echo "✔ Prokka already done"
    fi


    # 6️⃣ ABRICATE — AMR gene search
    if [[ ! -f "${SAMPLE}_abricate.txt" ]]; then
        echo "[6/6] Running ABRICATE..."
        abricate "${SAMPLE}_prokka/${SAMPLE}.fna" \
          > "${SAMPLE}_abricate.txt"
    else
        echo "✔ ABRICATE already done"
    fi

    echo "🎯 Finished sample: $SAMPLE"
done

echo "===================================================="
echo " 🏁 PIPELINE COMPLETED FOR ALL FASTQ SAMPLES"
echo " Output folder: $WORKDIR"
echo "===================================================="
