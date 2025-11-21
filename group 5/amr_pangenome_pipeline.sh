#!/usr/bin/env bash
# amr_pangenome_pipeline_fixed2.sh
# Author Sruthi Santhosh Kumar 
set -euo pipefail
IFS=$'\n\t'

# ---------- CONFIG ----------
ENV_NAME="amr_pangenome_env"
THREADS=4
MEM_GB=12
MIN_MEM_GB=8      # require at least 8 GB to run assemblies
MIN_DISK_GB=15    # require at least 15 GB free in OUT_DIR filesystem
MAX_AMR_HEATMAP_GENES=500

WGET_RETRIES=5
WGET_TIMEOUT=30
WGET_WAIT=1

# ---------- HELP ----------
usage(){
  cat <<EOF
Usage: $0 <fastq_dir> <out_dir> [--threads N] [--mem GB]
EOF
  exit 1
}
if [[ $# -lt 2 ]]; then usage; fi

FASTQ_DIR="$1"
OUT_DIR="$2"
shift 2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --threads) THREADS="$2"; shift 2;;
    --mem) MEM_GB="$2"; shift 2;;
    *) shift;;
  esac
done

mkdir -p "$OUT_DIR"
LOGDIR="$OUT_DIR/logs"; mkdir -p "$LOGDIR"
cd "$OUT_DIR"   # <<--- CRITICAL FIX: run all output creation inside OUT_DIR

# ---------- LOG helpers ----------
ts(){ date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log(){ printf "\n[%s] [INFO] %s\n" "$(ts)" "$*"; }
warn(){ printf "\n[%s] [WARN] %s\n" "$(ts)" "$*" >&2; }
err(){ printf "\n[%s] [ERROR] %s\n" "$(ts)" "$*" >&2; exit 1; }

# ---------- PREREQ CHECKS ----------
if [[ ! -d "$FASTQ_DIR" ]]; then err "FASTQ_DIR not found: $FASTQ_DIR"; fi
if ! command -v conda >/dev/null 2>&1; then err "conda not found - install Miniconda before running"; fi

# Memory check
if [[ -r /proc/meminfo ]]; then
  mem_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo || echo 0)
  mem_gb=$(( (mem_kb/1024/1024) ))
else
  mem_gb=0
fi
if (( mem_gb < MIN_MEM_GB )); then
  warn "Available memory ${mem_gb}GB < recommended ${MIN_MEM_GB}GB. Proceeding but SPAdes may fail."
fi

# Disk check (OUT_DIR filesystem)
avail_kb=$(df -Pk "$OUT_DIR" | awk 'NR==2{print $4}')
avail_gb=$((avail_kb/1024/1024))
if (( avail_gb < MIN_DISK_GB )); then
  warn "Available disk ${avail_gb}GB < recommended ${MIN_DISK_GB}GB in $OUT_DIR filesystem."
fi

# ---------- Conda env setup ----------
log "Initialize conda shell..."
eval "$(conda shell.bash hook)" || err "Failed to evaluate conda hook"
if ! conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
  log "Creating conda env: $ENV_NAME"
  conda create -y -n "$ENV_NAME" python=3.10 >/dev/null || err "conda create failed"
fi
log "Activating $ENV_NAME"
conda activate "$ENV_NAME" || err "Failed to activate conda env"

# Packages required
REQUIRED_PACKAGES=(fastqc fastp spades quast prokka ncbi-amrfinderplus panaroo blast mafft pandas matplotlib seaborn scipy biopython)
log "Installing/checking required conda packages (only missing ones will be installed)..."
for pkg in "${REQUIRED_PACKAGES[@]}"; do
  if ! conda list -n "$ENV_NAME" | awk '{print $1}' | grep -qx "$pkg"; then
    log "Installing $pkg..."
    conda install -y -n "$ENV_NAME" -c conda-forge -c bioconda "$pkg" || warn "conda install $pkg had issues"
  fi
done
# ensure makeblastdb available
if ! command -v makeblastdb >/dev/null 2>&1; then
  conda install -y -n "$ENV_NAME" -c bioconda blast || err "Installing blast failed"
fi

# ---------- AMRFinder DB (robust) ----------
AMR_BASE_DIR="$CONDA_PREFIX/share/amrfinderplus/data"
AMR_RELEASE="2024-07-22.1"
AMR_DOWNLOAD_URL="ftp://ftp.ncbi.nlm.nih.gov/pathogen/Antimicrobial_resistance/AMRFinderPlus/database/3.12/${AMR_RELEASE}/"

log "Ensure AMRFinder DB exists under: $AMR_BASE_DIR"
mkdir -p "$AMR_BASE_DIR"

if [[ ! -d "$AMR_BASE_DIR/latest" && ! -d "$AMR_BASE_DIR/$AMR_RELEASE" ]]; then
  log "Downloading AMRFinder DB (release ${AMR_RELEASE}) with timeout/retries..."
  # use wget with retries/timeouts
  wget --tries="$WGET_RETRIES" --timeout="$WGET_TIMEOUT" --wait="$WGET_WAIT" -r -np -nH --cut-dirs=6 -R "index.html*" "$AMR_DOWNLOAD_URL" -P "$AMR_BASE_DIR" \
    || warn "wget AMR DB may have failed; check network or retry manually"
fi

# create symlink 'latest' -> release dir if found
if [[ -d "$AMR_BASE_DIR/$AMR_RELEASE" ]]; then
  ln -sfn "$AMR_BASE_DIR/$AMR_RELEASE" "$AMR_BASE_DIR/latest"
  log "AMRFinder DB ready: $AMR_BASE_DIR/latest -> $AMR_RELEASE"
fi

# BLAST DB check (do not quote the glob; test with ls output)
if ls "$AMR_BASE_DIR/latest/AMRProt"* >/dev/null 2>&1; then
  # check whether BLAST DB files exist (.pin/.phr/.psq or .pdb etc)
  if ! ls "$AMR_BASE_DIR/latest/AMRProt"*.[pn][hr][sq] >/dev/null 2>&1; then
    log "Creating BLAST DB from AMRProt FASTA"
    makeblastdb -in "$AMR_BASE_DIR/latest/AMRProt" -dbtype prot -parse_seqids -out "$AMR_BASE_DIR/latest/AMRProt" \
      || warn "makeblastdb failed for AMRProt"
  fi
else
  warn "AMRProt FASTA not found in AMRFinder DB dir; amrfinder may fail for translated searches"
fi

# ---------- Collect R1 files robustly ----------
shopt -s nullglob
R1_GLOBS=( "$FASTQ_DIR"/*[Rr]1*.fastq* "$FASTQ_DIR"/*_1*.fastq* "$FASTQ_DIR"/*_R1*.* )
if [[ ${#R1_GLOBS[@]} -eq 0 ]]; then err "No R1 reads found under $FASTQ_DIR"; fi

# helper: derive sample name robustly (tries multiple patterns)
derive_sample_name(){
  local f="$1"
  local b
  b="$(basename "$f")"
  # try common suffix patterns (keep longest prefix before suffix)
  # patterns: _R1_001, _R1, _r1, _1, _read1, -1, .1
  # perform ordered replacements (longer patterns first)
  sample="${b%_R1_001*}"
  sample="${sample%_R1_001.*}"
  sample="${sample%_R1*}"
  sample="${sample%_r1*}"
  sample="${sample%_read1*}"
  sample="${sample%_1.fastq*}"
  sample="${sample%_1.fq*}"
  sample="${sample%-1.fastq*}"
  sample="${sample%-1.fq*}"
  sample="${sample%.*}"
  echo "$sample"
}

# improved function to find matching R2 for a given R1
find_r2_for_r1(){
  local r1="$1"
  local dir sample base alt r2 candidates
  dir="$(dirname "$r1")"
  sample="$(derive_sample_name "$r1")"
  base="$(basename "$r1")"
  candidates=()

  # explicit candidate patterns (preserve extension)
  candidates+=( "$dir/${sample}_R2_001.fastq.gz" )
  candidates+=( "$dir/${sample}_R2_001.fastq" )
  candidates+=( "$dir/${sample}_R2.fastq.gz" )
  candidates+=( "$dir/${sample}_R2.fastq" )
  candidates+=( "$dir/${sample}_R2_001.fq.gz" )
  candidates+=( "$dir/${sample}_R2.fq.gz" )
  candidates+=( "$dir/${sample}_2.fastq.gz" )
  candidates+=( "$dir/${sample}_2.fastq" )
  candidates+=( "$dir/${sample}_2.fq.gz" )
  candidates+=( "$dir/${sample}_read2.fastq.gz" )
  candidates+=( "$dir/${sample}_read2.fastq" )

  # attempt R1->R2 substitution in filename
  alt="${r1//[Rr]1/[Rr]2}"
  candidates+=( "$alt" )

  # fallback: search for files that share sample prefix and have R2-like token
  for possible in "$FASTQ_DIR"/"${sample}"*; do
    # accept if filename contains R2 or _2 or read2
    if [[ "$possible" =~ ([Rr]2|_2\b|_read2) ]] ; then
      candidates+=( "$possible" )
    fi
  done

  # prefer gz files if multiple matches: pick first existing candidate (prefer gz)
  for ext in ".gz" ""; do
    for c in "${candidates[@]}"; do
      if [[ $ext == ".gz" && "$c" != *.gz ]]; then continue; fi
      if [[ -f "$c" ]]; then
        echo "$c"
        return 0
      fi
    done
  done

  # no match
  return 1
}

# ---------- PROCESS SAMPLES ----------
PROKKA_GFFS=()
SAMPLE_LIST=()

for r1 in "${R1_GLOBS[@]}"; do
  sample="$(derive_sample_name "$r1")"

  # avoid duplicates
  if printf '%s\n' "${SAMPLE_LIST[@]}" | grep -qx -- "$sample"; then
    continue
  fi

  # find R2
  if r2="$(find_r2_for_r1 "$r1")"; then
    log "Sample: $sample -> R1: $(basename "$r1") R2: $(basename "$r2")"
  else
    warn "Could not find R2 for R1 $(basename "$r1") (sample prefix '$sample'), skipping sample"
    continue
  fi

  SAMPLE_LIST+=("$sample")
  SAMPLE_DIR="$OUT_DIR/$sample"
  mkdir -p "$SAMPLE_DIR"/{fastqc,fastp_report,spades_output,quast_report,prokka,amr}

  # FastQC
  log "FastQC: $sample"
  fastqc -q -o "$SAMPLE_DIR/fastqc" "$r1" "$r2" 2> "$LOGDIR/${sample}_fastqc.log" || warn "FastQC warning for $sample"

  # fastp (trimming)
  R1_TRIM="$SAMPLE_DIR/${sample}_R1_trimmed.fastq.gz"
  R2_TRIM="$SAMPLE_DIR/${sample}_R2_trimmed.fastq.gz"
  log "fastp trimming: $sample"
  fastp -i "$r1" -I "$r2" -o "$R1_TRIM" -O "$R2_TRIM" \
    -h "$SAMPLE_DIR/fastp_report/${sample}_fastp.html" -j "$SAMPLE_DIR/fastp_report/${sample}_fastp.json" \
    --thread "$THREADS" 2> "$LOGDIR/${sample}_fastp.log" || warn "fastp issues for $sample"

  if [[ ! -s "$R1_TRIM" || ! -s "$R2_TRIM" ]]; then
    warn "Trimmed files missing for $sample, skipping assembly"
    continue
  fi

  # quick memory check before assembly
  if (( mem_gb < MIN_MEM_GB )); then
    warn "Low memory (${mem_gb}GB) — SPAdes may fail or swap."
  fi

  # SPAdes
  log "SPAdes assembly: $sample"
  spades.py -1 "$R1_TRIM" -2 "$R2_TRIM" -o "$SAMPLE_DIR/spades_output" --threads "$THREADS" --memory "$MEM_GB" --only-assembler \
    2> "$LOGDIR/${sample}_spades.log" || warn "SPAdes had warnings/errors for $sample"

  CONTIGS="$SAMPLE_DIR/spades_output/contigs.fasta"
  if [[ ! -s "$CONTIGS" ]]; then
    warn "No contigs.fasta for $sample - skipping downstream steps"
    continue
  fi

  # QUAST
  log "QUAST: $sample"
  quast.py -o "$SAMPLE_DIR/quast_report" "$CONTIGS" --threads "$THREADS" 2> "$LOGDIR/${sample}_quast.log" || warn "QUAST warning for $sample"

  # PROKKA
  log "Prokka: $sample"
  prokka --force --outdir "$SAMPLE_DIR/prokka" --prefix "$sample" --cpus "$THREADS" "$CONTIGS" 2> "$LOGDIR/${sample}_prokka.log" || warn "Prokka warning for $sample"

  PROKKA_GFF="$SAMPLE_DIR/prokka/${sample}.gff"
  PROKKA_FNA="$SAMPLE_DIR/prokka/${sample}.fna"
  if [[ -s "$PROKKA_GFF" ]]; then
    PROKKA_GFFS+=("$PROKKA_GFF")
  else
    warn "Prokka GFF missing for $sample"
  fi

  # AMRFinder
  if [[ -s "$PROKKA_FNA" ]]; then
    log "AMRFinder: $sample (this can be slow)"
    amrfinder -n "$PROKKA_FNA" -o "$SAMPLE_DIR/amr/${sample}_amrfinder.tsv" --threads "$THREADS" 2> "$LOGDIR/${sample}_amrfinder.log" || warn "AMRFinder warnings for $sample"
  else
    warn "Prokka .fna missing for $sample - skipping AMRFinder"
  fi

done

if [[ ${#SAMPLE_LIST[@]} -eq 0 ]]; then err "No samples were processed. Exiting."; fi
log "Samples processed: ${#SAMPLE_LIST[@]}"

# ---------- Combine AMR results robustly ----------
COMBINED_AMR="$OUT_DIR/combined_amr_results.tsv"
log "Combining AMRFinder outputs into $COMBINED_AMR"

python3 - <<'PY'
import pandas as pd, glob, os
files = glob.glob(os.path.join("*", "amr", "*_amrfinder.tsv"))
rows=[]
for f in files:
    try:
        df = pd.read_csv(f, sep="\t", comment="#", dtype=str)
    except Exception:
        continue
    sample = f.split(os.sep)[0]
    df.insert(0, "sample", sample)
    rows.append(df)
if rows:
    out = pd.concat(rows, ignore_index=True, sort=False)
    out.to_csv("combined_amr_results.tsv", sep="\t", index=False)
    print("created combined_amr_results.tsv")
else:
    print("no amr files found")
PY

if [[ -f combined_amr_results.tsv ]]; then mv combined_amr_results.tsv "$COMBINED_AMR"; else warn "combined AMR not created"; fi

# ---------- Create AMR presence/absence matrix (explicit OUT_DIR paths) ----------
AMR_MATRIX="$OUT_DIR/amr_presence_absence.tsv"
log "Creating AMR presence/absence matrix: $AMR_MATRIX"
python3 - <<'PY'
import pandas as pd, os
if not os.path.exists("combined_amr_results.tsv"):
    print("combined_amr_results.tsv missing; looking in parent dir")
    if os.path.exists(os.path.join("..", "combined_amr_results.tsv")):
        df = pd.read_csv(os.path.join("..", "combined_amr_results.tsv"), sep="\t", dtype=str)
    else:
        raise SystemExit("combined_amr_results.tsv not found")
else:
    df = pd.read_csv("combined_amr_results.tsv", sep="\t", dtype=str)

# normalize header names (common AMRFinder headers)
cols_lower = {c.lower(): c for c in df.columns}
gene_col = None
for candidate in ("gene_symbol","gene symbol","gene","protein_id","protein_identifier"):
    if candidate in cols_lower:
        gene_col = cols_lower[candidate]; break
if gene_col is None:
    gene_col = df.columns[1]  # fallback

df['gene_symbol'] = df[gene_col].astype(str)
mat = df.pivot_table(index="sample", columns="gene_symbol", values=gene_col, aggfunc=lambda x:1, fill_value=0)
mat.to_csv("amr_presence_absence.tsv", sep="\t")
print("amr_presence_absence.tsv generated")
PY

if [[ -f amr_presence_absence.tsv ]]; then mv amr_presence_absence.tsv "$AMR_MATRIX"; fi

# ---------- AMR visualizations + dendrogram (write under OUT_DIR/visualization) ----------
VIS_DIR="$OUT_DIR/visualization"
mkdir -p "$VIS_DIR"
log "Generating AMR visualizations into $VIS_DIR (heatmap, top genes, dendrogram)"
python3 - <<'PY'
import pandas as pd, seaborn as sns, matplotlib.pyplot as plt, os
from scipy.cluster.hierarchy import linkage, dendrogram
os.makedirs("visualization", exist_ok=True)
mat_path="amr_presence_absence.tsv"
if not os.path.exists(mat_path):
    raise SystemExit("amr_presence_absence.tsv missing")
mat = pd.read_csv(mat_path, sep="\t", index_col=0)
# drop zero-columns
mat = mat.loc[:, mat.sum(axis=0) > 0]
# subset genes for heatmap to avoid huge image
max_cols = int(os.environ.get("MAX_AMR_HEATMAP_GENES", "500"))
if mat.shape[1] > max_cols:
    variances = mat.var(axis=0)
    topcols = variances.sort_values(ascending=False).head(max_cols).index
    mat_plot = mat[topcols]
else:
    mat_plot = mat

plt.figure(figsize=(20,10))
sns.heatmap(mat_plot, cmap="YlGnBu", cbar=True)
plt.title("AMR presence/absence (subset)")
plt.tight_layout()
plt.savefig("visualization/amr_heatmap.png", dpi=300)
plt.close()

# top genes barplot
top = mat.sum(axis=0).sort_values(ascending=False).head(20)
plt.figure(figsize=(9,6))
sns.barplot(x=top.values, y=top.index)
plt.title("Top 20 AMR genes")
plt.tight_layout()
plt.savefig("visualization/top_amr_genes.png", dpi=300)
plt.close()

# dendrogram (samples)
if mat.shape[0] >= 2:
    Z = linkage(mat, method='average', metric='hamming')
    plt.figure(figsize=(10,6))
    dendrogram(Z, labels=mat.index, leaf_rotation=90)
    plt.title("AMR gene-content dendrogram")
    plt.tight_layout()
    plt.savefig("visualization/amr_dendrogram.png", dpi=300)
    plt.close()

# move to OUT_DIR
for f in os.listdir("visualization"):
    os.replace(os.path.join("visualization", f), os.path.join(os.environ.get("OUT_DIR","."), "visualization", f))
print("AMR visualizations created")
PY

# move generated visualization files (created in script) into final $VIS_DIR
mv visualization/* "$VIS_DIR/" 2>/dev/null || true

# ---------- Panaroo (run once if >1 genome) ----------
if (( ${#PROKKA_GFFS[@]} > 1 )); then
  log "Running Panaroo with ${#PROKKA_GFFS[@]} genomes (strict mode)"
  mkdir -p "$OUT_DIR/panaroo_output"
  # join file list safely
  IFS=$'\n' GFF_LIST=("${PROKKA_GFFS[@]}")
  panaroo -i "${GFF_LIST[@]}" -o "$OUT_DIR/panaroo_output" --clean-mode strict --threads "$THREADS" 2> "$LOGDIR/panaroo.log" || warn "Panaroo had warnings"
  # generate pangenome dendrogram if gene_presence_absence.csv present
  if [[ -f "$OUT_DIR/panaroo_output/gene_presence_absence.csv" ]]; then
    python3 - <<'PY'
import pandas as pd
from scipy.cluster.hierarchy import linkage, dendrogram
import matplotlib.pyplot as plt
import os
df = pd.read_csv("panaroo_output/gene_presence_absence.csv")
meta = set(['Gene','Non-unique','Annotation','No. isolates','Protein IDs','Gene ID','Gene name'])
samples = [c for c in df.columns if c not in meta]
pa = df[samples].notna().astype(int)
Z = linkage(pa.T, method='average', metric='hamming')
os.makedirs("panaroo_output/tree", exist_ok=True)
plt.figure(figsize=(12,6))
dendrogram(Z, labels=pa.columns, leaf_rotation=90)
plt.tight_layout()
plt.savefig("panaroo_output/tree/pangenome_tree.png", dpi=300)
plt.close()
print("Saved panaroo_output/tree/pangenome_tree.png")
PY
  fi
else
  log "Panaroo skipped: need >1 genome (found ${#PROKKA_GFFS[@]})"
fi

# ---------- FINAL SUMMARY ----------
log "Pipeline completed. Summary (some key files):"
log " - Combined AMR TSV: $COMBINED_AMR"
log " - AMR presence/absence matrix: $AMR_MATRIX"
log " - AMR visualizations: $VIS_DIR"
if [[ -d "$OUT_DIR/panaroo_output/tree" ]]; then
  log " - Pangenome tree: $OUT_DIR/panaroo_output/tree/pangenome_tree.png"
fi

# clean up conda activation (optional)
conda deactivate || true

exit 0
