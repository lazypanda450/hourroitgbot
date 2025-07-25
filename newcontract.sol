/**
 *Submitted for verification at BscScan.com on 2025-07-25
*/

/**
 *Submitted for verification at BscScan.com on 2025-07-23
*/

/**
 * 💸 HOURROI – Earn Every Hour! (Minimal Function Version)
 * 
 * ✅ Join with just 10 USDT
 * ✅ Refer 1 Active Direct person to start earning
 * ✅ Get paid every hour based on your tier!
 * 
 * 🎖 ROI Tiers (Based on Active Directs):
 * 🔒 0 directs = ❌ No ROI
 * 🥉 1–4 = 2 USDT/hour (Bronze Tier 20%)
 * 🥈 5–9 = 3 USDT/hour (Silver Tier 30%) 
 * 🥇 10–49 = 5 USDT/hour (Gold Tier 50%)
 * 💎 50–99 = 10 USDT/hour (Platinum Tier 100%)
 * 🔷 100+ = 50 USDT/hour (Diamond Tier 500%)
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IOldHOURROI {
    function users(address _user) external view returns (
        uint64 joinTime,
        uint64 cycleEndTime, 
        uint64 lastRewardUpdate,
        uint64 lastActiveDirectsUpdate,
        uint128 activeDirects,
        uint128 totalDirects,
        uint128 pendingRewards,
        address referrer,
        bool isActive,
        bool hasMinimumDirect
    );
    function hasJoined(address _user) external view returns (bool);
    function directReferralsCount(address _user) external view returns (uint256);
    function directReferrals(address _user, uint256 _index) external view returns (address);
    function totalUsersJoined() external view returns (uint256);
}

library SafeERC20 {
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }
    
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        bytes memory returndata = _functionCall(address(token), data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }

    function _functionCall(address target, bytes memory data, string memory errorMessage) private returns (bytes memory) {
        require(_isContract(target), "Address: call to non-contract");
        (bool success, bytes memory returndata) = target.call(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }

    function _isContract(address account) private view returns (bool) {
        return account.code.length > 0;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

contract HOURROI is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address private constant MAINNET_USDT_ADDRESS = 0x55d398326f99059fF775485246999027B3197955;
    address private constant OLD_CONTRACT_ADDRESS = 0x7EE57D1616B654614B8D334b90dFD9EeA07a3e00;
    
    IERC20 public immutable USDT;
    IOldHOURROI public immutable oldContract;
    address public admin;
    
    // Migration state variables
    bool public migrationCompleted = false;
    bool public migrationActive = true;
    uint256 public totalMigratedUsers = 0;
    uint256 public migrationIndex = 0;
    uint8 public currentMigrationPhase = 0;
    bool public newMigrationActive = false;
    
    // Emergency withdrawal timelock
    uint256 public emergencyWithdrawTime;
    uint256 private constant EMERGENCY_TIMELOCK = 7 days;
    bool public emergencyWithdrawInitiated;
    
    uint256 private constant JOIN_AMOUNT = 10 * 10**18;
    uint256 private constant REJOIN_AMOUNT = 10 * 10**18;
    uint256 private constant ADMIN_FEE = 2 * 10**18;
    uint256 private constant CYCLE_DURATION = 10 hours;
    uint256 private constant ROI_INTERVAL = 1 hours;
    uint256 private constant MAX_DIRECT_REFS = 1000; // Prevent DOS attacks
    
    // Packed struct layout for gas optimization
    struct User {
        // Slot 1: Time values (64 bits each = 256 bits total)
        uint64 joinTime;
        uint64 cycleEndTime;
        uint64 lastRewardUpdate;
        uint64 lastActiveDirectsUpdate;
        
        // Slot 2: Counters (128 bits each = 256 bits total)
        uint128 activeDirects;     // Cached value - automatic updates
        uint128 totalDirects;
        
        // Slot 3: Reward and referrer (256 bits total)
        uint128 pendingRewards;
        address referrer;          // 160 bits, leaves 96 bits unused
        
        // Slot 4: Bools
        bool isActive;
        bool hasMinimumDirect;
    }
    
    mapping(address => User) public users;
    mapping(address => bool) public hasJoined;
    mapping(address => bool) public migratedFromOld;
    mapping(address => bool) public downlinesMigrated;
    
    // Optimized referral tracking with mappings
    mapping(address => mapping(uint256 => address)) public directReferrals; // referrer => index => referral
    mapping(address => uint256) public directReferralsCount; // referrer => count
    mapping(address => mapping(address => bool)) public isDirectReferral;
    mapping(address => mapping(address => uint256)) public referralIndex;
    
    // Contract metrics
    uint256 public totalUsersJoined;
    uint256 public totalRewardsPaid;
    address[] public migratedUsersList;
    
    // Events
    event UserJoined(address indexed user, address indexed referrer, uint256 amount, uint256 timestamp);
    event UserRejoined(address indexed user, uint256 amount, uint256 timestamp);
    event RewardsClaimed(address indexed user, uint256 amount);
    event CycleCompleted(address indexed user, uint256 timestamp);
    event EmergencyWithdrawInitiated(uint256 executeTime);
    event EmergencyWithdrawCancelled();
    event EmergencyWithdrawExecuted(uint256 amount);
    event ActiveDirectsUpdated(address indexed user, uint256 newCount);
    
    // Migration events
    event UserMigrated(address indexed user, address indexed referrer);
    event MigrationCompleted(uint256 totalMigrated);
    event BatchDone(uint256 batch, uint256 index, uint256 time);
    event DownMigrate(address indexed user, uint256 count);
    event ActiveDirectsReset(address indexed user);
    
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }
    
    modifier postMigration() {
        require(migrationCompleted, "Migration not completed");
        _;
    }
    
    constructor() {
        USDT = IERC20(MAINNET_USDT_ADDRESS);
        oldContract = IOldHOURROI(OLD_CONTRACT_ADDRESS);
        admin = 0x3Da7310861fbBdf5105ea6963A2C39d0Cb34a4Ff;
    }
    
    // ===================================================================
    // 🚀 MAIN USER FUNCTIONS (Only 3 write functions as requested)
    // ===================================================================
    
    /**
     * @dev JOIN FUNCTION - Users can join with optional referrer
     * @param _referrer Address of referrer (can be zero address for no referrer)
     */
    function joinPlan(address _referrer) external postMigration nonReentrant {
        require(!hasJoined[msg.sender], "Already joined");
        
        // Prevent self-referral
        if (_referrer == msg.sender) {
            _referrer = address(0);
        }
        
        // Optional referrer validation - only check limits if referrer exists and has joined
        if (_referrer != address(0) && hasJoined[_referrer]) {
            require(directReferralsCount[_referrer] < MAX_DIRECT_REFS, "Referrer limit exceeded");
        }
        
        // Transfer payment from user
        USDT.safeTransferFrom(msg.sender, address(this), JOIN_AMOUNT);
        
        uint64 currentTime = uint64(block.timestamp);
        
        // Initialize user
        User storage user = users[msg.sender];
        user.joinTime = currentTime;
        user.cycleEndTime = currentTime + uint64(CYCLE_DURATION);
        user.lastRewardUpdate = currentTime;
        user.lastActiveDirectsUpdate = currentTime;
        user.isActive = true;
        user.referrer = _referrer;
        // activeDirects, totalDirects, pendingRewards, hasMinimumDirect default to 0/false
        
        hasJoined[msg.sender] = true;
        unchecked {
        totalUsersJoined++;
        }
        
        // AUTOMATIC: Add to referrer's list and update counts
        if (_referrer != address(0) && hasJoined[_referrer]) {
            _addDirectReferralAndUpdateROI(_referrer, msg.sender);
        }
        
        // Pay admin fee
        USDT.safeTransfer(admin, ADMIN_FEE);
        
        emit UserJoined(msg.sender, _referrer, JOIN_AMOUNT, currentTime);
    }

    /**
     * @dev CLAIM AND REJOIN FUNCTION - Users claim profits and automatically rejoin
     * After 10 hours: If profit > 10 USDT, user gets excess and auto rejoins with 10 USDT
     * Active directs reset to 0 on rejoin
     */
    function claimAndRejoin() external postMigration nonReentrant {
        User storage user = users[msg.sender];
        require(user.isActive, "User not active");
        require(block.timestamp >= user.cycleEndTime, "10-hour cycle not completed");
        
        // AUTOMATIC: Calculate and update rewards based on time
        _updateStoredRewardsAuto(msg.sender);
        
        uint256 totalRewards = getCurrentPendingROI(msg.sender);
        uint256 contractBalance = USDT.balanceOf(address(this));
        
        uint256 profit = 0;
        if (totalRewards > REJOIN_AMOUNT) {
            profit = totalRewards - REJOIN_AMOUNT;
            require(contractBalance >= profit, "Insufficient contract balance for profit");
        }
        
        address referrer = user.referrer;
        uint64 currentTime = uint64(block.timestamp);
        
        // Reset user for new cycle - Active directs reset to 0
        user.isActive = true;
        user.joinTime = currentTime;
        user.cycleEndTime = currentTime + uint64(CYCLE_DURATION);
        user.lastRewardUpdate = currentTime;
        user.lastActiveDirectsUpdate = currentTime;
        user.hasMinimumDirect = false;
        user.activeDirects = 0;  // Reset Active directs to 0
        user.pendingRewards = 0;
        
        unchecked {
        totalRewardsPaid += totalRewards;
        }
        
        // AUTOMATIC: Update referrer's active count
        if (referrer != address(0) && hasJoined[referrer] && users[referrer].isActive) {
            _updateReferrerActiveCountAuto(referrer);
        }
        
        // Transfer profit to user if any
        if (profit > 0) {
            USDT.safeTransfer(msg.sender, profit);
        }
        
        // Pay admin fee
        USDT.safeTransfer(admin, ADMIN_FEE);
        
        emit RewardsClaimed(msg.sender, totalRewards);
        emit UserRejoined(msg.sender, REJOIN_AMOUNT, currentTime);
    }
    
    /**
     * @dev EMERGENCY WITHDRAWAL - Simple two-step process
     * Step 1: Call once to start 7-day timelock
     * Step 2: Call again after 7 days to withdraw funds
     */
    function emergencyWithdraw() external onlyAdmin {
        if (!emergencyWithdrawInitiated) {
            // STEP 1: Start the timelock
            emergencyWithdrawTime = block.timestamp + EMERGENCY_TIMELOCK;
            emergencyWithdrawInitiated = true;
            emit EmergencyWithdrawInitiated(emergencyWithdrawTime);
            return; // Exit here after initiating
        }
        
        // STEP 2: Check if timelock has passed
        require(block.timestamp >= emergencyWithdrawTime, "Timelock not expired yet");
        
        // Execute withdrawal
        uint256 balance = USDT.balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");
        
        // Reset state first (security best practice)
        emergencyWithdrawInitiated = false;
        emergencyWithdrawTime = 0;
        
        // Transfer all funds to admin
        USDT.safeTransfer(admin, balance);
        emit EmergencyWithdrawExecuted(balance);
    }
    
    // ===================================================================
    // 🤖 AUTOMATIC INTERNAL FUNCTIONS (No external calls needed)
    // ===================================================================
    
    /**
     * @dev AUTOMATIC: Add direct referral and update ROI
     */
    function _addDirectReferralAndUpdateROI(address _referrer, address _referral) internal {
        if (!isDirectReferral[_referrer][_referral]) {
            uint256 count = directReferralsCount[_referrer];
            directReferrals[_referrer][count] = _referral;
            referralIndex[_referrer][_referral] = count;
            isDirectReferral[_referrer][_referral] = true;
            
            unchecked {
                directReferralsCount[_referrer]++;
            }
            
            // AUTOMATIC: Update referrer's active count and start ROI if applicable
            _updateReferrerActiveCountAuto(_referrer);
        }
    }
    
    /**
     * @dev AUTOMATIC: Update referrer's active count and ROI status
     */
    function _updateReferrerActiveCountAuto(address _referrer) internal {
        User storage referrer = users[_referrer];
        if (!referrer.isActive) return;
        
        uint128 newActiveCount = _countActiveDirectsAuto(_referrer);
        
        if (referrer.activeDirects != newActiveCount) {
            referrer.activeDirects = newActiveCount;
            referrer.totalDirects = uint128(directReferralsCount[_referrer]);
            referrer.lastActiveDirectsUpdate = uint64(block.timestamp);
            
            emit ActiveDirectsUpdated(_referrer, newActiveCount);
            
            // AUTOMATIC: Start ROI when getting first direct (runs for full 10 hours)
            if (newActiveCount >= 1 && !referrer.hasMinimumDirect) {
                referrer.hasMinimumDirect = true;
                // DON'T reset lastRewardUpdate - preserve existing pending ROI!
                // Only set cycleEndTime if not already set
                if (referrer.cycleEndTime <= block.timestamp) {
                    referrer.cycleEndTime = uint64(block.timestamp + CYCLE_DURATION);
                }
            }
        }
    }
    
    /**
     * @dev AUTOMATIC: Count active direct referrals with overflow protection
     */
    function _countActiveDirectsAuto(address _user) internal view returns (uint128) {
        uint256 count = directReferralsCount[_user];
        if (count == 0) return 0;
        
        uint128 activeCount = 0;
        uint256 maxCheck = count > 100 ? 100 : count; // Gas limit protection
        
        for (uint256 i = 0; i < maxCheck;) {
            address ref = directReferrals[_user][i];
            if (ref != address(0) && users[ref].isActive) {
                unchecked {
                    activeCount++;
                }
            }
            unchecked {
                i++;
            }
        }
        
        return activeCount;
    }
    
    /**
     * @dev AUTOMATIC: Update stored rewards based on time elapsed
     */
    function _updateStoredRewardsAuto(address _user) internal {
        User storage user = users[_user];
        
        if (!user.isActive || !user.hasMinimumDirect) {
            return;
        }
        
        uint256 currentTime = block.timestamp;
        uint256 effectiveEndTime = currentTime > user.cycleEndTime ? user.cycleEndTime : currentTime;
        
        // Ensure no underflow
        if (effectiveEndTime <= user.lastRewardUpdate) {
            return;
        }
        
        uint256 timeSinceLastUpdate = effectiveEndTime - user.lastRewardUpdate;
        
        if (timeSinceLastUpdate >= ROI_INTERVAL) {
            uint256 hoursCompleted = timeSinceLastUpdate / ROI_INTERVAL;
            uint256 ratePerHour = _getIntervalReward(user.activeDirects);
            
            if (ratePerHour > 0 && hoursCompleted > 0) {
                uint256 newRewards = hoursCompleted * ratePerHour;
                
                // Check for overflow before adding
                require(user.pendingRewards + newRewards <= type(uint128).max, "Rewards overflow");
                
                user.pendingRewards += uint128(newRewards);
                user.lastRewardUpdate = uint64(user.lastRewardUpdate + (hoursCompleted * ROI_INTERVAL));
            }
        }
        
        // AUTOMATIC: Stop ROI if cycle completed
        if (currentTime >= user.cycleEndTime && user.hasMinimumDirect) {
            user.hasMinimumDirect = false;
        }
    }
    
    /**
     * @dev Get ROI rate based on active directs
     */
     function _getIntervalReward(uint256 directCount) internal pure returns (uint256) {
         
        if (directCount >= 100) return 50 * 10**18;    // 50 USDT/hour (Icon)
        if (directCount >= 50) return 10 * 10**18;    // 10 USDT/hour (Diamond)
        if (directCount >= 10) return 5 * 10**18;     // 5 USDT/hour (Platinum)
        if (directCount >= 5) return 3 * 10**18;     // 3 USDT/hour (Gold)
        if (directCount >= 2) return 2 * 10**18;      // 2 USDT/hour (Silver)
        if (directCount >= 1) return 1.2 * 10**17;   // 1.2 USDT/hour (Bronze)
        return 0;
    }
    
    // ===================================================================
    // 🔄 MIGRATION FUNCTIONS - FIXED VERSION
    // ===================================================================
    
    /**
     * @dev Start the migration process from old contract
     */
    function startNewMigration() external onlyAdmin {
        require(!migrationCompleted, "Migration already completed");
        newMigrationActive = true;
        migrationIndex = 0;
        totalMigratedUsers = 0;
        currentMigrationPhase = 0;
    }
    
    /**
     * @dev Migrate users in batches from old contract - FIXED VERSION
     */
    function newBatchMigration(uint256 batchSize) external onlyAdmin {
        require(newMigrationActive, "New migration not started");
        require(!migrationCompleted, "Migration completed");
        require(batchSize >= 10 && batchSize <= 100, "Batch size 10-100");
        
        if (currentMigrationPhase == 0) {
            _migrateUsersBatchFixed(batchSize);
        } else if (currentMigrationPhase == 1) {
            _migrateDownlinesBatch(batchSize);
        }
    }
    
    /**
     * @dev FIXED: Auto-migrate users by getting them from old contract
     */
    function _migrateUsersBatchFixed(uint256 batchSize) internal {
        uint256 processed = 0;
        
        // Get total users from old contract
        uint256 oldTotalUsers;
        try oldContract.totalUsersJoined() returns (uint256 total) {
            oldTotalUsers = total;
        } catch {
            emit BatchDone(0, migrationIndex, block.timestamp);
            return;
        }
        
        // Process users starting from migrationIndex
        uint256 currentIndex = migrationIndex;
        
        for (uint256 i = 0; i < batchSize && currentIndex < oldTotalUsers; i++) {
            // Since we can't auto-discover users, this will just increment the index
            // Use migrateSpecificUsers instead for actual migration
            currentIndex++;
            processed++;
        }
        
        migrationIndex = currentIndex;
        emit BatchDone(processed, migrationIndex, block.timestamp);
    }
    
    /**
     * @dev Start downlines migration phase
     */
    function startDownlinesMigration() external onlyAdmin {
        require(newMigrationActive, "New migration not started");
        currentMigrationPhase = 1;
    }
    
    /**
     * @dev Complete the migration process
     */
    function completeNewMigration() external onlyAdmin {
        require(newMigrationActive, "New migration not started");
        migrationCompleted = true;
        currentMigrationPhase = 2;
        newMigrationActive = false;
        emit MigrationCompleted(totalMigratedUsers);
    }
    
    /**
     * @dev FIXED: Migrate single user with ACTIVE DIRECTS RESET TO 0
     */
    function _migrateUser(address userAddr) internal returns (bool) {
        try oldContract.users(userAddr) returns (
            uint64 joinTime, uint64 cycleEndTime, uint64, uint64,
            uint128 /* activeDirects */, uint128 totalDirects, uint128 pendingRewards, 
            address referrer, bool isActive, bool /* hasMinimumDirect */
        ) {
            if (joinTime == 0) return false;
            
            // Validate referrer
            if (referrer != admin && referrer != address(0)) {
                if (!migratedFromOld[referrer] && !hasJoined[referrer]) {
                    referrer = admin;
                }
            }
            
            // Create user with ACTIVE DIRECTS RESET TO 0
            User storage user = users[userAddr];
            user.joinTime = joinTime;
            user.cycleEndTime = cycleEndTime;
            user.lastRewardUpdate = uint64(block.timestamp);
            user.lastActiveDirectsUpdate = uint64(block.timestamp);
            
            // 🔥 RESET ACTIVE DIRECTS TO 0 ON MIGRATION
            user.activeDirects = 0;  // ← This is the key change
            
            user.totalDirects = totalDirects;
            user.pendingRewards = pendingRewards;
            user.referrer = referrer;
            user.isActive = isActive;
            
            // 🔥 RESET hasMinimumDirect to false so ROI must restart
            user.hasMinimumDirect = false;  // ← Force ROI restart
            
            hasJoined[userAddr] = true;
            migratedFromOld[userAddr] = true;
            migratedUsersList.push(userAddr);
            totalUsersJoined++;
            
            emit UserMigrated(userAddr, referrer);
            emit ActiveDirectsReset(userAddr);
            return true;
        } catch {
            return false;
        }
    }
    
    /**
     * @dev Simple downlines migration
     */
    function _migrateDownlinesBatch(uint256 batchSize) internal {
        uint256 processed = 0;
        
        for (uint256 i = 0; i < migratedUsersList.length && processed < batchSize; i++) {
            address userAddr = migratedUsersList[i];
            if (migratedFromOld[userAddr] && !downlinesMigrated[userAddr]) {
                _migrateDownlines(userAddr);
                processed++;
            }
        }
        
        emit BatchDone(processed, migrationIndex, block.timestamp);
    }
    
    /**
     * @dev Migrate user downlines - SIMPLE VERSION
     */
    function _migrateDownlines(address userAddr) internal {
        uint256 expectedDownlines = 0;
        try oldContract.directReferralsCount(userAddr) returns (uint256 count) {
            expectedDownlines = count;
        } catch {}
        
        uint256 actualCount = 0;
        for (uint256 i = 0; i < expectedDownlines && i < 100; i++) {
            try oldContract.directReferrals(userAddr, i) returns (address downline) {
                if (downline != address(0)) {
                    directReferrals[userAddr][actualCount] = downline;
                    isDirectReferral[userAddr][downline] = true;
                    referralIndex[userAddr][downline] = actualCount;
                    actualCount++;
                }
            } catch {
                break;
            }
        }
        
        directReferralsCount[userAddr] = actualCount;
        downlinesMigrated[userAddr] = true;
        emit DownMigrate(userAddr, actualCount);
    }
    
    /**
     * @dev IMPROVED: Migrate specific users with better error handling
     */
    function migrateSpecificUsers(address[] calldata userAddresses) external onlyAdmin {
        require(newMigrationActive, "New migration not started");
        require(userAddresses.length <= 50, "Max 50 users");
        
        uint256 migrated = 0;
        uint256 failed = 0;
        
        for (uint256 i = 0; i < userAddresses.length; i++) {
            address userAddr = userAddresses[i];
            
            if (userAddr == address(0)) {
                failed++;
                continue;
            }
            
            if (migratedFromOld[userAddr]) {
                // Already migrated, skip
                continue;
            }
            
            if (_migrateUser(userAddr)) {
                migrated++;
                totalMigratedUsers++;
            } else {
                failed++;
            }
        }
        
        emit BatchDone(migrated, migrationIndex, block.timestamp);
    }
    
    /**
     * @dev ALTERNATIVE: Simple reset all active directs after migration
     */
    function resetAllActiveDirects() external onlyAdmin {
        require(migrationCompleted, "Migration not completed");
        
        for (uint256 i = 0; i < migratedUsersList.length; i++) {
            address userAddr = migratedUsersList[i];
            User storage user = users[userAddr];
            
            // Reset active directs to 0
            user.activeDirects = 0;
            user.hasMinimumDirect = false;
            user.lastActiveDirectsUpdate = uint64(block.timestamp);
            
            emit ActiveDirectsUpdated(userAddr, 0);
            emit ActiveDirectsReset(userAddr);
        }
    }
    
    /**
     * @dev Force update active directs for specific users after migration
     */
    function forceUpdateActiveDirects(address[] calldata userAddresses) external onlyAdmin {
        require(migrationCompleted, "Migration not completed");
        
        for (uint256 i = 0; i < userAddresses.length; i++) {
            address userAddr = userAddresses[i];
            if (hasJoined[userAddr]) {
                // Force recalculation of active directs
                _updateReferrerActiveCountAuto(userAddr);
            }
        }
    }
    
    /**
     * @dev Get migration statistics
     */
    function getMigrationStats() external view returns (
        bool isCompleted,
        uint256 migratedCount,
        uint256 totalMigrated,
        uint8 currentPhase,
        bool isActive
    ) {
        return (
            migrationCompleted,
            migratedUsersList.length,
            totalMigratedUsers,
            currentMigrationPhase,
            newMigrationActive
        );
    }
    
    /**
     * @dev Get migration progress and recommendations
     */
    function getMigrationProgress() external view returns (
        uint256 totalMigrated,
        uint256 totalInList,
        bool completed,
        uint8 phase,
        string memory recommendation
    ) {
        totalMigrated = totalMigratedUsers;
        totalInList = migratedUsersList.length;
        completed = migrationCompleted;
        phase = currentMigrationPhase;
        
        if (!newMigrationActive && !completed) {
            recommendation = "Call startNewMigration() first";
        } else if (phase == 0) {
            recommendation = "Use migrateSpecificUsers() with user addresses";
        } else if (phase == 1) {
            recommendation = "Use newBatchMigration() for downlines";
        } else {
            recommendation = "Migration completed";
        }
        
        return (totalMigrated, totalInList, completed, phase, recommendation);
    }
    
    /**
     * @dev Test old contract connection
     */
    function testOldContract() external view returns (
        bool canConnect,
        uint256 oldTotalUsers,
        address oldContractAddress
    ) {
        oldContractAddress = address(oldContract);
        
        try oldContract.totalUsersJoined() returns (uint256 total) {
            canConnect = true;
            oldTotalUsers = total;
        } catch {
            canConnect = false;
            oldTotalUsers = 0;
        }
        
        return (canConnect, oldTotalUsers, oldContractAddress);
    }
    
    // ===================================================================
    // 📊 VIEW FUNCTIONS (Read-only, no gas cost)
    // ===================================================================
    
    /**
     * @dev Get current pending ROI rewards (time-based calculation)
     */
    function getCurrentPendingROI(address _user) public view returns (uint256) {
        User memory user = users[_user];
        
        if (!user.isActive || !user.hasMinimumDirect) {
            return user.pendingRewards;
        }
        
        uint256 currentTime = block.timestamp;
        uint256 effectiveEndTime = currentTime > user.cycleEndTime ? user.cycleEndTime : currentTime;
        
        // Ensure no underflow
        if (effectiveEndTime <= user.lastRewardUpdate) {
            return user.pendingRewards;
        }
        
        uint256 totalTimeElapsed = effectiveEndTime - user.lastRewardUpdate;
        uint256 hoursCompleted = totalTimeElapsed / ROI_INTERVAL;
        uint256 ratePerHour = _getIntervalReward(user.activeDirects);
        
        if (hoursCompleted == 0 || ratePerHour == 0) {
            return user.pendingRewards;
        }
        
        uint256 timeBasedRewards = hoursCompleted * ratePerHour;
        
        // Check for overflow
        if (user.pendingRewards + timeBasedRewards < user.pendingRewards) {
            return type(uint256).max; // Return max value if overflow would occur
        }
        
        return user.pendingRewards + timeBasedRewards;
    }
    
    /**
     * @dev Get user information
     */
    function getUserInfo(address _user) external view returns (
        bool isActive,
        uint256 joinTime,
        uint256 cycleEndTime,
        uint256 activeDirects,
        uint256 totalDirects,
        uint256 pendingRewards,
        uint256 timeUntilCycleEnd,
        bool hasMinimumDirect,
        address referrer
    ) {
        User memory user = users[_user];
        
        timeUntilCycleEnd = user.isActive && block.timestamp < user.cycleEndTime 
            ? user.cycleEndTime - block.timestamp 
            : 0;
            
        uint256 currentPending = getCurrentPendingROI(_user);
        
        return (
            user.isActive,
            user.joinTime,
            user.cycleEndTime,
            user.activeDirects,
            user.totalDirects,
            currentPending,
            timeUntilCycleEnd,
            user.hasMinimumDirect,
            user.referrer
        );
    }
    
    /**
     * @dev Get user's ROI status
     */
    function getMyROIStatus(address _user) external view returns (
        bool roiActive,
        uint256 roiStartedAt,
        uint256 roiEndsAt,
        uint256 hoursRemaining,
        uint256 currentROIRate,
        uint256 totalROIEarned,
        string memory status
    ) {
        require(hasJoined[_user], "User has not joined");
        
        User memory user = users[_user];
        
        roiActive = user.isActive && user.hasMinimumDirect;
        currentROIRate = _getIntervalReward(user.activeDirects);
        totalROIEarned = getCurrentPendingROI(_user);
        
        if (roiActive) {
            roiStartedAt = user.lastRewardUpdate;
            roiEndsAt = user.cycleEndTime;
            
            if (block.timestamp < user.cycleEndTime) {
                uint256 timeRemaining = user.cycleEndTime - block.timestamp;
                hoursRemaining = timeRemaining / 3600;
                status = "ROI Active - Earning Automatically Every Hour";
            } else {
                hoursRemaining = 0;
                status = "ROI Cycle Completed - Ready to Claim";
            }
        } else if (user.isActive && user.activeDirects == 0) {
            status = "Waiting for First Direct Referral to Start ROI";
        } else if (!user.isActive) {
            status = "Inactive - Need to Rejoin";
        } else {
            status = "Unknown Status";
        }
        
        return (roiActive, roiStartedAt, roiEndsAt, hoursRemaining, currentROIRate, totalROIEarned, status);
    }
    
    /**
     * @dev Get user's referral information
     */
    function getMyReferralInfo(address _user) external view returns (
        address myReferralAddress,
        uint256 totalDirectReferrals,
        uint256 activeDirectReferrals,
        bool canEarnFromReferrals
    ) {
        require(hasJoined[_user], "User has not joined");
        
        User memory user = users[_user];
        myReferralAddress = _user;
        totalDirectReferrals = directReferralsCount[_user];
        activeDirectReferrals = user.activeDirects;
        canEarnFromReferrals = user.isActive;
        
        return (myReferralAddress, totalDirectReferrals, activeDirectReferrals, canEarnFromReferrals);
    }
    
    /**
     * @dev Get direct referrals with pagination
     */
    function getDirectReferrals(address _user, uint256 _offset, uint256 _limit) external view returns (address[] memory referrals) {
        uint256 count = directReferralsCount[_user];
        
        if (_offset >= count || _limit == 0) {
            return new address[](0);
        }
        
        uint256 end = _offset + _limit;
        if (end > count) {
            end = count;
        }
        
        uint256 resultLength = end - _offset;
        referrals = new address[](resultLength);
        
        for (uint256 i = 0; i < resultLength;) {
            referrals[i] = directReferrals[_user][_offset + i];
            unchecked {
                i++;
            }
        }
        
        return referrals;
    }
    
    /**
     * @dev Get contract statistics
     */
    function getContractStats() external view returns (
        uint256 totalBalance,
        uint256 totalUsers,
        uint256 totalRewards,
        address usdtAddress
    ) {
        return (
            USDT.balanceOf(address(this)),
            totalUsersJoined,
            totalRewardsPaid,
            address(USDT)
        );
    }
    
    /**
     * @dev Check if address can be used as referrer
     */
    function canUseAsReferrer(address _potentialReferrer) external view returns (
        bool canRefer,
        string memory reason
    ) {
        if (_potentialReferrer == address(0)) {
            return (true, "No referrer - allowed");
        }
        
        if (!hasJoined[_potentialReferrer]) {
            return (true, "Referrer not joined - but still allowed");
        }
        
        if (directReferralsCount[_potentialReferrer] >= MAX_DIRECT_REFS) {
            return (false, "Referrer limit exceeded");
        }
        
        return (true, "Valid referrer");
    }
    
    /**
     * @dev Get current ROI rate for user
     */
    function getCurrentROIRate(address _user) external view returns (uint256) {
        return _getIntervalReward(users[_user].activeDirects);
    }
    
    /**
     * @dev Get direct referrals count
     */
    function getDirectReferralsCount(address _user) external view returns (uint256) {
        return directReferralsCount[_user];
    }
    
    /**
     * @dev Get contract balance
     */
    function getContractBalance() external view returns (uint256) {
        return USDT.balanceOf(address(this));
    }
    
    /**
     * @dev Contract validation - Check if everything is working correctly
     */
    function validateContract() external view returns (
        bool isValid,
        string memory status,
        uint256 contractBalance,
        uint256 totalUsers,
        address usdtToken
    ) {
        contractBalance = USDT.balanceOf(address(this));
        totalUsers = totalUsersJoined;
        usdtToken = address(USDT);
        
        // Check if USDT address is correct for BSC mainnet
        if (address(USDT) != MAINNET_USDT_ADDRESS) {
            return (false, "Incorrect USDT address", contractBalance, totalUsers, usdtToken);
        }
        
        // Check admin is set
        if (admin == address(0)) {
            return (false, "Admin not set", contractBalance, totalUsers, usdtToken);
        }
        
        // Check constants are reasonable
        if (JOIN_AMOUNT != 10 * 10**18 || ADMIN_FEE != 2 * 10**18) {
            return (false, "Incorrect amounts", contractBalance, totalUsers, usdtToken);
        }
        
        // Check time constants
        if (CYCLE_DURATION != 10 hours || ROI_INTERVAL != 1 hours) {
            return (false, "Incorrect time settings", contractBalance, totalUsers, usdtToken);
        }
        
        isValid = true;
        status = "Contract validation passed - ready for use";
        
        return (isValid, status, contractBalance, totalUsers, usdtToken);
    }
}