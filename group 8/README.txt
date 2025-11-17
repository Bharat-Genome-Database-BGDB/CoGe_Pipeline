Automated Bacterial Genome Functional Annotation Pipeline

An automated pipeline for functional annotation of bacterial genomes using Prodigal, DIAMOND, and HMMER.

📋 Overview

This pipeline performs:
- Gene Prediction using Prodigal
- Homology Search against SwissProt using DIAMOND
- Domain Detection against Pfam using HMMER
- Combined Annotation output in TSV format
- HTML Reports for visualization


Quick Start (in bash)

1. Setup Pipeline
./setup_pipeline.sh

2. Add Your Genomes
# Place your bacterial genome files in the genomes directory
mkdir -p genomes
cp your_genomes/*.fna genomes/

3. Run Pipeline
./auto_pipeline.sh


Prerequisites - Required Tools (use steps below or manually download each tool)

1. Install Prodigal
# Ubuntu/Debian
sudo apt-get install prodigal
# Conda
conda install -c bioconda prodigal

2. Install DIAMOND
# Ubuntu/Debian
sudo apt-get install diamond
# Conda  
conda install -c bioconda diamond

3. Install HMMER
# Ubuntu/Debian
sudo apt-get install hmmer
# Conda
conda install -c bioconda hmmer


Required Database Downloads (use steps below or manually download each database)

1. SwissProt Database for DIAMOND
# Create databases directory
mkdir -p databases
# Download SwissProt
wget https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/uniprot_sprot.fasta.gz
gunzip uniprot_sprot.fasta.gz

# Create DIAMOND database
diamond makedb --in uniprot_sprot.fasta -d databases/swissprot.dmnd

# Clean up
rm uniprot_sprot.fasta

 2. Pfam Database for HMMER
# Download Pfam-A database
wget https://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/Pfam-A.hmm.gz
gunzip Pfam-A.hmm.gz
mv Pfam-A.hmm databases/
# Optional: Compress for faster searching
hmmpress databases/Pfam-A.hmm



Configuration

Edit `config.sh` to modify pipeline parameters:

# Number of CPU threads to use
THREADS=$(nproc)

# E-value threshold for searches
E_VALUE=1e-5

# Database paths
DIAMOND_DB="databases/swissprot.dmnd"
PFAM_DB="databases/Pfam-A.hmm"


📊 Output Files

For each genome, the pipeline generates:

-Gene Predictions: `.faa` (proteins), `.fna` (genes), `.gff` (annotations)
- Homology Results: SwissProt hits in TSV format
- Domain Annotations: Pfam domains in domtblout format
- Combined TSV: Integrated annotations with all results
- HTML Report: Visual summary with statistics
- Text Summary: Quick overview of results




Usage Examples

#run the pipeline
./auto_pipeline.sh

#Debug Database Paths
./debug_check.sh

#Process Specific Genome
# Manual processing example
prodigal -i genomes/your_genome.fna -a output/prodigal/your_genome.faa -o output/prodigal/your_genome.gff
diamond blastp --db databases/swissprot.dmnd --query output/prodigal/your_genome.faa --out output/diamond/your_genome.tsv
hmmscan --cpu 8 --domtblout output/hmmer/your_genome.domtblout databases/Pfam-A.hmm output/prodigal/your_genome.faa




Troubleshooting

1. Database not found:
   ./debug_check.sh  # Verify database paths

2. No .fna files in genomes/:
   - Ensure genome files have `.fna` extension
   - Check file permissions

3. Out of memory:
   - Reduce `THREADS` in `config.sh`
   - Process genomes sequentially

4. Tool not found:
   - Run `./setup_pipeline.sh` to check dependencies

   - Verify tools are in `$PATH`
