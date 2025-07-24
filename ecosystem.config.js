module.exports = {
  apps: [{
    name: 'hourroi-bot',
    script: 'ankr-bot.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '512M',
    restart_delay: 5000,
    max_restarts: 10,
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    env_production: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: '/var/log/hourroi-bot/err.log',
    out_file: '/var/log/hourroi-bot/out.log',
    log_file: '/var/log/hourroi-bot/combined.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    time: true,
    merge_logs: true,
    kill_timeout: 5000,
    listen_timeout: 10000,
    
    // VPS-specific settings
    cwd: '/opt/hourroi-bot',
    user: 'www-data',
    
    // Health monitoring
    min_uptime: '10s',
    max_restarts: 15,
    
    // Log rotation
    log_type: 'json'
  }]
}; 