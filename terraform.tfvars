name   = "demo"
region = "us-east-1"

# Lock this down in production (example IP)
allowed_api_cidrs = ["103.92.84.23/32"]

# Best production: use SSM (enable_ssh=false)
enable_ssh = false

# If you REALLY want SSH (break-glass), turn it on and restrict CIDR:
# enable_ssh = true
# ssh_key_name = "mykeypair2"
# ssh_allowed_cidrs = ["YOUR_PUBLIC_IP/32"]
