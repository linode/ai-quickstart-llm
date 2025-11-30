# Akamai inference Cloud - AI Quickstart gpt-oss-20b LLM

Automated deployment script to run your private, self-hosted LLM inference server on Akamai Cloud GPU instances. Pre-configured with OpenAI's gpt-oss-20b (20B parameter open-source model) optimized for instruction following. Get vLLM and Open-WebUI up and running in minutes with a single command.

-----------------------------------------
## 🚀 Quick Start

Just run this single command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/linode/ai-quickstart-gpt-oss-20b/main/deploy.sh)
```

That's it! The script will download required files and guide you through the interactive deployment process.

## ✨ Features
- Fully Automated Deployment: handles instance creation with real-time progress tracking
- Basic AI Stack: vLLM for LLM inference with pre-loaded model and Open-WebUI for chat interface
- Cross-Platform Support: Works on macOS and Windows (Git Bash/WSL)

-----------------------------------------

## 🏗️ What Gets Deployed

<img src="docs/architecture.svg" alt="Architecture" align="left" width="600"/>

<br clear="left"/>

### Linode GPU Instance with
- Ubuntu 24.04 LTS with NVIDIA drivers
- Docker & NVIDIA Container Toolkit
- Systemd service for automatic startup on reboot

### Docker container
| | Service | Description | 
|:--:|:--|:--|
| <img src="https://raw.githubusercontent.com/vllm-project/media-kit/main/vLLM-Logo.png" alt="vLLM" width="32"/> | **vLLM** | High-throughput LLM inference engine with OpenAI-compatible API (port 8000) |
| <img src="https://raw.githubusercontent.com/open-webui/open-webui/main/static/favicon.png" alt="Open-WebUI" width="32"/> | **Open-WebUI** | Feature-rich web interface for AI chat interactions (port 3000) |

-----------------------------------------

## 📋 Requirements

### Akamai Cloud Account
- Active Linode account with GPU access enabled

### Local System Requirements
- **Required**: bash, curl, ssh, jq
- **Note**: jq will be auto-installed if missing

-----------------------------------------
## 🚦 Getting Started

### 1. Option A: Single Command Execution

No installation required - just run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/linode/ai-quickstart-gpt-oss-20b/main/deploy.sh)
```

### 1. Option B: Download and Run

Download the script and run locally:

```bash
curl -fsSLO https://raw.githubusercontent.com/linode/ai-quickstart-gpt-oss-20b/main/deploy.sh
bash deploy.sh
```

### 1. Option C: Clone Repository

If you prefer to inspect or customize the scripts:

```bash
git clone https://github.com/linode/ai-quickstart-gpt-oss-20b
cd ai-quickstart-gpt-oss-20b
./deploy.sh
```

> [!NOTE]
> if you like to add more services check out docker compose template file
> ```
> vi /template/docker-compose.yml
> ```
>

### 2. Follow Interactive Prompts
The script will ask you to:
- Choose a region (e.g., us-east, eu-west)
- Select GPU instance type
- Provide instance label
- Select or generate SSH keys
- Confirm deployment

### 3. Wait for Deployment
The script automatically:
- Creates GPU instance in your linode account
- Monitors cloud-init installation progress
- Waits for Open-WebUI health check
- Waits for vLLM model loading

### 4. Access Your Services
Once complete, you'll see:
```
🎉 Setup Complete!

✅ Your AI LLM instance is now running!

🌐 Access URLs:
   Open-WebUI:  http://<instance-ip>:3000

🔐 Access Credentials:
   SSH:   ssh -i /path/to/your/key root@<instance-ip>
```

### Configuration files in GPU Instance
```
   # Install script called by cloud-init service
   /opt/ai-quickstart-gpt-oss-20b/install.sh

   # docker compose file calle by systemctl at startup
   /opt/ai-quickstart-gpt-oss-20b/docker-compose.yml

   # service definition
   /etc/systemd/system/ai-quickstart-gpt-oss-20b.service
```

-----------------------------------------

## 🗑️ Delete Instance

To delete a deployed instance:

```bash
# Remote execution
bash <(curl -fsSL https://raw.githubusercontent.com/linode/ai-quickstart-gpt-oss-20b/main/delete.sh) <instance_id>

# Or if you cloned the repo
./delete.sh <instance_id>
```

The script will show instance details and ask for confirmation before deletion.

-----------------------------------------

## 📁 Project Structure

```
ai-quickstart-gpt-oss-20b/
├── deploy.sh                    # Main deployment script
├── delete.sh                    # Instance deletion script
├── script/
│   └── quickstart_tools.sh      # Shared functions (API, OAuth, utilities)
└── template/
    ├── cloud-init.yaml          # Cloud-init configuration
    ├── docker-compose.yml       # Docker Compose configuration
    └── install.sh               # Post-boot installation script
```

-----------------------------------------
## 🔒 Security

**⚠️ IMPORTANT**: By default, ports 3000 are exposed to the internet

### Immediate Security Steps

1. **Configure Cloud Firewall** (Recommended)
   - Create Linode Cloud Firewall
   - Restrict access to ports 3000 by source IP
   - Allow SSH (port 22) from trusted IPs only

2. **SSH Security**
   - SSH key authentication required
   - Root password provided for emergency console access only

-----------------------------------------
## 🛠️ Useful Commands

```bash
# SSH into your instance
ssh -i /path/to/your/key root@<instance-ip>

# Check container status
docker ps -a

# Check Docker containers log
cd /opt/ai-quickstart-gpt-oss-20b && docker compose logs -f

# Check systemd service status
systemctl status ai-quickstart-gpt-oss-20b.service

# View systemd service logs
journalctl -u ai-quickstart-gpt-oss-20b.service -n 100

# Check cloud-init logs
tail -f /var/log/cloud-init-output.log -n 100

# Restart all services
systemctl restart ai-quickstart-gpt-oss-20b.service

# Check NVIDIA GPU status
nvidia-smi

# Check vLLM loaded models
curl http://localhost:8000/v1/models

# Check Open-WebUI health
curl http://localhost:3000/health

# Check vLLM container logs
docker logs vllm
```

## 🤝 Contributing

Issues and pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

## 📄 License

This project is licensed under the Apache License 2.0.

