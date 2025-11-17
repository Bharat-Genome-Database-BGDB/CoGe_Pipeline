🧬 Metabolic Pathway & Enzyme Annotation Pipeline — Group 2
🌍 1. Project Introduction

This project focuses on analyzing a genome downloaded from ODOG (Online Database of Organisms' Genomes).
The goal is to understand:

✔️ Which metabolic pathways the genome contains
✔️ How many genes from the genome participate in each pathway
✔️ Total number of pathways detected
✔️ Which enzymes (KO IDs) are present
✔️ How the genome fits into biological functions such as:

Energy metabolism

Carbohydrate metabolism

Amino acid biosynthesis

Environmental adaptation pathways

Secondary metabolism

Our pipeline converts raw sequencing reads → annotated pathways through the following steps:

➡️ Reads → Assembly → Predicted genes → KO enzyme annotation → KEGG pathways → Counts per pathway

This helps in answering the biological question:

“What can this organism do metabolically?”
“Which pathways are complete or partially complete?”
“How many genes map into each KEGG metabolic pathway?”

📘 2. Workflow Overview
 ┌───────────────┐
 | Raw Genome     |  (from ODOG)
 └──────┬────────┘
        ▼
 ┌───────────────┐
 | Read QC        |  FastQC + fastp
 └──────┬────────┘
        ▼
 ┌───────────────┐
 |  Assembly      |  SPAdes
 └──────┬────────┘
        ▼
 ┌───────────────┐
 | Gene Prediction|  Prokka
 └──────┬────────┘
        ▼
 ┌──────────────────────┐
 | Enzyme Annotation     |  KOfamScan → KO IDs
 └──────┬───────────────┘
        ▼
 ┌─────────────────────────────┐
 | KEGG Pathway Mapping        |  KO → pathway → counts
 └─────────────────────────────┘

🛠️ 3. Installation Requirements (Before Running Pipeline)

Complete these steps before executing final_run.sh.

✅ 3.1 Install KOfamScan Database
HMM profiles
wget ftp://ftp.genome.jp/pub/db/kofam/profiles.tar.gz
tar -xvzf profiles.tar.gz

KO list
wget ftp://ftp.genome.jp/pub/db/kofam/ko_list.gz
gunzip ko_list.gz

✅ 3.2 Install KOfamScan Tool
git clone https://github.com/takaram/kofam_scan.git

🌐 3.3 Download KEGG Mapping Tables
mkdir ~/pathway_mappings
cd ~/pathway_mappings

Pathway titles
wget https://rest.kegg.jp/list/pathway -O pathway_titles.tab

KO → pathway links
wget https://rest.kegg.jp/link/pathway/ko -O ko_to_pathway.tab

📁 4. Folder Structure
group2/
│── final_run.sh
│── README.md
│
├── kofam/
│     ├── profiles/
│     ├── ko_list
│     └── kofam_scan/
│
├── pathway_mappings/
│     ├── pathway_titles.tab
│     └── ko_to_pathway.tab
│
├── example_data/
├── outputs/
└── logs/

🚀 5. Running the Pipeline
bash final_run.sh <R1.fastq.gz> <R2.fastq.gz> <sample_name> <kofam_dir> <pathway_mapping_dir>

Example:
bash final_run.sh \
  SRR_R1.fastq.gz \
  SRR_R2.fastq.gz \
  sample1 \
  /home/group2/kofam \
  /home/group2/pathway_mappings

📦 6. Output Files Explained
File	Description
contigs.fasta	Genome assembly
sample.faa	Predicted proteins
sample_kegg.tsv	All KO hits
sample_kegg_filtered.tsv	KO hits (filtered high-confidence)
KO_list.txt	Unique KO IDs
ko_pathway_final.tsv	Complete KO → pathway mapping
pathway_counts.tsv	Pathway-wise gene counts
logfile.txt	Log of pipeline
🧬 7. Biological Interpretation (Easy Version)
🔍 What is a KO ID?

KO = KEGG Ortholog

Each KO corresponds to a specific enzyme or gene function

KO IDs map the genome to known metabolic pathways

🔬 Why pathway mapping?

It tells us:

✔️ What metabolic capabilities the organism has
✔️ Which pathways are present / absent / partial
✔️ How many genes participate in each pathway
✔️ Ecological and functional role of the organism

📊 8. Example Output Interpretation

After running the pipeline, you receive:

🔹 Total pathways detected

Example: 56 KEGG pathways found

🔹 Pathway-wise gene counts

Example:

Pathway	Genes From Genome
Glycolysis	18
TCA Cycle	14
Nitrogen Metabolism	9
Fatty Acid Biosynthesis	22
Amino Acid Biosynthesis	35
🔹 Key questions answered

“Is glycolysis present?” → Yes

“How many enzymes for amino acid metabolism exist?” → Count from table

“Does the organism have oxidative phosphorylation?” → Depends on KO IDs

“Which pathways are most enriched?” → Highest counts

🧠 9. How It Works (Super Simple)
1️⃣ Prokka → finds genes → produces proteins
2️⃣ KOfamScan → matches proteins to KO IDs
3️⃣ Mapping → KO IDs matched to KEGG pathways
4️⃣ Counting → how many genes hit each pathway
🎨 10. Flow Diagram
                    ┌──────────────────────────────┐
                    │  fastp (QC + trimming)        │
                    └───────────────┬───────────────┘
                                    │
                                    v
        ┌────────────────────────────────────────────┐
        │             SPAdes assembly                │
        └───────────────┬────────────────────────────┘
                        │
                        v
        ┌────────────────────────────────────────────┐
        │     Prokka (gene + protein prediction)     │
        └───────────────┬────────────────────────────┘
                        │
                        v
        ┌────────────────────────────────────────────┐
        │         KOfamScan (KO assignment)          │
        └───────────────┬────────────────────────────┘
                        │
                        v
        ┌────────────────────────────────────────────┐
        │       KEGG Pathway Mapping + Counts        │
        └────────────────────────────────────────────┘

📝 11. Summary of What You Learn From This Pipeline

✔️ Which pathways are present in the ODOG genome
✔️ How many pathway genes are detected
✔️ Which enzymes (KO IDs) the organism contains
✔️ Complete list of metabolic capabilities
✔️ Potential ecological functions
✔️ Functional richness vs other genomes
