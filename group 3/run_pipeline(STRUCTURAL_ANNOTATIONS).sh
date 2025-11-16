#!/bin/bash
# ==========================================================
# Automated bacterial genome pipeline (Sequential Execution)
# Author: Group3
# Input:  Paired-end FASTQ files in /mnt/d/cogfinal/genome/
# Output: One folder per genome with subfolders per tool
# ==========================================================

MAIN_DIR="/mnt/d/cogfinal/genome"
OUTPUT_DIR="/mnt/d/cogfinal"
THREADS=4
MEMORY=8
PROTEINS="/mnt/d/cog1/prodigal/prodigal.proteins.faa"

echo "🚀 Pipeline started at $(date)"
echo "Input folder: $MAIN_DIR"

# Loop through each paired-end genome
for R1 in "$MAIN_DIR"/*_R1_001.fastq.gz; do
    BASENAME=$(basename "$R1")
    SAMPLE=${BASENAME%%_R1_001.fastq.gz}
    R2="$MAIN_DIR/${SAMPLE}_R2_001.fastq.gz"

    if [[ ! -f "$R2" ]]; then
        echo "⚠️  Skipping $SAMPLE — missing R2 file!"
        continue
    fi

    echo "=========================================="
    echo " Processing genome: $SAMPLE"
    echo "Started at: $(date)"
    echo "=========================================="

    OUTDIR="$OUTPUT_DIR/$SAMPLE"
    mkdir -p "$OUTDIR"

    # Create subfolders for each tool
    for TOOL in fastqc fastp multiqc spades quast barrnap trf minced prodigal prokka_output; do
        mkdir -p "$OUTDIR/$TOOL"
    done

    # 1️⃣ FASTQC
    echo "Running FastQC..."
    fastqc -o "$OUTDIR/fastqc" "$R1" "$R2"

    # 2️⃣ FASTP
    echo "Running fastp..."
    fastp -i "$R1" -I "$R2" \
          -o "$OUTDIR/fastp/clean_R1.fastq" \
          -O "$OUTDIR/fastp/clean_R2.fastq" \
          -h "$OUTDIR/fastp/fastp.html" \
          -j "$OUTDIR/fastp/fastp.json"

    # 3️⃣ MULTIQC
    echo "Running MultiQC..."
    multiqc "$OUTDIR/fastqc" "$OUTDIR/fastp" -o "$OUTDIR/multiqc"

    # 4️⃣ SPADES
    echo "Running SPAdes assembly..."
    spades.py -1 "$OUTDIR/fastp/clean_R1.fastq" \
              -2 "$OUTDIR/fastp/clean_R2.fastq" \
              -o "$OUTDIR/spades" \
              --threads $THREADS \
              --memory $MEMORY

    # 5️⃣ QUAST
    echo "Running QUAST..."
    quast.py "$OUTDIR/spades/contigs.fasta" -o "$OUTDIR/quast"

    # 6️⃣ BARRNAP
    echo "Running Barrnap..."
    barrnap "$OUTDIR/spades/contigs.fasta" > "$OUTDIR/barrnap/barrnap.gff"

    # 7️⃣ TRF
    echo "Running TRF..."
    trf "$OUTDIR/spades/contigs.fasta" 2 7 7 80 10 50 500 -d -h > "$OUTDIR/trf/trf.out"

    # 8️⃣ MINCED
    echo "Running MinCED..."
    minced "$OUTDIR/spades/contigs.fasta" "$OUTDIR/minced/minced.out" -gff

    # 9️⃣ PRODIGAL
    echo "Running Prodigal..."
    prodigal -i "$OUTDIR/spades/contigs.fasta" \
             -a "$OUTDIR/prodigal/proteins.faa" \
             -d "$OUTDIR/prodigal/genes.fna" \
             -o "$OUTDIR/prodigal/prodigal.log" -p single

    # 🔟 PROKKA
    echo "Running Prokka..."
    prokka "$OUTDIR/spades/contigs.fasta" \
           --outdir "$OUTDIR/prokka_output" \
           --prefix "$SAMPLE" \
           --genus Lactobacillus \
           --usegenus \
           --cpus $THREADS \
           --addgenes \
           --rnammer \
           --proteins "$PROTEINS" \
           --gffver 3 \
           --force

    echo "✅ Finished processing $SAMPLE"
    echo "------------------------------------------"
done

echo "🎉 All samples processed!"
echo "Pipeline finished at $(date)"
