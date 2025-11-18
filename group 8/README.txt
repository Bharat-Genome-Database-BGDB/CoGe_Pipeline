🧬 Automated Bacterial Genome Functional Annotation Pipeline
A comprehensive, automated pipeline for functional annotation of bacterial genomes using gene prediction, homology searching, and domain detection.


📋 Overview
This pipeline provides a complete workflow for annotating bacterial genomes with:
- Gene Prediction using Prodigal
- Homology Search against SwissProt using DIAMOND
- Domain Detection using Pfam databases with HMMER
- Reporting with HTML and text summaries



Ensure you have the following tools installed:
- Prodigal - Gene prediction
- DIAMOND - Fast protein alignment
- HMMER - Domain detection
- Python 3 - For reporting scripts
- wget/curl - For database downloads


Installation & Setup
1. Clone or download the pipeline files
   # Make scripts executable
   chmod +x setup_pipeline.sh auto_pipeline.sh

2. Run the setup script (downloads databases automatically)
   ./setup_pipeline.sh

3. Place your genome files in the `genomes/` directory
   # Example: copy your .fna files
   cp your_genomes/*.fna genomes/

4. Run the annotation pipeline
   ./auto_pipeline.sh


Pipeline Steps:
The pipeline executes the following steps for each genome:

1. Preprocessing - Format validation and sequence deduplication
2. Gene Prediction - Identify coding sequences with Prodigal
3. Homology Search - BLASTp against SwissProt using DIAMOND
4. Domain Detection - Identify protein domains with HMMER/Pfam
5. Annotation Combination - Merge all results into comprehensive tables
6. Report Generation - Create HTML and text summaries


Configuration
The pipeline automatically configures with optimal settings
- Threads: Uses all available CPU cores
- E-value: 1e-5 for homology searches
- Max targets: 1 best hit per sequence
- Input format: FASTA files (.fna extension)
You can customize parameters by editing `config.sh` after setup.


📈Output Interpretation

Annotation Table Columns:
- Gene_ID: Unique identifier for each predicted gene
- Protein_Description: Functional description from gene prediction
- SwissProt_Annotation: Best match from SwissProt database
- Pfam_Domains: Detected protein domains
- Domain_Count: Number of domains per gene

Report Metrics:
- Annotation Coverage: Percentage of genes with SwissProt hits
- Domain Density: Average domains per gene
- Functional Categories: Based on SwissProt and Pfam annotations
