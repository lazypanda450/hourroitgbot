const { Web3 } = require('web3');
const config = require('./config-ankr');

async function testHOURROIConnection() {
    console.log('🧪 Testing HOURROI Contract Connection...');
    console.log('📝 Contract Address:', config.blockchain.contractAddress);
    
    try {
        // Initialize Web3 with Ankr
        const web3 = new Web3(config.blockchain.rpcUrls[0]);
        
        // Test basic connection
        console.log('\n🔗 Testing basic connection...');
        const blockNumber = await web3.eth.getBlockNumber();
        console.log('✅ Current block number:', blockNumber.toString());
        
        // Test contract connection
        console.log('\n📋 Testing contract connection...');
        const contract = new web3.eth.Contract(config.contractABI, config.blockchain.contractAddress);
        
        // Test getContractStats function
        console.log('\n📊 Testing getContractStats function...');
        const contractStats = await contract.methods.getContractStats().call();
        
        console.log('📊 Raw contract stats:', contractStats);
        console.log('📊 HOURROI Contract stats breakdown:');
        console.log('   - Index 0 (totalBalance):', (parseFloat(contractStats[0]) / 1e18).toFixed(4), 'USDT');
        console.log('   - Index 1 (totalUsers):', contractStats[1]);
        console.log('   - Index 2 (totalRewards):', (parseFloat(contractStats[2]) / 1e18).toFixed(4), 'USDT');
        console.log('   - Index 3 (usdtAddress):', contractStats[3]);
        
        // Test recent events
        console.log('\n📰 Testing recent events...');
        const currentBlock = Number(await web3.eth.getBlockNumber());
        const fromBlock = Math.max(0, currentBlock - 1000);
        
        console.log(`🔍 Searching for events from block ${fromBlock} to ${currentBlock}...`);
        
        const joinEvents = await contract.getPastEvents('UserJoined', {
            fromBlock: fromBlock,
            toBlock: currentBlock
        });
        
        const rejoinEvents = await contract.getPastEvents('UserRejoined', {
            fromBlock: fromBlock,
            toBlock: currentBlock
        });
        
        console.log(`✅ Found ${joinEvents.length} UserJoined events`);
        console.log(`✅ Found ${rejoinEvents.length} UserRejoined events`);
        
        if (joinEvents.length > 0) {
            console.log('\n📝 Sample UserJoined event:');
            const sampleEvent = joinEvents[0];
            console.log('   - User:', sampleEvent.returnValues.user);
            console.log('   - Referrer:', sampleEvent.returnValues.referrer);
            console.log('   - Amount:', (parseFloat(sampleEvent.returnValues.amount) / 1e18).toFixed(2), 'USDT');
            console.log('   - Timestamp:', sampleEvent.returnValues.timestamp);
            console.log('   - TX Hash:', sampleEvent.transactionHash);
        }
        
        if (rejoinEvents.length > 0) {
            console.log('\n📝 Sample UserRejoined event:');
            const sampleEvent = rejoinEvents[0];
            console.log('   - User:', sampleEvent.returnValues.user);
            console.log('   - Amount:', (parseFloat(sampleEvent.returnValues.amount) / 1e18).toFixed(2), 'USDT');
            console.log('   - Timestamp:', sampleEvent.returnValues.timestamp);
            console.log('   - TX Hash:', sampleEvent.transactionHash);
        }
        
        console.log('\n✅ HOURROI Contract test completed successfully!');
        console.log('📊 Contract balance:', (parseFloat(contractStats[0]) / 1e18).toFixed(0), 'USDT');
        console.log('📊 Total users:', contractStats[1]);
        
    } catch (error) {
        console.error('❌ HOURROI Contract test failed:', error.message);
        console.error('📍 Error details:', error);
    }
}

// Run the test
testHOURROIConnection().catch(console.error); 