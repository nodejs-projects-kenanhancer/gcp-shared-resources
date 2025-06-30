#!/bin/bash
# Function to print usage
print_usage() {
    echo "Description:"
    echo " Sets or updates properties in environment configuration files"
    echo
    echo "Usage (as standalone script):"
    echo " set_env_property.sh -f|--file <config-file> -k|--key <key> -v|--value <value>"
    echo
    echo "Usage (as sourced function):"
    echo " set_env_property --key <key> --value <value> --file <config-file>"
    echo
    echo "Arguments:"
    echo " -f, --file Path to configuration file"
    echo " -k, --key Key to update"
    echo " -v, --value New value to set"
    echo " -h, --help Show this help message"
    echo
    echo "Examples:"
    echo " # As standalone script:"
    echo " set_env_property.sh -f .env.myapp -k SERVER_PORT -v 8080"
    echo " set_env_property.sh -f configs/terraform.tfvars -k gcp_project_id -v my-new-project-id"
    echo
    echo " # As sourced function:"
    echo " source set_env_property.sh"
    echo " set_env_property --key SERVER_PORT --value 8080 --file .env.myapp"
}

# Function to update a key-value pair in a file with named parameters
set_env_property() {
    local params=()
    local file=""
    local key=""
    local value=""

    # Parse named parameters
    while [[ $# -gt 0 ]]; do
        case $1 in
        --file)
            file="$2"
            shift 2
            ;;
        --key)
            key="$2"
            shift 2
            ;;
        --value)
            value="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            return 1
            ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$file" || -z "$key" || -z "$value" ]]; then
        echo "Error: Missing required parameters for set_env_property function"
        echo "Required: --file, --key, --value"
        return 1
    fi

    echo "Updating '$key' in $file..."

    # Determine file type and use appropriate update method
    if [[ "$file" == *.env* || "$file" == env.* ]]; then
        # For .env files (format: KEY=VALUE)
        echo "Detected .env file format"

        # Debug output
        echo "Checking for key pattern: ^$key="
        grep -q "^$key=" "$file" && echo "Key found" || echo "Key not found"

        if grep -q "^$key=" "$file"; then
            # Key exists, update it
            echo "Updating existing key..."
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s|^$key=.*|$key=$value|" "$file"
            else
                sed -i "s|^$key=.*|$key=$value|" "$file"
            fi
        else
            echo "Key not found, adding it..."
            # Key doesn't exist, add it to appropriate section
            if [[ "$key" == BASIC_SETTINGS__* ]] && grep -q "^# Basic Settings" "$file"; then
                echo "Adding to Basic Settings section..."
                # Find the line number of the last BASIC_SETTINGS__ entry
                last_basic_line=$(grep -n "^BASIC_SETTINGS__" "$file" | tail -1 | cut -d: -f1)

                if [[ -n "$last_basic_line" ]]; then
                    # Insert after the last BASIC_SETTINGS__ line
                    echo "Inserting after line $last_basic_line"
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        sed -i '' "${last_basic_line}a\\
$key=$value" "$file"
                    else
                        sed -i "${last_basic_line}a\\$key=$value" "$file"
                    fi
                else
                    # No BASIC_SETTINGS__ lines found, add after the section header
                    echo "No existing BASIC_SETTINGS found, adding after section header"
                    section_line=$(grep -n "^# Basic Settings" "$file" | cut -d: -f1)
                    if [[ -n "$section_line" ]]; then
                        if [[ "$OSTYPE" == "darwin"* ]]; then
                            sed -i '' "${section_line}a\\
$key=$value" "$file"
                        else
                            sed -i "${section_line}a\\$key=$value" "$file"
                        fi
                    else
                        # No Basic Settings section, just append to the end
                        echo "No Basic Settings section found, appending to end of file"
                        echo "$key=$value" >>"$file"
                    fi
                fi
            else
                # For non-BASIC_SETTINGS keys or no Basic Settings section, just append to the end
                echo "Appending to end of file"
                echo "$key=$value" >>"$file"
            fi
        fi

        # Check if update was successful
        if grep -q "^$key=$value" "$file"; then
            echo "✅ Successfully updated $key to '$value' in $file"
        else
            echo "⚠️ Warning: Failed to update $key in $file"
            echo "Current content of file:"
            cat "$file"
        fi
    elif [[ "$file" == *.tfvars ]]; then
        # For terraform.tfvars files with possible nested maps
        echo "Detected Terraform tfvars file format"

        # Check different patterns for the key, including inside maps
        if grep -q "^$key *=" "$file"; then
            # Key exists as a top-level property
            echo "Found as top-level property"
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s/^$key *= *\"[^\"]*\"/$key = \"$value\"/" "$file"
            else
                sed -i "s/^$key *= *\"[^\"]*\"/$key = \"$value\"/" "$file"
            fi
        elif grep -q "^[[:space:]]*$key *=" "$file"; then
            # Key exists with indentation (likely in a map)
            echo "Found as indented property (in map)"
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s/^\([[:space:]]*\)$key *= *\"[^\"]*\"/\\1$key = \"$value\"/" "$file"
            else
                sed -i "s/^\([[:space:]]*\)$key *= *\"[^\"]*\"/\\1$key = \"$value\"/" "$file"
            fi
        else
            echo "Key not found as a direct property, need to add it"
            # Instead of blindly appending, we should find an appropriate place
            # For simplicity, append to end of file for now
            echo "$key = \"$value\"" >>"$file"
        fi

        # Check if update was successful - using broader pattern matching
        if grep -q "$key *= *\"$value\"" "$file"; then
            echo "✅ Successfully updated $key to '$value' in $file"
        else
            echo "⚠️ Warning: Failed to update $key in $file"
            echo "Current content of file (first 20 lines):"
            head -n 20 "$file"
        fi
    else
        # For standard config files (format: key = "value")
        echo "Detected standard config file format"

        # Use exact key matching with word boundaries for more precise matches
        if grep -q "\<$key\> *=" "$file"; then
            # Key exists, update it - using word boundaries to ensure exact matches
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s/\<$key\> *= *\"[^\"]*\"/\<$key\> = \"$value\"/" "$file"
            else
                sed -i "s/\<$key\> *= *\"[^\"]*\"/\<$key\> = \"$value\"/" "$file"
            fi
        else
            # Key doesn't exist, append it
            echo "$key = \"$value\"" >>"$file"
        fi

        # Check if update was successful
        if grep -q "\<$key\> *= *\"$value\"" "$file"; then
            echo "✅ Successfully updated $key to '$value' in $file"
        else
            echo "⚠️ Warning: Failed to update $key in $file or value was already set"
        fi
    fi
}

# Main function
main() {
    # Initialize variables
    local config_file=""
    local key=""
    local value=""

    # Parse named arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
        -f | --file)
            config_file="$2"
            shift 2
            ;;
        -k | --key)
            key="$2"
            shift 2
            ;;
        -v | --value)
            value="$2"
            shift 2
            ;;
        -h | --help)
            print_usage
            return 0
            ;;
        *)
            echo "Error: Unknown parameter $1"
            print_usage
            return 1
            ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$config_file" || -z "$key" || -z "$value" ]]; then
        echo "Error: Missing required arguments"
        print_usage
        return 1
    fi

    # Check if file exists
    if [ ! -f "$config_file" ]; then
        echo "Error: File $config_file not found"
        return 1
    fi

    # Update the key-value pair using named parameters
    set_env_property --key "$key" --value "$value" --file "$config_file"

    return 0
}

# If script is being run directly (not sourced), execute with provided arguments
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
    main "$@"
fi
