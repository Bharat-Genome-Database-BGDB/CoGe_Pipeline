#!/bin/bash

echo "🔧 Setting up Automated Functional Annotation Pipeline"
echo "======================================================"

# Create directory structure
echo "📁 Creating directory structure..."
mkdir -p scripts
mkdir -p output/{prodigal,diamond,hmmer,combined}
mkdir -p logs reports preprocessed

# Make scripts executable
echo "🔧 Making scripts executable..."
chmod +x auto_pipeline.sh

# Check for required tools
echo "🔍 Checking for required tools..."
for tool in prodigal diamond hmmscan; do
    if command -v $tool &>/dev/null; then
        echo "   ✅ $tool"
    else
        echo "   ❌ $tool not found"
        echo "   Please install $tool before running the pipeline"
    fi
done

# Check for databases
echo "🔍 Checking for databases..."
if [ -f "databases/swissprot.dmnd" ]; then
    echo "   ✅ SwissProt database found"
else
    echo "   ❌ SwissProt database not found in databases/"
    echo "   Please ensure databases/swissprot.dmnd exists"
fi

if [ -f "databases/Pfam-A.hmm" ]; then
    echo "   ✅ Pfam database found"
else
    echo "   ❌ Pfam database not found in databases/"
    echo "   Please ensure databases/Pfam-A.hmm exists"
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "📋 NEXT STEPS:"
echo "1. Ensure your genome files are in 'genomes/' directory"
echo "2. Ensure your databases are in 'databases/' directory"
echo "3. Run the pipeline: ./auto_pipeline.sh"
echo ""
echo "💡 The pipeline will:"
echo "   - Skip existing files to avoid reprocessing"
echo "   - Use your existing databases (no downloads)"
echo "   - Generate all outputs in organized directories"
