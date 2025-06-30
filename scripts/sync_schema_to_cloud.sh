#!/bin/bash

# Check if required tools are installed
command -v gsutil >/dev/null 2>&1 || {
    echo "❌ Error: gsutil is required but not installed."
    exit 1
}

# Function to display usage
usage() {
    echo "Usage: $0 -f FILE_PATH [-b BUCKET_NAME]"
    echo "Example: $0 -f schema/bronze-event-schema-v1.json"
    echo ""
    echo "Options:"
    echo "  -f FILE_PATH     Path to the schema file (e.g. schema/x.json)"
    echo "  -b BUCKET_NAME   (Optional) GCS bucket name. Defaults to \$APP_CONFIG_BUCKET"
    echo "  -h               Display this help message"
    exit 1
}

# Parse command line arguments
while getopts "f:b:h" opt; do
    case $opt in
    f) file_path="$OPTARG" ;;
    b) bucket_name="$OPTARG" ;;
    h) usage ;;
    ?) usage ;;
    esac
done

if [ -z "$file_path" ]; then
    echo "❌ Error: Missing required parameter -f FILE_PATH"
    usage
fi

# Fallback to environment variable if bucket not passed
bucket_name="${bucket_name:-$APP_CONFIG_BUCKET}"

if [ -z "$bucket_name" ]; then
    echo "❌ Error: GCS bucket not provided via -b or \$APP_CONFIG_BUCKET"
    exit 1
fi

# Extract file components
file_name_with_ext=$(basename "$file_path") #
file_name_no_ext="${file_name_with_ext%.*}"

# Upload the file
echo "📤 Uploading '$file_path' to 'gs://${bucket_name}/${file_path}'..."
gsutil cp "$file_path" "gs://${bucket_name}/${file_path}"

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to upload file to gs://${bucket_name}/${file_path}"
    exit 1
fi

echo "✅ Upload complete."
