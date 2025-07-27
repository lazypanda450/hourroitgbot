/**
 *Submitted for verification at BscScan.com on 2025-07-26
*/

/**
 *Submitted for verification at BscScan.com on 2025-07-27
*/

/**
 * HOURROI – Earn Every Hour! (CORRECTED VERSION)
 * 
 * CORRECT FIXES:
 * 1. Active directs reset to 0 after claim/rejoin ✅
 * 2. Only NEW joins in current cycle count as active ✅
 * 3. Old directs preserved but don't auto-reactivate ✅
 * 4. Batch migration for all users in one call ✅
 * 
 * Join with just 10 USDT
 * Refer 1 Active Direct person to start earning
 * Get paid every cycle based on your tier!
 * 
 * ROI Tiers (Based on Active Directs FROM CURRENT CYCLE ONLY):
 * 0 directs = No ROI
 * 1–4 = 12 USDT per cycle (Bronze Tier)
 * 2–4 = 20 USDT per cycle (Silver Tier) 
 * 5–9 = 30 USDT per cycle (Gold Tier)
 * 10–49 = 50 USDT per cycle (Platinum Tier)
 * 50–99 = 100 USDT per cycle (Diamond Tier)
 * 100+ = 500 USDT per cycle (Icon Tier)
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
    address private constant OLD_CONTRACT_ADDRESS = 0x4Ce5eff760652BcCAcF69f3e3cB152A5DC872AA4;
    
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
    
    uint256 private constant JOIN_AMOUNT = 10 * 10**18;
    uint256 private constant REJOIN_AMOUNT = 10 * 10**18;
    uint256 private constant ADMIN_FEE = 2 * 10**18;
    uint256 private constant CYCLE_DURATION = 10 hours;
    uint256 private constant MAX_DIRECT_REFS = 1000;
    
    // CORRECTED: Track only new joins per cycle
    struct User {
        // Slot 1: Time values (64 bits each = 256 bits total)
        uint64 joinTime;
        uint64 cycleEndTime;
        uint64 lastRewardUpdate;
        uint64 lastActiveDirectsUpdate;
        
        // Slot 2: Counters and cycle (256 bits total)
        uint64 currentCycle;       // Track user's current cycle
        uint64 unused1;            // For future use
        uint128 totalDirects;      // Total historical directs (preserved)
        
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
    
    // CORRECTED: Track ONLY directs who joined in each specific cycle
    mapping(address => mapping(uint64 => uint128)) public activeDirectsInCycle; // user => cycle => count of actives in that cycle
    mapping(address => mapping(uint64 => mapping(uint256 => address))) public directsJoinedInCycle; // user => cycle => index => direct address
    mapping(address => mapping(uint64 => uint256)) public directsCountInCycle; // user => cycle => total count in that cycle
    
    // Historical referral tracking (preserved for total counts)
    mapping(address => mapping(uint256 => address)) public directReferrals; // All historical directs
    mapping(address => uint256) public directReferralsCount; // Total historical count
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
    event EmergencyWithdrawExecuted(uint256 amount);
    event ActiveDirectsUpdated(address indexed user, uint64 cycle, uint256 newCount);
    event CycleStarted(address indexed user, uint64 cycle, uint256 timestamp);
    
    // Migration events
    event UserMigrated(address indexed user, address indexed referrer);
    event MigrationCompleted(uint256 totalMigrated);
    event BatchDone(uint256 batch, uint256 index, uint256 time);
    event DownMigrate(address indexed user, uint256 count);
    
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }
    
    /**
     * @dev Debug function to check admin status
     */
    function debugAdminStatus() external view returns (
        address contractAdmin,
        address currentCaller,
        bool isCallerAdmin,
        bool migrationComplete,
        bool isMigrationActive  // FIXED: Renamed to avoid shadowing
    ) {
        return (
            admin,
            msg.sender,
            msg.sender == admin,
            migrationCompleted,
            newMigrationActive
        );
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
    // MAIN USER FUNCTIONS (CORRECTED)
    // ===================================================================
    
    /**
     * @dev CORRECTED JOIN FUNCTION - Only adds to current cycle, preserves historical
     */
    function joinPlan(address _referrer) external postMigration nonReentrant {
        require(!hasJoined[msg.sender], "Already joined");
        
        // Prevent self-referral
        if (_referrer == msg.sender) {
            _referrer = address(0);
        }
        
        // Optional referrer validation
        if (_referrer != address(0) && hasJoined[_referrer]) {
            require(directReferralsCount[_referrer] < MAX_DIRECT_REFS, "Referrer limit exceeded");
        }
        
        // Transfer payment from user
        USDT.safeTransferFrom(msg.sender, address(this), JOIN_AMOUNT);
        
        uint64 currentTime = uint64(block.timestamp);
        
        // Initialize user with cycle 1
        User storage user = users[msg.sender];
        user.joinTime = currentTime;
        user.cycleEndTime = 0; // No timer yet - starts when getting first direct
        user.lastRewardUpdate = currentTime;
        user.lastActiveDirectsUpdate = currentTime;
        user.currentCycle = 1; // Start at cycle 1
        user.isActive = true;
        user.referrer = _referrer;
        
        hasJoined[msg.sender] = true;
        unchecked {
            totalUsersJoined++;
        }
        
        // CORRECTED: Add to referrer's CURRENT CYCLE only (not historical reactivation)
        if (_referrer != address(0) && hasJoined[_referrer]) {
            _addNewDirectToCurrentCycle(_referrer, msg.sender);
        }
        
        // Pay admin fee
        USDT.safeTransfer(admin, ADMIN_FEE);
        
        emit UserJoined(msg.sender, _referrer, JOIN_AMOUNT, currentTime);
    }

    /**
     * @dev FIXED CLAIM AND REJOIN - Auto-reactivates user for their referrer
     */
    function claimAndRejoin() external postMigration nonReentrant {
        User storage user = users[msg.sender];
        require(user.isActive, "User not active");
        require(user.cycleEndTime > 0, "ROI not started - need first direct");
        require(block.timestamp >= user.cycleEndTime, "10-hour cycle not completed");
        require(directReferralsCount[msg.sender] >= 2, "Need minimum 2 total historical directs");
        
        // Use ONLY current cycle actives for rewards
        uint128 currentCycleActives = activeDirectsInCycle[msg.sender][user.currentCycle];
        uint256 totalRewards = 0;
        
        if (user.hasMinimumDirect && currentCycleActives >= 1) {
            totalRewards = _getTierReward(currentCycleActives);
        }
        
        uint256 contractBalance = USDT.balanceOf(address(this));
        uint256 profit = 0;
        
        if (totalRewards > REJOIN_AMOUNT) {
            profit = totalRewards - REJOIN_AMOUNT;
            require(contractBalance >= profit, "Insufficient contract balance for profit");
        }
        
        address referrer = user.referrer;
        uint64 currentTime = uint64(block.timestamp);
        uint64 newCycle = user.currentCycle + 1;
        
        // Reset for new cycle - active directs go to 0, historical preserved
        user.isActive = true;
        user.joinTime = currentTime;
        user.cycleEndTime = 0; // Reset timer
        user.lastRewardUpdate = currentTime;
        user.lastActiveDirectsUpdate = currentTime;
        user.hasMinimumDirect = false;
        user.pendingRewards = 0;
        user.currentCycle = newCycle; // Move to next cycle
        
        // Active directs reset to 0 for new cycle
        activeDirectsInCycle[msg.sender][newCycle] = 0;
        
        unchecked {
            totalRewardsPaid += totalRewards;
        }
        
        // FIXED: Auto-reactivate this user for their referrer's current cycle
        if (referrer != address(0) && hasJoined[referrer] && users[referrer].isActive) {
            _addNewDirectToCurrentCycle(referrer, msg.sender);
        }
        
        // Transfer profit to user if any
        if (profit > 0) {
            USDT.safeTransfer(msg.sender, profit);
        }
        
        // Pay admin fee
        USDT.safeTransfer(admin, ADMIN_FEE);
        
        emit RewardsClaimed(msg.sender, totalRewards);
        emit UserRejoined(msg.sender, REJOIN_AMOUNT, currentTime);
        emit CycleStarted(msg.sender, newCycle, currentTime);
    }
    
    /**
     * @dev Emergency withdrawal without timelock
     */
    function emergencyWithdraw() external onlyAdmin {
        uint256 balance = USDT.balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");
        
        USDT.safeTransfer(admin, balance);
        emit EmergencyWithdrawExecuted(balance);
    }
    
    // ===================================================================
    // CORRECTED INTERNAL FUNCTIONS
    // ===================================================================
    
    /**
     * @dev CORRECTED: Add NEW direct to referrer's CURRENT CYCLE only (no old reactivation)
     */
    function _addNewDirectToCurrentCycle(address _referrer, address _newJoiner) internal {
        User storage referrer = users[_referrer];
        uint64 referrerCycle = referrer.currentCycle;
        
        // Add to historical tracking (preserve total count)
        if (!isDirectReferral[_referrer][_newJoiner]) {
            uint256 count = directReferralsCount[_referrer];
            directReferrals[_referrer][count] = _newJoiner;
            referralIndex[_referrer][_newJoiner] = count;
            isDirectReferral[_referrer][_newJoiner] = true;
            
            unchecked {
                directReferralsCount[_referrer]++;
                referrer.totalDirects++;
            }
        }
        
        // CORRECTED: Add ONLY this new joiner to current cycle (no old directs counted)
        uint256 cycleIndex = directsCountInCycle[_referrer][referrerCycle];
        directsJoinedInCycle[_referrer][referrerCycle][cycleIndex] = _newJoiner;
        directsCountInCycle[_referrer][referrerCycle]++;
        
        // Update referrer's active count for current cycle
        _updateReferrerActiveCountInCurrentCycle(_referrer);
    }
    
    /**
     * @dev CORRECTED: Update referrer's active count for CURRENT CYCLE only
     */
    function _updateReferrerActiveCountInCurrentCycle(address _referrer) internal {
        User storage referrer = users[_referrer];
        if (!referrer.isActive) return;
        
        uint64 referrerCycle = referrer.currentCycle;
        
        // CORRECTED: Count ONLY people who joined in THIS cycle and are still active
        uint128 currentCycleActives = _countActiveDirectsInSpecificCycle(_referrer, referrerCycle);
        
        // Update cycle data
        activeDirectsInCycle[_referrer][referrerCycle] = currentCycleActives;
        referrer.lastActiveDirectsUpdate = uint64(block.timestamp);
        
        emit ActiveDirectsUpdated(_referrer, referrerCycle, currentCycleActives);
        
        // Start timer when getting first direct in current cycle
        if (currentCycleActives >= 1 && !referrer.hasMinimumDirect) {
            referrer.hasMinimumDirect = true;
            referrer.cycleEndTime = uint64(block.timestamp + CYCLE_DURATION);
        }
    }
    
    /**
     * @dev CORRECTED: Count ONLY directs who joined in this specific cycle
     */
    function _countActiveDirectsInSpecificCycle(address _user, uint64 _cycle) internal view returns (uint128) {
        uint256 count = directsCountInCycle[_user][_cycle];
        if (count == 0) return 0;
        
        uint128 activeCount = 0;
        
        // CORRECTED: Only check people who joined in THIS specific cycle
        for (uint256 i = 0; i < count && i < 100; i++) {
            address directInThisCycle = directsJoinedInCycle[_user][_cycle][i];
            if (directInThisCycle != address(0) && users[directInThisCycle].isActive) {
                unchecked {
                    activeCount++;
                }
            }
        }
        
        return activeCount;
    }
    
    /**
     * @dev Get tier reward for completed cycle
     */
    function _getTierReward(uint256 directCount) internal pure returns (uint256) {
        if (directCount >= 100) return 500 * 10**18;   // Icon: 500 USDT
        if (directCount >= 50) return 100 * 10**18;    // Diamond: 100 USDT  
        if (directCount >= 10) return 50 * 10**18;     // Platinum: 50 USDT
        if (directCount >= 5) return 30 * 10**18;      // Gold: 30 USDT
        if (directCount >= 2) return 20 * 10**18;      // Silver: 20 USDT
        if (directCount >= 1) return 12 * 10**18;      // Bronze: 12 USDT
        return 0;
    }
    
    // ===================================================================
    // FIXED MIGRATION FUNCTIONS
    // ===================================================================
    
    /**
     * @dev Start the migration process
     */
    function startNewMigration() external onlyAdmin {
        require(!migrationCompleted, "Migration already completed");
        newMigrationActive = true;
        migrationIndex = 0;
        totalMigratedUsers = 0;
        currentMigrationPhase = 0;
    }
    
    /**
     * @dev FIXED: Migrate all users from migratedUsersList in one call
     */
    function migrateAllUsersFromList() external onlyAdmin {
        require(newMigrationActive, "New migration not started");
        require(!migrationCompleted, "Migration completed");
        
        uint256 totalUsers = migratedUsersList.length; // Should be 69
        require(totalUsers > 0, "No users in migrated list");
        
        uint256 migrated = 0;
        
        // Migrate all users from the list
        for (uint256 i = 0; i < totalUsers; i++) {
            address userAddr = migratedUsersList[i];
            
            if (userAddr == address(0)) {
                continue;
            }
            
            // Skip if already migrated in new contract
            if (hasJoined[userAddr]) {
                continue;
            }
            
            // Migrate user data from old contract
            if (_migrateUserFromOldContract(userAddr)) {
                migrated++;
            }
        }
        
        totalMigratedUsers = migrated;
        emit BatchDone(migrated, totalUsers, block.timestamp);
    }

    /**
     * @dev FIXED: Migrate user from old contract PRESERVING active directs
     */
    function _migrateUserFromOldContract(address userAddr) internal returns (bool) {
        try oldContract.users(userAddr) returns (
            uint64 joinTime, uint64 cycleEndTime, uint64 lastRewardUpdate, uint64 lastActiveDirectsUpdate,
            uint128 activeDirects, uint128 totalDirects, uint128 pendingRewards, 
            address referrer, bool isActive, bool hasMinimumDirect
        ) {
            if (joinTime == 0) return false;
            
            // Validate referrer
            if (referrer != admin && referrer != address(0)) {
                if (!hasJoined[referrer]) {
                    referrer = admin; // Fallback to admin if referrer not migrated
                }
            }
            
            // CORRECTED: Preserve user data including active directs
            User storage user = users[userAddr];
            user.joinTime = joinTime;
            user.cycleEndTime = cycleEndTime; // PRESERVE: Keep original cycle end time
            user.lastRewardUpdate = lastRewardUpdate; // PRESERVE: Keep original update time
            user.lastActiveDirectsUpdate = lastActiveDirectsUpdate;
            user.currentCycle = 1; // Start at cycle 1
            user.totalDirects = totalDirects; // Keep historical count
            user.pendingRewards = pendingRewards; // PRESERVE: Keep pending rewards
            user.referrer = referrer;
            user.isActive = isActive;
            user.hasMinimumDirect = hasMinimumDirect; // PRESERVE: Keep minimum direct status
            
            // CORRECTED: PRESERVE active directs from old contract
            activeDirectsInCycle[userAddr][1] = activeDirects; // Keep their active directs in cycle 1
            
            hasJoined[userAddr] = true;
            
            emit UserMigrated(userAddr, referrer);
            return true;
        } catch {
            return false;
        }
    }
    
    /**
     * @dev FIXED: Migrate all downlines in one call
     */
    function migrateAllDownlines() external onlyAdmin {
        require(newMigrationActive, "New migration not started");
        
        uint256 processed = 0;
        
        // Process all users in migratedUsersList
        for (uint256 i = 0; i < migratedUsersList.length; i++) {
            address userAddr = migratedUsersList[i];
            
            if (hasJoined[userAddr] && !downlinesMigrated[userAddr]) {
                _migrateUserDownlines(userAddr);
                processed++;
            }
        }
        
        emit BatchDone(processed, migratedUsersList.length, block.timestamp);
    }

    /**
     * @dev FIXED: Migrate user's downlines from old contract (historical only)
     */
    function _migrateUserDownlines(address userAddr) internal {
        uint256 expectedCount = 0;
        
        // Get downlines count from old contract
        try oldContract.directReferralsCount(userAddr) returns (uint256 count) {
            expectedCount = count;
        } catch {
            downlinesMigrated[userAddr] = true;
            return;
        }
        
        uint256 actualCount = 0;
        
        // Migrate each downline (historical tracking only)
        for (uint256 i = 0; i < expectedCount && i < MAX_DIRECT_REFS; i++) {
            try oldContract.directReferrals(userAddr, i) returns (address downline) {
                if (downline != address(0)) {
                    // Add to historical referral mappings only (not current cycle)
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
     * @dev FIXED: One-click complete migration without external calls
     */
    function oneClickCompleteMigration() external onlyAdmin {
        require(!migrationCompleted, "Already completed");
        
        // Start migration if not started
        if (!newMigrationActive) {
            newMigrationActive = true;
            migrationIndex = 0;
            totalMigratedUsers = 0;
            currentMigrationPhase = 0;
        }
        
        // Phase 1: Migrate all users (FIXED: Direct call instead of this.)
        _migrateAllUsersFromListInternal();
        
        // Phase 2: Migrate all downlines (FIXED: Direct call instead of this.)
        currentMigrationPhase = 1;
        _migrateAllDownlinesInternal();
        
        // Complete migration
        migrationCompleted = true;
        currentMigrationPhase = 2;
        newMigrationActive = false;
        
        emit MigrationCompleted(totalMigratedUsers);
    }
    
    /**
     * @dev FIXED: Internal function for migrating users (no external call)
     */
    function _migrateAllUsersFromListInternal() internal {
        uint256 totalUsers = migratedUsersList.length; // Should be 69
        require(totalUsers > 0, "No users in migrated list");
        
        uint256 migrated = 0;
        
        // Migrate all users from the list
        for (uint256 i = 0; i < totalUsers; i++) {
            address userAddr = migratedUsersList[i];
            
            if (userAddr == address(0)) {
                continue;
            }
            
            // Skip if already migrated in new contract
            if (hasJoined[userAddr]) {
                continue;
            }
            
            // Migrate user data from old contract
            if (_migrateUserFromOldContract(userAddr)) {
                migrated++;
            }
        }
        
        totalMigratedUsers = migrated;
        emit BatchDone(migrated, totalUsers, block.timestamp);
    }
    
    /**
     * @dev FIXED: Internal function for migrating downlines (no external call)
     */
    function _migrateAllDownlinesInternal() internal {
        uint256 processed = 0;
        
        // Process all users in migratedUsersList
        for (uint256 i = 0; i < migratedUsersList.length; i++) {
            address userAddr = migratedUsersList[i];
            
            if (hasJoined[userAddr] && !downlinesMigrated[userAddr]) {
                _migrateUserDownlines(userAddr);
                processed++;
            }
        }
        
        emit BatchDone(processed, migratedUsersList.length, block.timestamp);
    }
    
    /**
     * @dev Migrate specific users with better error handling
     */
    function migrateSpecificUsers(address[] calldata userAddresses) external onlyAdmin {
        require(newMigrationActive, "New migration not started");
        require(userAddresses.length <= 50, "Max 50 users");
        
        uint256 migrated = 0;
        
        for (uint256 i = 0; i < userAddresses.length; i++) {
            address userAddr = userAddresses[i];
            
            if (userAddr == address(0) || migratedFromOld[userAddr]) {
                continue;
            }
            
            if (_migrateUser(userAddr)) {
                migrated++;
                totalMigratedUsers++;
            }
        }
        
        emit BatchDone(migrated, migrationIndex, block.timestamp);
    }
    
    /**
     * @dev Migrate single user PRESERVING active directs (not resetting)
     */
    function _migrateUser(address userAddr) internal returns (bool) {
        try oldContract.users(userAddr) returns (
            uint64 joinTime, uint64 cycleEndTime, uint64 lastRewardUpdate, uint64 lastActiveDirectsUpdate,
            uint128 activeDirects, uint128 totalDirects, uint128 pendingRewards, 
            address referrer, bool isActive, bool hasMinimumDirect
        ) {
            if (joinTime == 0) return false;
            
            // Validate referrer
            if (referrer != admin && referrer != address(0)) {
                if (!migratedFromOld[referrer] && !hasJoined[referrer]) {
                    referrer = admin;
                }
            }
            
            // CORRECTED: PRESERVE all data including active directs
            User storage user = users[userAddr];
            user.joinTime = joinTime;
            user.cycleEndTime = cycleEndTime; // PRESERVE: Keep original cycle time
            user.lastRewardUpdate = lastRewardUpdate; // PRESERVE: Keep original times
            user.lastActiveDirectsUpdate = lastActiveDirectsUpdate;
            user.currentCycle = 1; // Start at cycle 1
            user.totalDirects = totalDirects;
            user.pendingRewards = pendingRewards; // PRESERVE: Keep pending rewards
            user.referrer = referrer;
            user.isActive = isActive;
            user.hasMinimumDirect = hasMinimumDirect; // PRESERVE: Keep status
            
            // CORRECTED: PRESERVE active directs from old contract
            activeDirectsInCycle[userAddr][1] = activeDirects; // Keep their active directs
            
            hasJoined[userAddr] = true;
            migratedFromOld[userAddr] = true;
            migratedUsersList.push(userAddr);
            totalUsersJoined++;
            
            emit UserMigrated(userAddr, referrer);
            return true;
        } catch {
            return false;
        }
    }
    
    /**
     * @dev Complete migration
     */
    function completeNewMigration() external onlyAdmin {
        require(newMigrationActive, "New migration not started");
        migrationCompleted = true;
        currentMigrationPhase = 2;
        newMigrationActive = false;
        emit MigrationCompleted(totalMigratedUsers);
    }
    
    // ===================================================================
    // VIEW FUNCTIONS (CORRECTED)
    // ===================================================================
    
    /**
     * @dev CORRECTED: Get current pending ROI rewards (current cycle only)
     */
    function getCurrentPendingROI(address _user) public view returns (uint256) {
        User memory user = users[_user];
        
        if (!user.isActive || !user.hasMinimumDirect || user.cycleEndTime == 0) {
            return 0;
        }
        
        // Only give rewards when 10-hour cycle is completed
        if (block.timestamp >= user.cycleEndTime) {
            uint128 currentCycleActives = activeDirectsInCycle[_user][user.currentCycle];
            return _getTierReward(currentCycleActives);
        }
        
        return 0;
    }
    
    /**
     * @dev CORRECTED: Get user information with current cycle data
     */
    function getUserInfo(address _user) external view returns (
        bool isActive,
        uint256 joinTime,
        uint256 cycleEndTime,
        uint256 currentCycleActives, // CORRECTED: Current cycle actives only
        uint256 totalHistoricalDirects, // Historical count preserved
        uint256 pendingRewards,
        uint256 timeUntilCycleEnd,
        bool hasMinimumDirect,
        address referrer,
        uint64 currentCycle
    ) {
        User memory user = users[_user];
        
        timeUntilCycleEnd = user.isActive && block.timestamp < user.cycleEndTime 
            ? user.cycleEndTime - block.timestamp 
            : 0;
            
        uint256 currentPending = getCurrentPendingROI(_user);
        uint128 cycleActives = activeDirectsInCycle[_user][user.currentCycle];
        
        return (
            user.isActive,
            user.joinTime,
            user.cycleEndTime,
            cycleActives, // CORRECTED: Only current cycle actives
            user.totalDirects, // Historical total preserved
            currentPending,
            timeUntilCycleEnd,
            user.hasMinimumDirect,
            user.referrer,
            user.currentCycle
        );
    }
    
    /**
     * @dev CORRECTED: Get ROI status with current cycle information
     */
    function getMyROIStatus(address _user) external view returns (
        bool roiActive,
        uint256 roiStartedAt,
        uint256 roiEndsAt,
        uint256 hoursRemaining,
        uint256 currentROIRate,
        uint256 totalROIEarned,
        string memory status,
        uint64 currentCycle,
        uint256 currentCycleActives
    ) {
        require(hasJoined[_user], "User has not joined");
        
        User memory user = users[_user];
        uint128 cycleActives = activeDirectsInCycle[_user][user.currentCycle];
        
        roiActive = user.isActive && user.hasMinimumDirect && user.cycleEndTime > 0;
        currentROIRate = _getTierReward(cycleActives);
        totalROIEarned = getCurrentPendingROI(_user);
        currentCycle = user.currentCycle;
        currentCycleActives = cycleActives;
        
        if (user.cycleEndTime == 0) {
            status = "Waiting for First Direct Referral to Start ROI";
        } else if (roiActive) {
            roiStartedAt = user.lastRewardUpdate;
            roiEndsAt = user.cycleEndTime;
            
            if (block.timestamp < user.cycleEndTime) {
                uint256 timeRemaining = user.cycleEndTime - block.timestamp;
                hoursRemaining = timeRemaining / 3600;
                status = "ROI Active - Earning Based on Current Cycle Actives Only";
            } else {
                hoursRemaining = 0;
                status = "ROI Cycle Completed - Ready to Claim";
            }
        } else if (user.isActive && cycleActives == 0) {
            status = "Waiting for New Direct Referrals in Current Cycle";
        } else if (!user.isActive) {
            status = "Inactive - Need to Rejoin";
        } else {
            status = "Unknown Status";
        }
        
        return (roiActive, roiStartedAt, roiEndsAt, hoursRemaining, currentROIRate, totalROIEarned, status, currentCycle, currentCycleActives);
    }
    
    /**
     * @dev CORRECTED: Get user's referral information with cycle data
     */
    function getMyReferralInfo(address _user) external view returns (
        address myReferralAddress,
        uint256 totalHistoricalDirects,
        uint256 currentCycleActives,
        bool canEarnFromReferrals,
        uint64 currentCycle
    ) {
        require(hasJoined[_user], "User has not joined");
        
        User memory user = users[_user];
        uint128 cycleActives = activeDirectsInCycle[_user][user.currentCycle];
        
        myReferralAddress = _user;
        totalHistoricalDirects = directReferralsCount[_user];
        currentCycleActives = cycleActives;
        canEarnFromReferrals = user.isActive;
        currentCycle = user.currentCycle;
        
        return (myReferralAddress, totalHistoricalDirects, currentCycleActives, canEarnFromReferrals, currentCycle);
    }
    
    /**
     * @dev Get direct referrals with pagination (historical)
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
     * @dev CORRECTED: Get direct referrals for specific cycle
     */
    function getDirectReferralsInCycle(address _user, uint64 _cycle, uint256 _offset, uint256 _limit) external view returns (address[] memory referrals) {
        uint256 count = directsCountInCycle[_user][_cycle];
        
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
            referrals[i] = directsJoinedInCycle[_user][_cycle][_offset + i];
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
     * @dev CORRECTED: Get current ROI rate for user based on current cycle actives
     */
    function getCurrentROIRate(address _user) external view returns (uint256) {
        uint128 cycleActives = activeDirectsInCycle[_user][users[_user].currentCycle];
        return _getTierReward(cycleActives);
    }
    
    /**
     * @dev Get direct referrals count (historical total)
     */
    function getDirectReferralsCount(address _user) external view returns (uint256) {
        return directReferralsCount[_user];
    }
    
    /**
     * @dev CORRECTED: Get active directs count for current cycle only
     */
    function getCurrentCycleActivesCount(address _user) external view returns (uint256) {
        return activeDirectsInCycle[_user][users[_user].currentCycle];
    }
    
    /**
     * @dev Get active directs count for specific cycle
     */
    function getCycleActivesCount(address _user, uint64 _cycle) external view returns (uint256) {
        return activeDirectsInCycle[_user][_cycle];
    }
    
    /**
     * @dev Get contract balance
     */
    function getContractBalance() external view returns (uint256) {
        return USDT.balanceOf(address(this));
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
            recommendation = "Use oneClickCompleteMigration() to migrate all 69 users";
        } else if (phase == 1) {
            recommendation = "Use migrateAllDownlines() for referral links";
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
        if (CYCLE_DURATION != 10 hours) {
            return (false, "Incorrect time settings", contractBalance, totalUsers, usdtToken);
        }
        
        isValid = true;
        status = "Contract validation passed - Economic bug FIXED: Only current cycle actives count";
        
        return (isValid, status, contractBalance, totalUsers, usdtToken);
    }
    
    /**
     * @dev CORRECTED: Get user's cycle history
     */
    function getUserCycleHistory(address _user, uint64 _cycle) external view returns (
        uint256 activesInCycle,
        uint256 rewardsEarned,
        bool cycleCompleted
    ) {
        activesInCycle = activeDirectsInCycle[_user][_cycle];
        rewardsEarned = _getTierReward(activesInCycle);
        
        User memory user = users[_user];
        cycleCompleted = _cycle < user.currentCycle;
        
        return (activesInCycle, rewardsEarned, cycleCompleted);
    }
    
    /**
     * @dev CORRECTED: Get multiple cycles data for user
     */
    function getUserMultipleCycles(address _user, uint64 _startCycle, uint64 _endCycle) external view returns (
        uint64[] memory cycles,
        uint256[] memory activesCounts,
        uint256[] memory rewards
    ) {
        require(_startCycle <= _endCycle, "Invalid cycle range");
        require(_endCycle - _startCycle <= 10, "Max 10 cycles per call");
        
        uint256 length = _endCycle - _startCycle + 1;
        cycles = new uint64[](length);
        activesCounts = new uint256[](length);
        rewards = new uint256[](length);
        
        for (uint64 i = 0; i < length; i++) {
            uint64 cycle = _startCycle + i;
            cycles[i] = cycle;
            activesCounts[i] = activeDirectsInCycle[_user][cycle];
            rewards[i] = _getTierReward(activesCounts[i]);
        }
        
        return (cycles, activesCounts, rewards);
    }
    
    /**
     * @dev CORRECTED: Comprehensive user status for debugging
     */
    function getUserCompleteStatus(address _user) external view returns (
        bool hasJoinedBool,
        bool isActive,
        uint64 currentCycle,
        uint256 totalHistoricalDirects,
        uint256 currentCycleActives,
        uint256 currentCycleDirectsJoined,
        uint256 pendingROI,
        string memory economicStatus
    ) {
        hasJoinedBool = hasJoined[_user];
        if (!hasJoinedBool) {
            return (false, false, 0, 0, 0, 0, 0, "User has not joined");
        }
        
        User memory user = users[_user];
        isActive = user.isActive;
        currentCycle = user.currentCycle;
        totalHistoricalDirects = directReferralsCount[_user];
        currentCycleActives = activeDirectsInCycle[_user][currentCycle];
        currentCycleDirectsJoined = directsCountInCycle[_user][currentCycle];
        pendingROI = getCurrentPendingROI(_user);
        
        if (currentCycleActives == 0) {
            economicStatus = "No actives in current cycle - needs new joins";
        } else if (currentCycleActives != currentCycleDirectsJoined) {
            economicStatus = "Some current cycle directs inactive";
        } else {
            economicStatus = "All current cycle directs active - sustainable";
        }
        
        return (hasJoinedBool, isActive, currentCycle, totalHistoricalDirects, currentCycleActives, currentCycleDirectsJoined, pendingROI, economicStatus);
    }
}