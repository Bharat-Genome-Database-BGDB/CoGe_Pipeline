#!/bin/bash

set -e

echo "🔧 Automated Bacterial Genome Annotation Pipeline Setup"
echo "======================================================"

# Create directory structure
echo "📁 Creating directory structure..."
mkdir -p scripts
mkdir -p output/{prodigal,diamond,hmmer,combined}
mkdir -p logs reports preprocessed genomes databases

# Make scripts executable
echo "🔧 Making scripts executable..."
chmod +x auto_pipeline.sh

# Check for required tools
echo "🔍 Checking for required tools..."
for tool in prodigal diamond hmmscan wget curl; do
    if command -v $tool &>/dev/null; then
        echo "   ✅ $tool"
    else
        echo "   ❌ $tool not found"
        if [ "$tool" != "wget" ] && [ "$tool" != "curl" ]; then
            echo "   Please install $tool before running the pipeline"
        fi
    fi
done

# Download SwissProt database if not exists
echo "📥 Downloading SwissProt database..."
if [ ! -f "databases/swissprot.dmnd" ]; then
    echo "   Downloading SwissProt fasta..."
    if command -v wget &>/dev/null; then
        wget -q -O databases/uniprot_sprot.fasta.gz "https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/uniprot_sprot.fasta.gz"
    else
        curl -s -o databases/uniprot_sprot.fasta.gz "https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/complete/uniprot_sprot.fasta.gz"
    fi
    
    echo "   Extracting and formatting database..."
    gunzip -c databases/uniprot_sprot.fasta.gz > databases/uniprot_sprot.fasta
    diamond makedb --in databases/uniprot_sprot.fasta -d databases/swissprot
    rm databases/uniprot_sprot.fasta.gz databases/uniprot_sprot.fasta
    echo "   ✅ SwissProt database created"
else
    echo "   ✅ SwissProt database already exists"
fi

# Download Pfam database if not exists
echo "📥 Downloading Pfam database..."
if [ ! -f "databases/Pfam-A.hmm" ]; then
    echo "   Downloading Pfam database..."
    if command -v wget &>/dev/null; then
        wget -q -O databases/Pfam-A.hmm.gz "https://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/Pfam-A.hmm.gz"
    else
        curl -s -o databases/Pfam-A.hmm.gz "https://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/Pfam-A.hmm.gz"
    fi
    
    echo "   Extracting database..."
    gunzip databases/Pfam-A.hmm.gz
    echo "   ✅ Pfam database downloaded"
else
    echo "   ✅ Pfam database already exists"
fi

# Create config file
echo "⚙️  Creating configuration file..."
cat > config.sh << 'EOF'
#!/bin/bash

# Tool paths
PRODIGAL="prodigal"
DIAMOND="diamond"
HMMSCAN="hmmscan"

# Database paths 
DIAMOND_DB="databases/swissprot.dmnd"  
PFAM_DB="databases/Pfam-A.hmm"         

# Parameters
THREADS=$(nproc)
E_VALUE=1e-5
MAX_TARGET_SEQS=1

# Directories
INPUT_GENOMES="genomes"
EOF

echo ""
echo "✅ Setup complete!"
echo ""
echo "📋 NEXT STEPS:"
echo "1. Place your genome files (.fna format) in the 'genomes/' directory"
echo "2. Run the pipeline: ./auto_pipeline.sh"
echo ""
echo "💡 Database Information:"
echo "   - SwissProt: $(ls -lh databases/swissprot.dmnd 2>/dev/null | awk '{print $5 " MB"}' || echo "Not found")"
echo "   - Pfam: $(ls -lh databases/Pfam-A.hmm 2>/dev/null | awk '{print $5 " MB"}' || echo "Not found")"
