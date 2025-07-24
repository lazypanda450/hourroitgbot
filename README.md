# HOURROI Telegram Bot 🚀

A high-performance Telegram notification bot for monitoring blockchain events on the HOURROI DApp smart contract. The bot tracks user joins and rejoins on the BSC (Binance Smart Chain) network and sends real-time notifications to a Telegram channel.

## ✨ Features

- 🔄 **Real-time WebSocket Event Monitoring** - 95% fewer API calls than polling
- 📡 **Hybrid System** - WebSocket primary, polling fallback 
- ⚡ **Ankr RPC Integration** - Premium blockchain connectivity
- 🔁 **Auto-reconnection** - Intelligent failover and recovery
- 📊 **Performance Monitoring** - Built-in health checks and statistics
- 🛡️ **Production Ready** - PM2 process management with systemd integration
- 📈 **Load Balancing** - Multiple RPC endpoints with automatic failover

## 📋 Prerequisites

- Linux VPS (Ubuntu 20.04+ recommended)
- Node.js 18.x or higher
- Telegram Bot Token
- Ankr API Key
- BSC Mainnet access

## 🚀 Quick Start

### 1. Server Preparation

```bash
# Download and run the setup script
wget https://raw.githubusercontent.com/your-repo/hourroi-bot/main/setup-vps.sh
chmod +x setup-vps.sh
./setup-vps.sh
```

### 2. Deploy Bot Files

```bash
# Upload your bot files to the server
scp -r * user@your-vps-ip:/opt/hourroi-bot/

# Or clone from repository
cd /opt/hourroi-bot
git clone https://github.com/your-repo/hourroi-bot.git .
```

### 3. Install Dependencies

```bash
cd /opt/hourroi-bot
sudo -u www-data npm install
```

### 4. Configure Environment

Create or update `.env` file:

```bash
sudo nano /opt/hourroi-bot/.env
```

```env
# Telegram Configuration
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here

# Ankr API Configuration  
ANKR_API_KEY=your_ankr_api_key_here

# Server Configuration
PORT=3000
NODE_ENV=production
```

### 5. Start the Bot

```bash
# Copy systemd service file
sudo cp hourroi-bot.service /etc/systemd/system/

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl enable hourroi-bot

# Start the bot
sudo systemctl start hourroi-bot

# Check status
sudo systemctl status hourroi-bot
```

## 📖 Detailed Deployment Guide

### Step 1: VPS Setup

#### System Requirements
- **OS**: Ubuntu 20.04 LTS or newer
- **RAM**: Minimum 1GB, 2GB recommended
- **Storage**: 10GB available space
- **Network**: Stable internet connection

#### Initial Server Setup

1. **Update system packages:**
```bash
sudo apt update && sudo apt upgrade -y
```

2. **Install essential tools:**
```bash
sudo apt install -y curl wget git ufw fail2ban htop
```

3. **Configure firewall:**
```bash
sudo ufw enable
sudo ufw allow ssh
sudo ufw allow 3000/tcp  # Health endpoint
sudo ufw allow 80/tcp    # HTTP (optional)
sudo ufw allow 443/tcp   # HTTPS (optional)
```

### Step 2: Node.js Installation

```bash
# Install Node.js 18.x
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify installation
node --version  # Should show v18.x.x
npm --version   # Should show 9.x.x or higher
```

### Step 3: PM2 Process Manager

```bash
# Install PM2 globally
sudo npm install -g pm2

# Verify PM2 installation
pm2 --version
```

### Step 4: Application Setup

#### Create Application Directory

```bash
# Create directories
sudo mkdir -p /opt/hourroi-bot
sudo mkdir -p /var/log/hourroi-bot

# Create user for the application
sudo useradd -r -s /bin/false www-data || true

# Set permissions
sudo chown -R www-data:www-data /opt/hourroi-bot
sudo chown -R www-data:www-data /var/log/hourroi-bot
```

#### Deploy Application Files

**Option A: Direct Upload**
```bash
# From your local machine
scp -r * user@your-vps-ip:/tmp/hourroi-bot/
ssh user@your-vps-ip
sudo mv /tmp/hourroi-bot/* /opt/hourroi-bot/
sudo chown -R www-data:www-data /opt/hourroi-bot
```

**Option B: Git Clone**
```bash
cd /opt/hourroi-bot
sudo -u www-data git clone https://github.com/your-repo/hourroi-bot.git .
```

#### Install Dependencies

```bash
cd /opt/hourroi-bot
sudo -u www-data npm install --production
```

### Step 5: Configuration

#### Environment Variables

Create the environment file:

```bash
sudo -u www-data nano /opt/hourroi-bot/.env
```

Add your configuration:

```env
# Telegram Bot Configuration
TELEGRAM_BOT_TOKEN=7201463630:AAFAKhbMb-gb4wiA9HrVHniKJAo8mWHbIFU
TELEGRAM_CHAT_ID=-1002774826288

# Ankr API Configuration
ANKR_API_KEY=41be6db3daba53f8161018ac9400564296e448b8b1b9efdfc88e0ab7c2570bf6

# Server Configuration
PORT=3000
NODE_ENV=production

# Optional: Custom settings
LOG_LEVEL=info
MAX_RETRIES=5
HEALTH_CHECK_INTERVAL=60000
```

#### Secure the Environment File

```bash
sudo chmod 600 /opt/hourroi-bot/.env
sudo chown www-data:www-data /opt/hourroi-bot/.env
```

### Step 6: Systemd Service Setup

#### Install Service File

```bash
# Copy the service file
sudo cp /opt/hourroi-bot/hourroi-bot.service /etc/systemd/system/

# Reload systemd daemon
sudo systemctl daemon-reload
```

#### Enable and Start Service

```bash
# Enable auto-start on boot
sudo systemctl enable hourroi-bot

# Start the service
sudo systemctl start hourroi-bot

# Check status
sudo systemctl status hourroi-bot
```

### Step 7: Verification and Testing

#### Check Service Status

```bash
# Service status
sudo systemctl status hourroi-bot

# Should show: Active: active (running)
```

#### Test Health Endpoint

```bash
# Test health endpoint
curl http://localhost:3000/health

# Expected response:
# {"status":"ok","uptime":123,"timestamp":"2025-01-24T..."}
```

#### Monitor Logs

```bash
# View live logs
sudo journalctl -u hourroi-bot -f

# View PM2 logs
sudo -u www-data pm2 logs hourroi-bot

# View error logs
sudo tail -f /var/log/hourroi-bot/err.log
```

## 🔧 Configuration Options

### Bot Configuration (`config-ankr.js`)

```javascript
// Key configuration options
{
  telegram: {
    botToken: process.env.TELEGRAM_BOT_TOKEN,
    chatId: process.env.TELEGRAM_CHAT_ID,
    enableNotifications: true
  },
  
  blockchain: {
    contractAddress: '0x7EE57D1616B654614B8D334b90dFD9EeA07a3e00',
    rpcUrls: [
      'https://rpc.ankr.com/bsc/YOUR_API_KEY',
      'https://bsc-dataseed.binance.org/'
    ],
    wsUrls: [
      'wss://rpc.ankr.com/bsc/ws/YOUR_API_KEY'
    ]
  },
  
  events: {
    enableWebSocket: true,           // Use WebSocket for real-time events
    checkIntervalSeconds: 30,        // Polling fallback interval
    wsReconnectDelay: 5000,         // WebSocket reconnection delay
    wsMaxReconnectAttempts: 10      // Max reconnection attempts
  }
}
```

### PM2 Configuration (`ecosystem.config.js`)

```javascript
{
  name: 'hourroi-bot',
  script: 'ankr-bot.js',
  instances: 1,
  autorestart: true,
  max_memory_restart: '512M',
  restart_delay: 5000,
  max_restarts: 15,
  env: {
    NODE_ENV: 'production',
    PORT: 3000
  }
}
```

## 📊 Monitoring and Maintenance

### Monitoring Commands

```bash
# Service status
sudo systemctl status hourroi-bot

# Live system logs
sudo journalctl -u hourroi-bot -f

# PM2 process monitoring
sudo -u www-data pm2 monit

# PM2 logs
sudo -u www-data pm2 logs hourroi-bot

# System resource usage
htop
```

### Maintenance Commands

```bash
# Restart the bot
sudo systemctl restart hourroi-bot

# Stop the bot
sudo systemctl stop hourroi-bot

# Reload PM2 configuration
sudo -u www-data pm2 reload hourroi-bot

# View PM2 process list  
sudo -u www-data pm2 list

# PM2 process resurrection (auto-start setup)
sudo -u www-data pm2 startup
sudo -u www-data pm2 save
```

### Log Management

```bash
# View logs by date
sudo journalctl -u hourroi-bot --since "2025-01-24 10:00:00"

# View logs with priority
sudo journalctl -u hourroi-bot -p err

# Rotate PM2 logs
sudo -u www-data pm2 flush hourroi-bot

# Clear old logs
sudo find /var/log/hourroi-bot -name "*.log" -mtime +7 -delete
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Bot Not Starting

**Problem**: Service fails to start
```bash
sudo systemctl status hourroi-bot
# Shows: failed (Result: exit-code)
```

**Solutions**:
```bash
# Check detailed logs
sudo journalctl -u hourroi-bot -n 50

# Verify file permissions
sudo chown -R www-data:www-data /opt/hourroi-bot

# Test manual start
cd /opt/hourroi-bot
sudo -u www-data node ankr-bot.js
```

#### 2. WebSocket Connection Issues

**Problem**: WebSocket fails to connect
```bash
# Logs show: WebSocket connection failed
```

**Solutions**:
```bash
# Test WebSocket endpoint manually
curl -H "Connection: Upgrade" -H "Upgrade: websocket" \
     wss://rpc.ankr.com/bsc/ws/YOUR_API_KEY

# Check firewall settings
sudo ufw status

# Verify API key
curl -X POST https://rpc.ankr.com/bsc/YOUR_API_KEY \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

#### 3. Telegram Notifications Not Working

**Problem**: No messages sent to Telegram
```bash
# Logs show: Telegram API error
```

**Solutions**:
```bash
# Test bot token
curl https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getMe

# Test chat ID
curl https://api.telegram.org/bot<YOUR_BOT_TOKEN>/sendMessage \
     -d chat_id=<YOUR_CHAT_ID> \
     -d text="Test message"

# Check environment variables
sudo -u www-data cat /opt/hourroi-bot/.env
```

#### 4. High Memory Usage

**Problem**: Bot consuming too much memory
```bash
# PM2 shows high memory usage
sudo -u www-data pm2 monit
```

**Solutions**:
```bash
# Adjust memory limit in ecosystem.config.js
max_memory_restart: '256M'

# Reload PM2 configuration
sudo -u www-data pm2 reload hourroi-bot

# Monitor memory usage
top -p $(pgrep -f hourroi-bot)
```

### Performance Optimization

#### WebSocket vs Polling Performance

| Mode | API Calls/Hour | Resource Usage | Latency |
|------|----------------|----------------|---------|
| WebSocket | ~12 calls | Low CPU/Memory | <1 second |
| Polling (30s) | ~7,200 calls | Medium CPU/Memory | 0-30 seconds |

#### Recommended Settings

For optimal performance:

```javascript
// config-ankr.js
events: {
  enableWebSocket: true,              // Primary mode
  checkIntervalSeconds: 30,           // Conservative polling
  wsReconnectDelay: 5000,            // Quick reconnection
  wsMaxReconnectAttempts: 10,        // Sufficient retries
  fallbackToPollingAfterSeconds: 60   // Reasonable fallback
}
```

## 📦 Project Structure

```
hourroi-bot/
├── ankr-bot.js                 # Main bot application
├── config-ankr.js             # Configuration file
├── newcontractabi.json         # Smart contract ABI
├── ecosystem.config.js         # PM2 configuration
├── hourroi-bot.service        # Systemd service file
├── setup-vps.sh              # VPS setup script
├── nginx-hourroi.conf         # Nginx configuration (optional)
├── test.js                    # Connection test script
├── package.json               # Node.js dependencies
├── botimage.png              # Telegram notification image
├── .env                      # Environment variables (create this)
└── README.md                 # This documentation
```

## 🔐 Security Best Practices

### Environment Security

```bash
# Secure environment file
sudo chmod 600 /opt/hourroi-bot/.env
sudo chown www-data:www-data /opt/hourroi-bot/.env

# Regular security updates
sudo apt update && sudo apt upgrade -y

# Monitor failed login attempts
sudo fail2ban-client status sshd
```

### Network Security

```bash
# Configure UFW firewall
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 3000/tcp  # Only if health endpoint needed
sudo ufw enable

# Check open ports
sudo netstat -tlnp
```

### File Permissions

```bash
# Set secure permissions
sudo find /opt/hourroi-bot -type f -exec chmod 644 {} \;
sudo find /opt/hourroi-bot -type d -exec chmod 755 {} \;
sudo chmod 600 /opt/hourroi-bot/.env
sudo chmod +x /opt/hourroi-bot/ankr-bot.js
```

## 🆕 Updates and Upgrades

### Updating the Bot

```bash
# Stop the service
sudo systemctl stop hourroi-bot

# Backup current version
sudo cp -r /opt/hourroi-bot /opt/hourroi-bot.backup.$(date +%Y%m%d)

# Update files (git method)
cd /opt/hourroi-bot
sudo -u www-data git pull origin main

# Or replace files manually
# Upload new files and run:
sudo chown -R www-data:www-data /opt/hourroi-bot

# Install new dependencies
sudo -u www-data npm install --production

# Start the service
sudo systemctl start hourroi-bot

# Verify update
sudo systemctl status hourroi-bot
```

### Node.js Updates

```bash
# Update Node.js (if needed)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Rebuild native modules
cd /opt/hourroi-bot
sudo -u www-data npm rebuild

# Restart bot
sudo systemctl restart hourroi-bot
```

## 📞 Support

### Getting Help

1. **Check logs first:**
   ```bash
   sudo journalctl -u hourroi-bot -n 100
   ```

2. **Test connectivity:**
   ```bash
   cd /opt/hourroi-bot
   npm test
   ```

3. **Health check:**
   ```bash
   curl http://localhost:3000/health
   ```

### Common Commands Reference

```bash
# Service Management
sudo systemctl start hourroi-bot      # Start service
sudo systemctl stop hourroi-bot       # Stop service  
sudo systemctl restart hourroi-bot    # Restart service
sudo systemctl status hourroi-bot     # Check status
sudo systemctl enable hourroi-bot     # Enable auto-start
sudo systemctl disable hourroi-bot    # Disable auto-start

# PM2 Management
sudo -u www-data pm2 list            # List processes
sudo -u www-data pm2 logs hourroi-bot # View logs
sudo -u www-data pm2 monit           # Monitor resources
sudo -u www-data pm2 restart hourroi-bot # Restart process
sudo -u www-data pm2 reload hourroi-bot  # Reload process
sudo -u www-data pm2 stop hourroi-bot    # Stop process

# Log Management
sudo journalctl -u hourroi-bot -f     # Follow system logs
sudo journalctl -u hourroi-bot --since "1 hour ago" # Recent logs
sudo tail -f /var/log/hourroi-bot/combined.log      # PM2 logs
```

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

**Made with ❤️ for the HOURROI community**

For technical support, please open an issue or contact the development team.