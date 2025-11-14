#!/bin/bash
set -e

echo "====================================="
echo " Installing Selected Bioinfo Tools"
echo "====================================="

sudo apt update -y
sudo apt install -y wget unzip git python3 python3-pip build-essential perl hmmer ncbi-blast+

echo "-------------------------------------"
echo " Installing FASTQC"
echo "-------------------------------------"
wget https://www.bioinformatics.babraham.ac.uk/projects/fastqc/fastqc_v0.12.1.zip
unzip fastqc_v0.12.1.zip
sudo mv FastQC /usr/local/bin/fastqc
sudo chmod +x /usr/local/bin/fastqc/fastqc

echo "-------------------------------------"
echo " Installing FASTP"
echo "-------------------------------------"
wget http://opengene.org/fastp/fastp
chmod +x fastp
sudo mv fastp /usr/local/bin/

echo "-------------------------------------"
echo " Installing MULTIQC"
echo "-------------------------------------"
pip install multiqc

echo "-------------------------------------"
echo " Installing SPAdes"
echo "-------------------------------------"
wget http://cab.spbu.ru/files/release3.15.5/SPAdes-3.15.5-Linux.tar.gz
tar -xzf SPAdes-3.15.5-Linux.tar.gz
sudo mv SPAdes-3.15.5-Linux /usr/local/bin/spades
sudo ln -s /usr/local/bin/spades/bin/spades.py /usr/local/bin/spades.py

echo "-------------------------------------"
echo " Installing QUAST"
echo "-------------------------------------"
wget https://github.com/ablab/quast/releases/download/quast_5.2.0/quast-5.2.0.tar.gz
tar -xzf quast-5.2.0.tar.gz
sudo mv quast-5.2.0 /usr/local/bin/quast
sudo ln -s /usr/local/bin/quast/quast.py /usr/local/bin/quast.py

echo "-------------------------------------"
echo " Installing PROKKA"
echo "-------------------------------------"
sudo apt install -y parallel bioperl
git clone https://github.com/tseemann/prokka.git
cd prokka
sudo make install
cd ..

echo "-------------------------------------"
echo " Installing DIAMOND"
echo "-------------------------------------"
wget https://github.com/bbuchfink/diamond/releases/download/v2.1.8/diamond-linux64.tar.gz
tar -xzf diamond-linux64.tar.gz
sudo mv diamond /usr/local/bin/diamond

echo "-------------------------------------"
echo " Installing SIGNALP 6"
echo "-------------------------------------"
pip install signalp-6-package

echo "-------------------------------------"
echo " Installing TMHMM 2"
echo "-------------------------------------"
wget https://services.healthtech.dtu.dk/services/TMHMM-2.0/TMHMM2.0c.Linux.tar.gz
tar -xzf TMHMM2.0c.Linux.tar.gz
sudo mv tmhmm-2.0c /usr/local/bin/tmhmm

echo "-------------------------------------"
echo " Installing AMRFinderPlus"
echo "-------------------------------------"
mkdir amrfinder_install
cd amrfinder_install
wget https://ftp.ncbi.nlm.nih.gov/pathogen/Antimicrobial_resistance/AMRFinderPlus/latest/amrfinder-linux-latest.tar.gz
tar -xzf amrfinder-linux-latest.tar.gz
sudo mv amrfinder* /usr/local/bin/amrfinder
sudo /usr/local/bin/amrfinder/amrfinder --update
cd ..

echo "====================================="
echo " Installation Complete!"
echo "====================================="
