import pydicom
import os

input_dir = '/home/alberto/P11/pre/T1/new_nii2dcm/'
output_dir = '/home/alberto/P11/pre/T1/fixed_nii2dcm/'

# Create output directory
os.makedirs(output_dir, exist_ok=True)

# Process all DICOM files
for filename in os.listdir(input_dir):
    if filename.endswith('.dcm'):
        # Read DICOM
        dcm = pydicom.dcmread(os.path.join(input_dir, filename))
        
        # Set the corrected orientation (with flipped Y components)
        dcm.ImageOrientationPatient = [0.9995173750741061, -0.030577011219287256, 0.005483001902670556, 0.027891304407167042, 0.9610401413769338, 0.2749980396305939]
        
        # Save corrected DICOM
        dcm.save_as(os.path.join(output_dir, filename))

print("All DICOM files processed!")