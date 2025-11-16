#!/bin/bash

echo "🔍 Debugging Database Paths"
echo "==========================="

# Source the config
source config.sh

echo "Current directory: $(pwd)"
echo "DIAMOND_DB variable: $DIAMOND_DB"
echo "PFAM_DB variable: $PFAM_DB"

echo ""
echo "Checking if files exist:"
if [ -f "$DIAMOND_DB" ]; then
    echo "✅ DIAMOND database found: $DIAMOND_DB"
else
    echo "❌ DIAMOND database NOT found: $DIAMOND_DB"
fi

if [ -f "$PFAM_DB" ]; then
    echo "✅ Pfam database found: $PFAM_DB"
else
    echo "❌ Pfam database NOT found: $PFAM_DB"
fi

echo ""
echo "Files in databases directory:"
ls -la databases/
