#!/usr/bin/env python
import os
import sys
import subprocess
import importlib

try:
    yaml = importlib.import_module("yaml")
except ImportError:
    print("❌ ERROR: Missing dependency 'PyYAML'. Install it with: pip install pyyaml")
    sys.exit(1)

# Paths
TEMPLATE_FILE = '/data3/project-sda/sda-bpctl/config.yaml.example'
OUTPUT_FILE = 'config.yaml'
S3_CONF_FILE = '/data3/project-sda/misc/bp-submission/s3cmd-bp-download.conf'

# Hard-coded values
HARDCODED_MAIL = "bp-notify@nbis.se"

def get_dataset_id():
    """extract dataset ID from the file dataset_id.txt in the current directory.
    if this file does not exist or is empty, fetch from the environment variable DATASET_ID. If both are missing, exit with an error.
    """
    try:
        with open('dataset_id.txt', 'r') as f:
            dataset_id = f.read().strip()
            if not dataset_id:
                raise ValueError("dataset_id.txt is empty")
            return dataset_id
    except FileNotFoundError:
        env_dataset_id = os.getenv("DATASET_ID")
        if env_dataset_id:
            return env_dataset_id
        print("❌ ERROR: dataset_id.txt not found and DATASET_ID environment variable is not set.")
        sys.exit(1)
    except Exception as e:
        print(f"❌ ERROR: Could not read dataset ID: {e}")
        sys.exit(1)

def get_user_id():
    """Fetches the user ID from ../inbox-all.s3.txt, or if that fails, from the environment variable USER_ID."""
    dataset_folder = os.getenv("DATASET_FOLDER")
    if not dataset_folder:
        print("❌ ERROR: DATASET_FOLDER environment variable is not set.")
        sys.exit(1)
    inbox_file = '../inbox-all.s3.txt'
    #  grep  $DATASET_FOLDER  inbox-all.s3.txt | awk '{print $NF}' | awk -F'/' '{print $4}' | sort | uniq -c
    # if the above command has more than two lines, it means there are multiple users for this dataset, which is an error. If it has exactly one line, we can extract the user ID from it. If it has zero lines, we fall back to the environment variable.
    try:
        cmd = f"grep {dataset_folder} {inbox_file} | awk '{{print $NF}}' | awk -F'/' '{{print $4}}' | sort | uniq -c"
        result = subprocess.check_output(cmd, shell=True, text=True).strip()
        lines = result.splitlines()
        if len(lines) > 1:
            print(f"❌ ERROR: Multiple users found for dataset folder '{dataset_folder}' in {inbox_file}:")
            print(result)
            sys.exit(1)
        elif len(lines) == 1:
            user_id = lines[0].split()[-1]
            # replace underscores with @ in the user ID
            user_id = user_id.replace('_', '@')
            return user_id
    except subprocess.CalledProcessError:
        print(f"⚠️ WARNING: Could not find user ID for dataset folder '{dataset_folder}' in {inbox_file}. Falling back to USER_ID environment variable.")   

    user_id = os.getenv("USER_ID")
    if not user_id:
        print("❌ ERROR: USER_ID environment variable is not set.")
        sys.exit(1)
    # replace underscores with @ in the user ID
    user_id = user_id.replace('_', '@')
    return user_id


def get_vault_password():
    """Fetches the email password from HashiCorp Vault."""
    try:
        # Runs the specific vault command to get the field
        cmd = ["vault", "kv", "get", "--field=email-pw", "bp-secrets/bp-notify"]
        password = subprocess.check_output(cmd, text=True).strip()
        if not password:
            raise ValueError("Vault returned an empty password")
        return password
    except subprocess.CalledProcessError as e:
        print("❌ ERROR: Vault command failed. Ensure you are logged in ('vault login').")
        print(f"   Details: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ ERROR: Could not fetch MAIL_PASSWORD from Vault: {e}")
        sys.exit(1)

def get_access_token():
    """Extracts the access token from the s3cmd config file."""
    try:
        cmd = f"grep access_token {S3_CONF_FILE} | awk '{{print $NF}}'"
        token = subprocess.check_output(cmd, shell=True, text=True).strip()
        if not token:
            raise ValueError("Token is empty")
        return token
    except Exception as e:
        print(f"❌ ERROR: Could not extract CLIENT_ACCESS_TOKEN from {S3_CONF_FILE}")
        print(f"   Details: {e}")
        sys.exit(1)

def generate_config():
    # the current folder name must be the same as the DATASET_FOLDER environment variable. This is a safety check to ensure we are generating the config for the correct dataset.
    dataset_folder = os.getenv("DATASET_FOLDER")
    if not dataset_folder:
        print("❌ ERROR: DATASET_FOLDER environment variable is not set. This variable must be set to the name of the dataset folder (e.g., 'dataset-12345').")
        sys.exit(1)
    current_folder = os.path.basename(os.getcwd())
    if current_folder != dataset_folder:
        print(f"❌ ERROR: Current folder '{current_folder}' does not match DATASET_FOLDER '{dataset_folder}'. Please navigate to the correct dataset folder before running this script.")
        sys.exit(1)

    # 1. Load the template
    try:
        with open(TEMPLATE_FILE, 'r') as f:
            config_data = yaml.safe_load(f)
    except FileNotFoundError:
        print(f"❌ ERROR: Template file not found at: {TEMPLATE_FILE}")
        sys.exit(1)

    missing_vars = []

    # 2. Process all keys found in the YAML template
    for key in config_data:
        # Case 1: Hard-coded Email
        if key == "MAIL_ADDRESS":
            config_data[key] = HARDCODED_MAIL
        
        # Case 2: Extract Token from file
        elif key == "CLIENT_ACCESS_TOKEN":
            config_data[key] = get_access_token()
            
        # Case 3: Fetch Password from Vault
        elif key == "MAIL_PASSWORD":
            config_data[key] = get_vault_password()

        elif key == "DATASET_ID":
            config_data[key] = get_dataset_id()
        
        elif key == "USER_ID":
            config_data[key] = get_user_id()
            
        # Case 4: Everything else from Environment Variables
        else:
            env_value = os.getenv(key)
            if env_value:
                config_data[key] = env_value
            else:
                missing_vars.append(key)

    # 3. Report errors
    if missing_vars:
        print("❌ ERROR: Missing Environment Variables:")
        for var in missing_vars:
            print(f"  - {var}")
        sys.exit(1)

    # 4. Write the final config
    try:
        with open(OUTPUT_FILE, 'w') as f:
            yaml.dump(config_data, f, default_flow_style=False, sort_keys=False, width=float('inf'))
            print(f"✅ Successfully generated: {OUTPUT_FILE}")
    except PermissionError:
        print(f"❌ ERROR: Permission denied when writing to: {OUTPUT_FILE}")
        sys.exit(1)

if __name__ == "__main__":
    generate_config()