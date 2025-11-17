#!/bin/bash
set -euo pipefail

################################################################################
# 🔹 SECTION 1 — INSTALL ALL REQUIRED TOOLS (One-time setup)
################################################################################
echo "===================================================="
echo " 🔧 Checking & Installing Dependencies"
echo "===================================================="

if [[ ! -f /etc/debian_version ]]; then
    echo "⚠️  WARNING: This script is designed for Ubuntu/Debian."
fi

sudo apt update -y
sudo apt install -y fastqc fastp spades quast abricate unzip wget git python3-biopython

# Install Prokka if not installed
if ! command -v prokka &>/dev/null; then
    echo "⚙ Installing Prokka..."
    sudo apt install -y prokka
else
    echo "✔ Prokka already installed"
fi

# Verify tools installed
REQUIRED_TOOLS=("fastqc" "fastp" "spades.py" "quast.py" "prokka" "abricate")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
        echo "❌ ERROR: $tool is missing — install manually"
        exit 1
    fi
done

echo "🔃 Updating Abricate database..."
abricate --setupdb
echo "===================================================="
echo " ✅ All Tools Installed Successfully"
echo "===================================================="


################################################################################
# 🔹 SECTION 2 — AUTOMATED GENOME ANALYSIS PIPELINE
################################################################################
WORKDIR="/mnt/d/automated_pipeline"
cd "$WORKDIR"

echo "===================================================="
echo " 🚀 STARTING / RESUMING PIPELINE"
echo " Working directory: $WORKDIR"
echo "===================================================="

if ! ls *_R1_001.fastq.gz 1>/dev/null 2>&1; then
    echo "❌ No FASTQ files found!"
    exit 1
fi

THREADS=$(nproc)
SAMPLE_COUNT=0
TOTAL_SAMPLES=$(ls *_R1_001.fastq.gz | wc -l)

for FWD in *_R1_001.fastq.gz; do
    SAMPLE=$(basename "$FWD" _R1_001.fastq.gz)
    REV="${SAMPLE}_R2_001.fastq.gz"
    SAMPLE_COUNT=$((SAMPLE_COUNT + 1))

    if [[ ! -f "$REV" ]]; then
        echo "⚠️ WARNING: Missing $REV → skipped"
        continue
    fi

    echo "===================================================="
    echo " 📁 SAMPLE [$SAMPLE_COUNT/$TOTAL_SAMPLES] → $SAMPLE"
    echo "===================================================="

    # 1️⃣ FASTQC
    if [[ ! -d "${SAMPLE}_fastqc" ]]; then
        echo "[1/6] Running FastQC..."
        mkdir -p "${SAMPLE}_fastqc"
        fastqc "$FWD" "$REV" -o "${SAMPLE}_fastqc" -q
    else
        echo "✔ [1/6] FastQC already done"
    fi

    # 2️⃣ fastp
    if [[ ! -f "${SAMPLE}_trimmed_R1.fastq" ]]; then
        echo "[2/6] Running fastp..."
        fastp -i "$FWD" -I "$REV" -q \
            -o "${SAMPLE}_trimmed_R1.fastq" \
            -O "${SAMPLE}_trimmed_R2.fastq" \
            -h "${SAMPLE}_fastp.html" \
            -j "${SAMPLE}_fastp.json" \
            --thread $THREADS
    else
        echo "✔ [2/6] fastp already done"
    fi

    # 3️⃣ SPAdes
    if [[ ! -s "${SAMPLE}_spades_output/contigs.fasta" ]]; then
        echo "[3/6] Running SPAdes..."
        spades.py --isolate \
          -1 "${SAMPLE}_trimmed_R1.fastq" \
          -2 "${SAMPLE}_trimmed_R2.fastq" \
          -o "${SAMPLE}_spades_output" \
          -t $THREADS
        
        # Verify assembly succeeded
        if [[ ! -s "${SAMPLE}_spades_output/contigs.fasta" ]]; then
            echo "❌ ERROR: SPAdes failed → Skipping $SAMPLE"
            continue
        fi
    else
        echo "✔ [3/6] SPAdes already done"
    fi

    # 4️⃣ QUAST
    if [[ ! -d "${SAMPLE}_quast" ]]; then
        echo "[4/6] Running QUAST..."
        quast.py "${SAMPLE}_spades_output/contigs.fasta" \
          -o "${SAMPLE}_quast" \
          --threads $THREADS
    else
        echo "✔ [4/6] QUAST already done"
    fi

    # 5️⃣ PROKKA
    if [[ ! -f "${SAMPLE}_prokka/${SAMPLE}.txt" ]]; then
        echo "[5/6] Running Prokka..."
        prokka --outdir "${SAMPLE}_prokka" \
               --prefix "$SAMPLE" \
               --cpus $THREADS \
               --force \
               "${SAMPLE}_spades_output/contigs.fasta"
    else
        echo "✔ [5/6] Prokka already done"
    fi

    # 6️⃣ ABRICATE
    if [[ ! -f "${SAMPLE}_abricate.txt" ]]; then
        echo "[6/6] Running Abricate..."
        abricate "${SAMPLE}_spades_output/contigs.fasta" > "${SAMPLE}_abricate.txt"
        
        # Show AMR gene count
        AMR_COUNT=$(grep -v "^#" "${SAMPLE}_abricate.txt" | wc -l)
        echo "   📊 Found $AMR_COUNT AMR gene(s)"
    else
        echo "✔ [6/6] Abricate already done"
    fi

    echo ""
    echo "✅ Finished: $SAMPLE"
    echo ""
done

echo "===================================================="
echo " 🎉 PIPELINE COMPLETED FOR ALL SAMPLES"
echo " Output location: $WORKDIR"
echo "===================================================="
echo ""
echo "📋 Output files per sample:"
echo "   {SAMPLE}_fastqc/          → Quality control"
echo "   {SAMPLE}_fastp.html       → Trimming stats"
echo "   {SAMPLE}_spades_output/   → Assembly"
echo "   {SAMPLE}_quast/           → Assembly metrics"
echo "   {SAMPLE}_prokka/          → Annotations"
echo "   {SAMPLE}_abricate.txt     → AMR genes"
echo ""