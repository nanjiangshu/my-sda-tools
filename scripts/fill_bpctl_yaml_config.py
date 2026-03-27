#!/usr/bin/env python
import os
import yaml
import sys
import subprocess

# Paths
TEMPLATE_FILE = '/data3/project-sda/sda-bpctl/config.yaml.example'
OUTPUT_FILE = 'config.yaml'
S3_CONF_FILE = '/data3/project-sda/misc/bp-submission/s3cmd-bp-download.conf'

# Hard-coded values
HARDCODED_MAIL = "bp-notify@nbis.se"

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
            yaml.dump(config_data, f, default_flow_style=False, sort_keys=False)
            print(f"✅ Successfully generated: {OUTPUT_FILE}")
    except PermissionError:
        print(f"❌ ERROR: Permission denied when writing to: {OUTPUT_FILE}")
        sys.exit(1)

if __name__ == "__main__":
    generate_config()