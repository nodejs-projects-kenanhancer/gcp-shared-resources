#!/usr/bin/env python3
import argparse
import json
import sys
from typing import Any, Dict


def print_usage():
    """Print usage information for the script."""
    usage = """
Usage: python convert.py [-h] (-f JSON_FILE | -j JSON_STRING) [-o OUTPUT_FILE]

Convert JSON configuration to HCL format.

Required arguments (choose one):
  -f JSON_FILE, --file JSON_FILE        Input JSON file path
  -j JSON_STRING, --json JSON_STRING    JSON string input

Optional arguments:
  -o OUTPUT_FILE, --output OUTPUT_FILE  Output HCL file path (default: stdout)
  -h, --help                           Show this help message and exit

Examples:
  python convert.py -f config.json -o terraform.tfvars
  python convert.py -j '{"key": "value"}' -o terraform.tfvars
  python convert.py -f config.json  # prints to stdout
  python convert.py -j '{"key": "value"}'  # prints to stdout
"""
    print(usage)


def load_json_file(json_file: str) -> Dict[str, Any]:
    """Load and parse JSON from file."""
    try:
        with open(json_file, "r") as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"Error: Input file '{json_file}' not found.", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"Error: Invalid JSON format in '{json_file}'.", file=sys.stderr)
        sys.exit(1)


def parse_json_string(json_string: str) -> Dict[str, Any]:
    """Parse JSON from string."""
    try:
        return json.loads(json_string)
    except json.JSONDecodeError:
        print("Error: Invalid JSON string format.", file=sys.stderr)
        sys.exit(1)


def dict_to_hcl(dictionary: Dict[str, Any], indent: int = 0) -> str:
    """Convert Python dictionary to HCL format."""
    hcl_str = ""
    indent_str = " " * indent

    for key, value in dictionary.items():
        if isinstance(value, dict):
            hcl_str += f"{indent_str}{key} = {{\n"
            hcl_str += dict_to_hcl(value, indent + 2)
            hcl_str += f"{indent_str}}}\n"
        elif isinstance(value, list):
            hcl_str += f"{indent_str}{key} = {json.dumps(value)}\n"
        else:
            hcl_str += f"{indent_str}{key} = {json.dumps(value)}\n"

    return hcl_str


def output_hcl(hcl_data: str, output_file: str | None = None):
    """Output HCL data to file or stdout."""
    if output_file:
        try:
            with open(output_file, "w") as f:
                f.write(hcl_data)
            print(
                f"HCL configuration has been written to {output_file}", file=sys.stderr
            )
        except IOError as e:
            print(f"Error: Failed to write to output file: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        # Print to stdout without any status messages
        print(hcl_data, end="")


def main():
    parser = argparse.ArgumentParser(
        description="Convert JSON configuration to HCL format."
    )
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument("-f", "--file", help="Input JSON file path")
    input_group.add_argument("-j", "--json", help="JSON string input")
    parser.add_argument("-o", "--output", help="Output HCL file path (default: stdout)")

    if len(sys.argv) == 1:
        print_usage()
        sys.exit(1)

    args = parser.parse_args()

    # Load and process the JSON
    if args.file:
        json_data = load_json_file(args.file)
    else:
        json_data = parse_json_string(args.json)

    # Convert to HCL
    hcl_data = dict_to_hcl(json_data)

    # Output the result
    output_hcl(hcl_data, args.output)


if __name__ == "__main__":
    main()
