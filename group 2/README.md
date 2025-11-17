# 🧬 Metabolic Pathway & Enzyme Annotation Pipeline

> **Analyze genome metabolic capabilities through automated enzyme annotation and pathway mapping**

---

## 🎯 What This Pipeline Does

Transforms raw genome sequences into comprehensive metabolic profiles by identifying genes, annotating enzymes, and mapping them to KEGG pathways.

**Key Questions Answered:**
- ✅ Which metabolic pathways exist in the genome?
- ✅ How many genes participate in each pathway?
- ✅ What are the organism's metabolic capabilities?
- ✅ Which pathways are complete vs. incomplete?

---

## 📊 Pipeline Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                      Raw FASTQ Reads (R1 & R2)                  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ↓
                    ┌────────────────┐
                    │    FastQC      │  Quality Assessment
                    └────────┬───────┘
                             │
                             ↓
                    ┌────────────────┐
                    │     fastp      │  Quality Trimming & Filtering
                    └────────┬───────┘
                             │
                             ↓
                    ┌────────────────┐
                    │    SPAdes      │  Genome Assembly → contigs.fasta
                    └────────┬───────┘
                             │
                             ↓
                    ┌────────────────┐
                    │    Prokka      │  Gene Prediction → proteins.faa
                    └────────┬───────┘
                             │
                             ↓
                    ┌────────────────┐
                    │  KOfamScan     │  KO Annotation → KO IDs
                    └────────┬───────┘
                             │
                             ↓
                    ┌────────────────┐
                    │  KEGG Mapping  │  KO → Pathways → Counts
                    └────────┬───────┘
                             │
                             ↓
           ┌─────────────────────────────────────┐
           │      pathway_counts.tsv             │
           │  (Metabolic Pathway Gene Counts)    │
           └─────────────────────────────────────┘
```

---

## 🔧 Quick Installation

```bash
# 1. Create conda environment
conda create -n metabolic_pipeline python=3.8
conda activate metabolic_pipeline

# 2. Install tools
conda install -c bioconda fastqc fastp spades prokka
conda install -c conda-forge ruby
gem install parallel

# 3. Install KOfamScan
git clone https://github.com/takaram/kofam_scan.git
cd kofam_scan && chmod +x exec_annotation

# 4. Download KOfam database (~2.5 GB)
mkdir -p ~/kofam_db && cd ~/kofam_db
wget ftp://ftp.genome.jp/pub/db/kofam/profiles.tar.gz
tar -xvzf profiles.tar.gz
wget ftp://ftp.genome.jp/pub/db/kofam/ko_list.gz
gunzip ko_list.gz

# 5. Download KEGG mapping files
mkdir -p ~/pathway_mappings && cd ~/pathway_mappings
wget https://rest.kegg.jp/list/pathway -O pathway_titles.tab
wget https://rest.kegg.jp/link/pathway/ko -O ko_to_pathway.tab
```

---

## 🚀 Running the Pipeline

```bash
bash final_run.sh <R1.fastq.gz> <R2.fastq.gz> <sample_name> <kofam_dir> <pathway_dir>
```

**Example:**
```bash
bash final_run.sh \
  SRR12345_R1.fastq.gz \
  SRR12345_R2.fastq.gz \
  my_genome \
  ~/kofam_db \
  ~/pathway_mappings
```

---

## 🧬 Understanding KO Annotation

### What is a KO ID?

**KO (KEGG Orthology)** = Unique identifier for a gene/enzyme function

```
Your Protein → KOfamScan HMM Matching → KO Assignment
```

**Example KO Assignments:**

| KO ID | Enzyme | Pathway |
|-------|--------|---------|
| K00845 | glucokinase | Glycolysis |
| K01647 | citrate synthase | TCA Cycle |
| K00134 | GAPDH | Glycolysis |
| K15780 | nitrogenase | Nitrogen Fixation |

### KOfamScan Process

```
Predicted Proteins (Prokka output)
          ↓
Compare against 20,000+ HMM profiles
          ↓
Score matches (E-value < 1e-5)
          ↓
Assign best KO ID above threshold
          ↓
KO list for your genome
```

---

## 🗺️ KO-to-Pathway Mapping

### 3-Step Mapping Process

```
┌──────────────────────────────────────────────────────────────┐
│  STEP 1: KO Assignment                                       │
│  Gene_001 → K00845 (glucokinase)                            │
│  Gene_002 → K01810 (G6P isomerase)                          │
│  Gene_003 → K00134 (GAPDH)                                  │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ↓
┌──────────────────────────────────────────────────────────────┐
│  STEP 2: Link KO to Pathways                                │
│  K00845 → map00010 (Glycolysis)                             │
│  K01810 → map00010 (Glycolysis)                             │
│  K00134 → map00010 (Glycolysis), map00710 (Carbon fixation) │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ↓
┌──────────────────────────────────────────────────────────────┐
│  STEP 3: Count Genes per Pathway                            │
│  map00010 (Glycolysis): 3 genes                             │
│  map00710 (Carbon fixation): 1 gene                         │
└──────────────────────────────────────────────────────────────┘
```

**Mapping Files:**

`ko_to_pathway.tab` - Links KO to pathways:
```
ko:K00845    path:map00010
ko:K01810    path:map00010
```

`pathway_titles.tab` - Pathway names:
```
path:map00010    Glycolysis / Gluconeogenesis
path:map00020    Citrate cycle (TCA cycle)
```

---

## 📦 Key Output Files

| File | Description |
|------|-------------|
| `contigs.fasta` | Assembled genome |
| `{sample}.faa` | Predicted proteins |
| `{sample}_kegg.tsv` | KO assignments |
| `KO_list.txt` | Unique KO IDs |
| `pathway_counts.tsv` | **Gene counts per pathway** |

### Example Output: `pathway_counts.tsv`

```
Pathway_ID    Pathway_Name                      Gene_Count
map00010      Glycolysis                        18
map00020      TCA cycle                         14
map00190      Oxidative phosphorylation         25
map00220      Arginine biosynthesis             12
map00230      Purine metabolism                 31
map00290      Valine/leucine biosynthesis       11
```

---

## 🔍 Biological Interpretation

### Reading Your Results

**High Gene Count (>20 genes)**
- Well-represented pathway
- Core metabolic capability
- Example: *Oxidative phosphorylation (25) → aerobic organism*

**Medium Gene Count (10-20 genes)**
- Complete or near-complete pathway
- Example: *Glycolysis (18) → can metabolize glucose*

**Low Gene Count (<10 genes)**
- Partial pathway or missing steps
- May require external nutrients
- Example: *Tryptophan biosynthesis (3) → incomplete pathway*

**Zero Genes**
- Pathway absent
- Example: *Photosynthesis (0) → not photosynthetic*

### Example Interpretation

```
Marine Bacterium Analysis Results:

✅ Oxidative phosphorylation: 28 genes → Aerobic respiration
✅ Sulfur metabolism: 22 genes → Sulfur-cycling capability  
✅ Amino acid biosynthesis: 89 genes → Nutritionally independent
❌ Photosynthesis: 0 genes → Chemotroph (not photosynthetic)
❌ Nitrogen fixation: 2 genes → Cannot fix atmospheric nitrogen

Conclusion: Aerobic chemotroph adapted to sulfur-rich marine 
environments. Nutritionally independent but requires fixed nitrogen.
```

---

## 📋 Tools Overview

| Tool | Purpose | Output |
|------|---------|--------|
| **FastQC** | Quality assessment | Quality reports |
| **fastp** | Read trimming/filtering | Clean FASTQ |
| **SPAdes** | Genome assembly | Contigs |
| **Prokka** | Gene prediction | Proteins (.faa) |
| **KOfamScan** | Enzyme annotation | KO assignments |
| **KEGG** | Pathway mapping | Gene counts |

---

## 🐛 Troubleshooting

**KOfamScan fails:**
```bash
cd ~/kofam_scan && chmod +x exec_annotation
```

**Low KO assignment (<40%):**
- Normal! Many proteins lack KO annotations
- Try relaxing E-value threshold

**Assembly quality poor (N50 <10kb):**
- Check read quality with FastQC
- Increase sequencing depth
- Try different k-mer sizes

**Missing mapping files:**
```bash
wget https://rest.kegg.jp/list/pathway -O pathway_titles.tab
wget https://rest.kegg.jp/link/pathway/ko -O ko_to_pathway.tab
```

---

## 📚 Resources

- **KEGG Database:** https://www.kegg.jp/
- **KOfamScan:** https://github.com/takaram/kofam_scan
- **Prokka:** https://github.com/tseemann/prokka
- **SPAdes:** https://cab.spbu.ru/software/spades/

---

## 👥 Credits

**Pipeline by:** Group 2 - MSc Bioinformatics

**Tools:** FastQC, fastp, SPAdes, Prokka, KOfamScan, KEGG Database

---

**Version:** 1.0 | **Last Updated:** November 2025
