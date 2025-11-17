#!/usr/bin/env bash
set -euo pipefail

##############################################################
#   GENOME PIPELINE INSTALLER (FINAL VERSION - AUTO-CONDA)
##############################################################

ENV_NAME="genome-pipeline"

# Where to install antiSMASH DB (change if HOME is small)
ANTISMASH_DB_DIR="$HOME/antismash_db"

echo "===================================================="
echo "        GENOME PIPELINE INSTALLATION SCRIPT"
echo "===================================================="


##############################################################
# STEP 1 — Detect or Install Conda
##############################################################

echo "➤ Checking for conda…"

if ! command -v conda >/dev/null 2>&1; then
    echo "  Conda not detected — installing Miniconda..."

    mkdir -p "$HOME/miniconda3"
    wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
        -O "$HOME/miniconda3/miniconda.sh"

    bash "$HOME/miniconda3/miniconda.sh" -b -u -p "$HOME/miniconda3"
    rm "$HOME/miniconda3/miniconda.sh"

    echo "✔ Miniconda installed."
else
    echo "✔ Conda already installed."
fi


##############################################################
# STEP 2 — Auto-locate conda.sh and initialize Conda
##############################################################

echo "➤ Locating conda installation…"

CANDIDATES=(
    "$HOME/miniconda3/etc/profile.d/conda.sh"
    "$HOME/miniconda/etc/profile.d/conda.sh"
    "$HOME/anaconda3/etc/profile.d/conda.sh"
    "/opt/miniconda3/etc/profile.d/conda.sh"
    "/opt/anaconda3/etc/profile.d/conda.sh"
)

CONDA_FOUND="false"

for c in "${CANDIDATES[@]}"; do
    if [ -f "$c" ]; then
        echo "✔ Found conda at: $c"
        source "$c"
        CONDA_FOUND="true"
        break
    fi
done

if [ "$CONDA_FOUND" = "false" ]; then
    echo " ERROR: conda.sh not found! Unable to initialize conda."
    echo "   Checked the following locations:"
    printf '   - %s\n' "${CANDIDATES[@]}"
    exit 1
fi

# Ensure conda command is on PATH
export PATH="$(dirname "$(dirname "$(which conda 2>/dev/null || echo "$HOME/miniconda3/bin/conda")")")/bin:$PATH"
hash -r

echo "✔ Conda initialized."


##############################################################
# STEP 3 — Accept Conda Terms of Service
##############################################################

echo "➤ Accepting Conda Terms of Service..."

conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

echo "✔ Conda ToS accepted."


##############################################################
# STEP 4 — Create Conda Environment
##############################################################

if conda env list | grep -q "^${ENV_NAME}"; then
    echo "✔ Environment '$ENV_NAME' already exists."
else
    echo "➤ Creating environment: $ENV_NAME"
    conda create -y -n "$ENV_NAME" python=3.10
    echo "✔ Environment created."
fi

conda activate "$ENV_NAME"


##############################################################
# STEP 5 — Configure Channels
##############################################################

echo "➤ Configuring bioconda channels…"

conda config --add channels defaults 2>/dev/null || true
conda config --add channels bioconda 2>/dev/null || true
conda config --add channels conda-forge 2>/dev/null || true

echo "✔ Channels configured."


##############################################################
# STEP 6 — Install Tools
##############################################################

echo
echo "===================================================="
echo "        Installing Genome Pipeline Tools"
echo "===================================================="

echo "➤ Installing GNU Parallel..."
conda install -y parallel

echo "➤ Installing FastQC..."
conda install -y fastqc

echo "➤ Installing fastp..."
conda install -y fastp

echo "➤ Installing SPAdes..."
conda install -y spades

echo "➤ Installing QUAST..."
conda install -y quast

echo "➤ Installing Prokka..."
conda install -y prokka

echo "➤ Installing antiSMASH..."
conda install -y antismash


##############################################################
# STEP 7 — Install antiSMASH Databases
##############################################################

echo
echo "===================================================="
echo "        Installing antiSMASH Databases"
echo "===================================================="

echo "➤ Database directory: $ANTISMASH_DB_DIR"
mkdir -p "$ANTISMASH_DB_DIR"

# Check available disk space
DB_SPACE=$(df -h "$ANTISMASH_DB_DIR" | awk 'NR==2 {print $4}')
DB_GB=$(echo "$DB_SPACE" | sed 's/G//')

if (( $(echo "$DB_GB < 15" | bc -l) )); then
    echo "  WARNING: Only $DB_GB GB free — antiSMASH DB (~15–20GB) may fail."
fi

echo "➤ Downloading antiSMASH databases..."
download-antismash-databases --database-dir "$ANTISMASH_DB_DIR" || {
    echo " ERROR: antiSMASH DB download failed!"
    exit 1
}

echo "✔ antiSMASH databases installed successfully."
echo "   -> $ANTISMASH_DB_DIR"


##############################################################
# INSTALLATION COMPLETE
##############################################################

echo
echo "===================================================="
echo "        INSTALLATION COMPLETED SUCCESSFULLY!"
echo "===================================================="
echo "Activate your environment with:"
echo "   conda activate $ENV_NAME"
echo
echo "You can now run your pipeline script."
echo
