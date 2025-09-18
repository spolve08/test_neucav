#!/bin/bash

# NIfTI Round-trip Conversion Script
# Performs iterative conversions: NIfTI -> DICOM -> NIfTI
# Usage: ./roundtrip_convert.sh -i <input_nifti> -n <iterations> [-h]

# Default values
ITERATIONS=1
INPUT_FILE=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_OUTPUT_DIR="roundtrip_output"

# Function to display help
show_help() {
    echo "Usage: $0 -i <input_nifti> -n <iterations> [-h]"
    echo ""
    echo "Options:"
    echo "  -i <input_nifti>   Input NIfTI file (required)"
    echo "  -n <iterations>    Number of round-trip iterations (default: 1)"
    echo "  -h                 Show this help message"
    echo ""
    echo "Description:"
    echo "  This script performs iterative round-trip conversions:"
    echo "  NIfTI -> DICOM (nii2dcm) -> NIfTI (dcm2niix)"
    echo ""
    echo "  Each iteration creates a new folder named 'round_<N>' containing:"
    echo "  - dicom/     : DICOM files from nii2dcm"
    echo "  - nifti/     : Final NIfTI file from dcm2niix"
    echo ""
    echo "Example:"
    echo "  $0 -i brain.nii.gz -n 5"
}

# Function to check if required tools are available
check_dependencies() {
    local missing_deps=()
    
    if ! command -v nii2dcm &> /dev/null; then
        missing_deps+=("nii2dcm")
    fi
    
    if ! command -v dcm2niix &> /dev/null; then
        missing_deps+=("dcm2niix")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "Error: Missing required dependencies:"
        printf " - %s\n" "${missing_deps[@]}"
        echo "Please install the missing tools and try again."
        exit 1
    fi
}

# Function to validate input file
validate_input() {
    if [ -z "$INPUT_FILE" ]; then
        echo "Error: Input NIfTI file not specified."
        echo "Use -i <input_nifti> to specify the input file."
        exit 1
    fi
    
    if [ ! -f "$INPUT_FILE" ]; then
        echo "Error: Input file '$INPUT_FILE' does not exist."
        exit 1
    fi
    
    # Get absolute path
    INPUT_FILE=$(realpath "$INPUT_FILE")
    
    # Check if it's a NIfTI file (basic check)
    case "${INPUT_FILE,,}" in
        *.nii|*.nii.gz)
            echo "Input file: $INPUT_FILE"
            ;;
        *)
            echo "Warning: Input file doesn't have a typical NIfTI extension (.nii or .nii.gz)"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
            ;;
    esac
}

# Parse command line arguments
while getopts "i:n:h" opt; do
    case $opt in
        i)
            INPUT_FILE="$OPTARG"
            ;;
        n)
            ITERATIONS="$OPTARG"
            ;;
        h)
            show_help
            exit 0
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            echo "Use -h for help."
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
    esac
done

# Validate iterations parameter
if ! [[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: Number of iterations must be a positive integer."
    exit 1
fi

echo "=== NIfTI Round-trip Conversion Script ==="
echo "Iterations: $ITERATIONS"

# Check dependencies
check_dependencies

# Validate input
validate_input

# Create base output directory
if [ ! -d "$BASE_OUTPUT_DIR" ]; then
    mkdir -p "$BASE_OUTPUT_DIR"
    echo "Created output directory: $BASE_OUTPUT_DIR"
fi

# Get the base name of input file (without path and extension)
INPUT_BASENAME=$(basename "$INPUT_FILE")
INPUT_BASENAME="${INPUT_BASENAME%.nii.gz}"
INPUT_BASENAME="${INPUT_BASENAME%.nii}"

# Current working file (starts with original input)
CURRENT_FILE="$INPUT_FILE"

echo ""
echo "Starting round-trip conversions..."
echo "Base name: $INPUT_BASENAME"

# Main conversion loop
for ((round=1; round<=ITERATIONS; round++)); do
    echo ""
    echo "=== Round $round/$ITERATIONS ==="
    
    # Create round directory
    ROUND_DIR="$BASE_OUTPUT_DIR/round_$round"
    DICOM_DIR="$ROUND_DIR/dicom"
    NIFTI_DIR="$ROUND_DIR/nifti"
    
    mkdir -p "$DICOM_DIR" "$NIFTI_DIR"
    echo "Created directories: $ROUND_DIR"
    
    # Step 1: Convert NIfTI to DICOM
    echo "Step 1: Converting NIfTI to DICOM..."
    echo "Command: nii2dcm \"$CURRENT_FILE\" \"$DICOM_DIR\""
    
    if ! nii2dcm "$CURRENT_FILE" "$DICOM_DIR" -d MR; then
        echo "Error: Failed to convert NIfTI to DICOM in round $round"
        exit 1
    fi
    
    # Check if DICOM files were created
    DICOM_COUNT=$(find "$DICOM_DIR" -name "*.dcm" 2>/dev/null | wc -l)
    echo "Created $DICOM_COUNT DICOM files"
    
    if [ "$DICOM_COUNT" -eq 0 ]; then
        echo "Warning: No DICOM files found in $DICOM_DIR"
    fi
    
    # Step 2: Convert DICOM back to NIfTI
    echo "Step 2: Converting DICOM to NIfTI..."
    echo "Command: dcm2niix -o \"$NIFTI_DIR\" \"$DICOM_DIR\""
    
    if ! dcm2niix -o "$NIFTI_DIR" "$DICOM_DIR"; then
        echo "Error: Failed to convert DICOM to NIfTI in round $round"
        exit 1
    fi
    
    # Find the created NIfTI file for next iteration
    NIFTI_FILES=($(find "$NIFTI_DIR" -name "*.nii*" 2>/dev/null))
    
    if [ ${#NIFTI_FILES[@]} -eq 0 ]; then
        echo "Error: No NIfTI files created in round $round"
        exit 1
    elif [ ${#NIFTI_FILES[@]} -gt 1 ]; then
        echo "Warning: Multiple NIfTI files created:"
        printf " - %s\n" "${NIFTI_FILES[@]}"
        echo "Using the first one for next iteration: ${NIFTI_FILES[0]}"
    fi
    
    # Update current file for next iteration
    CURRENT_FILE="${NIFTI_FILES[0]}"
    
    echo "Round $round completed successfully"
    echo "Output NIfTI: $CURRENT_FILE"
done

echo ""
echo "=== Conversion Summary ==="
echo "Original file: $INPUT_FILE"
echo "Final file: $CURRENT_FILE"
echo "Completed $ITERATIONS round-trip conversions"
echo "Output directory: $BASE_OUTPUT_DIR"
echo ""
echo "Directory structure:"
find "$BASE_OUTPUT_DIR" -type d | sort