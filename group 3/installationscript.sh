#!/bin/bash
# ==========================================================
#   INSTALLATION SCRIPT FOR BACTERIAL GENOME PIPELINE
#   Creates conda env + installs required tools if missing
# ==========================================================

ENV_NAME="bactpipe"

TOOLS=(
    fastqc
    fastp
    multiqc
    spades
    quast
    barrnap
    trf
    minced
    prodigal
    prokka
)

echo "🚀 Starting installation…"

# ----------------------------------------------------------
# 1️⃣ CHECK IF CONDA EXISTS
# ----------------------------------------------------------
if ! command -v conda &> /dev/null; then
    echo "❌ Conda not found! Install Miniconda first."
    exit 1
fi

# ----------------------------------------------------------
# 2️⃣ CREATE ENVIRONMENT IF NOT EXISTS
# ----------------------------------------------------------
if conda env list | grep -q "$ENV_NAME"; then
    echo "✔️ Conda environment '$ENV_NAME' already exists."
else
    echo "📦 Creating conda environment: $ENV_NAME"
    conda create -y -n $ENV_NAME python=3.10
fi

echo "📌 Activating environment…"
source ~/anaconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate $ENV_NAME

# ----------------------------------------------------------
# 3️⃣ INSTALL ALL TOOLS USING CONDA
# ----------------------------------------------------------
echo "🔍 Checking and installing required tools…"

for tool in "${TOOLS[@]}"; do
    if command -v $tool &> /dev/null; then
        echo "✔️ $tool already installed"
    else
        echo "📦 Installing $tool…"
        conda install -y -c bioconda -c conda-forge $tool
    fi
done

# ----------------------------------------------------------
# 4️⃣ SPECIAL INSTALLS (NOT IN CONDA)
# ----------------------------------------------------------

# 🔹 TRF
if ! command -v trf &> /dev/null; then
    echo "⬇️ Installing TRF manually…"
    mkdir -p ~/tools/trf
    wget -q https://tandem.bu.edu/trf/downloads/trf409.linux64 -O ~/tools/trf/trf
    chmod +x ~/tools/trf/trf
    sudo ln -sf ~/tools/trf/trf /usr/local/bin/trf
fi

# ----------------------------------------------------------
# 5️⃣ RUN THE PIPELINE SCRIPT
# ----------------------------------------------------------
echo "🚀 All tools installed successfully!"
echo "👉 Running your pipeline…"

bash run_pipeline.sh

echo "🎉 Installation + pipeline completed!"
