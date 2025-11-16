#!/usr/bin/env python3

"""
Production-Level Genome Annotation Report Generator

This script creates a comprehensive, visually appealing HTML report
for prokaryotic genome annotation results.

Usage: python3 generate_single_report.py BASENAME
"""

import sys
import os
import re
from pathlib import Path
from datetime import datetime
import html

def safe_read_file(filepath):
    """Safely read a file and return its content, or None if it fails."""
    try:
        if os.path.exists(filepath) and os.path.getsize(filepath) > 0:
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                return f.read()
    except Exception as e:
        print(f"Warning: Could not read {filepath}: {e}")
    return None

def parse_prokka_stats(prokka_txt_path):
    """Parse Prokka statistics file."""
    stats = {}
    content = safe_read_file(prokka_txt_path)
    if not content:
        return stats
    
    for line in content.split('\n'):
        if ':' in line:
            key, value = line.split(':', 1)
            stats[key.strip()] = value.strip()
    
    return stats

def parse_prokka_gff(gff_path):
    """Parse Prokka GFF file and extract features."""
    features = []
    content = safe_read_file(gff_path)
    if not content:
        return features
    
    for line in content.split('\n'):
        if line.startswith('#') or not line.strip():
            continue
        
        parts = line.split('\t')
        if len(parts) >= 9:
            features.append({
                'seqid': parts[0],
                'source': parts[1],
                'type': parts[2],
                'start': parts[3],
                'end': parts[4],
                'score': parts[5],
                'strand': parts[6],
                'phase': parts[7],
                'attributes': parts[8]
            })
    
    return features

def parse_fasta(fasta_path, limit=20):
    """Parse FASTA file and return sequence records."""
    records = []
    content = safe_read_file(fasta_path)
    if not content:
        return records
    
    current_header = None
    current_seq = []
    
    for line in content.split('\n'):
        line = line.strip()
        if line.startswith('>'):
            if current_header:
                records.append({
                    'header': current_header,
                    'sequence': ''.join(current_seq)
                })
                if len(records) >= limit:
                    break
            current_header = line[1:]
            current_seq = []
        else:
            current_seq.append(line)
    
    if current_header and len(records) < limit:
        records.append({
            'header': current_header,
            'sequence': ''.join(current_seq)
        })
    
    return records

def parse_bed(bed_path, limit=50):
    """Parse BED file."""
    features = []
    content = safe_read_file(bed_path)
    if not content:
        return features
    
    for i, line in enumerate(content.split('\n')):
        if i >= limit or not line.strip():
            break
        
        parts = line.split('\t')
        if len(parts) >= 6:
            features.append({
                'chrom': parts[0],
                'start': parts[1],
                'end': parts[2],
                'name': parts[3],
                'score': parts[4],
                'strand': parts[5]
            })
    
    return features

def parse_trna_scan(trna_path):
    """Parse tRNAscan-SE output file."""
    results = []
    content = safe_read_file(trna_path)
    if not content:
        return results
    
    lines = content.split('\n')
    for line in lines:
        line = line.strip()
        if not line or line.startswith('Sequence') or line.startswith('Name') or line.startswith('---'):
            continue
        
        # tRNAscan output is space-delimited
        parts = line.split()
        if len(parts) >= 9:
            results.append({
                'sequence': parts[0],
                'trna_num': parts[1],
                'begin': parts[2],
                'end': parts[3],
                'type': parts[4],
                'anticodon': parts[5] if len(parts) > 5 else 'N/A',
                'intron_begin': parts[6] if len(parts) > 6 else '0',
                'intron_end': parts[7] if len(parts) > 7 else '0',
                'score': parts[8] if len(parts) > 8 else 'N/A'
            })
    
    return results

def parse_cmscan(cmscan_path, limit=50):
    """Parse cmscan table output."""
    results = []
    content = safe_read_file(cmscan_path)
    if not content:
        return results
    
    for i, line in enumerate(content.split('\n')):
        if line.startswith('#') or not line.strip():
            continue
        if len(results) >= limit:
            break
        
        parts = line.split()
        if len(parts) >= 18:
            results.append({
                'target': parts[0],
                'accession': parts[1],
                'query': parts[2],
                'e_value': parts[15],
                'score': parts[14],
                'bias': parts[16]
            })
    
    return results

def parse_hmmscan(hmmscan_path, limit=50):
    """Parse hmmscan domain table output."""
    results = []
    content = safe_read_file(hmmscan_path)
    if not content:
        return results
    
    for i, line in enumerate(content.split('\n')):
        if line.startswith('#') or not line.strip():
            continue
        if len(results) >= limit:
            break
        
        parts = line.split()
        if len(parts) >= 23:
            results.append({
                'target': parts[0],
                'accession': parts[1],
                'query': parts[3],
                'e_value': parts[12],
                'score': parts[13],
                'description': ' '.join(parts[22:]) if len(parts) > 22 else 'N/A'
            })
    
    return results

def parse_fimo_tsv(fimo_path, limit=100):
    """Parse FIMO TSV output."""
    results = []
    content = safe_read_file(fimo_path)
    if not content:
        return results
    
    lines = content.split('\n')
    for i, line in enumerate(lines):
        if i == 0 or not line.strip():  # Skip header
            continue
        if len(results) >= limit:
            break
        
        parts = line.split('\t')
        if len(parts) >= 9:
            results.append({
                'motif_id': parts[0],
                'motif_alt_id': parts[1],
                'sequence_name': parts[2],
                'start': parts[3],
                'stop': parts[4],
                'strand': parts[5],
                'score': parts[6],
                'p_value': parts[7],
                'q_value': parts[8],
                'matched_sequence': parts[9] if len(parts) > 9 else 'N/A'
            })
    
    return results

def italicize_species_name(text, basename):
    """Replace all instances of the genome name with italicized version."""
    # Try to extract genus and species from basename
    parts = basename.replace('_', ' ').split()
    if len(parts) >= 2:
        species_name = f"{parts[0]} {parts[1]}"
        text = text.replace(basename.replace('_', ' '), f"<em>{species_name}</em>")
        text = text.replace(basename, f"<em>{species_name}</em>")
    return text

def generate_html_report(basename):
    """Generate the complete HTML report."""
    
    # Define paths
    results_dir = Path(f"results/{basename}")
    prokka_dir = results_dir / "prokka_output"
    report_path = results_dir / f"{basename}_Annotation_Report.html"
    
    # Check if directories exist
    if not results_dir.exists():
        print(f"Error: Results directory not found: {results_dir}")
        return False
    
    # Parse all data files
    print(f"Parsing annotation data for {basename}...")
    
    prokka_stats = parse_prokka_stats(prokka_dir / f"{basename}.txt")
    prokka_features = parse_prokka_gff(prokka_dir / f"{basename}.gff")[:100]
    proteins = parse_fasta(prokka_dir / f"{basename}.faa", limit=20)
    cds_bed = parse_bed(prokka_dir / f"{basename}.cds.bed")
    upstream_seqs = parse_fasta(prokka_dir / f"{basename}.upstream.200.fa", limit=20)
    trna_results = parse_trna_scan(prokka_dir / f"{basename}.tRNAscan.out")
    cmscan_results = parse_cmscan(prokka_dir / f"{basename}.cmscan.tbl")
    hmmscan_results = parse_hmmscan(prokka_dir / f"{basename}.pfam.domtblout")
    fimo_results = parse_fimo_tsv(prokka_dir / "fimo_out" / "fimo.tsv")
    
    # Check for optional screenshots
    screenshot_dir = Path("report_assets")
    screenshots = {}
    if screenshot_dir.exists():
        for img_file in screenshot_dir.glob("*.png"):
            screenshots[img_file.stem] = img_file.name
    
    # Generate HTML
    species_name = basename.replace('_', ' ')
    
    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Annotation Report: {species_name}</title>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #2c3e50;
            line-height: 1.6;
            padding: 20px;
        }}
        
        .container {{
            max-width: 1400px;
            margin: 0 auto;
            background: #ffffff;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
            animation: fadeIn 0.8s ease-in;
        }}
        
        @keyframes fadeIn {{
            from {{ opacity: 0; transform: translateY(20px); }}
            to {{ opacity: 1; transform: translateY(0); }}
        }}
        
        header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 60px 40px;
            text-align: center;
            border-bottom: 8px solid #5a67d8;
            position: relative;
            overflow: hidden;
        }}
        
        header::before {{
            content: '';
            position: absolute;
            top: -50%;
            left: -50%;
            width: 200%;
            height: 200%;
            background: radial-gradient(circle, rgba(255,255,255,0.1) 0%, transparent 70%);
            animation: pulse 15s infinite;
        }}
        
        @keyframes pulse {{
            0%, 100% {{ transform: scale(1); }}
            50% {{ transform: scale(1.1); }}
        }}
        
        h1 {{
            font-size: 3em;
            font-weight: 700;
            margin-bottom: 15px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.2);
            position: relative;
            z-index: 1;
        }}
        
        .subtitle {{
            font-size: 1.3em;
            opacity: 0.95;
            font-weight: 300;
            position: relative;
            z-index: 1;
        }}
        
        .content {{
            padding: 40px;
        }}
        
        .section {{
            margin-bottom: 50px;
            background: linear-gradient(to right, #f8f9ff 0%, #fff 100%);
            padding: 30px;
            border-radius: 15px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.05);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }}
        
        .section:hover {{
            transform: translateY(-5px);
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }}
        
        h2 {{
            color: #5a67d8;
            font-size: 2em;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 3px solid #667eea;
            display: inline-block;
        }}
        
        h3 {{
            color: #764ba2;
            font-size: 1.5em;
            margin: 25px 0 15px 0;
        }}
        
        .stats-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 25px 0;
        }}
        
        .stat-card {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 25px;
            border-radius: 12px;
            text-align: center;
            box-shadow: 0 5px 15px rgba(102,126,234,0.3);
            transition: transform 0.3s ease;
        }}
        
        .stat-card:hover {{
            transform: scale(1.05);
        }}
        
        .stat-label {{
            font-size: 0.9em;
            opacity: 0.9;
            text-transform: uppercase;
            letter-spacing: 1px;
        }}
        
        .stat-value {{
            font-size: 2.5em;
            font-weight: bold;
            margin-top: 10px;
        }}
        
        table {{
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
            background: white;
            border-radius: 10px;
            overflow: hidden;
            box-shadow: 0 3px 10px rgba(0,0,0,0.05);
        }}
        
        thead {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }}
        
        th {{
            padding: 15px;
            text-align: left;
            font-weight: 600;
            text-transform: uppercase;
            font-size: 0.85em;
            letter-spacing: 1px;
        }}
        
        td {{
            padding: 12px 15px;
            border-bottom: 1px solid #e8e8e8;
            color: #2c3e50;
        }}
        
        tbody tr {{
            transition: background-color 0.2s ease;
        }}
        
        tbody tr:hover {{
            background-color: #f8f9ff;
        }}
        
        tbody tr:nth-child(even) {{
            background-color: #fafafa;
        }}
        
        .table-container {{
            max-height: 500px;
            overflow-y: auto;
            border-radius: 10px;
            margin: 20px 0;
        }}
        
        .table-container::-webkit-scrollbar {{
            width: 10px;
        }}
        
        .table-container::-webkit-scrollbar-track {{
            background: #f1f1f1;
            border-radius: 10px;
        }}
        
        .table-container::-webkit-scrollbar-thumb {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 10px;
        }}
        
        .no-data {{
            text-align: center;
            padding: 40px;
            color: #888;
            font-style: italic;
            font-size: 1.1em;
        }}
        
        .screenshot {{
            max-width: 100%;
            border-radius: 10px;
            box-shadow: 0 5px 20px rgba(0,0,0,0.2);
            margin: 20px 0;
            transition: transform 0.3s ease;
        }}
        
        .screenshot:hover {{
            transform: scale(1.02);
        }}
        
        .sequence {{
            background: #f5f5f5;
            padding: 15px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
            word-break: break-all;
            line-height: 1.8;
            color: #2c3e50;
            border-left: 4px solid #667eea;
        }}
        
        code {{
            background: #f5f5f5;
            padding: 2px 6px;
            border-radius: 4px;
            font-family: 'Courier New', monospace;
            color: #e83e8c;
        }}
        
        footer {{
            background: #2c3e50;
            color: white;
            padding: 30px;
            text-align: center;
        }}
        
        footer p {{
            margin: 5px 0;
            opacity: 0.9;
        }}
        
        .badge {{
            display: inline-block;
            padding: 5px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 600;
            margin: 2px;
        }}
        
        .badge-success {{
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            color: white;
        }}
        
        .badge-info {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }}
        
        .badge-warning {{
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            color: white;
        }}
        
        em {{
            font-style: italic;
            color: #764ba2;
            font-weight: 500;
        }}
        
        @media (max-width: 768px) {{
            h1 {{
                font-size: 2em;
            }}
            
            .content {{
                padding: 20px;
            }}
            
            .stats-grid {{
                grid-template-columns: 1fr;
            }}
            
            table {{
                font-size: 0.85em;
            }}
        }}
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🧬 Genome Annotation Report</h1>
            <p class="subtitle"><em>{species_name}</em></p>
        </header>
        
        <div class="content">
"""
    
    # Section 1: Overview
    html_content += """
            <div class="section">
                <h2>📊 Annotation Overview</h2>
"""
    
    if prokka_stats:
        html_content += '                <div class="stats-grid">\n'
        
        key_stats = ['organism', 'contigs', 'bases', 'CDS', 'rRNA', 'tRNA']
        for key in key_stats:
            for stat_key, stat_value in prokka_stats.items():
                if key.lower() in stat_key.lower():
                    html_content += f"""
                    <div class="stat-card">
                        <div class="stat-label">{html.escape(stat_key)}</div>
                        <div class="stat-value">{html.escape(stat_value)}</div>
                    </div>
"""
                    break
        
        html_content += '                </div>\n'
    else:
        html_content += '                <div class="no-data">No Prokka statistics found</div>\n'
    
    html_content += '            </div>\n'
    
    # Section 2: Gene Annotations
    html_content += """
            <div class="section">
                <h2>🧬 Gene Annotations</h2>
"""
    
    if prokka_features:
        html_content += """
                <div class="table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>Sequence ID</th>
                                <th>Type</th>
                                <th>Start</th>
                                <th>End</th>
                                <th>Strand</th>
                                <th>Attributes</th>
                            </tr>
                        </thead>
                        <tbody>
"""
        
        for feature in prokka_features:
            html_content += f"""
                            <tr>
                                <td>{html.escape(feature['seqid'])}</td>
                                <td><span class="badge badge-info">{html.escape(feature['type'])}</span></td>
                                <td>{html.escape(feature['start'])}</td>
                                <td>{html.escape(feature['end'])}</td>
                                <td>{html.escape(feature['strand'])}</td>
                                <td style="font-size: 0.85em;">{html.escape(feature['attributes'][:100])}...</td>
                            </tr>
"""
        
        html_content += """
                        </tbody>
                    </table>
                </div>
"""
    else:
        html_content += '                <div class="no-data">No gene annotations found</div>\n'
    
    html_content += '            </div>\n'
    
    # Section 3: Protein Sequences
    html_content += """
            <div class="section">
                <h2>🔬 Protein Sequences</h2>
"""
    
    if proteins:
        html_content += f'                <p>Showing {len(proteins)} of the annotated proteins:</p>\n'
        
        for i, protein in enumerate(proteins, 1):
            seq_preview = protein['sequence'][:100] + ('...' if len(protein['sequence']) > 100 else '')
            html_content += f"""
                <h3>Protein {i}: {html.escape(protein['header'][:80])}</h3>
                <div class="sequence">{html.escape(seq_preview)}</div>
"""
    else:
        html_content += '                <div class="no-data">No protein sequences found</div>\n'
    
    html_content += '            </div>\n'
    
    # Section 4: CDS Coordinates
    html_content += """
            <div class="section">
                <h2>📍 CDS Coordinates</h2>
"""
    
    if cds_bed:
        html_content += """
                <div class="table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>Chromosome</th>
                                <th>Start</th>
                                <th>End</th>
                                <th>Name</th>
                                <th>Strand</th>
                            </tr>
                        </thead>
                        <tbody>
"""
        
        for feature in cds_bed:
            html_content += f"""
                            <tr>
                                <td>{html.escape(feature['chrom'])}</td>
                                <td>{html.escape(feature['start'])}</td>
                                <td>{html.escape(feature['end'])}</td>
                                <td>{html.escape(feature['name'])}</td>
                                <td>{html.escape(feature['strand'])}</td>
                            </tr>
"""
        
        html_content += """
                        </tbody>
                    </table>
                </div>
"""
    else:
        html_content += '                <div class="no-data">No CDS coordinates found</div>\n'
    
    html_content += '            </div>\n'
    
    # Section 5: Upstream Sequences
    html_content += """
            <div class="section">
                <h2>⬆️ Upstream Sequences (200bp)</h2>
"""
    
    if upstream_seqs:
        html_content += f'                <p>Showing {len(upstream_seqs)} upstream sequences:</p>\n'
        
        for i, seq in enumerate(upstream_seqs, 1):
            seq_preview = seq['sequence'][:100] + ('...' if len(seq['sequence']) > 100 else '')
            html_content += f"""
                <h3>Upstream {i}: {html.escape(seq['header'][:80])}</h3>
                <div class="sequence">{html.escape(seq_preview)}</div>
"""
    else:
        html_content += '                <div class="no-data">No upstream sequences found</div>\n'
    
    html_content += '            </div>\n'
    
    # Section 6: tRNA Results
    html_content += """
            <div class="section">
                <h2>🧵 tRNA Scan Results</h2>
"""
    
    if trna_results:
        html_content += """
                <div class="table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>Sequence</th>
                                <th>tRNA #</th>
                                <th>Begin</th>
                                <th>End</th>
                                <th>Type</th>
                                <th>Anticodon</th>
                                <th>Score</th>
                            </tr>
                        </thead>
                        <tbody>
"""
        
        for trna in trna_results:
            html_content += f"""
                            <tr>
                                <td>{html.escape(trna['sequence'])}</td>
                                <td>{html.escape(trna['trna_num'])}</td>
                                <td>{html.escape(trna['begin'])}</td>
                                <td>{html.escape(trna['end'])}</td>
                                <td><span class="badge badge-success">{html.escape(trna['type'])}</span></td>
                                <td>{html.escape(trna['anticodon'])}</td>
                                <td>{html.escape(trna['score'])}</td>
                            </tr>
"""
        
        html_content += """
                        </tbody>
                    </table>
                </div>
"""
    else:
        html_content += '                <div class="no-data">No tRNA results found</div>\n'
    
    html_content += '            </div>\n'
    
    # Section 7: ncRNA Results
    html_content += """
            <div class="section">
                <h2>🎯 ncRNA Scan Results (cmscan)</h2>
"""
    
    if cmscan_results:
        html_content += """
                <div class="table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>Target</th>
                                <th>Accession</th>
                                <th>Query</th>
                                <th>E-value</th>
                                <th>Score</th>
                            </tr>
                        </thead>
                        <tbody>
"""
        
        for result in cmscan_results:
            html_content += f"""
                            <tr>
                                <td>{html.escape(result['target'])}</td>
                                <td>{html.escape(result['accession'])}</td>
                                <td>{html.escape(result['query'])}</td>
                                <td>{html.escape(result['e_value'])}</td>
                                <td>{html.escape(result['score'])}</td>
                            </tr>
"""
        
        html_content += """
                        </tbody>
                    </table>
                </div>
"""
    else:
        html_content += '                <div class="no-data">No ncRNA results found</div>\n'
    
    html_content += '            </div>\n'
    
    # Section 8: Transcription Factors
    html_content += """
            <div class="section">
                <h2>🔬 Transcription Factor Predictions (hmmscan)</h2>
"""
    
    if hmmscan_results:
        html_content += """
                <div class="table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>Target Domain</th>
                                <th>Accession</th>
                                <th>Protein Query</th>
                                <th>E-value</th>
                                <th>Score</th>
                                <th>Description</th>
                            </tr>
                        </thead>
                        <tbody>
"""
        
        for result in hmmscan_results:
            html_content += f"""
                            <tr>
                                <td><span class="badge badge-warning">{html.escape(result['target'])}</span></td>
                                <td>{html.escape(result['accession'])}</td>
                                <td>{html.escape(result['query'])}</td>
                                <td>{html.escape(result['e_value'])}</td>
                                <td>{html.escape(result['score'])}</td>
                                <td>{html.escape(result['description'][:60])}</td>
                            </tr>
"""
        
        html_content += """
                        </tbody>
                    </table>
                </div>
"""
    else:
        html_content += '                <div class="no-data">No transcription factor hits found</div>\n'
    
    html_content += '            </div>\n'
    
    # Section 9: Motif Locations (FIMO)
    html_content += """
            <div class="section">
                <h2>🎨 Regulatory Motif Locations (FIMO)</h2>
"""
    
    if fimo_results:
        html_content += """
                <div class="table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>Motif ID</th>
                                <th>Sequence Name</th>
                                <th>Start</th>
                                <th>Stop</th>
                                <th>Strand</th>
                                <th>Score</th>
                                <th>P-value</th>
                                <th>Q-value</th>
                                <th>Matched Sequence</th>
                            </tr>
                        </thead>
                        <tbody>
"""
        
        for result in fimo_results:
            html_content += f"""
                            <tr>
                                <td><span class="badge badge-info">{html.escape(result['motif_id'])}</span></td>
                                <td>{html.escape(result['sequence_name'][:30])}</td>
                                <td>{html.escape(result['start'])}</td>
                                <td>{html.escape(result['stop'])}</td>
                                <td>{html.escape(result['strand'])}</td>
                                <td>{html.escape(result['score'])}</td>
                                <td>{html.escape(result['p_value'])}</td>
                                <td>{html.escape(result['q_value'])}</td>
                                <td><code>{html.escape(result['matched_sequence'])}</code></td>
                            </tr>
"""
        
        html_content += """
                        </tbody>
                    </table>
                </div>
"""
    else:
        html_content += '                <div class="no-data">No motif locations found (MEME may have been skipped or found no significant motifs)</div>\n'
    
    html_content += '            </div>\n'
    
    # Section 10: Screenshots (if available)
    if screenshots:
        html_content += """
            <div class="section">
                <h2>📸 Pipeline Screenshots</h2>
"""
        
        for name, filename in screenshots.items():
            html_content += f"""
                <h3>{html.escape(name.replace('_', ' '))}</h3>
                <img src="../../../report_assets/{filename}" alt="{html.escape(name)}" class="screenshot">
"""
        
        html_content += '            </div>\n'
    
    # Footer
    html_content += f"""
        </div>
        
        <footer>
            <p><strong>Prokaryotic Genome Annotation Pipeline</strong></p>
            <p>Report generated on {datetime.now().strftime('%Y-%m-%d at %H:%M:%S')}</p>
            <p>Genome: <em>{species_name}</em></p>
        </footer>
    </div>
</body>
</html>
"""
    
    # Italicize species name throughout
    html_content = italicize_species_name(html_content, basename)
    
    # Write HTML file
    try:
        with open(report_path, 'w', encoding='utf-8') as f:
            f.write(html_content)
        print(f"✓ Report successfully generated: {report_path}")
        return True
    except Exception as e:
        print(f"✗ Error writing report: {e}")
        return False

def main():
    """Main entry point for the script."""
    if len(sys.argv) != 2:
        print("Usage: python3 generate_single_report.py BASENAME")
        sys.exit(1)
    
    basename = sys.argv[1]
    
    print(f"\n{'='*60}")
    print(f"Generating HTML Report for: {basename}")
    print(f"{'='*60}\n")
    
    success = generate_html_report(basename)
    
    if success:
        print(f"\n{'='*60}")
        print("Report generation completed successfully!")
        print(f"{'='*60}\n")
        sys.exit(0)
    else:
        print(f"\n{'='*60}")
        print("Report generation failed!")
        print(f"{'='*60}\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
