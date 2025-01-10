// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Importing the UserToken contract and IERC20 interface from OpenZeppelin
import "./Token.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Main contract inheriting from the UserToken contract
contract StakingDapp is UserToken {
    address public contractOwner; // Owner of the contract
    IERC20 public stakingToken; // The token used in the contract

    // Struct to define the properties of each reward tier
    struct RewardTier {
        uint256 annualRewardRate; // The reward rate for the tier (in basis points)
        uint256 lockDuration;   // Lock duration for the tier (in seconds)
    }

    // Struct to hold information about a user's stake
    struct StakeDetails {
        uint256 stakedAmount;     // The amount the user has staked
        uint256 accruedReward;     // The reward accumulated for this stake
        uint256 unlockTimestamp; // The time when the stake can be withdrawn
        bool hasBeenClaimed;       // Whether the stake has been claimed or not
    }

    // Mappings to store contract state:
    mapping(uint8 => RewardTier) public rewardTiers; // Mapping of tier id to its respective properties
    mapping(address => mapping(uint8 => StakeDetails)) public userStakes; // Mapping of user address to tier stakes
    mapping(address => bool) public approvedStakers; // Mapping of approved stakers
    mapping(address => uint256) public lastStakeTime; // The last time a user made a stake
    mapping(address => bool) public stakeClaimed; // Whether a user has claimed their stake

    uint256 public stakingCooldownPeriod = 1 days; // The cooldown period between stakes for a user

    // Events to log important contract actions
    event RewardTierUpdated(uint8 indexed tierId, uint256 rewardRate, uint256 lockDuration);
    event TokensStaked(address indexed user, uint256 amount, uint8 tierId, uint256 reward, uint256 unlockTimestamp);
    event StakeClaimed(address indexed user, uint256 amount);
    event StakerApprovalUpdated(address indexed user, bool status);

    // Custom errors to handle require statement failures
    error OnlyOwnerAllowed();
    error NotApprovedStaker();
    error NoActiveStake(uint8 tierId);
    error CooldownPeriodActive();
    error StakeAlreadyClaimed();
    error InvalidRewardTier(uint8 tierId);
    error ZeroStakeAmount();
    error StakeStillLocked(uint256 unlockTimestamp);

    // Modifier to allow only the contract owner to execute a function
    modifier onlyContractOwner() {
        if (msg.sender != contractOwner) revert OnlyOwnerAllowed();
        _;
    }

    // Modifier to allow only approved stakers to execute a function
    modifier onlyApprovedStakers() {
        if (!approvedStakers[msg.sender]) revert NotApprovedStaker();
        _;
    }

    // Modifier to ensure the user has an active stake for the specified tier
    modifier hasActiveStake(uint8 _tierId) {
        if (userStakes[msg.sender][_tierId].stakedAmount == 0) revert NoActiveStake(_tierId);
        _;
    }

    // Modifier to ensure the staking cooldown period has passed before allowing another stake
    modifier cooldownPeriodPassed() {
        if (block.timestamp < lastStakeTime[msg.sender] + stakingCooldownPeriod) revert CooldownPeriodActive();
        _;
    }

    // Modifier to ensure that the user has not already claimed their stake for the tier
    modifier canClaimReward(uint8 _tierId) {
        if (stakeClaimed[msg.sender]) revert StakeAlreadyClaimed();
        _;
    }

    // Constructor to initialize the contract with the token address
    constructor(address _tokenAddress) {
        contractOwner = msg.sender; // Set the owner of the contract to the deployer
        stakingToken = IERC20(_tokenAddress); // Initialize the token contract
        // Initialize default reward tiers with reward rates and lock durations
        rewardTiers[1] = RewardTier(500, 7 days);   // Tier 1: 5% reward, 7-day lock
        rewardTiers[2] = RewardTier(1000, 14 days); // Tier 2: 10% reward, 14-day lock
        rewardTiers[3] = RewardTier(1500, 30 days); // Tier 3: 15% reward, 30-day lock
    }

    // Function to update the reward rate and lock duration for a specific reward tier
    function modifyRewardTier(uint8 _tierId, uint256 _rewardRate, uint256 _lockDuration) external onlyContractOwner {
        if (_tierId == 0) revert InvalidRewardTier(_tierId); // Reject tier 0 as invalid
        rewardTiers[_tierId] = RewardTier(_rewardRate, _lockDuration); // Update tier properties
        emit RewardTierUpdated(_tierId, _rewardRate, _lockDuration); // Emit an event for the update
    }

    // Function to approve or remove a staker's approval
    function updateStakerApproval(address _user, bool _status) external onlyContractOwner {
        approvedStakers[_user] = _status; // Update the approval status for the staker
        emit StakerApprovalUpdated(_user, _status); // Emit an event for the change
    }

    // Function to stake tokens into the contract and start earning rewards
    function stakeTokens(uint8 _tierId, uint256 _amount) external payable onlyApprovedStakers cooldownPeriodPassed {
        if (_amount == 0) revert ZeroStakeAmount(); // Reject zero stake amounts
        if (rewardTiers[_tierId].lockDuration == 0) revert InvalidRewardTier(_tierId); // Reject invalid tiers

        StakeDetails storage currentStake = userStakes[msg.sender][_tierId]; // Get the user's stake details for the specified tier
        // Calculate the reward based on the tier's reward rate
        uint256 reward = (_amount * rewardTiers[_tierId].annualRewardRate) / 10000;
        stakingToken.transferFrom(msg.sender, address(this), _amount); // Transfer tokens from the user to the contract

        // Update the user's stake information
        userStakes[msg.sender][_tierId] = StakeDetails({
            stakedAmount: currentStake.stakedAmount + _amount,
            accruedReward: currentStake.accruedReward + reward,
            unlockTimestamp: currentStake.unlockTimestamp + block.timestamp + rewardTiers[_tierId].lockDuration,
            hasBeenClaimed: false
        });

        lastStakeTime[msg.sender] = block.timestamp; // Update the last stake time

        emit TokensStaked(msg.sender, _amount, _tierId, reward, block.timestamp + rewardTiers[_tierId].lockDuration); // Emit a stake event
    }

    // Function to claim the staked amount and its reward after the lock period
    function claimStake(uint8 _tierId) external onlyApprovedStakers hasActiveStake(_tierId) canClaimReward(_tierId) {
        StakeDetails storage userStake = userStakes[msg.sender][_tierId]; // Get the user's stake for the tier
        if (block.timestamp <= userStake.unlockTimestamp) revert StakeStillLocked(userStake.unlockTimestamp); // Reject if the stake is still locked

        uint256 totalAmount = userStake.stakedAmount + userStake.accruedReward; // Calculate the total amount to be claimed
        stakeClaimed[msg.sender] = true; // Mark the user as having claimed their stake

        // Reset the user's stake information
        userStakes[msg.sender][_tierId] = StakeDetails({
            stakedAmount: 0,
            accruedReward: 0,
            unlockTimestamp: 0,
            hasBeenClaimed: true
        });

        stakingToken.transfer(msg.sender, totalAmount); // Transfer the total amount (principal + reward) to the user
        emit StakeClaimed(msg.sender, totalAmount); // Emit a claim event
    }

    // Function to get the details of a user's stake for a specific tier
    function getStakeDetails(address _user, uint8 _tierId) external view returns (uint256, uint256, uint256, bool) {
        StakeDetails memory userStake = userStakes[_user][_tierId]; // Get the stake details
        return (userStake.stakedAmount, userStake.accruedReward, userStake.unlockTimestamp, userStake.hasBeenClaimed); // Return the details
    }

    // Fallback function to accept Ether sent to the contract
    receive() external payable {}
}
