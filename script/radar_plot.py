import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from math import pi
import os
import argparse

def create_radar_plot(data_dict, title, color, ax):
    """
    Crea un radar plot per i dati forniti
    
    Parameters:
    - data_dict: dizionario con etichette e valori
    - title: titolo del grafico
    - color: colore del grafico
    - ax: asse matplotlib
    """
    # Ordine personalizzato delle categorie
    desired_order = [
        'Semantic', 'Phonological', 'Speech Arrest', 'Motor', 
        'Movement Arrest', 'Sensorial', 'Visual', 'Spatial Perception', 
        'Mentalizing', 'Anomia'
    ]
    
    # Funzione per mappare nomi simili
    def find_matching_key(desired_key, available_keys):
        # Cerca corrispondenza esatta prima
        if desired_key in available_keys:
            return desired_key
        
        # Cerca corrispondenze parziali
        for key in available_keys:
            if desired_key.lower() in key.lower() or key.lower() in desired_key.lower():
                return key
        return None
    
    # Riordina i dati secondo l'ordine desiderato
    ordered_data = {}
    available_keys = list(data_dict.keys())
    
    # Prima aggiungi le categorie nell'ordine desiderato
    for desired_key in desired_order:
        matching_key = find_matching_key(desired_key, available_keys)
        if matching_key:
            ordered_data[matching_key] = data_dict[matching_key]
            available_keys.remove(matching_key)
    
    # Poi aggiungi eventuali categorie rimanenti
    for remaining_key in available_keys:
        # Salta categorie che sembrano essere varianti di quelle già incluse
        if not any(remaining_key.lower() in existing.lower() for existing in ordered_data.keys()):
            ordered_data[remaining_key] = data_dict[remaining_key]
    
    # Prepara i dati riordinati
    categories = list(ordered_data.keys())
    values = list(ordered_data.values())
    
    print(f"   🔄 Ordine finale per {title}: {categories}")
    
    # Numero di variabili
    N = len(categories)
    
    # Calcola gli angoli per ogni asse
    angles = [n / float(N) * 2 * pi for n in range(N)]
    angles += angles[:1]  # Chiude il cerchio
    
    # Aggiungi il primo valore alla fine per chiudere il poligono
    values += values[:1]
    
    # Plot
    ax.set_theta_offset(pi / 2)
    ax.set_theta_direction(-1)
    
    # Disegna il radar plot con stile migliorato
    ax.plot(angles, values, 'o-', linewidth=3, label=title, color=color, markersize=8)
    ax.fill(angles, values, alpha=0.25, color=color)
    
    # Aggiungi le etichette delle categorie con styling migliorato
    ax.set_xticks(angles[:-1])
    ax.set_xticklabels(categories, fontsize=15, fontweight='bold')
    
    # Migliora la distanza delle etichette manualmente - aumentato molto per evitare sovrapposizioni
    ax.tick_params(axis='x', which='major', pad=55)
    
    # Aggiungi le linee della griglia con stile migliorato
    ax.set_ylim(0, 1)
    ax.set_yticks(np.arange(0, 1.1, 0.2))
    ax.set_yticklabels([f'{x:.1f}' for x in np.arange(0, 1.1, 0.2)], fontsize=10)
    ax.grid(True, alpha=0.6, linewidth=0.8)
    
    # Titolo
    ax.set_title(title, size=16, weight='bold', pad=25)

def load_and_process_data(gm_file, wm_file):
    """
    Carica e processa i dati dai file CSV
    
    Parameters:
    - gm_file: path del file CSV per materia grigia
    - wm_file: path del file CSV per materia bianca
    
    Returns:
    - gm_data: dizionario con i dati GM processati
    - wm_data: dizionario con i dati WM processati
    """
    print(f"🔍 Controllo esistenza file GM: {gm_file}")
    print(f"   Esiste? {os.path.exists(gm_file)}")
    
    print(f"🔍 Controllo esistenza file WM: {wm_file}")
    print(f"   Esiste? {os.path.exists(wm_file)}")
    
    if not os.path.exists(gm_file):
        raise FileNotFoundError(f"File GM non trovato: {gm_file}")
    if not os.path.exists(wm_file):
        raise FileNotFoundError(f"File WM non trovato: {wm_file}")
    
    # Carica i dati
    print("📖 Caricamento file GM...")
    gm_df = pd.read_csv(gm_file)
    print(f"   Shape GM: {gm_df.shape}")
    print(f"   Colonne GM: {list(gm_df.columns[:5])}...")
    
    print("📖 Caricamento file WM...")
    wm_df = pd.read_csv(wm_file)
    print(f"   Shape WM: {wm_df.shape}")
    print(f"   Colonne WM: {list(wm_df.columns[:5])}...")
    
    # Funzione per pulire i nomi delle colonne
    def clean_column_names(columns):
        cleaned = []
        for col in columns:
            # Salta colonne non valide: vuote, template, unnamed, o indici
            if (col == '' or 
                'template' in col.lower() or 
                'unnamed' in col.lower() or 
                col.isdigit()):
                print(f"   ⏭️  Saltando colonna: '{col}'")
                continue
            
            # Rimuovi .nii.gz e sostituisci underscore con spazi
            clean_name = col.replace('.nii.gz', '').replace('_', ' ')
            # Capitalizza le parole
            clean_name = ' '.join(word.capitalize() for word in clean_name.split())
            cleaned.append((col, clean_name))
            print(f"   ✅ Colonna processata: '{col}' -> '{clean_name}'")
        return cleaned
    
    # Processa GM data
    print("🔧 Processamento dati GM...")
    gm_columns = clean_column_names(gm_df.columns)
    gm_data = {}
    for orig_col, clean_col in gm_columns:
        if orig_col in gm_df.columns:
            try:
                value = float(gm_df[orig_col].iloc[0])
                gm_data[clean_col] = value
                print(f"   📊 {clean_col}: {value:.3f}")
            except (ValueError, TypeError) as e:
                print(f"   ⚠️  Errore conversione {orig_col}: {e}")
                continue
    print(f"   ✅ Variabili GM processate: {len(gm_data)}")
    
    # Processa WM data
    print("🔧 Processamento dati WM...")
    wm_columns = clean_column_names(wm_df.columns)
    wm_data = {}
    for orig_col, clean_col in wm_columns:
        if orig_col in wm_df.columns:
            try:
                value = float(wm_df[orig_col].iloc[0])
                wm_data[clean_col] = value
                print(f"   📊 {clean_col}: {value:.3f}")
            except (ValueError, TypeError) as e:
                print(f"   ⚠️  Errore conversione {orig_col}: {e}")
                continue
    print(f"   ✅ Variabili WM processate: {len(wm_data)}")
    
    return gm_data, wm_data

def create_comparison_radar_plot(gm_data, wm_data, save_path=None):
    """
    Crea un radar plot comparativo per GM e WM
    
    Parameters:
    - gm_data: dizionario con dati materia grigia
    - wm_data: dizionario con dati materia bianca
    - save_path: percorso per salvare il grafico (opzionale)
    """
    
    # Ordine personalizzato delle categorie
    desired_order = [
        'Semantic', 'Phonological', 'Speech Arrest', 'Motor', 
        'Movement Arrest', 'Sensorial', 'Visual', 'Spatial Perception', 
        'Mentalizing', 'Anomia'
    ]
    
    # Funzione per mappare nomi simili
    def find_matching_key(desired_key, available_keys):
        if desired_key in available_keys:
            return desired_key
        for key in available_keys:
            if desired_key.lower() in key.lower() or key.lower() in desired_key.lower():
                return key
        return None
    
    # Trova le categorie comuni e riordinale
    common_categories = set(gm_data.keys()) & set(wm_data.keys())
    ordered_categories = []
    
    # Aggiungi categorie nell'ordine desiderato
    for desired_key in desired_order:
        matching_key = find_matching_key(desired_key, common_categories)
        if matching_key:
            ordered_categories.append(matching_key)
            common_categories.remove(matching_key)
    
    # Aggiungi eventuali categorie rimanenti
    ordered_categories.extend(sorted(list(common_categories)))
    
    print(f"📊 Categorie comuni trovate: {len(ordered_categories)}")
    print(f"🔄 Ordine finale: {ordered_categories}")
    
    # Filtra i dati per le categorie comuni riordinate
    gm_filtered = {cat: gm_data[cat] for cat in ordered_categories}
    wm_filtered = {cat: wm_data[cat] for cat in ordered_categories}
    
    # Crea il grafico comparativo
    fig, ax = plt.subplots(figsize=(16, 12), subplot_kw=dict(projection='polar'))
    
    # Prepara i dati
    categories = list(gm_filtered.keys())
    gm_values = list(gm_filtered.values())
    wm_values = list(wm_filtered.values())
    
    N = len(categories)
    angles = [n / float(N) * 2 * pi for n in range(N)]
    angles += angles[:1]
    
    gm_values += gm_values[:1]
    wm_values += wm_values[:1]
    
    # Plot con colori personalizzati
    ax.set_theta_offset(pi / 2)
    ax.set_theta_direction(-1)
    
    # Colori personalizzati: ocra-oro per GM, grigio chiaro per WM
    gm_color = '#DAA520'  # Goldenrod (ocra-oro)
    wm_color = '#808080'  # Gray (grigio medio)
    
    # GM plot
    ax.plot(angles, gm_values, 'o-', linewidth=3.5, label='Materia Grigia (GM)', 
            color=gm_color, markersize=9, markerfacecolor=gm_color, markeredgecolor='white', markeredgewidth=2)
    ax.fill(angles, gm_values, alpha=0.2, color=gm_color)
    
    # WM plot
    ax.plot(angles, wm_values, 's-', linewidth=3.5, label='Materia Bianca (WM)', 
            color=wm_color, markersize=9, markerfacecolor=wm_color, markeredgecolor='white', markeredgewidth=2)
    ax.fill(angles, wm_values, alpha=0.2, color=wm_color)
    
    # Personalizzazione con styling migliorato
    ax.set_xticks(angles[:-1])
    ax.set_xticklabels(categories, fontsize=15, fontweight='bold')
    ax.tick_params(axis='x', which='major', pad=45)  # Distanziamento maggiore delle label
    ax.set_ylim(0, 1)
    ax.set_yticks(np.arange(0, 1.1, 0.2))
    ax.set_yticklabels([f'{x:.1f}' for x in np.arange(0, 1.1, 0.2)], fontsize=11, fontweight='bold')
    ax.grid(True, alpha=0.6, linewidth=0.8)
    
    # Titolo e legenda migliorati
    plt.title('Confronto Importanza Funzioni Cognitive\nMateria Grigia vs Materia Bianca', 
              size=18, weight='bold', pad=35)
    plt.legend(loc='upper right', bbox_to_anchor=(1.25, 1.1), fontsize=12, framealpha=0.9)
    
    plt.tight_layout()
    
    if save_path:
        full_path = os.path.abspath(save_path)
        plt.savefig(save_path, dpi=300, bbox_inches='tight', facecolor='white')
        print(f"✅ Grafico comparativo salvato: {full_path}")
    
    plt.show()
    return fig

def create_individual_plots(gm_data, wm_data, save_prefix=None):
    """
    Crea radar plot individuali per GM e WM come file PNG separati
    """
    # Colori personalizzati: ocra-oro per GM, grigio chiaro per WM
    gm_color = '#DAA520'  # Goldenrod (ocra-oro)
    wm_color = '#808080'  # Gray (grigio medio)
    
    # PRIMO GRAFICO: Solo GM
    fig1, ax1 = plt.subplots(figsize=(12, 10), subplot_kw=dict(projection='polar'))
    create_radar_plot(gm_data, 'Materia Grigia (GM)', gm_color, ax1)
    plt.tight_layout()
    
    if save_prefix:
        gm_path = f'{save_prefix}_GM.png'
        full_gm_path = os.path.abspath(gm_path)
        plt.savefig(gm_path, dpi=300, bbox_inches='tight', facecolor='white')
        print(f"✅ Grafico GM salvato: {full_gm_path}")
    
    plt.show()
    
    # SECONDO GRAFICO: Solo WM
    fig2, ax2 = plt.subplots(figsize=(12, 10), subplot_kw=dict(projection='polar'))
    create_radar_plot(wm_data, 'Materia Bianca (WM)', wm_color, ax2)
    plt.tight_layout()
    
    if save_prefix:
        wm_path = f'{save_prefix}_WM.png'
        full_wm_path = os.path.abspath(wm_path)
        plt.savefig(wm_path, dpi=300, bbox_inches='tight', facecolor='white')
        print(f"✅ Grafico WM salvato: {full_wm_path}")
    
    plt.show()
    
    return fig1, fig2

def create_sample_data():
    """
    Crea dati di esempio per testare lo script senza i file CSV originali
    """
    gm_sample = {
        'Semantic': 0.505,
        'Phonological': 0.706,
        'Speech Arrest': 0.931,
        'Movement Arrest': 0.907,
        'Motor': 0.933,
        'Sensorial': 1.0,
        'Visual': 0.889,
        'Spatial Perception': 0.862,
        'Mentalizing': 0.559,
        'Anomia': 0.482,
        'Amodal Anomia': 0.526,
        'Verbal Apraxia': 0.907
    }

    wm_sample = {
        'Semantic': 0.300,
        'Phonological': 0.373,
        'Speech Arrest': 0.590,
        'Movement Arrest': 0.710,
        'Motor': 0.855,
        'Sensorial': 0.947,
        'Visual': 0.508,
        'Spatial Perception': 0.779,
        'Mentalizing': 0.448,
        'Anomia': 0.193,
        'Amodal Anomia': 0.472,
        'Verbal Apraxia': 0.697
    }
    return gm_sample, wm_sample

def run_example(output_dir='.'):
    """
    Esegue l'esempio con dati simulati
    """
    print("🔄 Esecuzione con dati di esempio...")
    gm_data, wm_data = create_sample_data()
    
    print("📊 Dati di esempio caricati:")
    print(f"   GM: {len(gm_data)} variabili")
    print(f"   WM: {len(wm_data)} variabili")
    
    # Assicurati che la directory di output esista
    os.makedirs(output_dir, exist_ok=True)
    print(f"📂 Directory di output: {os.path.abspath(output_dir)}")
    
    # Crea i percorsi completi per i file di output
    comparison_path = os.path.join(output_dir, "radar_comparison_example.png")
    individual_prefix = os.path.join(output_dir, "radar_example")
    
    create_comparison_radar_plot(gm_data, wm_data, comparison_path)
    create_individual_plots(gm_data, wm_data, individual_prefix)

# ESECUZIONE PRINCIPALE
if __name__ == "__main__":
    print("🧠 GENERATORE RADAR PLOT NEUROIMAGING")
    print("=" * 50)
    parser = argparse.ArgumentParser(description='Create plots from GM and WM CSV files')
    parser.add_argument('-gray_matter', '-g',
                        help='Path to gray matter csv file',
                        required=True)
    parser.add_argument('-white_matter', '-w',
                        help='Path to white matter csv file',
                        required=True)
    parser.add_argument('--output_dir', '-o',
                        help='Output directory for saving plots',
                        default='.')
    
    args = parser.parse_args()
    gm_file = args.gray_matter
    wm_file = args.white_matter
    output_directory = args.output_dir
    
    # Assicurati che la directory di output esista
    os.makedirs(output_directory, exist_ok=True)
    
    # Mostra directory corrente e di output
    current_dir = os.getcwd()
    print(f"📂 Directory corrente: {current_dir}")
    print(f"📁 Directory di output: {os.path.abspath(output_directory)}")
    
    print(f"🎯 File GM target: {gm_file}")
    print(f"🎯 File WM target: {wm_file}")
    
    # Prova prima con i file reali
    try:
        print("\n📁 Tentativo di caricamento file CSV...")
        gm_data, wm_data = load_and_process_data(gm_file, wm_file)
        
        print("\n✅ File caricati con successo!")
        print(f"📊 Funzioni GM trovate: {len(gm_data)}")
        print(f"📊 Funzioni WM trovate: {len(wm_data)}")
        
        # Mostra un preview dei dati
        print("\n📋 Preview dati GM:")
        for func, val in list(gm_data.items())[:3]:
            print(f"   {func}: {val:.3f}")
        if len(gm_data) > 3:
            print("   ...")
        
        print("\n🎨 Creazione grafici...")
        
        # Crea i percorsi completi per i file di output
        comparison_path = os.path.join(output_directory, "radar_comparison.png")
        individual_prefix = os.path.join(output_directory, "radar_plots")
        
        # Crea grafico comparativo
        print("   📈 Radar plot comparativo...")
        create_comparison_radar_plot(gm_data, wm_data, comparison_path)
        
        # Crea grafici individuali
        print("   📊 Radar plot individuali...")
        create_individual_plots(gm_data, wm_data, individual_prefix)
        
        print("\n✅ GRAFICI CREATI CON SUCCESSO!")
        print(f"📂 File salvati nella directory: {os.path.abspath(output_directory)}")
        print("📄 File generati:")
        print(f"   - {os.path.basename(comparison_path)} (grafico comparativo)")
        print(f"   - {os.path.basename(individual_prefix)}_GM.png (solo materia grigia)")
        print(f"   - {os.path.basename(individual_prefix)}_WM.png (solo materia bianca)")
        
    except FileNotFoundError as e:
        print(f"\n❌ File non trovato: {e}")
        print("🔄 Passaggio ai dati di esempio...")
        run_example(output_directory)
        
    except Exception as e:
        print(f"\n❌ Errore durante l'elaborazione: {e}")
        print("🔄 Passaggio ai dati di esempio...")
        run_example(output_directory)