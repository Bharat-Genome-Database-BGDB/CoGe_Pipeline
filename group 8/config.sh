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
