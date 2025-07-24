#!/bin/bash

# Complete VPS Setup Script for HOURROI Bot
# Run as: curl -sSL https://your-domain.com/setup-vps.sh | bash

set -e

echo "🚀 HOURROI Bot VPS Setup Starting..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}This script should not be run as root${NC}"
   exit 1
fi

# Update system
echo -e "${YELLOW}📦 Updating system...${NC}"
sudo apt update && sudo apt upgrade -y

# Install dependencies
echo -e "${YELLOW}🔧 Installing dependencies...${NC}"
sudo apt install -y curl wget git ufw fail2ban htop

# Install Node.js 18.x
echo -e "${YELLOW}🟢 Installing Node.js 18.x...${NC}"
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify Node.js installation
node_version=$(node --version)
npm_version=$(npm --version)
echo -e "${GREEN}✅ Node.js ${node_version} and npm ${npm_version} installed${NC}"

# Install PM2 globally
echo -e "${YELLOW}⚡ Installing PM2...${NC}"
sudo npm install -g pm2

# Create user for bot (if doesn't exist)
if ! id "www-data" &>/dev/null; then
    sudo useradd -r -s /bin/false www-data
fi

# Create directories
echo -e "${YELLOW}📁 Creating directories...${NC}"
sudo mkdir -p /opt/hourroi-bot
sudo mkdir -p /var/log/hourroi-bot
sudo chown -R www-data:www-data /opt/hourroi-bot
sudo chown -R www-data:www-data /var/log/hourroi-bot

# Set up firewall
echo -e "${YELLOW}🔥 Configuring firewall...${NC}"
sudo ufw --force enable
sudo ufw allow ssh
sudo ufw allow 3000/tcp  # Health endpoint
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS

# Configure fail2ban
echo -e "${YELLOW}🛡️ Configuring fail2ban...${NC}"
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

echo -e "${GREEN}✅ VPS Setup Complete!${NC}"
echo ""
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo "1. Upload your bot files to /opt/hourroi-bot/"
echo "2. Run: sudo chown -R www-data:www-data /opt/hourroi-bot"
echo "3. Run: cd /opt/hourroi-bot && sudo -u www-data npm install"
echo "4. Copy systemd service: sudo cp hourroi-bot.service /etc/systemd/system/"
echo "5. Enable service: sudo systemctl enable hourroi-bot"
echo "6. Start service: sudo systemctl start hourroi-bot"
echo ""
echo -e "${GREEN}🎯 Monitoring Commands:${NC}"
echo "• Status: sudo systemctl status hourroi-bot"
echo "• Logs: sudo journalctl -u hourroi-bot -f"
echo "• PM2 Logs: sudo -u www-data pm2 logs"
echo "• PM2 Status: sudo -u www-data pm2 status"