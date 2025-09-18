#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Thu Aug 21 16:37:09 2025
@author: ludovicocoletta
"""
import os
import glob
import numpy as np
import nibabel as nib
import pandas as pd
import argparse

def main(lesions_path, output_path):
    path_to_maps = '/home/alberto/test_subalpamaps/APSS_Atlas/apss_subcortical_maps'
    maps = sorted(glob.glob(os.path.join(path_to_maps, '*gz')))
    map_names = [ii.split('_union_randomise_1mm.nii.gz')[0].split('/')[-1] for ii in maps]
    
    # Handle single lesion file
    lesion = lesions_path
    df_as_array = np.zeros((1, len(maps)))
    
    # Extract patient ID from lesion path
    pat_ids = [os.path.basename(lesion).split('_')[0]]  # More robust patient ID extraction
    
    # Load patient lesion data
    pat_data = nib.load(lesion).get_fdata()
    pat_data[pat_data!=0]=1
    # Process each map
    for nifti_index, nifti_map in enumerate(maps):
        nifti_data = nib.load(nifti_map).get_fdata()
        inter = nifti_data * pat_data
        
        # Calculate 90th percentile of non-zero intersection values
        non_zero_inter = inter[inter != 0]
        if len(non_zero_inter) > 0:
            df_as_array[0, nifti_index] = np.percentile(non_zero_inter, 90)
        else:
            df_as_array[0, nifti_index] = 0  # Handle case where no intersection exists
    
    # Save results to Excel
    df = pd.DataFrame(df_as_array, index=pat_ids, columns=map_names)
    df.to_csv(output_path)
    print(f"Results saved to {output_path}")
    print(f"Processed patient: {pat_ids[0]}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Analyze lesion-map intersections')
    parser.add_argument('--lesions-path', '-l',
                        help='Path to lesion file',
                        required=True)
    parser.add_argument('--output-path', '-o',
                        help='Output path for Excel file',
                        default='WM_importance.csv')
    
    args = parser.parse_args()
    
    # Validate input file exists
    if not os.path.exists(args.lesions_path):
        raise FileNotFoundError(f"Lesion file not found: {args.lesions_path}")
    
    main(args.lesions_path, args.output_path)