#!/bin/bash

# HOURROI Bot Quick Deployment Script
# This script automates the deployment process on a VPS

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "🚀 HOURROI Bot Quick Deployment"
echo "================================"
echo -e "${NC}"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}❌ This script should not be run as root${NC}"
   exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js is not installed. Please run setup-vps.sh first${NC}"
    exit 1
fi

# Check if PM2 is installed
if ! command -v pm2 &> /dev/null; then
    echo -e "${RED}❌ PM2 is not installed. Please run setup-vps.sh first${NC}"
    exit 1
fi

echo -e "${YELLOW}📋 Pre-deployment checks...${NC}"

# Check if we're in the correct directory
if [[ ! -f "ankr-bot.js" ]]; then
    echo -e "${RED}❌ ankr-bot.js not found. Please run this script from the bot directory${NC}"
    exit 1
fi

# Check if environment file exists
if [[ ! -f ".env" ]]; then
    echo -e "${YELLOW}⚠️ .env file not found. Creating from template...${NC}"
    if [[ -f ".env.example" ]]; then
        cp .env.example .env
        echo -e "${YELLOW}📝 Please edit .env file with your configuration:${NC}"
        echo "   nano .env"
        echo -e "${YELLOW}Press Enter when ready to continue...${NC}"
        read
    else
        echo -e "${RED}❌ .env.example not found. Please create .env manually${NC}"
        exit 1
    fi
fi

echo -e "${YELLOW}📦 Installing dependencies...${NC}"
npm install --production

echo -e "${YELLOW}🧪 Testing bot configuration...${NC}"
if npm test; then
    echo -e "${GREEN}✅ Configuration test passed${NC}"
else
    echo -e "${RED}❌ Configuration test failed. Please check your .env file${NC}"
    exit 1
fi

echo -e "${YELLOW}🔧 Setting up PM2 configuration...${NC}"

# Stop any existing instance
pm2 delete hourroi-bot 2>/dev/null || true

# Start the bot with PM2
pm2 start ecosystem.config.js --env production

# Save PM2 configuration
pm2 save

echo -e "${YELLOW}⚙️ Setting up system service...${NC}"

# Check if systemd service exists
if [[ -f "hourroi-bot.service" ]]; then
    echo -e "${YELLOW}Installing systemd service...${NC}"
    sudo cp hourroi-bot.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable hourroi-bot
    
    # Start the service
    if sudo systemctl start hourroi-bot; then
        echo -e "${GREEN}✅ Systemd service started successfully${NC}"
    else
        echo -e "${YELLOW}⚠️ Systemd service failed, but PM2 is running${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ systemd service file not found, using PM2 only${NC}"
fi

echo -e "${GREEN}"
echo "🎉 DEPLOYMENT COMPLETE!"
echo "======================"
echo -e "${NC}"

echo -e "${BLUE}📊 Status Check:${NC}"
pm2 status

echo -e "${BLUE}🔍 Monitoring Commands:${NC}"
echo "  pm2 logs hourroi-bot       # View logs"
echo "  pm2 monit                  # Monitor resources"  
echo "  pm2 restart hourroi-bot    # Restart bot"
echo ""

if systemctl is-active --quiet hourroi-bot 2>/dev/null; then
    echo -e "${BLUE}🔧 System Service Commands:${NC}"
    echo "  sudo systemctl status hourroi-bot   # Check status"
    echo "  sudo systemctl restart hourroi-bot  # Restart service"
    echo "  sudo journalctl -u hourroi-bot -f   # View system logs"
    echo ""
fi

echo -e "${BLUE}🌐 Health Check:${NC}"
if curl -s http://localhost:3000/health > /dev/null; then
    echo -e "${GREEN}✅ Health endpoint is responding${NC}"
    curl http://localhost:3000/health
else
    echo -e "${YELLOW}⚠️ Health endpoint not responding (this may be normal)${NC}"
fi

echo ""
echo -e "${GREEN}🚀 Bot is now running! Check your Telegram channel for notifications.${NC}"