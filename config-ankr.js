// Ankr-Optimized AutoPool Telegram Bot Configuration
// Enhanced configuration using Ankr.com infrastructure for better performance

module.exports = {
    // Telegram Bot Configuration
    telegram: {
        botToken: process.env.TELEGRAM_BOT_TOKEN || '7201463630:AAFAKhbMb-gb4wiA9HrVHniKJAo8mWHbIFU',
        chatId: process.env.TELEGRAM_CHAT_ID || '-1002774826288',
        enableNotifications: true
    },

    // Ankr Blockchain Configuration
    blockchain: {
        // Ankr-only RPC endpoints
        rpcUrls: [
            `https://rpc.ankr.com/bsc/${process.env.ANKR_API_KEY || '41be6db3daba53f8161018ac9400564296e448b8b1b9efdfc88e0ab7c2570bf6'}`,
            'https://rpc.ankr.com/bsc'
        ],
        // Ankr fallback endpoints
        fallbackRpcUrls: [
            'https://rpc.ankr.com/bsc'
        ],
        // Ankr WebSocket endpoints (disabled due to reliability)
        wsUrls: [],
        // UPDATED: New contract address
        contractAddress: '0xe20b7F0AC2bc61dFA03A23280Caf60D0133134e0',
        usdtContractAddress: '0x55d398326f99059fF775485246999027B3197955',
        chainId: 56,
        networkName: 'BSC Mainnet'
    },

    // Ankr Service Configuration
    ankr: {
        apiKeys: [
            process.env.ANKR_API_KEY || '41be6db3daba53f8161018ac9400564296e448b8b1b9efdfc88e0ab7c2570bf6'  // Your new Ankr API key
        ],
        enableApiKeyRotation: false, // Single key, no rotation needed
        rateLimitBuffer: 0.7, // Use 70% of rate limit to conserve credits
        enableMonitoring: true
    },

    // Enhanced Event Monitoring - WebSocket + Polling Hybrid
    events: {
        enableJoinNotifications: true,
        enableRejoinNotifications: true,
        enableBonusNotifications: false, // Disabled - only show joins and rejoins
        enableStatistics: false, // Disabled to reduce API calls
        
        // WebSocket Configuration (Disabled due to reliability issues)
        enableWebSocket: false,
        wsReconnectDelay: 5000, // 5 seconds reconnect delay
        wsMaxReconnectAttempts: 3, // Reduced to fail faster
        wsHeartbeatInterval: 30000, // 30 seconds ping/pong
        
        // Polling Configuration (Primary method)
        checkIntervalSeconds: 5, // 5 seconds for better event detection
        maxBlockRange: 500, // Optimized range for Ankr
        batchDelay: 1000, // 1 second delay between batches
        retryDelay: 2000, // 2 second retry delay
        maxRetries: 5, // Increased retry attempts
        enableBatchRequests: true, // Ankr supports efficient batching
        maxBatchSize: 10,
        
        // Hybrid mode settings
        fallbackToPollingAfterSeconds: 60 // Switch to polling if WebSocket fails for 60s
    },

    // Enhanced Connection Settings
    connection: {
        reconnectAttempts: 10, // Increased due to better reliability
        reconnectDelayMs: 3000, // Reduced delay
        timeoutMs: 15000, // Reduced timeout (Ankr is fast)
        enableHealthCheck: true,
        healthCheckIntervalMs: 60000, // Check connection health every minute
        enableLoadBalancing: true
    },

    // Enhanced Message Formatting
    messages: {
        includeEmojis: true,
        includeAmounts: true,
        includeStats: false, // Disabled for cleaner messages
        includeLinks: true,
        includeAnkrStats: false, // Disabled for cleaner messages
        bscScanUrl: 'https://bscscan.com'
    },

    // Performance Monitoring
    monitoring: {
        enablePerformanceLogging: true,
        logRpcResponseTimes: true,
        alertOnSlowResponse: true,
        slowResponseThresholdMs: 2000,
        enableDashboard: true
    },

    // V11 Contract ABI - Load from external file
    contractABI: require('./newcontractabi.json')
}; 
