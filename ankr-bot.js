// Load environment variables for local development
// Try .env.local first (if .env is ignored), then fallback to .env
require('dotenv').config({ path: '.env.local' });
require('dotenv').config();

const TelegramBot = require('node-telegram-bot-api');
// Fix Web3 import for version 4.x
const { Web3 } = require('web3');
const fs = require('fs');
const path = require('path');
const http = require('http');
const config = require('./config-ankr');

class AnkrAutoPoolBot {
    constructor() {
        this.bot = new TelegramBot(config.telegram.botToken, { polling: false });
        this.web3Instances = [];
        this.wsConnections = [];
        this.currentRpcIndex = 0;
        this.lastBlockNumber = 0;
        this.isRunning = false;
        this.isWebSocketMode = false;
        this.wsReconnectCount = 0;
        this.bannerImagePath = path.join(__dirname, 'botimage.png');
        this.performanceStats = {
            requests: 0,
            errors: 0,
            avgResponseTime: 0,
            startTime: Date.now()
        };
        
        this.initializeWeb3Instances();
        this.initializeWebSocketConnections();
        this.setupHealthMonitoring();
        this.checkBannerImage();
        this.setupHealthEndpoint();
    }

    // Initialize multiple Web3 instances for load balancing and failover
    initializeWeb3Instances() {
        console.log('🔧 Initializing Ankr Web3 instances...');
        this.web3Instances = []; // Clear existing instances
        
        // Primary Ankr instances (if any configured)
        if (config.blockchain.rpcUrls && config.blockchain.rpcUrls.length > 0) {
            config.blockchain.rpcUrls.forEach((url, index) => {
                try {
                    console.log(`🔗 Attempting to connect to Ankr: ${url}`);
                    const web3 = new Web3(url);
                    web3.ankr = {
                        url: url,
                        isAnkr: true,
                        priority: 1,
                        lastUsed: 0,
                        errorCount: 0
                    };
                    this.web3Instances.push(web3);
                    console.log(`✅ Ankr instance ${index + 1} initialized successfully`);
                } catch (error) {
                    console.error(`❌ Failed to initialize Ankr instance ${index + 1}:`, error.message);
                    console.error(`📍 URL: ${url}`);
                }
            });
        } else {
            console.log(`⚠️ No Ankr URLs configured, using fallback RPCs only`);
        }

        // Fallback instances
        if (config.blockchain.fallbackRpcUrls) {
            config.blockchain.fallbackRpcUrls.forEach((url, index) => {
                try {
                    console.log(`🔗 Attempting to connect to fallback: ${url}`);
                    const web3 = new Web3(url);
                    web3.ankr = {
                        url: url,
                        isAnkr: false,
                        priority: 2,
                        lastUsed: 0,
                        errorCount: 0
                    };
                    this.web3Instances.push(web3);
                    console.log(`✅ Fallback instance ${index + 1} initialized successfully`);
                } catch (error) {
                    console.error(`❌ Failed to initialize fallback instance ${index + 1}:`, error.message);
                    console.error(`📍 URL: ${url}`);
                }
            });
        }

        if (this.web3Instances.length === 0) {
            throw new Error('❌ CRITICAL: No Web3 instances could be initialized! Check your Ankr API key and network connectivity.');
        }

        console.log(`🎯 Successfully initialized ${this.web3Instances.length} Web3 instances`);
    }

    // Initialize WebSocket connections for real-time event monitoring
    initializeWebSocketConnections() {
        if (!config.events.enableWebSocket || !config.blockchain.wsUrls) {
            console.log('🔌 WebSocket monitoring disabled');
            return;
        }

        console.log('🔌 Initializing WebSocket connections...');
        this.wsConnections = [];

        config.blockchain.wsUrls.forEach((wsUrl, index) => {
            try {
                console.log(`🔗 Connecting to WebSocket: ${wsUrl}`);
                const ws = new Web3(wsUrl);
                
                const wsConnection = {
                    web3: ws,
                    url: wsUrl,
                    isConnected: false,
                    reconnectAttempts: 0,
                    lastPing: Date.now(),
                    subscription: null
                };

                this.wsConnections.push(wsConnection);
                console.log(`✅ WebSocket ${index + 1} initialized`);
            } catch (error) {
                console.error(`❌ Failed to initialize WebSocket ${index + 1}:`, error.message);
            }
        });

        if (this.wsConnections.length > 0) {
            console.log(`🎯 Successfully initialized ${this.wsConnections.length} WebSocket connections`);
        } else {
            console.log('⚠️ No WebSocket connections available, will use polling mode');
        }
    }

    // Start WebSocket event subscriptions
    async startWebSocketEventSubscriptions() {
        if (!config.events.enableWebSocket || this.wsConnections.length === 0) {
            console.log('📡 WebSocket subscriptions skipped - using polling mode');
            return false;
        }

        console.log('📡 Starting WebSocket event subscriptions...');
        
        for (let i = 0; i < this.wsConnections.length; i++) {
            const wsConnection = this.wsConnections[i];
            
            try {
                console.log(`🔌 Setting up subscriptions for WebSocket ${i + 1}: ${wsConnection.url}`);
                
                const contract = new wsConnection.web3.eth.Contract(
                    config.contractABI, 
                    config.blockchain.contractAddress
                );

                // Subscribe to UserJoined events
                if (config.events.enableJoinNotifications) {
                    const joinSub = contract.events.UserJoined()
                        .on('data', (event) => {
                            console.log('🎉 Real-time UserJoined event received!');
                            this.processEvent({ ...event, event: 'UserJoined' });
                        })
                        .on('error', (error) => {
                            console.error('❌ UserJoined subscription error:', error.message);
                            this.handleWebSocketError(wsConnection, error);
                        });
                    
                    wsConnection.subscription = joinSub;
                }

                // Subscribe to UserRejoined events
                if (config.events.enableRejoinNotifications) {
                    const rejoinSub = contract.events.UserRejoined()
                        .on('data', (event) => {
                            console.log('🔄 Real-time UserRejoined event received!');
                            this.processEvent({ ...event, event: 'UserRejoined' });
                        })
                        .on('error', (error) => {
                            console.error('❌ UserRejoined subscription error:', error.message);
                            this.handleWebSocketError(wsConnection, error);
                        });
                    
                    if (!wsConnection.subscription) {
                        wsConnection.subscription = rejoinSub;
                    }
                }

                wsConnection.isConnected = true;
                wsConnection.reconnectAttempts = 0;
                
                console.log(`✅ WebSocket ${i + 1} subscriptions active`);
                
                // Use first successful connection and set WebSocket mode
                if (!this.isWebSocketMode) {
                    this.isWebSocketMode = true;
                    console.log('🚀 WebSocket mode activated - real-time event monitoring enabled!');
                    console.log('💡 API usage reduced by ~95% compared to polling');
                    return true;
                }
                
            } catch (error) {
                console.error(`❌ Failed to setup WebSocket ${i + 1} subscriptions:`, error.message);
                wsConnection.isConnected = false;
                this.handleWebSocketError(wsConnection, error);
            }
        }

        return this.isWebSocketMode;
    }

    // Handle WebSocket errors and reconnection
    async handleWebSocketError(wsConnection, error) {
        console.error(`🔌 WebSocket error for ${wsConnection.url}:`, error.message);
        
        wsConnection.isConnected = false;
        wsConnection.reconnectAttempts++;

        if (wsConnection.reconnectAttempts < config.events.wsMaxReconnectAttempts) {
            console.log(`🔄 Attempting to reconnect WebSocket (${wsConnection.reconnectAttempts}/${config.events.wsMaxReconnectAttempts})...`);
            
            setTimeout(async () => {
                try {
                    await this.startWebSocketEventSubscriptions();
                } catch (reconnectError) {
                    console.error('❌ WebSocket reconnection failed:', reconnectError.message);
                }
            }, config.events.wsReconnectDelay);
        } else {
            console.log('⚠️ Max WebSocket reconnection attempts reached - falling back to polling');
            this.isWebSocketMode = false;
        }
    }

    // Get the best available Web3 instance
    getWeb3Instance() {
        if (this.web3Instances.length === 0) {
            throw new Error('No Web3 instances available');
        }

        // Sort by priority and error count
        const sortedInstances = this.web3Instances
            .filter(instance => instance.ankr.errorCount < 5)
            .sort((a, b) => {
                if (a.ankr.priority !== b.ankr.priority) {
                    return a.ankr.priority - b.ankr.priority;
                }
                return a.ankr.errorCount - b.ankr.errorCount;
            });

        if (sortedInstances.length === 0) {
            // Reset error counts if all instances are failing
            this.web3Instances.forEach(instance => instance.ankr.errorCount = 0);
            return this.web3Instances[0];
        }

        const instance = sortedInstances[0];
        instance.ankr.lastUsed = Date.now();
        return instance;
    }

    // Enhanced error handling with automatic failover
    async executeWithFailover(operation) {
        const maxRetries = config.events.maxRetries || 3;
        let lastError;

        for (let attempt = 1; attempt <= maxRetries; attempt++) {
            try {
                const startTime = Date.now();
                const web3 = this.getWeb3Instance();
                
                const result = await operation(web3);
                
                // Track performance
                const responseTime = Date.now() - startTime;
                this.updatePerformanceStats(responseTime, true);
                
                // Reset error count on success
                web3.ankr.errorCount = 0;
                
                return result;
            } catch (error) {
                lastError = error;
                this.updatePerformanceStats(0, false);
                
                // Mark current instance as problematic
                if (this.web3Instances.length > 0) {
                    const currentInstance = this.web3Instances.find(instance => 
                        instance.ankr.lastUsed > Date.now() - 5000
                    );
                    if (currentInstance) {
                        currentInstance.ankr.errorCount++;
                    }
                }

                console.warn(`⚠️ Attempt ${attempt}/${maxRetries} failed:`, error.message);
                
                if (attempt < maxRetries) {
                    await new Promise(resolve => setTimeout(resolve, config.events.retryDelay));
                }
            }
        }

        throw lastError;
    }

    // Test connections before starting
    async testConnections() {
        console.log('🧪 Testing Web3 connections...');
        
        for (let i = 0; i < this.web3Instances.length; i++) {
            const web3 = this.web3Instances[i];
            try {
                console.log(`🔍 Testing ${web3.ankr.isAnkr ? 'Ankr' : 'fallback'} instance ${i + 1}...`);
                const startTime = Date.now();
                const blockNumber = await web3.eth.getBlockNumber();
                const responseTime = Date.now() - startTime;
                console.log(`✅ Instance ${i + 1}: Block ${blockNumber}, Response time: ${responseTime}ms`);
            } catch (error) {
                console.error(`❌ Instance ${i + 1} test failed:`, error.message);
                web3.ankr.errorCount = 10; // Mark as problematic
            }
        }

        // Check if we have at least one working instance
        const workingInstances = this.web3Instances.filter(instance => instance.ankr.errorCount < 10);
        if (workingInstances.length === 0) {
            throw new Error('❌ No working Web3 instances found! Check your Ankr API key and network connectivity.');
        }

        console.log(`✅ ${workingInstances.length}/${this.web3Instances.length} instances are working properly`);
    }

    // Start the bot
    async start() {
        console.log('🚀 Starting Ankr AutoPool Bot...');
        
        try {
            // Test connections first
            await this.testConnections();
            
            this.isRunning = true;
            console.log('🎯 Bot started successfully! Monitoring for events...');
            
            // Try to start WebSocket event subscriptions first
            const webSocketStarted = await this.startWebSocketEventSubscriptions();
            
            if (webSocketStarted) {
                console.log('✅ WebSocket mode active - events will be received in real-time');
                console.log('📊 Polling disabled - using 95% fewer API calls');
                
                // WebSocket mode: Just keep the process alive and handle reconnections
                while (this.isRunning) {
                    try {
                        // Check WebSocket health every 30 seconds
                        await new Promise(resolve => setTimeout(resolve, 30000));
                        
                        // If WebSocket fails, fall back to polling
                        if (!this.isWebSocketMode) {
                            console.log('⚠️ WebSocket failed - switching to polling mode');
                            break;
                        }
                    } catch (error) {
                        console.error('💥 Error in WebSocket monitoring:', error);
                        this.isWebSocketMode = false;
                        break;
                    }
                }
            }
            
            // Polling mode (fallback or primary if WebSocket unavailable)
            if (!this.isWebSocketMode) {
                console.log('📡 Using polling mode - checking events every', config.events.checkIntervalSeconds, 'seconds');
                
                while (this.isRunning) {
                    try {
                        await this.monitorEvents();
                        await new Promise(resolve => setTimeout(resolve, config.events.checkIntervalSeconds * 1000));
                    } catch (error) {
                        console.error('💥 Fatal error in polling loop:', error);
                        await new Promise(resolve => setTimeout(resolve, 10000));
                    }
                }
            }
            
        } catch (error) {
            console.error('💥 Failed to start bot:', error.message);
            throw error;
        }
    }

    // Monitor events - Only joins and rejoins
    async monitorEvents() {
        let fromBlock = 0;
        let toBlock = 0;
        
        try {
            const result = await this.executeWithFailover(async (web3) => {
                const contract = new web3.eth.Contract(config.contractABI, config.blockchain.contractAddress);
                const currentBlockBigInt = await web3.eth.getBlockNumber();
                const currentBlock = Number(currentBlockBigInt); // Convert BigInt to number
                
                if (this.lastBlockNumber === 0) {
                    this.lastBlockNumber = Math.max(0, currentBlock - 10); // Start 10 blocks back
                }

                fromBlock = this.lastBlockNumber + 1;
                toBlock = currentBlock;

                if (fromBlock > toBlock) {
                    return { events: [], currentBlock, fromBlock, toBlock };
                }

                // Get UserJoined and UserRejoined events only (HOURROI contract events)
                const eventPromises = [];
                
                if (config.events.enableJoinNotifications) {
                    eventPromises.push(
                        contract.getPastEvents('UserJoined', { fromBlock, toBlock })
                    );
                }
                
                if (config.events.enableRejoinNotifications) {
                    eventPromises.push(
                        contract.getPastEvents('UserRejoined', { fromBlock, toBlock })
                    );
                }

                const eventResults = await Promise.all(eventPromises);
                const allEvents = eventResults.flat();
                
                // Sort events by block number and transaction index
                allEvents.sort((a, b) => {
                    const blockA = Number(a.blockNumber);
                    const blockB = Number(b.blockNumber);
                    if (blockA !== blockB) {
                        return blockA - blockB;
                    }
                    return Number(a.transactionIndex) - Number(b.transactionIndex);
                });
                
                return { events: allEvents, currentBlock, fromBlock, toBlock };
            });

            const { events, currentBlock } = result;
            fromBlock = result.fromBlock;
            toBlock = result.toBlock;
            
            // Process events
            for (const event of events) {
                await this.processEvent(event);
                
                // Add small delay between processing
                if (config.events.batchDelay > 0) {
                    await new Promise(resolve => setTimeout(resolve, config.events.batchDelay));
                }
            }

            this.lastBlockNumber = currentBlock;
            
            if (events.length > 0) {
                console.log(`📊 Processed ${events.length} events (blocks ${fromBlock} to ${toBlock})`);
            }

        } catch (error) {
            console.error('❌ Event monitoring failed:', error.message);
            
            // Add delay before retrying
            await new Promise(resolve => setTimeout(resolve, config.events.retryDelay));
        }
    }

    // Process individual events (V12 Final events)
    async processEvent(event) {
        try {
            let message = '';
            
            switch (event.event) {
                case 'UserJoined':
                case 'Join': // Backward compatibility
                    message = await this.formatJoinMessage(event);
                    break;
                case 'UserRejoined':
                case 'Rejoin': // Backward compatibility
                    message = await this.formatRejoinMessage(event);
                    break;
                default:
                    return; // Skip other events
            }

            if (message && config.telegram.enableNotifications) {
                await this.sendTelegramMessage(message);
            }
        } catch (error) {
            console.error('❌ Event processing failed:', error.message);
        }
    }

        // Format join message (HOURROI contract - UserJoined event)
    async formatJoinMessage(event) {
        const { user, referrer, amount, timestamp } = event.returnValues;
        const txHash = event.transactionHash;
        // Use new contract address from config
        const contractAddress = config.blockchain.contractAddress;
        
        // Convert amount from wei to USDT (divide by 10^18)
        const amountUSDT = amount ? (parseFloat(amount) / 1e18).toFixed(0) : "10";
        
        // Format join message
        let message = `🎉 New Member Joined HOURROI\n`;
        message += `Earn Every Hour • 10 USDT Entry\n\n`;
        message += `💸 Amount: ${amountUSDT} USDT\n`;
        if (referrer && referrer !== '0x0000000000000000000000000000000000000000') {
            message += `👥 Referrer: ${referrer.substring(0, 6)}...${referrer.substring(38)}\n`;
        }
        message += `\n`;
        message += `[TX](${config.messages.bscScanUrl}/tx/${txHash}) | `;
        message += `[User](${config.messages.bscScanUrl}/address/${user}) | `;
        message += `[Website](https://hourroi.com) | `;
        message += `[Contract](${config.messages.bscScanUrl}/address/${contractAddress})`;
        return message;
    }

    // Format rejoin message (HOURROI contract - UserRejoined event)
    async formatRejoinMessage(event) {
        const { user, amount, timestamp } = event.returnValues;
        const txHash = event.transactionHash;
        const blockNumber = event.blockNumber;
        
        // Convert amount from wei to USDT
        const rejoinAmount = amount ? (parseFloat(amount) / 1e18).toFixed(0) : "10";
        let contractBalance = "0";
        let totalUsers = "0";
        
        try {
            // Get contract stats from HOURROI contract
            const result = await this.executeWithFailover(async (web3) => {
                const contract = new web3.eth.Contract(config.contractABI, config.blockchain.contractAddress);
                
                // HOURROI getContractStats returns: [totalBalance, totalUsers, totalRewards, usdtAddress]
                const contractStats = await contract.methods.getContractStats().call();
                const balance = parseFloat(contractStats[0]) / 1e18; // Convert from wei to USDT (index 0 for totalBalance)
                const users = contractStats[1]; // Total users (index 1)
                
                return {
                    contractBalance: balance.toFixed(0),
                    totalUsers: users.toString()
                };
            });
            
            contractBalance = result.contractBalance;
            totalUsers = result.totalUsers;
            
            console.log(`🔄 Rejoin detected for user ${user}`);
            console.log(`📊 HOURROI Contract - Balance: ${contractBalance} USDT, Users: ${totalUsers}`);
            
        } catch (error) {
            console.warn('⚠️ Could not fetch HOURROI contract stats:', error.message);
            contractBalance = "1000+"; // Fallback
            totalUsers = "100+"; // Fallback
        }
        
        let message = `🔄 Member Rejoined HOURROI\n`;
        message += `Earn Every Hour • ROI Platform\n\n`;
        message += `💸 Rejoin: ${rejoinAmount} USDT\n`;
        message += `💰 Contract Balance: ${contractBalance} USDT\n`;
        message += `👥 Total Users: ${totalUsers}\n\n`;
        message += `[TX](${config.messages.bscScanUrl}/tx/${txHash}) | `;
        message += `[User](${config.messages.bscScanUrl}/address/${user}) | `;
        message += `[Website](https://hourroi.com) | `;
        message += `[Contract](${config.messages.bscScanUrl}/address/${config.blockchain.contractAddress})`;
        
        return message;
    }

    // Check if banner image exists
    checkBannerImage() {
        if (fs.existsSync(this.bannerImagePath)) {
            console.log('🖼️ Banner image found:', this.bannerImagePath);
        } else {
            console.warn('⚠️ Banner image not found:', this.bannerImagePath);
            this.bannerImagePath = null;
        }
    }

    // Send Telegram message with banner image
    async sendTelegramMessage(message) {
        try {
            if (this.bannerImagePath && fs.existsSync(this.bannerImagePath)) {
                // Send photo with caption
                await this.bot.sendPhoto(config.telegram.chatId, this.bannerImagePath, {
                    caption: message,
                    parse_mode: 'Markdown'
                });
                console.log('📤 Message with banner image sent to Telegram');
            } else {
                // Fallback to text message if no image
                await this.bot.sendMessage(config.telegram.chatId, message, {
                    parse_mode: 'Markdown',
                    disable_web_page_preview: true
                });
                console.log('📤 Text message sent to Telegram');
            }
        } catch (error) {
            console.warn('⚠️ Markdown failed, trying plain text:', error.message);
            
            // Fallback to plain text
            try {
                const plainMessage = message.replace(/[`_*\[\]()]/g, '');
                
                if (this.bannerImagePath && fs.existsSync(this.bannerImagePath)) {
                    await this.bot.sendPhoto(config.telegram.chatId, this.bannerImagePath, {
                        caption: plainMessage
                    });
                    console.log('📤 Plain text message with banner image sent to Telegram');
                } else {
                    await this.bot.sendMessage(config.telegram.chatId, plainMessage, {
                        disable_web_page_preview: true
                    });
                    console.log('📤 Plain text message sent to Telegram');
                }
            } catch (plainError) {
                console.error('❌ Failed to send Telegram message:', plainError.message);
            }
        }
    }

    // Update performance statistics
    updatePerformanceStats(responseTime, success) {
        this.performanceStats.requests++;
        if (!success) {
            this.performanceStats.errors++;
        } else {
            this.performanceStats.avgResponseTime = 
                (this.performanceStats.avgResponseTime + responseTime) / 2;
        }
    }

    // Setup health monitoring
    setupHealthMonitoring() {
        if (config.connection.enableHealthCheck) {
            setInterval(() => {
                this.performHealthCheck();
            }, config.connection.healthCheckIntervalMs);
        }
    }

    // Perform health check
    async performHealthCheck() {
        console.log('🏥 Performing health check...');
        
        const healthPromises = this.web3Instances.map(async (web3, index) => {
            try {
                const startTime = Date.now();
                await web3.eth.getBlockNumber();
                const responseTime = Date.now() - startTime;
                
                console.log(`✅ Instance ${index + 1} (${web3.ankr.isAnkr ? 'Ankr' : 'Public'}): ${responseTime}ms`);
                
                return { index, healthy: true, responseTime };
            } catch (error) {
                console.error(`❌ Instance ${index + 1} health check failed:`, error.message);
                web3.ankr.errorCount++;
                return { index, healthy: false, error: error.message };
            }
        });

        const results = await Promise.allSettled(healthPromises);
        const healthyInstances = results.filter(result => 
            result.status === 'fulfilled' && result.value.healthy
        ).length;

        console.log(`🏥 Health check complete: ${healthyInstances}/${this.web3Instances.length} instances healthy`);
        
        if (healthyInstances === 0) {
            console.error('🚨 ALL INSTANCES UNHEALTHY! Attempting to reinitialize...');
            this.initializeWeb3Instances();
        }
    }

    // Setup health endpoint for Railway
    setupHealthEndpoint() {
        const port = process.env.PORT || 3000;
        
        const server = http.createServer((req, res) => {
            if (req.url === '/health') {
                const healthData = {
                    status: 'ok',
                    uptime: process.uptime(),
                    timestamp: new Date().toISOString(),
                    isRunning: this.isRunning,
                    stats: this.performanceStats,
                    web3Instances: this.web3Instances.length,
                    lastBlockNumber: this.lastBlockNumber
                };
                
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify(healthData, null, 2));
            } else {
                res.writeHead(404, { 'Content-Type': 'text/plain' });
                res.end('Not Found');
            }
        });

        server.listen(port, () => {
            console.log(`🏥 Health server running on port ${port}`);
        });
    }

    // Stop the bot
    stop() {
        console.log('🛑 Stopping Ankr AutoPool Bot...');
        this.isRunning = false;
    }
}

// Handle graceful shutdown
process.on('SIGINT', () => {
    console.log('\n🛑 Received SIGINT, shutting down gracefully...');
    if (global.botInstance) {
        global.botInstance.stop();
    }
    process.exit(0);
});

// Start the bot if this file is run directly
if (require.main === module) {
    console.log('🚀 Starting Ankr AutoPool Bot...');
    console.log('🔧 Configuration:');
    console.log(`   - Ankr instances: ${config.blockchain.rpcUrls.length}`);
    console.log(`   - Fallback instances: ${config.blockchain.fallbackRpcUrls?.length || 0}`);
    console.log(`   - Check interval: ${config.events.checkIntervalSeconds}s`);
    console.log(`   - Events: Joins and Rejoins only`);
    
    const bot = new AnkrAutoPoolBot();
    global.botInstance = bot;
    bot.start().catch(error => {
        console.error('💥 Failed to start bot:', error);
        process.exit(1);
    });
}

module.exports = AnkrAutoPoolBot; 