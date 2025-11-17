#!/bin/bash

#===============================================================================
# 🧬 PROKARYOTIC GENOME ANNOTATION PIPELINE v3.0 - NO DOCKER VERSION 🧬
# Fully automated - NO password prompts!
# Uses Conda Prokka instead of Docker
#===============================================================================

set -u  # Only exit on undefined variables

# ============================================================================
# 🎨 COLORS & EMOJIS
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;93m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

DNA="🧬"
GENE="🔬"
BACTERIA="🦠"
ROCKET="🚀"
CHECK="✅"
CROSS="❌"
WARNING="⚠️"
FIRE="🔥"
STAR="⭐"
CLOCK="⏰"
CHART="📊"
FOLDER="📁"
FILE="📄"
TOOLS="🛠️"
SUCCESS="🎉"
SEARCH="🔍"
COMPUTER="💻"
HOURGLASS="⏳"

# ============================================================================
# ⚙️ CONFIGURATION
# ============================================================================
INPUT_DIR="genomes_to_process"
OUTPUT_DIR="results"
DB_DIR="data/dbs"
LOG_DIR="logs"
UPSTREAM_LENGTH=200
CPU_CORES=6

mkdir -p "$OUTPUT_DIR" "$LOG_DIR"

# ============================================================================
# 📝 LOGGING FUNCTIONS
# ============================================================================
print_separator() {
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
}

print_double_separator() {
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════════╗${NC}"
}

print_banner() {
    clear
    echo ""
    print_double_separator
    echo -e "${MAGENTA}║${NC}                                                                      ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}     ${BOLD}${CYAN}${DNA}  PROKARYOTIC GENOME ANNOTATION PIPELINE v3.0  ${DNA}${NC}      ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}     ${WHITE}${BACTERIA} Fully Automated - NO Docker - NO Passwords ${BACTERIA}${NC}       ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}                                                                      ${MAGENTA}║${NC}"
    print_double_separator
    echo ""
}

log_step() {
    local step_num=$1
    local step_name=$2
    echo ""
    echo -e "${BOLD}${YELLOW}━━━ STEP ${step_num}/14: ${step_name} ${YELLOW}━━━${NC}"
}

log_info() {
    echo -e "${CYAN}${COMPUTER} [INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}${CHECK} [SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}${CROSS} [ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}${WARNING} [WARNING]${NC} $1"
}

log_processing() {
    echo -e "${MAGENTA}${HOURGLASS} [PROCESSING]${NC} $1"
}

log_searching() {
    echo -e "${CYAN}${SEARCH} [SCANNING]${NC} $1"
}

# ============================================================================
# 🧬 GENOME PROCESSING HEADER
# ============================================================================
print_genome_header() {
    local genome_name=$1
    local num=$2
    local total=$3
    
    echo ""
    echo ""
    print_double_separator
    echo -e "${MAGENTA}║${NC}                                                                      ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}   ${BOLD}${WHITE}${ROCKET} PROCESSING GENOME ${num} OF ${total}${NC}                                   ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}   ${CYAN}${DNA} Organism: ${genome_name}${NC}"
    echo -e "${MAGENTA}║${NC}                                                                      ${MAGENTA}║${NC}"
    print_double_separator
    echo ""
}

# ============================================================================
# 🧬 FASTA CLEANING FUNCTIONS
# ============================================================================
clean_fasta_headers() {
    local input_file=$1
    local output_file=$2
    
    log_processing "Cleaning FASTA headers and normalizing sequences..."
    
    awk '
    BEGIN { 
        contig_num = 0
        current_seq = ""
        current_header = ""
    }
    /^>/ {
        if (current_header != "") {
            print current_header
            print current_seq
        }
        contig_num++
        current_header = ">contig_" contig_num
        current_seq = ""
        next
    }
    {
        gsub(/[^ACGTNacgtn]/, "", $0)
        current_seq = current_seq $0
    }
    END {
        if (current_header != "") {
            print current_header
            print current_seq
        }
    }
    ' "$input_file" > "$output_file"
    
    if [ -s "$output_file" ]; then
        local num_seqs=$(grep -c "^>" "$output_file" 2>/dev/null || echo 0)
        local file_size=$(du -h "$output_file" 2>/dev/null | cut -f1 || echo "?")
        log_success "FASTA cleaned: ${num_seqs} contigs, ${file_size} total size"
        return 0
    else
        log_error "FASTA cleaning failed"
        return 1
    fi
}

clean_upstream_for_meme() {
    local input_fa=$1
    local output_fa=$2
    
    log_processing "Filtering upstream sequences for MEME (minimum 50bp required)..."
    
    awk '
    BEGIN { seq_count = 0; current_seq = ""; current_header = "" }
    /^>/ {
        if (length(current_seq) >= 50) {
            print current_header
            print current_seq
            seq_count++
        }
        current_header = ">upstream_" (seq_count + 1)
        current_seq = ""
        next
    }
    {
        gsub(/[^ACGTacgt]/, "N", $0)
        current_seq = current_seq toupper($0)
    }
    END {
        if (length(current_seq) >= 50) {
            print current_header
            print current_seq
            seq_count++
        }
    }
    ' "$input_fa" > "$output_fa"
    
    local seq_count=$(grep -c "^>" "$output_fa" 2>/dev/null || echo 0)
    
    if [ "$seq_count" -ge 3 ]; then
        log_success "Prepared ${seq_count} sequences for MEME motif discovery"
        return 0
    else
        log_warning "Only ${seq_count} sequences found (MEME requires at least 3)"
        return 1
    fi
}

# ============================================================================
# 🧬 MAIN GENOME PROCESSING FUNCTION (BULLETPROOF!)
# ============================================================================
process_single_genome() {
    local genome_file=$1
    local genome_num=$2
    local total_genomes=$3
    
    local filename=$(basename "$genome_file")
    local BASENAME="${filename%.*}"
    
    local genome_status="SUCCESS"
    
    print_genome_header "$BASENAME" "$genome_num" "$total_genomes"
    
    local OUTDIR="$OUTPUT_DIR/${BASENAME}"
    mkdir -p "$OUTDIR" || true
    
    local CLEAN_GENOME="$OUTDIR/${BASENAME}_clean.fna"
    local PROKKA_DIR="$OUTDIR/prokka_output"
    
    local start_time=$(date +%s)
    
    # ========================================================================
    # STEP 1: Clean FASTA
    # ========================================================================
    log_step "1" "FASTA Header Cleaning & Sequence Normalization ${DNA}"
    
    if clean_fasta_headers "$genome_file" "$CLEAN_GENOME"; then
        log_info "Original file: $(du -h "$genome_file" 2>/dev/null | cut -f1 || echo "?")"
        log_info "Cleaned file: $(du -h "$CLEAN_GENOME" 2>/dev/null | cut -f1 || echo "?")"
    else
        log_error "Cannot continue without cleaned FASTA. Skipping this genome."
        genome_status="FAILED"
        return 1
    fi
    
    # ========================================================================
    # STEP 2: Index Genome
    # ========================================================================
    log_step "2" "Genome Indexing with samtools faidx ${GENE}"
    
    log_processing "Creating genome index for fast sequence retrieval..."
    
    if samtools faidx "$CLEAN_GENOME" 2>"$LOG_DIR/${BASENAME}_samtools.log"; then
        local num_contigs=$(wc -l < "${CLEAN_GENOME}.fai" 2>/dev/null || echo 0)
        local total_bp=$(awk '{sum+=$2} END {print sum}' "${CLEAN_GENOME}.fai" 2>/dev/null || echo 0)
        local total_mbp=$(echo "scale=2; $total_bp/1000000" | bc 2>/dev/null || echo "?")
        log_success "Indexed ${num_contigs} contig(s), total size: ${total_mbp} Mbp"
    else
        log_error "Genome indexing failed"
        genome_status="FAILED"
        return 1
    fi
    
    # ========================================================================
    # STEP 3: Prokka Annotation (CONDA VERSION - NO DOCKER!)
    # ========================================================================
    log_step "3" "Gene Annotation with Prokka (Conda) ${BACTERIA}"
    
    log_info "Running Prokka annotation pipeline..."
    log_info "This step identifies: CDS, rRNA, tRNA, and other features"
    log_processing "Processing with ${CPU_CORES} CPU cores (may take 5-15 minutes)..."
    
    # Create output directory
    mkdir -p "$PROKKA_DIR"
    
    # Run Prokka directly (no Docker, no sudo!)
    if prokka \
        --outdir "$PROKKA_DIR" \
        --prefix "$BASENAME" \
        --cpus "$CPU_CORES" \
        --kingdom Bacteria \
        --force \
        "$CLEAN_GENOME" \
        > "$LOG_DIR/${BASENAME}_prokka_full.log" 2>&1; then
        
        if [ -f "$PROKKA_DIR/${BASENAME}.gff" ]; then
            local gene_count=$(grep -c "CDS" "$PROKKA_DIR/${BASENAME}.gff" 2>/dev/null || echo 0)
            local rrna_count=$(grep -c "rRNA" "$PROKKA_DIR/${BASENAME}.gff" 2>/dev/null || echo 0)
            local trna_count=$(grep -c "tRNA" "$PROKKA_DIR/${BASENAME}.gff" 2>/dev/null || echo 0)
            
            log_success "Prokka annotation completed!"
            log_info "${GENE} Genes (CDS): ${gene_count}"
            log_info "${DNA} rRNA genes: ${rrna_count}"
            log_info "${DNA} tRNA genes: ${trna_count}"
        else
            log_error "Prokka output file missing!"
            genome_status="FAILED"
            return 1
        fi
    else
        log_error "Prokka execution failed!"
        genome_status="FAILED"
        return 1
    fi
    
    # NO STEP 4 NEEDED! (No Docker = No permission issues!)
    log_info "${TOOLS} No permission fixes needed (Conda version)"
    
    # ========================================================================
    # STEP 5: Extract CDS
    # ========================================================================
    log_step "5" "Extracting Coding Sequences (CDS) ${GENE}"
    
    local CDS_BED="$PROKKA_DIR/${BASENAME}.cds.bed"
    
    log_processing "Converting GFF annotations to BED format..."
    
    awk '$3=="CDS"{
        OFS="\t";
        start=$4-1;
        if(start<0) start=0;
        split($9,a,";");
        id=a[1];
        gsub("ID=","",id);
        print $1, start, $5, id, ".", $7
    }' "$PROKKA_DIR/${BASENAME}.gff" > "$CDS_BED" 2>/dev/null || true
    
    if [ -s "$CDS_BED" ]; then
        local cds_count=$(wc -l < "$CDS_BED" 2>/dev/null || echo 0)
        log_success "Extracted ${cds_count} CDS features"
    else
        log_error "CDS extraction failed"
        genome_status="FAILED"
        return 1
    fi
    
    # ========================================================================
    # STEP 6-14: Rest of the steps remain EXACTLY the same
    # ========================================================================
    
    # STEP 6: Extract Upstream Sequences
    log_step "6" "Extracting Upstream Regulatory Regions ${DNA}"
    
    local UPSTREAM_BED="$PROKKA_DIR/${BASENAME}.upstream.bed"
    local UPSTREAM_FA="$PROKKA_DIR/${BASENAME}.upstream.${UPSTREAM_LENGTH}.fa"
    local UPSTREAM_CLEAN_FA="$PROKKA_DIR/${BASENAME}.upstream.${UPSTREAM_LENGTH}.clean.fa"
    
    log_processing "Extracting ${UPSTREAM_LENGTH}bp upstream of each gene..."
    
    if bedtools flank -i "$CDS_BED" -g "${CLEAN_GENOME}.fai" -l "$UPSTREAM_LENGTH" -r 0 -s > "$UPSTREAM_BED" 2>"$LOG_DIR/${BASENAME}_bedtools_flank.log"; then
        log_success "Generated upstream coordinates"
    else
        log_error "bedtools flank failed"
        genome_status="FAILED"
        return 1
    fi
    
    if bedtools getfasta -fi "$CLEAN_GENOME" -bed "$UPSTREAM_BED" -s -fo "$UPSTREAM_FA" 2>"$LOG_DIR/${BASENAME}_bedtools_getfasta.log"; then
        local seq_count=$(grep -c "^>" "$UPSTREAM_FA" 2>/dev/null || echo 0)
        log_success "Extracted ${seq_count} upstream sequences"
    else
        log_error "bedtools getfasta failed"
        genome_status="FAILED"
        return 1
    fi
    
    # STEP 7: tRNA Scanning
    log_step "7" "Scanning for tRNA Genes ${DNA}"
    
    local TRNA_OUT="$PROKKA_DIR/${BASENAME}.tRNAscan.out"
    
    log_searching "Running tRNAscan-SE in bacterial mode..."
    
    if tRNAscan-SE -B -o "$TRNA_OUT" "$CLEAN_GENOME" 2>"$LOG_DIR/${BASENAME}_tRNAscan.log"; then
        local trna_count=$(grep -cv "^-\|^Sequence\|^Name\|^---" "$TRNA_OUT" 2>/dev/null || echo 0)
        log_success "tRNA scan completed: ${trna_count} tRNAs identified"
    else
        log_warning "tRNAscan-SE encountered issues (non-critical)"
    fi
    
    # STEP 8: ncRNA Scanning
    log_step "8" "Scanning for Non-Coding RNAs ${DNA}"
    
    local CMSCAN_OUT="$PROKKA_DIR/${BASENAME}.cmscan.tbl"
    
    log_searching "Running cmscan against Rfam database with ${CPU_CORES} cores..."
    log_info "Searching for riboswitches, sRNAs, and regulatory RNAs..."
    
    if cmscan --cpu "$CPU_CORES" --tblout "$CMSCAN_OUT" "$DB_DIR/Rfam.cm" "$CLEAN_GENOME" > "$LOG_DIR/${BASENAME}_cmscan.log" 2>&1; then
        local ncrna_count=$(grep -cv "^#" "$CMSCAN_OUT" 2>/dev/null || echo 0)
        log_success "ncRNA scan completed: ${ncrna_count} hits found"
    else
        log_warning "cmscan had issues (non-critical)"
    fi
    
    # STEP 9: Transcription Factor Scanning
    log_step "9" "Scanning for Transcription Factors ${GENE}"
    
    local PROTEOME="$PROKKA_DIR/${BASENAME}.faa"
    local PFAM_OUT="$PROKKA_DIR/${BASENAME}.pfam.domtblout"
    
    log_searching "Running hmmscan against Pfam database with ${CPU_CORES} cores..."
    log_info "Identifying DNA-binding domains and regulatory proteins..."
    
    if [ -f "$PROTEOME" ]; then
        if hmmscan --cpu "$CPU_CORES" --domtblout "$PFAM_OUT" "$DB_DIR/Pfam-A.hmm" "$PROTEOME" > "$LOG_DIR/${BASENAME}_hmmscan.log" 2>&1; then
            local tf_count=$(grep -cv "^#" "$PFAM_OUT" 2>/dev/null || echo 0)
            log_success "Protein domain scan completed: ${tf_count} domain hits"
        else
            log_warning "hmmscan had issues (non-critical)"
        fi
    else
        log_warning "Proteome file not found, skipping hmmscan"
    fi
    
    # STEP 10: MEME Motif Discovery
    log_step "10" "Discovering Regulatory Motifs with MEME ${FIRE}"
    
    local MEME_DIR="$PROKKA_DIR/meme_out"
    local MEME_XML="$MEME_DIR/meme.xml"
    
    if ! clean_upstream_for_meme "$UPSTREAM_FA" "$UPSTREAM_CLEAN_FA"; then
        log_warning "Insufficient sequences for MEME - skipping motif discovery"
        mkdir -p "$MEME_DIR" || true
        echo "# MEME skipped: insufficient sequences" > "$MEME_DIR/meme.txt"
        
        log_info "Generating partial report without motif analysis..."
        python3 generate_single_report.py "$BASENAME" 2>/dev/null || log_warning "Report generation had issues"
        
        genome_status="PARTIAL"
        log_warning "Genome processed partially (no motif analysis)"
        return 0
    fi
    
    log_processing "Running MEME motif discovery with ${CPU_CORES} cores..."
    log_info "${FIRE} This is the most intensive step - may take 10-30 minutes!"
    log_info "MEME is searching for conserved DNA sequence patterns..."
    
    if meme "$UPSTREAM_CLEAN_FA" \
        -oc "$MEME_DIR" \
        -dna \
        -mod zoops \
        -nmotifs 10 \
        -minw 6 \
        -maxw 20 \
        -revcomp \
        -maxsize 1000000 \
        -p "$CPU_CORES" \
        > "$LOG_DIR/${BASENAME}_meme.log" 2>&1; then
        
        if [ -f "$MEME_XML" ]; then
            local motif_count=$(grep -c "<motif " "$MEME_XML" 2>/dev/null || echo 0)
            log_success "MEME completed: ${motif_count} motifs discovered!"
        else
            log_warning "MEME did not produce expected output"
            python3 generate_single_report.py "$BASENAME" 2>/dev/null || true
            genome_status="PARTIAL"
            return 0
        fi
    else
        log_warning "MEME execution encountered errors"
        python3 generate_single_report.py "$BASENAME" 2>/dev/null || true
        genome_status="PARTIAL"
        return 0
    fi
    
    # STEP 11: FIMO Motif Scanning
    log_step "11" "Scanning for Motif Occurrences with FIMO ${SEARCH}"
    
    local FIMO_DIR="$PROKKA_DIR/fimo_out"
    local FIMO_TSV="$FIMO_DIR/fimo.tsv"
    
    log_searching "Mapping discovered motifs across the genome..."
    
    if fimo --oc "$FIMO_DIR" --thresh 0.0001 "$MEME_XML" "$UPSTREAM_CLEAN_FA" > "$LOG_DIR/${BASENAME}_fimo.log" 2>&1; then
        if [ -f "$FIMO_TSV" ]; then
            local site_count=$(($(wc -l < "$FIMO_TSV" 2>/dev/null || echo 1) - 1))
            log_success "FIMO completed: ${site_count} regulatory sites identified"
        else
            log_error "FIMO output missing"
            genome_status="PARTIAL"
            return 0
        fi
    else
        log_error "FIMO execution failed"
        genome_status="PARTIAL"
        return 0
    fi
    
    # STEP 12: Convert FIMO to GFF
    log_step "12" "Converting FIMO Results to GFF Format ${FILE}"
    
    local FIMO_GFF="$PROKKA_DIR/${BASENAME}.fimo_upstream.gff"
    
    log_processing "Creating standardized GFF3 annotation file..."
    
    awk 'NR>1 && $9 != "nan" {
        printf "%s\tFIMO\tTF_binding_site\t%d\t%d\t%g\t%s\t.\tID=%s_%d;motif=%s;pvalue=%g;qvalue=%g\n",
        $3, $4, $5, $7, $6, $2, NR, $2, $8, $9
    }' "$FIMO_TSV" > "$FIMO_GFF" 2>/dev/null || true
    
    if [ -s "$FIMO_GFF" ]; then
        local gff_count=$(wc -l < "$FIMO_GFF" 2>/dev/null || echo 0)
        log_success "Created GFF with ${gff_count} regulatory elements"
    else
        log_warning "No significant motifs to convert (setting empty marker)"
        echo "# No significant motifs found" > "$FIMO_GFF"
    fi
    
    # STEP 13: Merge Annotations
    log_step "13" "Merging Annotations ${FOLDER}"
    
    local MERGED_GFF="$OUTDIR/${BASENAME}_regulatory_merged.gff"
    
    log_processing "Combining gene annotations with regulatory elements..."
    
    cat "$PROKKA_DIR/${BASENAME}.gff" "$FIMO_GFF" > "$MERGED_GFF" 2>/dev/null || true
    
    if [ -f "$MERGED_GFF" ]; then
        local merged_size=$(du -h "$MERGED_GFF" 2>/dev/null | cut -f1 || echo "?")
        log_success "Final annotation created: ${merged_size}"
    else
        log_error "Failed to merge annotations"
        genome_status="FAILED"
        return 1
    fi
    
    # STEP 14: Generate HTML Report
    log_step "14" "Generating Comprehensive HTML Report ${CHART}"
    
    log_processing "Creating interactive visualization and summary..."
    
    if python3 generate_single_report.py "$BASENAME" 2>/dev/null; then
        log_success "HTML report generated successfully!"
        log_info "${FOLDER} Report location: ${OUTDIR}/${BASENAME}_Annotation_Report.html"
    else
        log_warning "Report generation had minor issues"
    fi
    
    # ========================================================================
    # COMPLETION SUMMARY
    # ========================================================================
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    
    echo ""
    print_separator
    
    if [ "$genome_status" = "SUCCESS" ]; then
        echo -e "${GREEN}${SUCCESS} GENOME COMPLETED SUCCESSFULLY! ${SUCCESS}${NC}"
    elif [ "$genome_status" = "PARTIAL" ]; then
        echo -e "${YELLOW}${WARNING} GENOME PARTIALLY COMPLETED ${WARNING}${NC}"
    else
        echo -e "${RED}${CROSS} GENOME FAILED ${CROSS}${NC}"
    fi
    
    echo -e "${WHITE}Genome:${NC} ${CYAN}${BASENAME}${NC}"
    echo -e "${WHITE}Status:${NC} ${CYAN}${genome_status}${NC}"
    echo -e "${WHITE}Time:${NC} ${CYAN}${minutes}m ${seconds}s${NC}"
    echo -e "${WHITE}Output:${NC} ${CYAN}${OUTDIR}/${NC}"
    print_separator
    echo ""
    
    return 0
}

# ============================================================================
# 🚀 MAIN EXECUTION
# ============================================================================
main() {
    print_banner
    
    log_info "Pipeline started at $(date)"
    log_info "${COMPUTER} System: $(uname -s), CPU cores: ${CPU_CORES}"
    echo ""
    print_separator
    
    # Find all genomes
    log_searching "Scanning for genome files in ${INPUT_DIR}/..."
    
    local genome_files=()
    while IFS= read -r -d '' file; do
        genome_files+=("$file")
    done < <(find "$INPUT_DIR" -type f \( -name "*.fna" -o -name "*.fa" -o -name "*.fasta" \) -print0 | sort -z)
    
    local total_genomes=${#genome_files[@]}
    
    if [ $total_genomes -eq 0 ]; then
        log_error "No genome files found in ${INPUT_DIR}/"
        echo ""
        log_info "Please add FASTA files (.fna, .fa, or .fasta) to the input directory"
        exit 1
    fi
    
    log_success "Found ${total_genomes} genome(s) to process"
    echo ""
    
    log_info "${CHART} Genome list:"
    for i in "${!genome_files[@]}"; do
        local num=$((i + 1))
        local name=$(basename "${genome_files[$i]}")
        echo -e "  ${CYAN}${num}.${NC} ${name}"
    done
    
    echo ""
    print_separator
    log_info "${ROCKET} Starting batch processing..."
    print_separator
    
    # Process each genome
    local success_count=0
    local partial_count=0
    local failed_count=0
    local total_start=$(date +%s)
    
    for i in "${!genome_files[@]}"; do
        local genome_num=$((i + 1))
        
        if process_single_genome "${genome_files[$i]}" "$genome_num" "$total_genomes"; then
            ((success_count++)) || true
        else
            if [ -f "$OUTPUT_DIR/$(basename "${genome_files[$i]}" | sed 's/\.[^.]*$//')_Annotation_Report.html" ]; then
                ((partial_count++)) || true
            else
                ((failed_count++)) || true
            fi
        fi
        
        sleep 2
    done
    
    # ========================================================================
    # FINAL SUMMARY
    # ========================================================================
    local total_end=$(date +%s)
    local total_elapsed=$((total_end - total_start))
    local total_minutes=$((total_elapsed / 60))
    local total_seconds=$((total_elapsed % 60))
    
    echo ""
    echo ""
    print_double_separator
    echo -e "${MAGENTA}║${NC}                                                                      ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}          ${BOLD}${WHITE}${STAR} PIPELINE EXECUTION COMPLETE ${STAR}${NC}                       ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}                                                                      ${MAGENTA}║${NC}"
    print_double_separator
    echo ""
    echo -e "${BOLD}${WHITE}${CHART} FINAL SUMMARY:${NC}"
    print_separator
    echo -e "${WHITE}Total Genomes:${NC}          ${CYAN}${total_genomes}${NC}"
    echo -e "${GREEN}Fully Completed:${NC}        ${BOLD}${GREEN}${success_count}${NC}"
    echo -e "${YELLOW}Partially Completed:${NC}    ${BOLD}${YELLOW}${partial_count}${NC}"
    echo -e "${RED}Failed:${NC}                 ${BOLD}${RED}${failed_count}${NC}"
    echo -e "${WHITE}Total Time:${NC}             ${CYAN}${total_minutes}m ${total_seconds}s${NC}"
    echo -e "${WHITE}Average per Genome:${NC}     ${CYAN}$((total_elapsed / total_genomes / 60))m $((total_elapsed / total_genomes % 60))s${NC}"
    echo ""
    echo -e "${WHITE}${FOLDER} Results:${NC}   ${CYAN}${OUTPUT_DIR}/${NC}"
    echo -e "${WHITE}${FILE} Logs:${NC}      ${CYAN}${LOG_DIR}/${NC}"
    print_separator
    echo ""
    
    if [ $failed_count -eq 0 ] && [ $partial_count -eq 0 ]; then
        echo -e "${GREEN}${SUCCESS}${SUCCESS}${SUCCESS} ALL GENOMES PROCESSED SUCCESSFULLY! ${SUCCESS}${SUCCESS}${SUCCESS}${NC}"
    elif [ $failed_count -eq 0 ]; then
        echo -e "${YELLOW}${WARNING} Pipeline completed with some partial results ${WARNING}${NC}"
    else
        echo -e "${YELLOW}${WARNING} Pipeline completed with some failures ${WARNING}${NC}"
    fi
    
    echo ""
    log_info "Pipeline finished at $(date)"
    echo ""
}

# RUN THE PIPELINE!
main "$@"
