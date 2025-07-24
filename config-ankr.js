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
        // Primary Ankr RPC (with load balancing)
        rpcUrls: [
            `https://rpc.ankr.com/bsc/${process.env.ANKR_API_KEY || '41be6db3daba53f8161018ac9400564296e448b8b1b9efdfc88e0ab7c2570bf6'}`,
            'https://bsc-dataseed.binance.org/',
            'https://bsc-dataseed1.defibit.io/'
        ],
        // Fallback to additional public endpoints
        fallbackRpcUrls: [
            'https://bsc-dataseed2.defibit.io/',
            'https://bsc-dataseed3.defibit.io/',
            'https://bsc-dataseed4.defibit.io/',
            'https://rpc.ankr.com/bsc'
        ],
        // WebSocket endpoints for real-time event monitoring
        wsUrls: [
            'wss://rpc.ankr.com/bsc/ws/41be6db3daba53f8161018ac9400564296e448b8b1b9efdfc88e0ab7c2570bf6',
            'wss://bsc-ws-node.nariox.org:443',
            'wss://bsc.publicnode.com'
        ],
        // UPDATED: New contract address
        contractAddress: '0x7EE57D1616B654614B8D334b90dFD9EeA07a3e00',
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
        
        // WebSocket Configuration (Primary method)
        enableWebSocket: true,
        wsReconnectDelay: 5000, // 5 seconds reconnect delay
        wsMaxReconnectAttempts: 10,
        wsHeartbeatInterval: 30000, // 30 seconds ping/pong
        
        // Polling Configuration (Fallback method)
        checkIntervalSeconds: 30, // 30 seconds to conserve API credits
        maxBlockRange: 100, // Smaller range for efficiency
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
