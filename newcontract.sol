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

    // MAINNET USDT TOKEN ADDRESS - BSC MAINNET
    address private constant MAINNET_USDT_ADDRESS = 0x55d398326f99059fF775485246999027B3197955;
    
    IERC20 public immutable USDT;
    address public admin;
    
    // Emergency withdrawal timelock
    uint256 public emergencyWithdrawTime;
    uint256 private constant EMERGENCY_TIMELOCK = 7 days;
    bool public emergencyWithdrawInitiated;
    
    uint256 private constant JOIN_AMOUNT = 10 * 10**18; // 10 USDT
    uint256 private constant REJOIN_AMOUNT = 10 * 10**18; // 10 USDT
    uint256 private constant ADMIN_FEE = 2 * 10**18;   // 2 USDT (for both join and rejoin)
    uint256 private constant MIN_CLAIM = 10 * 10**18;  // 10 USDT minimum claim
    uint256 private constant CYCLE_DURATION = 10 hours; // 10 hours ROI cycle
    uint256 private constant ROI_INTERVAL = 1 hours;    // 1 hour ROI intervals
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
    
    // Optimized referral tracking with mappings
    mapping(address => mapping(uint256 => address)) public directReferrals; // referrer => index => referral
    mapping(address => uint256) public directReferralsCount; // referrer => count
    mapping(address => mapping(address => bool)) public isDirectReferral;
    mapping(address => mapping(address => uint256)) public referralIndex;
    
    // Contract metrics
    uint256 public totalUsersJoined;
    uint256 public totalRewardsPaid;
    
    // Events
    event UserJoined(address indexed user, address indexed referrer, uint256 amount, uint256 timestamp);
    event UserRejoined(address indexed user, uint256 amount, uint256 timestamp);
    event RewardsClaimed(address indexed user, uint256 amount);
    event CycleCompleted(address indexed user, uint256 timestamp);
    event EmergencyWithdrawInitiated(uint256 executeTime);
    event EmergencyWithdrawCancelled();
    event EmergencyWithdrawExecuted(uint256 amount);
    event ActiveDirectsUpdated(address indexed user, uint256 newCount);
    
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }
    
    constructor() {
        USDT = IERC20(MAINNET_USDT_ADDRESS);
        admin = 0x3Da7310861fbBdf5105ea6963A2C39d0Cb34a4Ff;
    }
    
    // ===================================================================
    // 🚀 MAIN USER FUNCTIONS (Only 4 write functions as requested)
    // ===================================================================
    
    /**
     * @dev JOIN FUNCTION - Users can join with optional referrer
     * @param _referrer Address of referrer (can be zero address for no referrer)
     */
    function joinPlan(address _referrer) external nonReentrant {
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
     * @dev REJOIN FUNCTION - Users can rejoin after cycle completion
     */
    function rejoinPlan() external nonReentrant {
        require(hasJoined[msg.sender], "Never joined before");
        
        User storage user = users[msg.sender];
        require(!user.isActive, "Still active");
        
        // Transfer payment
        USDT.safeTransferFrom(msg.sender, address(this), REJOIN_AMOUNT);
        
        uint64 currentTime = uint64(block.timestamp);
        address referrer = user.referrer;
        
        // Reset user for new cycle
        user.isActive = true;
        user.joinTime = currentTime;
        user.cycleEndTime = currentTime + uint64(CYCLE_DURATION);
        user.lastRewardUpdate = currentTime;
        user.lastActiveDirectsUpdate = currentTime;
        user.hasMinimumDirect = false;
        user.activeDirects = 0;
        user.pendingRewards = 0;
        
        // AUTOMATIC: Update referrer's active count
        if (referrer != address(0) && hasJoined[referrer] && users[referrer].isActive) {
            _updateReferrerActiveCountAuto(referrer);
        }
        
        // Pay admin fee
        USDT.safeTransfer(admin, ADMIN_FEE);
        
        emit UserRejoined(msg.sender, REJOIN_AMOUNT, currentTime);
    }
    
    /**
     * @dev CLAIM ROI FUNCTION - Users can claim accumulated rewards
     */
    function claimRewards() external nonReentrant {
        User storage user = users[msg.sender];
        require(user.isActive, "User not active");
        
        // AUTOMATIC: Calculate and update rewards based on time
        _updateStoredRewardsAuto(msg.sender);
        
        uint256 totalRewards = getCurrentPendingROI(msg.sender);
        require(totalRewards >= MIN_CLAIM, "Below minimum claim");
        
        uint256 contractBalance = USDT.balanceOf(address(this));
        require(contractBalance >= totalRewards, "Insufficient contract balance");
        
        bool cycleCompleted = block.timestamp >= user.cycleEndTime;
        
        // Update state before transfer
        user.pendingRewards = 0;
        user.lastRewardUpdate = uint64(block.timestamp);
        
        unchecked {
            totalRewardsPaid += totalRewards;
        }
        
        // AUTOMATIC: Complete cycle if 10 hours elapsed
        if (cycleCompleted) {
            user.isActive = false;
            user.activeDirects = 0;
            user.hasMinimumDirect = false;
            
            // AUTOMATIC: Update referrer's count
            address referrer = user.referrer;
            if (referrer != address(0) && hasJoined[referrer] && users[referrer].isActive) {
                _updateReferrerActiveCountAuto(referrer);
            }
            
            emit CycleCompleted(msg.sender, block.timestamp);
        }
        
        // Transfer rewards
        USDT.safeTransfer(msg.sender, totalRewards);
        emit RewardsClaimed(msg.sender, totalRewards);
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
    
    /**
     * @dev Cancel emergency withdrawal process (resets timelock)
     */
    function cancelEmergencyWithdraw() external onlyAdmin {
        require(emergencyWithdrawInitiated, "No emergency withdraw to cancel");
        emergencyWithdrawInitiated = false;
        emergencyWithdrawTime = 0;
        emit EmergencyWithdrawCancelled();
    }
    
    /**
     * @dev Check emergency withdrawal status
     */
    function getEmergencyWithdrawStatus() external view returns (
        bool initiated,
        uint256 executeTime,
        uint256 timeRemaining,
        bool canExecute
    ) {
        initiated = emergencyWithdrawInitiated;
        executeTime = emergencyWithdrawTime;
        
        if (initiated && block.timestamp < emergencyWithdrawTime) {
            timeRemaining = emergencyWithdrawTime - block.timestamp;
            canExecute = false;
        } else if (initiated) {
            timeRemaining = 0;
            canExecute = true;
        } else {
            timeRemaining = 0;
            canExecute = false;
        }
        
        return (initiated, executeTime, timeRemaining, canExecute);
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
                referrer.lastRewardUpdate = uint64(block.timestamp);
                referrer.cycleEndTime = uint64(block.timestamp + CYCLE_DURATION);
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
        if (directCount >= 100) return 50 * 10**18; // 50 USDT/hour (Diamond)
        if (directCount >= 50) return 10 * 10**18;  // 10 USDT/hour (Platinum)
        if (directCount >= 10) return 5 * 10**18;   // 5 USDT/hour (Gold)
        if (directCount >= 5) return 3 * 10**18;    // 3 USDT/hour (Silver)
        if (directCount >= 1) return 2 * 10**18;    // 2 USDT/hour (Bronze)
        return 0;
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