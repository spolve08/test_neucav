#! /bin/bash
#########################################################################################################################
#########################################################################################################################
###################                                                                                   ###################
################### title:          Neucav: DL tool for post surgery cavity mask                      ###################
###################                                                                                   ###################
###################                                                                                   ###################
################### description:    Deep learning tool for post-surgery cavity mask generation        ###################
###################                                                                                   ###################
################### version:        1.0.0.1                                                           ###################
################### notes:          Install ANTs, FSL to use this script                              ###################
###################                 needs IMAGINGlib, REGlib,FILESlib,CPUslib libraries               ###################
###################                 requirements: GPU/CPU                                             ###################
###################                 (see details here https://github.com/MIC-DKFZ/nnUNet)             ###################
################### bash version:   tested on GNU bash, version 4.2.53                                ###################
###################                                                                                   ###################
################### autor: aspolverato                                                                ###################
################### email: aspolverato@fbk.eu                                                         ###################
################### affiliation: NILab (CIMeC and FBK)                                                ###################
#########################################################################################################################
#########################################################################################################################

function Usage {
    cat <<USAGE
    

Usage:

`basename $0` [-h] -i <filename> -m <output extension> [-z]


Main arguments:

  -i, --input=<filename>            Input a post operative T1-w-CE image. It could be a NifTI file, a dicom folder or a zip cointainting dicoms 
  -o, --output=<filename>           Output directory.
  -e, --output_extension=<modality> Output file extension (default: same as the input). <extension> can be one of the following: n (nii.gz), d (dicom). The image will be stored accordinlgy.
  -q, --quality=<quality>   (UPDATE API)        Quality of the output mask (default: 1). It can be 0 (low), 1 (high). The higher the quality, the longer the processing time.
  -z, --zip                 (DEFAULT)        Create a zip archive of the output files
Optional:
  -h, --help                        Show this help message
  
Examples:

`basename $0` -i sub_xxx_T1w_CE.nii.gz -m n
`basename $0` -i sub_xxx_T1w_CE/ -m d

NB: in case of DICOM format, the output will be a folder and not a single file. Use the option -z to receive a compressed file.
USAGE
    exit 1
}


function exists {
    [ -f "$1" ] && echo 1 || echo 0
}

function fail {
    echo "ERROR: $1" >&2
    exit 1
}
dicom_to_nifti() {
    local fileT1=${1}
    local outputdir=${2}
    local basename=${3}
    local fileT1_dicomdir=${fileT1}
    local fileT1_converted_dir=${outputdir}
    local fileT1=${fileT1_converted_dir}'/'${basename}'_T1w.nii.gz'
    local json_T1=${fileT1_converted_dir}'/'${basename}'_T1w.json'
    
    if ( [ $( exists ${fileT1} ) -eq 0 ] ); then
        echo "T1-w convert directory:" ${fileT1_converted_dir}
        echo "T1-w dicom directory:" ${fileT1_dicomdir}
        mkdir -p ${fileT1_converted_dir}
        dcm2niix -o ${fileT1_converted_dir} -z y -v y -f %p -m y ${fileT1_dicomdir}
        
        fileT1_conv=( $( ls ${fileT1_converted_dir}/*nii.gz* ) )
        json_T1_conv=( $( ls ${fileT1_converted_dir}/*json* ) )
        
        if [ ${#fileT1_conv[@]} -gt 1 ]; then
            echo "WARNING: more the one T1-w NifTI file found. "
            echo ${fileT1_conv[@]}
            echo "Only the first one will be considered"
        elif [ ${#fileT1_conv[@]} -lt 1 ]; then
            echo ${fileT1_conv[@]}
            fail "Error: Cannot find the NifTI file in the conversion folder"
            return -1
        fi
        
        local fileT1_conv=${fileT1_conv[0]}
        local json_T1_conv=${json_T1_conv[0]}
        mv $fileT1_conv $fileT1
        mv $json_T1_conv $json_T1
    fi
}
reorient_T1() {
    # to RAS orientation
    local input_T1_toReorient=${1}
    local basename=${2}
    local output_dir=${3}
    
    local output_file=${output_dir}/${basename}_RAS.nii.gz
    reorient_matrix=${output_dir}/${basename}_reorient.mat
    
    # Check if reoriented file already exists
    # if [ -f "$output_file" ]; then
    #     echo "Reoriented file already exists: $output_file"
    #     echo "Skipping reorientation step."
    #     return 0
    # fi
    
    # Create output directory if it doesn't exist
    mkdir -p "$output_dir"
    
    # Apply reorientation
    fslreorient2std -m "$reorient_matrix" "$input_T1_toReorient" "$output_file"

    echo "Reorientation completed. Matrix saved to: $reorient_matrix"

    return 0
}
resample_T1() {
	#to isotropic 1x1x1mm
	#save the original resolution
	local input_T1_toResample=${1}
	local basename=${2}
	# local subject_id=$(basename ${input_T1_toResample} | cut -d. -f1)
	local output_dir=${3}  # Add output directory parameter
    local output_file=${output_dir}/${basename}_resampled.nii.gz
    if [ -f "$output_file" ]; then
        echo "Resampled file already exists: $output_file"
        echo "Skipping resampling step."
        return 0
    fi
    flirt -in "$input_T1_toResample" -ref "$input_T1_toResample" -applyisoxfm 1.0 -interp trilinear -nosearch -out "$output_file" -v
}
MNI_registration() { #flirt
	local input_T1_toRegister=${1}
	local basename=${2}
	# local subject_id=$(basename ${input_T1_toRegister} | cut -d. -f1)
	local output_dir=${3}
	local output_mat=${output_dir}/${basename}_MNI.mat
	local output_T1_registered=${output_dir}/${basename}_MNI.nii.gz
	local template="${FSLDIR}/data/standard/MNI152_T1_1mm_brain.nii.gz"
	# Check if the output file already exists
	if [ -f "$output_T1_registered" ]; then
		echo "Registered file already exists: $output_T1_registered"
		echo "Skipping registration step."
		return 0
	fi

	# Perform registration using FLIRT
	flirt \
       -in $input_T1_toRegister \
       -ref $template \
       -omat $output_mat \
       -v
    flirt \
       -in $input_T1_toRegister \
       -ref $template \
       -applyxfm -init $output_mat \
       -out $output_T1_registered \
	   -v
}

Skull_Stripping() { #synthstrip
    local T1_with_skull=${1}
	local basename=${2}
	local output_dir=${3}
	# local subject_id=$(basename ${T1_with_skull} | cut -d. -f1)
	local T1_without_skull=${output_dir}/${basename}_sk.nii.gz
	if [ -f "$T1_without_skull" ]; then
		echo "Skull stripped file already exists: $T1_without_skull"
		echo "Skipping skull stripping step."
		return 0
	fi
	mri_synthstrip \
       -i $T1_with_skull \
       -o $T1_without_skull \
       -m ${output_dir}/${basename}_sk_mask.nii.gz
}
#for local test in worksation


# nnUNet_prediction() {
#     local preprocessed_T1=${1}
#     local output_dir=${2}
#     local basename=${3}
    
#     local expected_mask="${output_dir}/${basename}_surgical_mask.nii.gz"
#     if [ -f "$expected_mask" ]; then
#         echo "Mask already exists, skipping prediction"
#         mask_path="$expected_mask"
#         return 0
#     fi
#     source nnunetv2/bin/activate
#     export nnUNet_raw="/home/alberto/nnunetv2/nnUNet_raw"
#     export nnUNet_preprocessed="/home/alberto/nnunetv2/nnUNet_preprocessed"
#     export nnUNet_results="/home/alberto/nnunetv2/nnUNet_results"
#     # Setup directories
#     local nnunet_input_dir="${output_dir}/nnunet_input"
#     local temp_output_dir=$(mktemp -d)
#     mkdir -p "$nnunet_input_dir"
    
#     # Copy preprocessed image with nnUNet naming
#     local clean_name=$(echo "$basename" | sed 's/[-_]//g' | tr '[:upper:]' '[:lower:]')
#     cp "$preprocessed_T1" "${nnunet_input_dir}/${clean_name}_001_0000.nii.gz"
    
#     # Run prediction
#     local cmd="nnUNetv2_predict -i ${nnunet_input_dir} -o ${temp_output_dir} -d 950 -c 3d_fullres_bs12 -tr nnUNetTrainer_100epochs"
#     [ $mask_quality -eq 0 ] && cmd="$cmd -f 0 -device cpu"
#     [ $mask_quality -eq 1 ] && [ "$use_gpu" = false ] && cmd="$cmd -device cpu"
    
#     echo "Running nnUNet prediction (quality: $mask_quality)..."
#     eval $cmd
    
#     # Copy output mask
#     local output_mask=$(ls "${temp_output_dir}"/*.nii.gz | head -1)
#     [ ! -f "$output_mask" ] && { echo "Error: No output mask found!"; exit 1; }
    
#     cp "$output_mask" "$expected_mask"
#     mask_path="$expected_mask"
#     rm -rf "$temp_output_dir"
    
#     echo "Prediction complete: $expected_mask"
# }

nnUNet_prediction() {
    local preprocessed_T1=${1}
    local output_dir=${2}
    local basename=${3}
    
    local expected_mask="${output_dir}/${basename}_surgical_mask.nii.gz"
    if [ -f "$expected_mask" ]; then
        echo "Mask already exists, skipping prediction"
        mask_path="$expected_mask"
        return 0
    fi
    
    # No need to activate virtual environment in Docker - nnUNet is installed globally
    # source nnunetv2/bin/activate
    export nnUNet_raw="/app/data/raw"
    export nnUNet_preprocessed="/app/data/preprocessed"
    export nnUNet_results="/app/data/results"
    
    # Setup directories
    local nnunet_input_dir="${output_dir}/nnunet_input"
    local temp_output_dir=$(mktemp -d)
    mkdir -p "$nnunet_input_dir"
    
    # Copy preprocessed image with nnUNet naming
    local clean_name=$(echo "$basename" | sed 's/[-_]//g' | tr '[:upper:]' '[:lower:]')
    cp "$preprocessed_T1" "${nnunet_input_dir}/${clean_name}_001_0000.nii.gz"
    
    # Run prediction
    local cmd="nnUNetv2_predict -i ${nnunet_input_dir} -o ${temp_output_dir} -d 950 -c 3d_fullres_bs12 -tr nnUNetTrainer_100epochs"
    [ $mask_quality -eq 0 ] && cmd="$cmd -f 0 -device cpu"
    [ $mask_quality -eq 1 ] && [ "$use_gpu" = false ] && cmd="$cmd -device cpu"
    
    echo "Running nnUNet prediction (quality: $mask_quality)..."
    eval $cmd
    
    # Copy output mask
    local output_mask=$(ls "${temp_output_dir}"/*.nii.gz | head -1)
    [ ! -f "$output_mask" ] && { echo "Error: No output mask found!"; exit 1; }
    
    cp "$output_mask" "$expected_mask"
    mask_path="$expected_mask"
    rm -rf "$temp_output_dir"
    
    echo "Prediction complete: $expected_mask"
}

nifti_to_dicom_surgical_mask () {
    local nifti_mask=${1}
    local dicom_mask=${2}
    local ref_dicom_dir=${3}

    # Convert NIfTI mask to DICOM format
    mkdir -p ${dicom_mask}
    nii2dcm $nifti_mask $dicom_mask -r $ref_dicom_dir -d MR
}

mask_to_subjectSpace() {
    local predicted_mask=${1}
    local original_T1=${2}
    local subSpace_mask=${3}
    local basename=${4}
    output_dir=$(dirname "$predicted_mask")
    
    local affine_matrix="${output_dir}/${basename}_MNI.mat"
    
    # Check matrix exists
    [[ ! -f "$affine_matrix" ]] && { echo "ERROR: Matrix not found: $affine_matrix"; return 1; }
    
    # Remove existing output and apply inverse transform
    convert_xfm -omat /tmp/inv.mat -inverse "$affine_matrix" && \
    flirt -in "$predicted_mask" -ref "$original_T1" -applyxfm -init /tmp/inv.mat -out "$subSpace_mask" -interp nearestneighbour && \
    rm -f /tmp/inv.mat
}

mask_to_anisotropic() {
	#to original resolution
	local predicted_mask=${1}
	local original_T1=${2}
	local resampled_mask=${3}
    if [ -f "$resampled_mask" ]; then
        echo "Resampled mask already exists: $resampled_mask"
        echo "Skipping anisotropic resampling step."
        return 0
    fi
	3dresample -master $original_T1 -prefix $resampled_mask -input $predicted_mask

}

mask_to_original_orientation(){
    local mask_in_subSpace=${1}
    local original_T1=${2}
    local basename=${3}
    local output_dir=${4}
    
    local reorient_matrix="${output_dir}/${basename}_reorient.mat"
    local output_mask="${output_dir}/${basename}_original_orientation_mask.nii.gz"
    
    convert_xfm -omat /tmp/inv.mat -inverse "$reorient_matrix" && \
    flirt -in "$mask_in_subSpace" -ref "$original_T1" -applyxfm -init /tmp/inv.mat -out "$output_mask" -interp nearestneighbour && \
    rm -f /tmp/inv.mat
}


#As long as there is at least one more argument, keep looping
while [[ $# -gt 0 ]]; do
    key="$1"
    case "$key" in
		-h|--help)
			Usage
			exit 0
			;;
		-i|--input)
		shift
		T1=${1}
		;;
		-e|--output_extension)
		shift
		output_extension="${1}"
		;;
		-e|--output_extension=*)
		output_extension="${key#*=}"
		;;
		-o|--output)	
		shift
		output_directory=${1}
		;;
		-q|--quality)
		shift
		mask_quality=${1}
		;;
		-q|--quality=*)
		mask_quality="${key#*=}"
		;;
		-z|--zip)
		shift
		zip_output=true
		;;
		-gpu|--gpu)
		use_gpu=true
		;;
		*)
		echo "Unknown option: $key"
		Usage
	esac
	#this final shift is necessary to make $1 empy. For example: bash /home/aspolverato/test_neucav/script/Neucav.sh -i /home/aspolverato/pre/T1/structural_T1_pre.nii.gz
	#after the first loop $1 will be /home/aspolverato/pre/T1/structural_T1_pre.nii.gz, so we need to shift it again, otherwise the loop will start again trying to recognize the path as an option.
	shift
done

if [ -z "$T1" ]; then
    echo "Error: Input file (-i) is required"
    Usage
fi

if [ -z "$output_directory" ]; then
	echo "Output directory not specified."
	Usage
fi

if [ -z "$output_extension" ]; then
    T1_ext="${T1##*.}"
    if [ "$T1_ext" == "gz" ]; then
        output_extension="n" 
    else
        output_extension="n"
    fi
fi



#########################################################################################################################
##########################################   BEGIN MAIN SCRIPT   ########################################################
#########################################################################################################################

# ------------------- VARIABLES & DIRECTORIES -------------------
nargs=0
is_dicom=false
extract_dir="/tmp/neucav_extract_$$"
zip_output=true
use_gpu=false

# Script and helper paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT_SUB="${SCRIPT_DIR}/calculate_overlap_with_subROIs.py"
PYTHON_SCRIPT_COR="${SCRIPT_DIR}/calculate_overlap_with_corROIs.py"
PYTHON_SCRIPT_PLOT="${SCRIPT_DIR}/radar_plot.py"
# Input file info
T1_ext="${T1##*.}"
T1_basename=$(basename "$T1" | sed -E 's/\.(nii\.gz|nii|zip)$//')
T1_dirname=$(dirname "$T1")

# Output directory setup
if [ ! -d "$output_directory" ]; then
    echo "Creating output directory: $output_directory"
    mkdir -p "$output_directory"
fi

# Copy input to output directory (if not already there)
if [ "$T1_dirname" != "$output_directory" ]; then
    cp "$T1" "$output_directory/"
fi

###################################################
######## CHECK FILE EXTENSION AND UNZIP ###########
###################################################
if [ "$T1_ext" == "nii" ] || [ "$T1_ext" == "gz" ]; then
    fileT1=${T1}
    echo "The file is a Nifti!"
    # Set T1_new_dir to current file directory
    T1_new_dir=$(dirname "$T1")
    echo "T1_new_dir set to: $T1_new_dir"
elif [ $T1_ext == "zip" ]; then
    echo "The file is .zip folder!"
    unzip "$T1" -d "$extract_dir" > /dev/null 2>&1 # Suppress output
    # Set fileT1 to the extraction directory
    fileT1="$extract_dir"
    echo $T1_basename
    for f in "$extract_dir"/*; do
        dicom_found=false
        if [ -f "$f" ]; then # Make sure it's a file
            f_ext=$(echo "${f##*.}" | tr '[:upper:]' '[:lower:]') # Get extension in lowercase
            if [ "$f_ext" == "dcm" ] || [ "$f_ext" == "dicom" ]; then
                dicom_found=true
                break
            fi
        fi
    done
    fileT1="$extract_dir"
    is_dicom=true
else
    echo "Unsupported file extension; $T1_ext"
    exit 1
fi

echo "Processed file/directory: $fileT1"

###################################################
######## CONVERT DICOM TO NIFTI ###################
###################################################
if [ $is_dicom == true ]; then
    # Convert DICOM to NIfTI (original conversion)
    dicom_to_nifti $fileT1 $output_directory $T1_basename
    fileT1=${output_directory}/$T1_basename"_T1w.nii.gz"
    
    # Create new folder in input directory for the converted NIfTI copy
    input_dir=$(dirname "$T1")
    T1_new_dir="${input_dir}/${T1_basename}_nifti"
    mkdir -p "$T1_new_dir"
    
    # Copy the converted NIfTI to the new folder
    cp "$fileT1" "$T1_new_dir/"
    echo "Converted NIfTI copied to: $T1_new_dir"
    echo "T1_new_dir set to: $T1_new_dir"
fi

###################################################
######## RESAMPLE TO 1X1X1MM ######################
###################################################

resample_T1 $fileT1 $T1_basename $output_directory
fileT1=${output_directory}/$T1_basename"_resampled.nii.gz"

###################################################
######## REORIENT TO RAS ##########################
###################################################

reorient_T1 $fileT1 $T1_basename $output_directory
fileT1=${output_directory}/$T1_basename"_RAS.nii.gz"

###################################################
######## SKULL STRIPPING ##########################
###################################################

Skull_Stripping $fileT1 $T1_basename $output_directory
fileT1=${output_directory}/$T1_basename"_sk.nii.gz"

###################################################
######## MNI REGISTRATION #########################
###################################################

MNI_registration $fileT1 $T1_basename $output_directory
fileT1=${output_directory}/$T1_basename"_MNI.nii.gz"

###################################################
######## NNUNET PREDICTION ########################
###################################################

nnUNet_prediction $fileT1 $output_directory $T1_basename

fslstats "$mask_path" -V | cut -d' ' -f2- > ${output_directory}/vol.txt
vol=$(cat ${output_directory}/vol.txt)
if (( $(echo "$vol == 0" | bc -l) )); then
    echo "Warning: The predicted mask is empty (volume = 0). Please check the input image." > ${output_directory}/NO_SEG_CREATED.txt
fi
###################################################
######### MASK PROCESSING STEPS ###################
###################################################
if [ $is_dicom == true ]; then
    original_T1="${output_directory}/${T1_basename}_T1w.nii.gz"
else
    original_T1="$T1"
fi

resampled_T1="${output_directory}/${T1_basename}_resampled.nii.gz"
ras_T1="${output_directory}/${T1_basename}_RAS.nii.gz"

echo "Starting mask transformation back to original space..."

# Step 1: MNI space back to subject space
mask_in_subSpace="${output_directory}/${T1_basename}_subSpace_mask.nii.gz"
mask_to_subjectSpace $mask_path $ras_T1 $mask_in_subSpace $T1_basename
echo "Mask in subject space saved as: $mask_in_subSpace"

# Step 2: Back to original orientation
mask_original_orient="${output_directory}/${T1_basename}_original_orientation_mask.nii.gz"
mask_to_original_orientation $mask_in_subSpace $resampled_T1 $T1_basename $output_directory
echo "Mask in original orientation saved as: $mask_original_orient"

# Step 3: Back to original resolution
final_mask="${output_directory}/${T1_basename}_final_mask.nii.gz"
mask_to_anisotropic $mask_original_orient $original_T1 $final_mask
echo "Final mask in original space saved as: $final_mask"

fslcpgeom $original_T1 $final_mask

###################################################
######## CONVERT MASK  IN DICOM (BETA) ############
###################################################


# if [ "$output_extension" == "d" ]; then
#     dicom_mask_dir="${output_directory}/${T1_basename}_surgical_mask_dicom"
#     ref_dicom=$extract_dir/*
#     nifti_to_dicom_surgical_mask $resampled_mask $dicom_mask_dir $ref_dicom
#     echo "DICOM mask saved in directory: $dicom_mask_dir"
#     # if [ "$zip_output" = true ]; then
#     #     zip_file="${output_directory}/${T1_basename}_surgical_mask_dicom.zip"
#     #     zip -r "$zip_file" "$dicom_mask_dir"
#     #     echo "Zipped DICOM mask saved as: $zip_file"
#     #     rm -rf "$dicom_mask_dir"
#     # fi 
# elif [ "$output_extension" == "n" ]; then
#     echo "NIfTI mask saved as: $resampled_mask"
# else
#     echo "Unsupported output extension; $output_extension"
#     exit 1
# fi


###################################################
######## CALCULATE OVERLAP WITH ROIs ##############
###################################################

output_sub="${output_directory}/${T1_basename}_WM_importance.csv"
output_cor="${output_directory}/${T1_basename}_GM_importance.csv"

python3 "$PYTHON_SCRIPT_SUB" --lesions-path $mask_path -o $output_sub
python3 "$PYTHON_SCRIPT_COR" --lesions-path $mask_path -o $output_cor
python3 "$PYTHON_SCRIPT_PLOT" -g $output_cor -w $output_sub -o $output_directory




###################################################
######## COPY FINAL OUTPUTS TO ZIP FOLDER ########
###################################################

# Create final output folder
final_output_dir="${output_directory}/${T1_basename}_final_outputs"
mkdir -p "$final_output_dir"

# Copy files with standardized names
# (i) Resection cavity in native space
if [ "$output_extension" == "d" ]; then
    # For DICOM output - copy the DICOM folder and zip it
    if [ -d "$dicom_mask_dir" ]; then
        zip -r "${final_output_dir}/res_cavity.zip" "$dicom_mask_dir"
    fi
else
    # For NIfTI output
    cp "$final_mask" "${final_output_dir}/res_cavity.nii.gz"
fi

# (ii) Affine matrix for MNI registration
cp "${output_directory}/${T1_basename}_MNI.mat" "${final_output_dir}/flirt_to_mni.mat"

# (iii) Resection cavity in MNI space
cp "$mask_path" "${final_output_dir}/res_cavity_MNI.nii.gz"

# (iv) CSV files with importance measures
cp "${output_directory}/${T1_basename}_GM_importance.csv" "${final_output_dir}/GM_importance.csv"
cp "${output_directory}/${T1_basename}_WM_importance.csv" "${final_output_dir}/WM_importance.csv"

# (v) Radar plots (assuming they're saved as PNG files)
find "$output_directory" -name "*radar*" -type f \( -name "*.png" -o -name "*.pdf" -o -name "*.svg" \) -exec cp {} "$final_output_dir"/ \;

echo "Final outputs copied to: $final_output_dir"

# Optional: Create zip of final outputs
if [ "$zip_output" = true ]; then
    zip_final="${output_directory}/${T1_basename}_final_results.zip"
    (cd "$output_directory" && zip -r "$(basename "$zip_final")" "$(basename "$final_output_dir")")
    echo "Final results zipped as: $zip_final"
fi