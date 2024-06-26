// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ISubscription {
    function checkManyRoles(address account, bytes32[] memory rolesToCheck) external view returns (bool);
}

contract StakingContract is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant STAKE_MANAGER_ROLE = keccak256("STAKE_MANAGER_ROLE");
    IERC20 public stakingToken;
    ISubscription public subscriptionContract;
    bytes32[] public roles; 

    uint256 public averageBlockTime; // Configurable average block time in seconds

    struct StakingEvent {
        uint256 startBlock;
        uint256 endBlock;
        uint256 totalGEMAI; // Total reward tokens for the event
        uint256 totalStaked;
        uint256 totalUnits;
        bool isActive;
        bool requiresRoleCheck;
        uint256 maxPerWallet; // Maximum staking amount per wallet
    }

    struct Stake {
        uint256 amount;
        uint256 units;
        uint256 stakeBlockNumber;
    }

    mapping(uint256 => StakingEvent) public stakingEvents;
    mapping(uint256 => mapping(address => Stake)) public stakes;
    mapping(uint256 => address[]) public eventStakers;
    uint256 public currentEventId;

    // Event declarations
    event StakingEventCreated(uint256 indexed eventId, uint256 startBlock, uint256 endBlock, uint256 totalGEMAI, bool requiresRoleCheck, uint256 maxPerWallet);
    event Staked(uint256 indexed eventId, address indexed staker, uint256 amount, uint256 blockNumber, uint256 units);
    event Claimed(uint256 indexed eventId, address indexed staker, uint256 stakedAmount, uint256 rewardAmount);
    event RolesUpdated(bytes32[] newRoles);
    event AverageBlockTimeUpdated(uint256 newAverageBlockTime);
    event EmergencyExit(address indexed admin, address indexed to, uint256 amount);

    constructor(address subscriptionAddress, IERC20 _stakingToken, uint256 _averageBlockTime) {
        subscriptionContract = ISubscription(subscriptionAddress);
        stakingToken = _stakingToken;
        averageBlockTime = _averageBlockTime;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STAKE_MANAGER_ROLE, msg.sender);
    }

    /**
     * @dev Sets or updates the roles array.
     * @param newRoles The new array of roles.
     */
    function setRoles(bytes32[] calldata newRoles) external onlyRole(DEFAULT_ADMIN_ROLE) {
        roles = newRoles;
        emit RolesUpdated(newRoles);
    }

    /**
     * @dev Sets or updates the average block time.
     * @param _averageBlockTime The new average block time in seconds.
     */
    function setAverageBlockTime(uint256 _averageBlockTime) external onlyRole(DEFAULT_ADMIN_ROLE) {
        averageBlockTime = _averageBlockTime;
        emit AverageBlockTimeUpdated(_averageBlockTime);
    }

    /**
     * @dev Creates a new staking event and optionally loads tokens into the contract.
     * @param startBlock The block number when the staking event starts.
     * @param endBlock The block number when the staking event ends.
     * @param totalGEMAI The total amount of reward tokens to be distributed in the staking event.
     * @param amountToLoad The amount of staking tokens to be loaded into the contract.
     * @param requiresRoleCheck Boolean flag indicating if role check is required for this event.
     * @param maxPerWallet The maximum amount of tokens that a single wallet can stake.
     */
    function createStakingEvent(uint256 startBlock, uint256 endBlock, uint256 totalGEMAI, uint256 amountToLoad, bool requiresRoleCheck, uint256 maxPerWallet) external onlyRole(STAKE_MANAGER_ROLE) {
        require(endBlock > startBlock, "StakingContract: End block must be greater than start block");
        require(totalGEMAI > 0, "StakingContract: Total reward tokens must be greater than zero");
        require(amountToLoad >= totalGEMAI, "StakingContract: Amount to load must be at least equal to total reward tokens");
        require(maxPerWallet > 0, "StakingContract: Max per wallet must be greater than zero");

        stakingToken.safeTransferFrom(msg.sender, address(this), amountToLoad);

        uint256 eventId = ++currentEventId;
        stakingEvents[eventId] = StakingEvent(startBlock, endBlock, totalGEMAI, 0, 0, true, requiresRoleCheck, maxPerWallet);
        emit StakingEventCreated(eventId, startBlock, endBlock, totalGEMAI, requiresRoleCheck, maxPerWallet);
    }

    /**
     * @dev Allows a user to stake tokens in an active staking event.
     * @param eventId The ID of the staking event.
     * @param amount The amount of tokens to stake.
     */
    function stake(uint256 eventId, uint256 amount) external nonReentrant {
        require(eventId <= currentEventId, "StakingContract: Staking event does not exist");
        StakingEvent storage stakingEvent = stakingEvents[eventId];
        require(stakingEvent.isActive, "StakingContract: Event not active");
        require(block.number >= stakingEvent.startBlock && block.number <= stakingEvent.endBlock, "StakingContract: Not within staking period");
        require(amount > 0, "StakingContract: Amount must be greater than zero");

        if (stakingEvent.requiresRoleCheck) {
            require(subscriptionContract.checkManyRoles(msg.sender, roles), "StakingContract: User does not have a valid subscription");
        }

        Stake storage userStake = stakes[eventId][msg.sender];
        uint256 newAmount = userStake.amount + amount;
        require(newAmount <= stakingEvent.maxPerWallet, "StakingContract: Exceeds max per wallet limit");

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        if (userStake.amount == 0) {
            eventStakers[eventId].push(msg.sender);
        }

        uint256 stakeUnits = amount * (stakingEvent.endBlock - block.number);
        userStake.amount = newAmount;
        userStake.units += stakeUnits;
        userStake.stakeBlockNumber = block.number;

        stakingEvent.totalStaked += amount;
        stakingEvent.totalUnits += stakeUnits;

        emit Staked(eventId, msg.sender, amount, block.number, stakeUnits);
    }

    /**
     * @dev Allows a user to claim their staked tokens and rewards after the staking event has ended.
     * @param eventId The ID of the staking event.
     */
    function claim(uint256 eventId) external nonReentrant {
        require(eventId <= currentEventId, "StakingContract: Staking event does not exist");
        updateStakingEventStatus(eventId);
        require(!stakingEvents[eventId].isActive, "StakingContract: Staking event not yet ended");

        Stake storage userStake = stakes[eventId][msg.sender];
        uint256 stakedAmount = userStake.amount;
        require(stakedAmount > 0, "StakingContract: No staking tokens to unstake");

        uint256 rewardAmount = calculateReward(eventId, msg.sender);

        userStake.amount = 0;
        userStake.units = 0;

        uint256 totalAmount = stakedAmount + rewardAmount;
        stakingToken.safeTransfer(msg.sender, totalAmount);

        emit Claimed(eventId, msg.sender, stakedAmount, rewardAmount);
    }

    /**
     * @dev Calculates the reward for a user based on their stake in a staking event.
     * @param eventId The ID of the staking event.
     * @param user The address of the user.
     * @return The calculated reward for the user.
     */
    function calculateReward(uint256 eventId, address user) public view returns (uint256) {
        StakingEvent storage stakingEvent = stakingEvents[eventId];
        Stake storage userStake = stakes[eventId][user];

        if (stakingEvent.totalUnits == 0) return 0;

        uint256 userShare = userStake.units * stakingEvent.totalGEMAI / stakingEvent.totalUnits;
        return userShare;
    }

    /**
     * @dev Calculates the Personal APY for a user in a staking event.
     * @param eventId The ID of the staking event.
     * @param user The address of the user.
     * @return The calculated Personal APY for the user.
     */
    function calculatePersonalAPY(uint256 eventId, address user) public view returns (uint256) {
        require(eventId <= currentEventId, "StakingContract: Staking event does not exist");
        StakingEvent storage stakingEvent = stakingEvents[eventId];
        Stake storage userStake = stakes[eventId][user];
        uint256 day = (stakingEvent.endBlock - stakingEvent.startBlock) / 6500;
        if (day == 0) day = 1; // Handle case with zero days

        if (userStake.amount == 0) return 99999; // High APY for no staking

        uint256 personalRewardAmount = calculateReward(eventId, user);
        return personalRewardAmount * 365 * 100 / (userStake.amount * day);
    }

    /**
     * @dev Calculates the Global APY for a staking event.
     * @param eventId The ID of the staking event.
     * @return The calculated Global APY for the staking event.
     */
    function calculateGlobalAPY(uint256 eventId) public view returns (uint256) {
        require(eventId <= currentEventId, "StakingContract: Staking event does not exist");
        StakingEvent storage stakingEvent = stakingEvents[eventId];
        uint256 day = (stakingEvent.endBlock - stakingEvent.startBlock) / 6500;
        if (day == 0) day = 1; // Handle case with zero days

        if (stakingEvent.totalStaked == 0) return 99999; // High APY for no staking

        return stakingEvent.totalGEMAI * 365 * 100 / (stakingEvent.totalStaked * day);
    }

    /**
     * @dev Returns the list of stakers for a specific staking event.
     * @param eventId The ID of the staking event.
     * @return An array of addresses of the stakers.
     */
    function getEventStakers(uint256 eventId) external view returns (address[] memory) {
        return eventStakers[eventId];
    }

    /**
     * @dev Returns the total number of stakers for a specific staking event.
     * @param eventId The ID of the staking event.
     * @return The total number of stakers.
     */
    function getTotalStakers(uint256 eventId) external view returns (uint256) {
        return eventStakers[eventId].length;
    }

    /**
     * @dev Returns the total amount of tokens staked in a specific staking event.
     * @param eventId The ID of the staking event.
     * @return The total amount of staked tokens.
     */
    function getTotalStaked(uint256 eventId) external view returns (uint256) {
        return stakingEvents[eventId].totalStaked;
    }

    /**
     * @dev Returns the remaining blocks until the staking event ends.
     * @param eventId The ID of the staking event.
     * @return The number of remaining blocks.
     */
    function getRemainingBlocks(uint256 eventId) public view returns (uint256) {
        return block.number >= stakingEvents[eventId].endBlock ? 0 : stakingEvents[eventId].endBlock - block.number;
    }

    /**
     * @dev Returns the remaining time in seconds until the staking event ends.
     * @param eventId The ID of the staking event.
     * @return The number of remaining seconds.
     */
    function getRemainingTime(uint256 eventId) public view returns (uint256) {
        return getRemainingBlocks(eventId) * averageBlockTime;
    }

    /**
     * @dev Grants the stake manager role to an address.
     * @param _manager The address to be granted the stake manager role.
     */
    function grantStakeManager(address _manager) public onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(STAKE_MANAGER_ROLE, _manager);
    }

    /**
     * @dev Revokes the stake manager role from an address.
     * @param _manager The address to have the stake manager role revoked.
     */
    function revokeStakeManager(address _manager) public onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(STAKE_MANAGER_ROLE, _manager);
    }

    /**
     * @dev Allows the admin to withdraw all tokens from the contract in case of an emergency.
     * @param to The address to send the tokens to.
     */
    function emergencyExit(address to) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        uint256 contractBalance = stakingToken.balanceOf(address(this));
        stakingToken.safeTransfer(to, contractBalance);
        emit EmergencyExit(msg.sender, to, contractBalance);
    }

    /**
     * @dev Internal function to update the isActive status of a staking event.
     * @param eventId The ID of the staking event.
     */
    function updateStakingEventStatus(uint256 eventId) internal {
        if (block.number > stakingEvents[eventId].endBlock) {
            stakingEvents[eventId].isActive = false;
        }
    }
}
