#!/bin/bash

#===============================================================================
# SIMPLE SETUP SCRIPT - Uses environment.yml
# Creates folders, environment, downloads databases
#===============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;93m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  🧬 Genome Pipeline Setup - Using environment.yml 🧬${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
echo ""

PROJECT_DIR="$HOME/genomics_pipeline"

echo -e "${BLUE}[1/6] Creating directories...${NC}"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"
mkdir -p genomes_to_process results logs data/dbs temp
echo -e "${GREEN}✓ Done${NC}"
echo ""

CONDA_BASE=""
if [ -d "$HOME/miniconda3" ]; then
    CONDA_BASE="$HOME/miniconda3"
elif [ -d "$HOME/anaconda3" ]; then
    CONDA_BASE="$HOME/anaconda3"
elif [ -d "/opt/conda" ]; then
    CONDA_BASE="/opt/conda"
fi

if [ -z "$CONDA_BASE" ]; then
    echo -e "${BLUE}Step 2: Installing Miniconda...${NC}"
    
    wget --progress=bar:force https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
    
    bash /tmp/miniconda.sh -b -p "$HOME/miniconda3"
    rm -f /tmp/miniconda.sh
    
    CONDA_BASE="$HOME/miniconda3"
    echo -e "${GREEN}✓ Miniconda installed${NC}"
else
    echo -e "${GREEN}✓ Conda found: $CONDA_BASE${NC}"
fi

echo ""
echo -e "${BLUE}Step 3: Initializing Conda...${NC}"

source "$CONDA_BASE/etc/profile.d/conda.sh"

"$CONDA_BASE/bin/conda" init bash >/dev/null 2>&1

echo -e "${GREEN}✓ Conda initialized${NC}"
echo ""



if [ ! -f "environment.yml" ]; then
    echo -e "${RED}ERROR: environment.yml not found!${NC}"
    echo -e "${YELLOW}Please place environment.yml in: $PROJECT_DIR${NC}"
    exit 1
fi

echo -e "${BLUE}[2/6] Creating conda environment from environment.yml...${NC}"

if conda env list | grep -q "^reganno "; then
    echo -e "${YELLOW}Removing old environment...${NC}"
    conda env remove -n reganno -y
fi

conda env create -f environment.yml

echo -e "${GREEN}✓ Environment created${NC}"
echo ""

eval "$(conda shell.bash hook)"
conda activate reganno

echo -e "${BLUE}[3/6] Downloading Pfam database (~700 MB)...${NC}"
cd data/dbs

if [ ! -f "Pfam-A.hmm" ]; then
    wget --progress=bar:force https://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/Pfam-A.hmm.gz || \
    wget --progress=bar:force http://ftp.ebi.ac.uk/pub/databases/Pfam/releases/Pfam35.0/Pfam-A.hmm.gz
    
    gunzip -f Pfam-A.hmm.gz
    hmmpress Pfam-A.hmm
    echo -e "${GREEN}✓ Pfam ready${NC}"
else
    echo -e "${GREEN}✓ Pfam exists${NC}"
fi

echo ""
echo -e "${BLUE}[4/6] Downloading Rfam database (~50 MB)...${NC}"

if [ ! -f "Rfam.cm" ]; then
    wget --progress=bar:force https://ftp.ebi.ac.uk/pub/databases/Rfam/CURRENT/Rfam.cm.gz || \
    wget --progress=bar:force http://ftp.ebi.ac.uk/pub/databases/Rfam/14.10/Rfam.cm.gz
    
    gunzip -f Rfam.cm.gz
    cmpress Rfam.cm
    echo -e "${GREEN}✓ Rfam ready${NC}"
else
    echo -e "${GREEN}✓ Rfam exists${NC}"
fi

source ~/.bashrc

echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ SETUP COMPLETE! ✓${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Location:${NC} $PROJECT_DIR"
echo ""
echo -e "${YELLOW}RUN NOW:${NC}"
echo -e "  ${CYAN}conda activate reganno${NC}"
echo ""
echo -e "${YELLOW}VERIFY:${NC}"
echo -e "  ${CYAN}prokka --version${NC}"
echo -e "  ${CYAN}meme -version${NC}"
echo ""
echo -e "${YELLOW}NEXT STEPS:${NC}"
echo -e "  1. Add genomes → ${CYAN}genomes_to_process/${NC}"
echo -e "  2. Run → ${CYAN}./run_pipeline.sh${NC}"
