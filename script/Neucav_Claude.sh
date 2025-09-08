#!/bin/bash

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

# Initialize variables
nargs=0
is_dicom=false
extract_dir="/tmp/neucav_extract_$$"
zip_output=false
mask_quality=1

function Usage {
    cat <<USAGE
    

Usage:

`basename $0` [-h] -i <filename> -m <output extension> [-z]


Main arguments:

  -i, --input=<filename>            Input a post operative T1-w-CE image. It could be a NifTI file, a dicom folder or a zip cointainting dicoms 
  -o, --output=<filename>           Output file name (default: same as the input + "mask"). The output is a surgical cavity mask in the same space of the subject.
  -e, --output_extension=<modality> Output file extension (default: same as the input). <extension> can be one of the following: n (nii.gz), d (dicom). The image will be stored accordinlgy.
  -q, --quality=<quality>   (UPDATE API)        Quality of the output mask (default: 1). It can be 0 (low), 1 (high). The higher the quality, the longer the processing time.
Optional:
  -h, --help                        Show this help message
  -z, --zip                         Create a zip archive of the output files
Examples:

`basename $0` -i sub_xxx_T1w_CE.nii.gz -m n
`basename $0` -i sub_xxx_T1w_CE/ -m d

NB: in case of DICOM format, the output will be a folder and not a single file. Use the option -z to receive a compressed file.
USAGE
    exit 1
}

# Add exists function
function exists {
    [ -f "$1" ] && echo 1 || echo 0
}

# Add fail function
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
	local fileT1=${fileT1_converted_dir}'/'${basename}'T1w.nii'
	local json_T1=${fileT1_converted_dir}'/'${basename}'T1w.json'

	if ( [ $( exists ${fileT1} ) -eq 0 ] ); then
		echo "T1-w convert directory:" ${fileT1_converted_dir}
		echo "T1-w dicom directory:" ${fileT1_dicomdir}
		mkdir -p ${fileT1_converted_dir}
		dcm2niix -o ${fileT1_converted_dir} -z n -v y -f %p ${fileT1_dicomdir}
		
		fileT1_conv=( $( ls ${fileT1_converted_dir}/*nii*   ) )
		json_T1_conv=( $( ls ${fileT1_converted_dir}/*json*   ) )
		
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

rescale_T1() {
	#to isotropic 1x1x1mm
	#save the original resolution
	local input_T1_toResample=${1}
	local subject_id=$(basename ${input_T1_toResample} | cut -d. -f1)
	local dirname=$(dirname ${input_T1_toResample})
	local output_file=${dirname}/${subject_id}_resampled.nii.gz

	flirt -in "$input_T1_toResample" -ref "$input_T1_toResample" -applyisoxfm 1.0 -interp trilinear -nosearch -out "$output_file"

}

MNI_registration() { #flirt
	local input_T1_toRegister=${1}
	local subject_id=$(basename ${input_T1_toRegister} | cut -d. -f1)
	local dirname=$(dirname ${input_T1_toRegister})
	local output_mat=${dirname}/${subject_id}_2MNI.mat
	local output_T1_registered=${dirname}/${subject_id}_2MNI.nii.gz
	local template="${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz"

	flirt \
       -in $input_T1_toRegister \
       -ref $template \
       -omat $output_mat
       
    flirt \
       -in $input_T1_toRegister \
       -ref $template \
       -applyxfm -init $output_mat \
       -out $output_T1_registered
}

Skull_Stripping() { #synthstrip
    local T1_with_skull=${1}
	local dirname=$(dirname ${T1_with_skull})
	local subject_id=$(basename ${T1_with_skull} | cut -d. -f1)
	local T1_without_skull=${dirname}/${subject_id}_sk.nii.gz
	local output_img=${dirname}/${subject_id}_sk_brain.nii.gz
	
	mri_synthstrip \
       -i $T1_with_skull \
       -m $T1_without_skull \
       --out $output_img 

}

nnUNet_prediction() {
    local input_nifti_dir=${1}
    local output_dir=${2}
    
    if [ "$mask_quality" == "1" ]; then
        #HIGH QUALITY MASK
        nnUNet_predict -i ${input_nifti_dir} -o ${output_dir} -d 900 -c 3d_fullres_bs12 -tr nnUNetTrainer_100epochs -f all --device CPU
    else
        #LOW QUALITY MASK
        nnUNet_predict -i ${input_nifti_dir} -o ${output_dir} -d 900 -c 3d_fullres_bs12 -tr nnUNetTrainer_100epochs -f 0 --device CPU
    fi
}

nifti_to_dicom_surgical_mask () {
    local nifti_mask=${1}
    local dicom_mask=${2}

    # Convert NIfTI mask to DICOM format
    mkdir -p ${dicom_mask}
    nii2dcm $nifti_mask $dicom_mask -d MR
}

mask_to_anisotropic() {
	#to original resolution
	local predicted_mask=${1}
	local original_T1=${2}

	3dresample -master $original_T1 -prefix ${predicted_mask}_resampled.nii -input $predicted_mask

}

# create_csv_for_cortical() {
# 	#with Ludovico
# }


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
		output_filename=${1}
		;;
		-q|--quality)
		shift
		mask_quality=${1}
		;;
		-q|--quality=*)
		mask_quality="${key#*=}"
		;;
		-z|--zip)
		zip_output=true
		;;
		*)
		echo "Unknown option: $key"
		Usage
		;;
	esac
	shift
done

# Check if input file was provided
if [ -z "$T1" ]; then
    echo "Error: Input file (-i) is required"
    Usage
fi

# Set default output filename if not provided
if [ -z "$output_filename" ]; then
    output_filename="${T1%.*}_mask"
fi

# Set default output extension if not provided
if [ -z "$output_extension" ]; then
    T1_ext="${T1##*.}"
    if [ "$T1_ext" == "gz" ]; then
        output_extension="n"  # nii.gz
    else
        output_extension="n"  # default to nifti
    fi
fi

### TEST NII2DCM ###
# nifti_mask="/home/aspolverato/BraTS_predicted_mask/Dataset900_fold0/BraTS-GLI_00020.nii.gz"
# output_dir="/home/aspolverato/test/output"
# mkdir -p $output_dir
# nifti_to_dicom_surgical_mask $nifti_mask $output_dir -d MR
### END TEST NII2DCM ###

###SCRIPT###

T1_ext="${T1##*.}"
if [ "$T1_ext" == "nii" ] || [ "$T1_ext" == "gz" ]; then
	fileT1=${T1}
	echo "The file is a Nifti!"
	T1_dirname=$( dirname $fileT1 )
elif [ "$T1_ext" == "zip" ]; then
	echo "The file is .zip folder!"
	mkdir -p "$extract_dir"
	unzip "$T1" -d "$extract_dir"
	T1_dirname="$extract_dir"

	dicom_found=false
	for f in "$extract_dir"/*; do
        if [ -f "$f" ]; then  # Make sure it's a file
            f_ext=$(echo "${f##*.}" | tr '[:upper:]' '[:lower:]')  # Get extension in lowercase
            if [ "$f_ext" == "dcm" ] || [ "$f_ext" == "dicom" ]; then
                dicom_found=true
                break
            fi
        fi
    done
	if [ "$dicom_found" = false ]; then
		echo "The folder doesn't contain DICOM files"
		exit 1
	fi
	fileT1="$extract_dir"
	is_dicom=true
elif [ -d "$T1" ]; then
	echo "The input is a directory (assuming DICOM)!"
	fileT1="$T1"
	T1_dirname="$T1"
	is_dicom=true
else
	echo "Unsupported file extension or format: $T1_ext"
	exit 1
fi

echo "Processed file/directory: $fileT1"