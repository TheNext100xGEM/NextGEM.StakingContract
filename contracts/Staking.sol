// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface ISubscription {
    function checkManyRoles(address account, bytes32[] memory rolesToCheck) external view returns (bool);
    function listRoles() external view returns (bytes32[] memory);
}

contract StakingContract is AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMath for uint256;

    bytes32 public constant STAKE_MANAGER_ROLE = keccak256("STAKE_MANAGER_ROLE");
    IERC20Upgradeable public stakingToken;
    ISubscription public subscriptionContract;
    bytes32[] public roles;

    struct StakingEvent {
        uint256 startBlock;
        uint256 endBlock;
        uint256 totalGEMAI; // Total reward tokens for the event
        uint256 totalStaked;
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
    event Unstaked(uint256 indexed eventId, address indexed staker, uint256 amount);
    event Claimed(uint256 indexed eventId, address indexed staker, uint256 stakedAmount, uint256 rewardAmount);
    event RolesUpdated(bytes32[] newRoles);

    function initialize(address subscriptionAddress, IERC20Upgradeable _stakingToken) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        subscriptionContract = ISubscription(subscriptionAddress);
        stakingToken = _stakingToken;
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
        require(amountToLoad > 0, "StakingContract: Amount to load must be greater than zero");
        require(maxPerWallet > 0, "StakingContract: Max per wallet must be greater than zero");

        stakingToken.safeTransferFrom(msg.sender, address(this), amountToLoad);

        currentEventId++;
        stakingEvents[currentEventId] = StakingEvent(startBlock, endBlock, totalGEMAI, 0, true, requiresRoleCheck, maxPerWallet);
        emit StakingEventCreated(currentEventId, startBlock, endBlock, totalGEMAI, requiresRoleCheck, maxPerWallet);
    }

    /**
     * @dev Allows a user to stake tokens in an active staking event.
     * @param eventId The ID of the staking event.
     * @param amount The amount of tokens to stake.
     */
    function stake(uint256 eventId, uint256 amount) external nonReentrant {
        StakingEvent storage stakingEvent = stakingEvents[eventId];
        require(stakingEvent.isActive, "StakingContract: Event not active");
        require(block.number >= stakingEvent.startBlock && block.number <= stakingEvent.endBlock, "StakingContract: Not within staking period");
        require(amount > 0, "StakingContract: Amount must be greater than zero");

        if (stakingEvent.requiresRoleCheck) {
            require(subscriptionContract.checkManyRoles(msg.sender, roles), "StakingContract: User does not have a valid subscription");
        }

        Stake storage userStake = stakes[eventId][msg.sender];
        require(userStake.amount.add(amount) <= stakingEvent.maxPerWallet, "StakingContract: Exceeds max per wallet limit");

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        if (userStake.amount == 0) {
            eventStakers[eventId].push(msg.sender);
        }

        userStake.amount = userStake.amount.add(amount);
        userStake.stakeBlockNumber = block.number;

        uint256 stakeUnits = amount.mul(stakingEvent.endBlock.sub(block.number));
        userStake.units = userStake.units.add(stakeUnits);

        stakingEvent.totalStaked = stakingEvent.totalStaked.add(amount);
        emit Staked(eventId, msg.sender, amount, block.number, stakeUnits);
    }

    /**
     * @dev Allows a user to claim their staked tokens and rewards after the staking event has ended.
     * @param eventId The ID of the staking event.
     */
    function claim(uint256 eventId) external nonReentrant {
        require(block.number > stakingEvents[eventId].endBlock, "StakingContract: Staking event not yet ended");

        Stake storage userStake = stakes[eventId][msg.sender];
        uint256 stakedAmount = userStake.amount;
        require(stakedAmount > 0, "StakingContract: No staking tokens to unstake");

        uint256 rewardAmount = calculateReward(eventId, msg.sender);

        userStake.amount = 0;
        userStake.units = 0;

        uint256 totalAmount = stakedAmount.add(rewardAmount);
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

        uint256 totalUnits = 0;
        for (uint i = 0; i < eventStakers[eventId].length; i++) {
            totalUnits = totalUnits.add(stakes[eventId][eventStakers[eventId][i]].units);
        }

        if (totalUnits == 0) return 0;

        uint256 userShare = userStake.units.mul(stakingEvent.totalGEMAI).div(totalUnits);
        return userShare;
    }

    /**
     * @dev Calculates the Annual Percentage Yield (APY) for a staking event.
     * @param eventId The ID of the staking event.
     * @return The calculated APY for the staking event.
     */
    function calculateAPY(uint256 eventId) public view returns (uint256) {
        StakingEvent storage stakingEvent = stakingEvents[eventId];
        uint256 day = (stakingEvent.endBlock.sub(stakingEvent.startBlock)).div(6500);  
        if (day == 0) return 99999; // Handle case with zero days
        if (stakingEvent.totalStaked == 0) return 99999; // High APY for no staking

        return stakingEvent.totalGEMAI.mul(365).mul(100).div(stakingEvent.totalStaked.mul(day));
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
        if (block.number >= stakingEvents[eventId].endBlock) {
            return 0;
        } else {
            return stakingEvents[eventId].endBlock.sub(block.number);
        }
    }

    /**
     * @dev Returns the remaining time in seconds until the staking event ends.
     * Assumes an average block time of 13 seconds.
     * @param eventId The ID of the staking event.
     * @return The number of remaining seconds.
     */
    function getRemainingTime(uint256 eventId) public view returns (uint256) {
        uint256 remainingBlocks = getRemainingBlocks(eventId);
        return remainingBlocks.mul(13); // Assuming an average block time of 13 seconds
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
}