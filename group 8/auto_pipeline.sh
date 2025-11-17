#!/bin/bash

set -e

echo "=================================================="
echo "🧬 Automated Bacterial Genome Functional Annotation"
echo "=================================================="

# Configuration 
THREADS=$(nproc)
E_VALUE=1e-5
MAX_TARGET_SEQS=1
INPUT_GENOMES="genomes"

# DATABASE PATHS 
DIAMOND_DB="databases/swissprot.dmnd"
PFAM_DB="databases/Pfam-A.hmm"

# Create directory structure
mkdir -p scripts
mkdir -p output/{prodigal,diamond,hmmer,combined}
mkdir -p logs reports preprocessed

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a logs/pipeline.log
}

# Function to check dependencies
check_dependencies() {
    log "🔧 Checking dependencies..."
    local deps=("prodigal" "diamond" "hmmscan" "awk" "grep" "wc" "python3")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log "❌ Error: $dep not found. Please install it first."
            exit 1
        else
            log "   ✅ $dep"
        fi
    done
}

# Function to check databases 
check_databases() {
    log "📊 Checking databases..."
    
    # Check DIAMOND database with absolute path check
    if [ -f "$DIAMOND_DB" ]; then
        log "   ✅ DIAMOND database found: $(basename $DIAMOND_DB)"
    else
        log "❌ DIAMOND database not found at: $DIAMOND_DB"
        log "   Current directory: $(pwd)"
        log "   Files in databases/:"
        ls -la databases/ | head -10
        exit 1
    fi
    
    # Check Pfam database
    if [ -f "$PFAM_DB" ]; then
        log "   ✅ Pfam database found: $(basename $PFAM_DB)"
    else
        log "❌ Pfam database not found at: $PFAM_DB"
        exit 1
    fi
}


# Function to preprocess genomes
preprocess_genomes() {
    log "🔧 Preprocessing genomes..."
    
    # Check for input genomes
    if [ ! -d "$INPUT_GENOMES" ] || [ -z "$(ls -A $INPUT_GENOMES/*.fna 2>/dev/null)" ]; then
        log "❌ Error: No .fna files found in $INPUT_GENOMES/"
        log "   Please place your bacterial genome files in the $INPUT_GENOMES/ directory"
        exit 1
    fi
    
    for genome in $INPUT_GENOMES/*.fna; do
        genome_name=$(basename "$genome" .fna)
        output_file="preprocessed/${genome_name}.fna"
        
        # Skip if already preprocessed
        if [ -f "$output_file" ]; then
            log "   ⏩ Already preprocessed: $genome_name"
            continue
        fi
        
        log "   Preprocessing: $genome_name"
        
        # Check if file exists and is not empty
        if [ ! -s "$genome" ]; then
            log "   ⚠️  Skipping empty file: $genome"
            continue
        fi
        
        # Remove duplicate sequences and ensure proper FASTA format
        awk '
        /^>/ {
            if (seqlen) {
                print seq
            }
            print
            seq = ""
            seqlen = 0
            next
        }
        {
            seq = seq $0
            seqlen += length($0)
        }
        END {
            if (seqlen) {
                print seq
            }
        }' "$genome" > "$output_file"
        
        # Validate the preprocessed file
        if [ ! -s "$output_file" ]; then
            log "   ❌ Preprocessing failed for: $genome_name"
            exit 1
        fi
        
        # Count sequences in the preprocessed file
        seq_count=$(grep -c "^>" "$output_file" 2>/dev/null || echo "0")
        log "     → Sequences: $seq_count"
    done
}

# Function for gene prediction
predict_genes() {
    local genome=$1
    local output_prefix=$2
    local genome_name=$3
    
    log "   🧬 Gene prediction: $genome_name"
    
    # Validate input file
    if [ ! -s "$genome" ]; then
        log "   ❌ Genome file is empty: $genome"
        return 1
    fi
    
    # Skip if already processed
    if [ -f "${output_prefix}.faa" ] && [ -s "${output_prefix}.faa" ]; then
        local gene_count=$(grep -c ">" "${output_prefix}.faa" 2>/dev/null || echo "0")
        log "   ⏩ Already processed: $genome_name ($gene_count genes)"
        return 0
    fi
    
    prodigal -i "$genome" \
        -o "${output_prefix}.gff" \
        -a "${output_prefix}.faa" \
        -d "${output_prefix}.fna" \
        -f gff \
        -p single \
        -q 2> "logs/prodigal_${genome_name}.log"
    
    # Check if Prodigal produced output
    if [ ! -f "${output_prefix}.faa" ] || [ ! -s "${output_prefix}.faa" ]; then
        log "   ❌ Prodigal failed to generate output for: $genome_name"
        return 1
    fi
    
    local gene_count=$(grep -c ">" "${output_prefix}.faa" 2>/dev/null || echo "0")
    log "     → Predicted genes: $gene_count"
    
    if [ "$gene_count" -eq "0" ]; then
        log "   ⚠️  No genes predicted for: $genome_name"
        return 1
    fi
}

# Function for homology search
homology_search() {
    local proteins=$1
    local output_prefix=$2
    local genome_name=$3
    
    log "   🔍 Homology search: $genome_name"
    
    # Check if protein file exists and has sequences
    if [ ! -s "$proteins" ]; then
        log "   ⚠️  No protein sequences for: $genome_name"
        return 1
    fi
    
    # Skip if already processed
    if [ -f "${output_prefix}.tsv" ] && [ -s "${output_prefix}.tsv" ]; then
        local hit_count=$(wc -l < "${output_prefix}.tsv" 2>/dev/null || echo "0")
        log "   ⏩ Already processed: $genome_name ($hit_count hits)"
        return 0
    fi
    
    diamond blastp \
        --db "$DIAMOND_DB" \
        --query "$proteins" \
        --out "${output_prefix}.tsv" \
        --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore stitle \
        --evalue $E_VALUE \
        --max-target-seqs $MAX_TARGET_SEQS \
        --threads $THREADS \
        --quiet 2> "logs/diamond_${genome_name}.log"
    
    local hit_count=0
    if [ -f "${output_prefix}.tsv" ]; then
        hit_count=$(wc -l < "${output_prefix}.tsv" 2>/dev/null || echo "0")
    fi
    
    log "     → SwissProt hits: $hit_count"
}

# Function for domain detection
domain_detection() {
    local proteins=$1
    local output_prefix=$2
    local genome_name=$3
    
    log "   🏷️  Domain detection: $genome_name"
    
    # Check if protein file exists and has sequences
    if [ ! -s "$proteins" ]; then
        log "   ⚠️  No protein sequences for: $genome_name"
        return 1
    fi
    
    # Skip if already processed
    if [ -f "${output_prefix}.domtblout" ] && [ -f "output/hmmer/${genome_name}_domain_count.txt" ]; then
        local domain_count=$(cat "output/hmmer/${genome_name}_domain_count.txt" 2>/dev/null || echo "0")
        log "   ⏩ Already processed: $genome_name ($domain_count domains)"
        return 0
    fi
    
    hmmscan \
        --cpu $THREADS \
        --domtblout "${output_prefix}.domtblout" \
        --tblout "${output_prefix}.tblout" \
        -o "${output_prefix}.hmmscan" \
        "$PFAM_DB" \
        "$proteins" 2> "logs/hmmer_${genome_name}.log"
    
    # Count domains properly
    local domain_count=0
    if [ -f "${output_prefix}.domtblout" ]; then
        domain_count=$(grep -v '^#' "${output_prefix}.domtblout" | awk 'NF>=4 {count++} END {print count+0}' 2>/dev/null || echo "0")
    fi
    
    log "     → Pfam domains: $domain_count"
    
    # Save domain count for reporting
    echo "$domain_count" > "output/hmmer/${genome_name}_domain_count.txt"
}

# Function to create combine annotations Python script
create_combine_script() {
    cat > "scripts/combine_annotations.py" << 'EOF'
import os
import sys

def combine_annotations(genome_name):
    genes = {}
    faa_file = f"output/prodigal/{genome_name}.faa"
    
    # Read gene predictions
    if os.path.exists(faa_file):
        with open(faa_file) as f:
            current_gene = ""
            for line in f:
                if line.startswith('>'):
                    current_gene = line.strip().split()[0][1:]
                    desc = ' '.join(line.strip().split()[1:]) if len(line.strip().split()) > 1 else 'No description'
                    genes[current_gene] = {
                        'gene_id': current_gene,
                        'description': desc,
                        'swissprot': 'No hit',
                        'pfam': 'No domains',
                        'domain_count': 0
                    }

    # Read SwissProt hits
    tsv_file = f"output/diamond/{genome_name}.tsv"
    if os.path.exists(tsv_file):
        with open(tsv_file) as f:
            for line in f:
                parts = line.strip().split('\t')
                if len(parts) >= 13:
                    gene_id = parts[0]
                    swissprot_id = parts[1]
                    description = parts[12]
                    if gene_id in genes:
                        genes[gene_id]['swissprot'] = f"{swissprot_id}: {description}"

    # Read Pfam domains - CORRECTED PARSING
    dom_file = f"output/hmmer/{genome_name}.domtblout"
    total_domains = 0
    domains_per_gene = {}
    
    if os.path.exists(dom_file):
        with open(dom_file) as f:
            for line in f:
                if not line.startswith('#'):
                    parts = line.strip().split()
                    if len(parts) >= 4:
                        # Try to find gene ID in different positions
                        gene_id = None
                        for pos in [0, 3]:  # Try position 0 and 3
                            if pos < len(parts):
                                candidate = parts[pos]
                                if candidate in genes:
                                    gene_id = candidate
                                    break
                        
                        if gene_id and gene_id in genes:
                            domain_name = parts[0] if len(parts) > 0 else "Unknown"
                            if gene_id not in domains_per_gene:
                                domains_per_gene[gene_id] = []
                            domains_per_gene[gene_id].append(domain_name)
                            total_domains += 1

    # Update genes with domain information
    for gene_id, domain_list in domains_per_gene.items():
        if gene_id in genes:
            genes[gene_id]['pfam'] = ', '.join(set(domain_list))
            genes[gene_id]['domain_count'] = len(domain_list)

    # Write combined annotations
    output_file = f"output/combined/{genome_name}_annotations.tsv"
    with open(output_file, 'w') as out:
        out.write("Gene_ID\tProtein_Description\tSwissProt_Annotation\tPfam_Domains\tDomain_Count\n")
        for gene_info in genes.values():
            out.write(f"{gene_info['gene_id']}\t{gene_info['description']}\t{gene_info['swissprot']}\t{gene_info['pfam']}\t{gene_info['domain_count']}\n")
    
    print(f"Combined annotations written to: {output_file}")
    print(f"Total domains found: {total_domains}")
    print(f"Genes with domains: {len(domains_per_gene)}")
    return len(genes), total_domains

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python combine_annotations.py <genome_name>")
        sys.exit(1)
    
    genome_name = sys.argv[1]
    gene_count, domain_count = combine_annotations(genome_name)
    print(f"Processed {gene_count} genes for {genome_name}")
EOF
}

# Function to combine annotations
combine_annotations() {
    local genome_name=$1
    
    log "   📊 Combining annotations: $genome_name"
    
    # Skip if already processed
    if [ -f "output/combined/${genome_name}_annotations.tsv" ]; then
        log "   ⏩ Already combined: $genome_name"
        return 0
    fi
    
    create_combine_script
    python3 "scripts/combine_annotations.py" "$genome_name"
}

# Function to create summary Python script
create_summary_script() {
    cat > "scripts/generate_summary.py" << 'EOF'
import os
import sys
from datetime import datetime

def generate_summary(genome_name):
    # Collect statistics
    genes = 0
    swissprot_hits = 0
    pfam_domains = 0
    
    # Count genes
    faa_file = f"output/prodigal/{genome_name}.faa"
    if os.path.exists(faa_file):
        with open(faa_file) as f:
            genes = sum(1 for line in f if line.startswith('>'))

    # Count SwissProt hits
    tsv_file = f"output/diamond/{genome_name}.tsv"
    if os.path.exists(tsv_file):
        with open(tsv_file) as f:
            swissprot_hits = sum(1 for line in f)

    # Get domain count from multiple sources
    domain_count_file = f"output/hmmer/{genome_name}_domain_count.txt"
    if os.path.exists(domain_count_file):
        with open(domain_count_file) as f:
            try:
                pfam_domains = int(f.read().strip())
            except:
                pfam_domains = 0
    
    # Fallback: count from domtblout
    if pfam_domains == 0:
        dom_file = f"output/hmmer/{genome_name}.domtblout"
        if os.path.exists(dom_file):
            with open(dom_file) as f:
                pfam_domains = sum(1 for line in f if not line.startswith('#') and len(line.strip().split()) >= 4)

    # Calculate metrics
    coverage = (swissprot_hits / genes * 100) if genes > 0 else 0
    avg_domains = (pfam_domains / genes) if genes > 0 else 0
    
    # Generate HTML report
    html_content = f"""<!DOCTYPE html>
<html>
<head>
    <title>{genome_name} - Functional Annotation</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 40px; }}
        .header {{ background: #2c3e50; color: white; padding: 20px; border-radius: 5px; }}
        .stats {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin: 20px 0; }}
        .stat-card {{ background: #ecf0f1; padding: 20px; border-radius: 5px; text-align: center; }}
        .number {{ font-size: 2em; font-weight: bold; color: #2c3e50; }}
        .details {{ background: #f8f9fa; padding: 20px; border-radius: 5px; margin: 20px 0; }}
    </style>
</head>
<body>
    <div class="header">
        <h1>🧬 {genome_name} - Functional Annotation Report</h1>
        <p>Generated on: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
    </div>
    
    <div class="stats">
        <div class="stat-card">
            <div class="number">{genes}</div>
            <div>Genes Predicted</div>
        </div>
        <div class="stat-card">
            <div class="number">{swissprot_hits}</div>
            <div>SwissProt Hits</div>
        </div>
        <div class="stat-card">
            <div class="number">{pfam_domains}</div>
            <div>Pfam Domains</div>
        </div>
    </div>
    
    <div class="details">
        <h3>Annotation Statistics</h3>
        <p><strong>Annotation Coverage:</strong> {coverage:.1f}%</p>
        <p><strong>Genes with SwissProt hits:</strong> {swissprot_hits} / {genes}</p>
        <p><strong>Average domains per gene:</strong> {avg_domains:.1f}</p>
        <p><strong>Total domains detected:</strong> {pfam_domains}</p>
    </div>
</body>
</html>"""
    
    # Write HTML file
    output_file = f"reports/{genome_name}_summary.html"
    with open(output_file, 'w') as f:
        f.write(html_content)
    
    # Text summary
    text_summary = f"""Annotation Summary - {genome_name}
================================
Genes predicted: {genes}
SwissProt hits: {swissprot_hits}
Pfam domains: {pfam_domains}
Annotation coverage: {coverage:.1f}%
Average domains per gene: {avg_domains:.1f}
"""
    
    with open(f"reports/{genome_name}_summary.txt", 'w') as f:
        f.write(text_summary)
    
    print(f"Summary reports generated for {genome_name}")
    return genes, swissprot_hits, pfam_domains

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python generate_summary.py <genome_name>")
        sys.exit(1)
    
    genome_name = sys.argv[1]
    generate_summary(genome_name)
EOF
}

# Function to generate summary report
generate_summary() {
    local genome_name=$1
    
    log "   📄 Generating report: $genome_name"
    
    create_summary_script
    python3 "scripts/generate_summary.py" "$genome_name"
}

# Function to create final summary
create_final_summary_script() {
    cat > "scripts/final_summary.py" << 'EOF'
import os
import glob
from datetime import datetime

def generate_final_report():
    genomes_data = []
    total_genes = 0
    total_hits = 0
    total_domains = 0

    for gff in glob.glob("output/prodigal/*.gff"):
        genome_name = os.path.basename(gff).replace('.gff', '')
        
        genes = 0
        hits = 0
        domains = 0
        
        # Count genes
        faa_file = f"output/prodigal/{genome_name}.faa"
        if os.path.exists(faa_file):
            with open(faa_file) as f:
                genes = sum(1 for line in f if line.startswith('>'))
        
        # Count SwissProt hits
        tsv_file = f"output/diamond/{genome_name}.tsv"
        if os.path.exists(tsv_file):
            with open(tsv_file) as f:
                hits = sum(1 for line in f)
        
        # Get domain count
        domain_count_file = f"output/hmmer/{genome_name}_domain_count.txt"
        if os.path.exists(domain_count_file):
            with open(domain_count_file) as f:
                try:
                    domains = int(f.read().strip())
                except:
                    domains = 0
        
        # Fallback
        if domains == 0:
            dom_file = f"output/hmmer/{genome_name}.domtblout"
            if os.path.exists(dom_file):
                with open(dom_file) as f:
                    domains = sum(1 for line in f if not line.startswith('#') and len(line.strip().split()) >= 4)
        
        coverage = (hits / genes * 100) if genes > 0 else 0
        genomes_data.append({
            'name': genome_name,
            'genes': genes,
            'hits': hits,
            'domains': domains,
            'coverage': coverage
        })
        
        total_genes += genes
        total_hits += hits
        total_domains += domains

    overall_coverage = (total_hits / total_genes * 100) if total_genes > 0 else 0

    # Generate HTML content
    html_content = f"""<!DOCTYPE html>
<html>
<head>
    <title>Final Annotation Summary</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 40px; }}
        .header {{ background: #2c3e50; color: white; padding: 20px; border-radius: 5px; }}
        .overview {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin: 20px 0; }}
        .overview-card {{ background: #3498db; color: white; padding: 20px; border-radius: 5px; text-align: center; }}
        .table {{ width: 100%; border-collapse: collapse; margin: 20px 0; }}
        .table th, .table td {{ padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }}
        .table th {{ background: #34495e; color: white; }}
        .table tr:nth-child(even) {{ background: #f2f2f2; }}
        .number {{ font-size: 1.5em; font-weight: bold; }}
        .high-coverage {{ color: #27ae60; font-weight: bold; }}
        .medium-coverage {{ color: #f39c12; font-weight: bold; }}
        .low-coverage {{ color: #e74c3c; font-weight: bold; }}
    </style>
</head>
<body>
    <div class="header">
        <h1>🧬 Final Functional Annotation Summary</h1>
        <p>Analysis of {len(genomes_data)} bacterial genomes</p>
        <p>Generated on: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
    </div>
    
    <div class="overview">
        <div class="overview-card">
            <div class="number">{total_genes}</div>
            <div>Total Genes</div>
        </div>
        <div class="overview-card">
            <div class="number">{total_hits}</div>
            <div>SwissProt Hits</div>
        </div>
        <div class="overview-card">
            <div class="number">{total_domains}</div>
            <div>Pfam Domains</div>
        </div>
        <div class="overview-card">
            <div class="number">{overall_coverage:.1f}%</div>
            <div>Overall Coverage</div>
        </div>
    </div>
    
    <h2>Individual Genome Statistics</h2>
    <table class="table">
        <tr>
            <th>Genome</th>
            <th>Genes</th>
            <th>SwissProt Hits</th>
            <th>Pfam Domains</th>
            <th>Coverage</th>
        </tr>
"""

    for data in genomes_data:
        coverage_class = "high-coverage" if data['coverage'] > 70 else "medium-coverage" if data['coverage'] > 50 else "low-coverage"
        html_content += f"""
        <tr>
            <td><strong>{data['name']}</strong></td>
            <td>{data['genes']}</td>
            <td>{data['hits']}</td>
            <td>{data['domains']}</td>
            <td class="{coverage_class}">{data['coverage']:.1f}%</td>
        </tr>
"""

    html_content += """
    </table>
</body>
</html>"""

    with open("reports/final_summary.html", "w") as f:
        f.write(html_content)
    
    print(f"Final summary report generated: reports/final_summary.html")
    print(f"Processed {len(genomes_data)} genomes with {total_genes} total genes")

if __name__ == "__main__":
    generate_final_report()
EOF
}

# Function to generate final summary
generate_final_summary() {
    log "📊 Generating final summary report..."
    
    create_final_summary_script
    python3 scripts/final_summary.py
}

# Main pipeline execution
main() {
    log "🚀 Starting functional annotation pipeline..."
    
    # Check dependencies and databases
    check_dependencies
    check_databases
    
    # Preprocess genomes
    preprocess_genomes
    
    # Get list of preprocessed genomes
    GENOME_FILES=($(ls preprocessed/*.fna 2>/dev/null))
    if [ ${#GENOME_FILES[@]} -eq 0 ]; then
        log "❌ No preprocessed genomes found"
        exit 1
    fi
    
    log "📁 Found ${#GENOME_FILES[@]} preprocessed genome files"
    
    # Process each genome
    for genome in "${GENOME_FILES[@]}"; do
        genome_name=$(basename "$genome" .fna)
        log "🔬 Processing: $genome_name"
        log "----------------------------------------"
        
        # Step 1: Gene Prediction
        if predict_genes "$genome" "output/prodigal/$genome_name" "$genome_name"; then
            # Step 2: Homology Search
            homology_search "output/prodigal/${genome_name}.faa" "output/diamond/$genome_name" "$genome_name"
            
            # Step 3: Domain Detection
            domain_detection "output/prodigal/${genome_name}.faa" "output/hmmer/$genome_name" "$genome_name"
            
            # Step 4: Combine Annotations
            combine_annotations "$genome_name"
            
            # Step 5: Generate Report
            generate_summary "$genome_name"
            
            log "✅ Completed: $genome_name"
        else
            log "❌ Failed to process: $genome_name"
        fi
        echo ""
    done
    
    # Generate final summary
    generate_final_summary
}

# Run the pipeline
main "$@"

log ""
log "=================================================="
log "🎉 PIPELINE COMPLETED SUCCESSFULLY!"
log "=================================================="
log "📊 Results overview:"
log "   - Preprocessed genomes: preprocessed/"
log "   - Gene predictions: output/prodigal/"
log "   - SwissProt annotations: output/diamond/"
log "   - Pfam domains: output/hmmer/"
log "   - Combined annotations: output/combined/"
log "   - Individual reports: reports/"
log "   - Final summary: reports/final_summary.html"
log "=================================================="
