# AutoPool Telegram Bot - Railway Deployment Guide

## Overview
AutoPool Telegram Bot monitors blockchain events on the BSC network and sends notifications to Telegram. This version is optimized for Railway deployment.

## Railway Deployment

### Environment Variables Required
Set these in Railway's environment variables section:

```
TELEGRAM_BOT_TOKEN=your_telegram_bot_token
TELEGRAM_CHAT_ID=your_telegram_chat_id
ANKR_API_KEY=your_ankr_api_key
PORT=3000
NODE_ENV=production
```

### Quick Deploy
1. Connect your GitHub repository to Railway
2. Set the environment variables above
3. Railway will automatically detect and deploy using the `railway.json` configuration

### Health Check
The bot includes a health endpoint at `/health` for Railway monitoring.

## Contract Configuration
- **Network**: BSC Mainnet (Chain ID: 56)
- **Contract**: 0xe20b7F0AC2bc61dFA03A23280Caf60D0133134e0
- **Events Monitored**: UserJoined, UserRejoined

## Features
- ✅ Ankr RPC endpoints for reliability
- ✅ Polling-based event monitoring (WebSocket disabled)
- ✅ Automatic failover and health monitoring
- ✅ Telegram notifications with banner images
- ✅ Railway-optimized configuration

## Bot Configuration
- **Polling Interval**: 5 seconds
- **Block Range**: 500 blocks per batch
- **RPC Provider**: Ankr (premium + public endpoints)
- **Message Format**: Markdown with BSCScan links

## Testing
```bash
npm test          # Test blockchain connection
node test-telegram.js  # Test Telegram connection
```

## Monitoring
Check Railway logs for:
- Connection status
- Event processing
- Telegram message delivery
- Health check results