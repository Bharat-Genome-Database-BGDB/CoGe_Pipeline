#!/usr/bin/env bash
# pipeline_fixed_kofam.sh
# Full pipeline with explicit ruby invocation for KOfam exec_annotation
set -euo pipefail
IFS=$'\n\t'

# ---------- helpers ----------
info(){ printf "\n[INFO] %s\n" "$*"; }
warn(){ printf "\n[WARN] %s\n" "$*" >&2; }
die(){ printf "\n[ERROR] %s\n" "$*" >&2; exit 1; }

trace_fail(){
  local rc=$? file="${BASH_SOURCE[1]}" line="${BASH_LINENO[0]}"
  printf "\n[ERROR] Script failed at %s:%s (exit %d)\n" "$file" "$line" "$rc" >&2
  exit "$rc"
}
trap trace_fail ERR

draw_progress(){
  local cur=$1 total=$2 width=40
  (( total<=0 )) && total=1
  local pct filled rest bar
  pct=$(( cur*100/total ))
  (( pct<0 )) && pct=0
  (( pct>100 )) && pct=100
  filled=$(( pct*width/100 ))
  rest=$(( width-filled ))
  bar=$(printf '%0.s#' $(seq 1 $filled))$(printf '%0.s-' $(seq 1 $rest))
  printf "Progress: [%s] %3s%% (%d/%d)\n" "$bar" "$pct" "$cur" "$total"
}

# ---------- args ----------
if (( $# != 5 )); then
  echo "Usage: $0 <R1.fastq.gz> <R2.fastq.gz> <PREFIX> <KOFAM_DIR> <PATHWAY_DIR>"
  exit 1
fi

R1="$1"; R2="$2"; PREFIX="$3"; KOFAM_DIR="$4"; PATHWAY_DIR="$5"
PROJECT_DIR="$(pwd)"
WORKDIR="${PROJECT_DIR}/CoG_run_${PREFIX}"
OUTDIR="${WORKDIR}/out/${PREFIX}"
LOGDIR="${WORKDIR}/logs"
mkdir -p "$WORKDIR" "$OUTDIR" "$LOGDIR"

MASTER_LOG="${LOGDIR}/pipeline.log"
exec > >(tee -a "$MASTER_LOG") 2>&1

info "Launching pipeline"
info "R1 = $R1"
info "R2 = $R2"
info "PREFIX = $PREFIX"
info "WORKDIR = $WORKDIR"
info "KOFAM_DIR = $KOFAM_DIR"
info "PATHWAY_DIR = $PATHWAY_DIR"

TOTAL_STEPS=16
STEP=0
draw_progress $STEP $TOTAL_STEPS

# ---------- ensure conda available ----------
STEP=$((STEP+1)); info "STEP $STEP/$TOTAL_STEPS: Check conda"
if ! command -v conda >/dev/null 2>&1; then
  die "conda not found. Install Miniconda/Miniforge first."
fi
eval "$(conda shell.bash hook)" || die "Failed to initialize conda shell hook"
draw_progress $STEP $TOTAL_STEPS

# ---------- ensure odog_env and tools ----------
STEP=$((STEP+1)); info "STEP $STEP/$TOTAL_STEPS: Ensure environment odog_env"
if conda env list | awk '{print $1}' | grep -qx "odog_env"; then
  info "odog_env exists"
else
  info "Creating odog_env with core tools (may take time)..."
  conda create -n odog_env -y -c conda-forge -c bioconda \
    python=3.9 fastqc fastp spades quast prokka hmmer diamond blast prodigal perl-xml-simple || die "Failed creating odog_env"
fi
# install ruby into odog_env if missing (KOfam needs ruby)
if ! conda run -n odog_env --no-capture-output ruby -v >/dev/null 2>&1; then
  info "Installing ruby into odog_env..."
  conda install -n odog_env -y -c conda-forge ruby > "${LOGDIR}/conda_ruby_install.log" 2>&1 || die "Failed to install ruby in odog_env"
fi
draw_progress $STEP $TOTAL_STEPS

# helper to run commands inside odog_env
run_env(){ conda run -n odog_env --no-capture-output "$@"; }

# ---------- STEP: FASTQC ----------
STEP=$((STEP+1)); info "STEP $STEP/$TOTAL_STEPS: FASTQC raw"
mkdir -p "${OUTDIR}_fastqc_raw"
if run_env fastqc --version >/dev/null 2>&1; then
  run_env fastqc "$R1" "$R2" -o "${OUTDIR}_fastqc_raw" > "${LOGDIR}/fastqc_raw.log" 2>&1 || warn "fastqc raw failed (see ${LOGDIR}/fastqc_raw.log)"
else
  warn "fastqc not available in odog_env"
fi
draw_progress $STEP $TOTAL_STEPS

# ---------- STEP: fastp ----------
STEP=$((STEP+1)); info "STEP $STEP/$TOTAL_STEPS: fastp trimming"
mkdir -p "${OUTDIR}_fastp"
R1_CLEAN="${OUTDIR}_fastp/${PREFIX}_R1_clean.fastq.gz"
R2_CLEAN="${OUTDIR}_fastp/${PREFIX}_R2_clean.fastq.gz"
if run_env fastp -v >/dev/null 2>&1; then
  run_env fastp -i "$R1" -I "$R2" -o "${R1_CLEAN}" -O "${R2_CLEAN}" -h "${OUTDIR}_fastp/report.html" -j "${OUTDIR}_fastp/report.json" > "${LOGDIR}/fastp.log" 2>&1 \
    || die "fastp failed (see ${LOGDIR}/fastp.log)"
else
  die "fastp not found in odog_env; install fastp and rerun"
fi
draw_progress $STEP $TOTAL_STEPS

# ---------- STEP: spades ----------
STEP=$((STEP+1)); info "STEP $STEP/$TOTAL_STEPS: SPAdes"
mkdir -p "${OUTDIR}_spades"
CONTIGS="${OUTDIR}_spades/contigs.fasta"
if run_env spades.py --version >/dev/null 2>&1; then
  run_env spades.py -1 "${R1_CLEAN}" -2 "${R2_CLEAN}" -o "${OUTDIR}_spades" --threads 4 --memory 8 > "${LOGDIR}/spades.log" 2>&1 || warn "spades warnings (see ${LOGDIR}/spades.log)"
else
  warn "spades missing - skipping assembly"
fi
draw_progress $STEP $TOTAL_STEPS

# ---------- STEP: quast ----------
STEP=$((STEP+1)); info "STEP $STEP/$TOTAL_STEPS: QUAST"
mkdir -p "${OUTDIR}_quast"
if [[ -f "${CONTIGS}" ]] && run_env quast --version >/dev/null 2>&1; then
  run_env quast "${CONTIGS}" -o "${OUTDIR}_quast" > "${LOGDIR}/quast.log" 2>&1 || warn "quast issues (see ${LOGDIR}/quast.log)"
else
  warn "QUAST or contigs missing; skipping"
fi
draw_progress $STEP $TOTAL_STEPS

# ---------- STEP: prokka ----------
STEP=$((STEP+1)); info "STEP $STEP/$TOTAL_STEPS: PROKKA annotation"
mkdir -p "${OUTDIR}_prokka"
PROKKA_OUT="${OUTDIR}_prokka"
PROKKA_FAA="${PROKKA_OUT}/${PREFIX}.faa"
if [[ -f "${CONTIGS}" ]]; then
  if run_env prokka --version >/dev/null 2>&1; then
    run_env prokka "${CONTIGS}" --prefix "${PREFIX}" --cpus 4 --outdir "${PROKKA_OUT}" --force > "${LOGDIR}/prokka.log" 2>&1 || warn "Prokka returned non-zero (see ${LOGDIR}/prokka.log)"
    if [[ -f "${PROKKA_FAA}" ]]; then
      info "Prokka .faa produced: ${PROKKA_FAA}"
    else
      warn "Prokka .faa not found; KOfam will be skipped"
    fi
  else
    die "Prokka not installed in odog_env; install prokka and rerun"
  fi
else
  die "contigs.fasta missing - cannot run Prokka"
fi
draw_progress $STEP $TOTAL_STEPS

# ---------- KOfam pre-checks ----------
STEP=$((STEP+1)); info "STEP $STEP/$TOTAL_STEPS: KOfam checks"
KOFAM_EXEC="${KOFAM_DIR%/}/kofam_scan/exec_annotation"
KOFAM_PROFILES="${KOFAM_DIR%/}/profiles"
KOFAM_KO_LIST="${KOFAM_DIR%/}/ko_list"
mkdir -p "${OUTDIR}_kofam"

# ensure exec exists and is executable
if [[ ! -f "${KOFAM_EXEC}" ]]; then
  warn "exec_annotation not found at ${KOFAM_EXEC}"
else
  chmod +x "${KOFAM_EXEC}" 2>/dev/null || true
fi

# ensure ruby available (we installed earlier, but check)
if ! run_env ruby -v >/dev/null 2>&1; then
  warn "ruby not available in odog_env; attempting install"
  conda install -n odog_env -y -c conda-forge ruby > "${LOGDIR}/conda_ruby_install.log" 2>&1 || die "Failed to install ruby"
fi
draw_progress $STEP $TOTAL_STEPS

# ---------- Run KOfam using explicit ruby from env ----------
STEP=$((STEP+1)); info "STEP $STEP/$TOTAL_STEPS: Run KOfam (exec_annotation via odog_env ruby)"
KOFAM_TSV="${OUTDIR}_kofam/${PREFIX}_kegg.tsv"
if [[ -f "${PROKKA_FAA}" && -x "${KOFAM_EXEC}" && -d "${KOFAM_PROFILES}" && -f "${KOFAM_KO_LIST}" ]]; then
  # run with conda-run invoking ruby explicitly to avoid shebang problems
  info "Running: conda run -n odog_env --no-capture-output ruby ${KOFAM_EXEC} -f detail-tsv -o ${KOFAM_TSV} -p ${KOFAM_PROFILES}/ -k ${KOFAM_KO_LIST} --cpu 4 ${PROKKA_FAA}"
  if ! conda run -n odog_env --no-capture-output ruby "${KOFAM_EXEC}" -f detail-tsv -o "${KOFAM_TSV}" -p "${KOFAM_PROFILES}/" -k "${KOFAM_KO_LIST}" --cpu 4 "${PROKKA_FAA}" > "${LOGDIR}/kofam.log" 2>&1 ; then
    warn "kofam returned non-zero (check ${LOGDIR}/kofam.log)"
  else
    info "KOfam completed -> ${KOFAM_TSV}"
  fi
else
  warn "Skipping KOfam: missing PROKKA_FAA or KOfam DB or exec"
fi
draw_progress $STEP $TOTAL_STEPS

# ---------- Filter high-confidence '*' ----------
STEP=$((STEP+1)); info "STEP $STEP/$TOTAL_STEPS: Filter KOfam high-confidence '*'"
KOFAM_FILTER="${OUTDIR}_kofam/${PREFIX}_kegg_filtered.tsv"
if [[ -f "${KOFAM_TSV}" ]]; then
  # use grep -P for PCRE ^\* ; if grep doesn't support -P fallback to awk
  if grep -P '^\*' "${KOFAM_TSV}" > "${KOFAM_FILTER}" 2>/dev/null; then
    :
  else
    awk '/^\*/{print}' "${KOFAM_TSV}" > "${KOFAM_FILTER}" || true
  fi
  if [[ ! -s "${KOFAM_FILTER}" ]]; then
    warn "Filtered KOfam empty (no '*' rows)"
  else
    info "Filtered -> ${KOFAM_FILTER}"
  fi
else
  warn "KOfam output TSV missing; cannot filter"
fi
draw_progress $STEP $TOTAL_STEPS

# ---------- Extract unique KO list ----------
STEP=$((STEP+1)); info "STEP $STEP/$TOTAL_STEPS: Extract KO ids"
KO_LIST="${OUTDIR}_kofam/${PREFIX}_KO_list.txt"
if [[ -f "${KOFAM_FILTER}" && -s "${KOFAM_FILTER}" ]]; then
  cut -f3 "${KOFAM_FILTER}" | sort -u > "${KO_LIST}" || true
  info "KO list -> ${KO_LIST}"
else
  warn "KOfam filtered file missing/empty; KO list not created"
fi
draw_progress $STEP $TOTAL_STEPS

# ---------- KO -> pathway mapping ----------
STEP=$((STEP+1)); info "STEP $STEP/$TOTAL_STEPS: KO -> pathway mapping"
KO_PATH_FILTERED="${OUTDIR}_kofam/${PREFIX}_ko_pathway_filtered.tab"
KO_PATH_CLEAN="${OUTDIR}_kofam/${PREFIX}_ko_pathway_clean.tsv"
if [[ -f "${KO_LIST}" && -f "${PATHWAY_DIR%/}/ko_to_pathway.tab" ]]; then
  grep -Ff "${KO_LIST}" "${PATHWAY_DIR%/}/ko_to_pathway.tab" > "${KO_PATH_FILTERED}" || true
  grep 'map' "${KO_PATH_FILTERED}" > "${KO_PATH_FILTERED}.map" || true
  sed 's/ko://; s/path://;' "${KO_PATH_FILTERED}.map" > "${KO_PATH_CLEAN}" || true
  info "KO->path mapping clean -> ${KO_PATH_CLEAN}"
else
  warn "KO list or ko_to_pathway.tab missing - cannot map"
fi
draw_progress $STEP $TOTAL_STEPS

# ---------- Add pathway titles ----------
STEP=$((STEP+1)); info "STEP $STEP/$TOTAL_STEPS: Add pathway titles"
KO_PATH_FINAL="${OUTDIR}_kofam/${PREFIX}_ko_pathway_final.tsv"
if [[ -f "${KO_PATH_CLEAN}" && -f "${PATHWAY_DIR%/}/pathway_titles.tab" ]]; then
  awk -F'\t' 'NR==FNR{title[$1]=$2;next}{print $1"\t"$2"\t"title[$2]}' "${PATHWAY_DIR%/}/pathway_titles.tab" "${KO_PATH_CLEAN}" > "${KO_PATH_FINAL}" || true
  info "KO pathway final -> ${KO_PATH_FINAL}"
else
  warn "KO_path_clean or pathway_titles.tab missing - skipping"
fi
draw_progress $STEP $TOTAL_STEPS

# ---------- Clean KOfam/Kegg table ----------
STEP=$((STEP+1)); info "STEP $STEP/$TOTAL_STEPS: Clean KOfam/Kegg table"
KOFAM_CLEAN_FINAL="${OUTDIR}_kofam/${PREFIX}_kegg_clean_final.tsv"
if [[ -f "${KOFAM_FILTER}" ]]; then
  awk -F'\t' '{ gsub(/"/,"",$7); print $2"\t"$3"\t"$7 }' "${KOFAM_FILTER}" > "${KOFAM_CLEAN_FINAL}" || true
  info "Kegg clean final -> ${KOFAM_CLEAN_FINAL}"
else
  warn "Filtered KOfam missing; skipping"
fi
draw_progress $STEP $TOTAL_STEPS

# ---------- Join KO with pathway into master ----------
STEP=$((STEP+1)); info "STEP $STEP/$TOTAL_STEPS: Join KO with pathways"
MASTER_Kegg_Path="${OUTDIR}_kofam/${PREFIX}_kegg_pathways.tsv"
if [[ -f "${KO_PATH_FINAL}" && -f "${KOFAM_CLEAN_FINAL}" ]]; then
  awk -F'\t' 'BEGIN{OFS="\t"} NR==FNR{map[$1]=$2"\t"$3; next} {print $0, (map[$2]?map[$2]:"NA\tNA")}' "${KO_PATH_FINAL}" "${KOFAM_CLEAN_FINAL}" > "${MASTER_Kegg_Path}" || true
  info "Joined master -> ${MASTER_Kegg_Path}"
else
  warn "Inputs to join missing; skipping join"
fi
draw_progress $STEP $TOTAL_STEPS

# ---------- Generate pathway counts (Step 14) ----------
STEP=$((STEP+1)); info "STEP $STEP/$TOTAL_STEPS: Generate pathway counts (KEGG-style)"
PATHWAY_COUNTS="${OUTDIR}_kofam/${PREFIX}_pathway_counts.tsv"
if [[ -f "${KO_PATH_FINAL}" ]]; then
  awk -F'\t' '{ count[$2]++; name[$2]=$3 } END { for (p in count) print p "\t" name[p] "\t" count[p] }' "${KO_PATH_FINAL}" | sort > "${PATHWAY_COUNTS}"
  info "Pathway counts -> ${PATHWAY_COUNTS}"
else
  warn "KO pathway final missing; cannot produce pathway counts"
fi
draw_progress $STEP $TOTAL_STEPS

info ""
info "Pipeline Successfully completed. Thank you for using Metabolic Pathway & Enzyme Annotation pipeline. Outputs (if created):"
info "Logs: ${LOGDIR}"
draw_progress $TOTAL_STEPS $TOTAL_STEPS

