// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title PlatformToken
 * @author Agwara Nnaemeka
 * @dev ERC20 token with staking, burning, gambling platform features, and one-time bonus system
 * @notice This token is designed specifically for the decentralized gambling platform
 */
contract PlatformToken is ERC20, Ownable, ReentrancyGuard, Pausable {
    // =============================================================
    //                           CONSTANTS
    // =============================================================

    /// @notice Minimum staking amount (prevents dust attacks)
    uint256 public constant MIN_STAKE_AMOUNT = 10 * 10 ** 18; // 10 tokens

    /// @notice Minimum staking duration before unstaking (prevents gaming)
    uint256 public constant MIN_STAKE_DURATION = 24 hours;

    /// @notice Maximum tokens that can be staked by a single user (prevents whale dominance)
    uint256 public constant MAX_STAKE_PER_USER = 100_000 * 10 ** 18; // 100k tokens

    /// @notice Burn rate in basis points (100 = 1%)
    uint256 public constant BURN_RATE = 500; // 5%

    /// @notice Default gift amount for new users (transferred to wallet)
    uint256 public constant DEFAULT_GIFT_AMOUNT = 200 * 10 ** 18; // 200 tokens

    /// @notice Default stake amount for new users (auto-staked)
    uint256 public constant DEFAULT_STAKE_AMOUNT = 50 * 10 ** 18; // 50 tokens

    // =============================================================
    //                            STORAGE
    // =============================================================

    /// @notice Amount of tokens staked by each user
    mapping(address => uint256) public stakedBalance;

    /// @notice Timestamp when user last staked tokens
    mapping(address => uint256) public stakingTimestamp;

    /// @notice Total amount of tokens currently staked across all users
    uint256 public totalStaked;

    /// @notice Total amount of tokens burned
    uint256 public totalBurned;

    /// @notice Addresses authorized to burn tokens (e.g., gaming contracts)
    mapping(address => bool) public authorizedBurners;

    /// @notice Addresses authorized to transfer staked tokens (e.g., reward distributor)
    mapping(address => bool) public authorizedTransferors;

    /// @notice Emergency withdrawal enabled flag
    bool public emergencyWithdrawalEnabled;

    // =============================================================
    //                        BONUS SYSTEM STORAGE
    // =============================================================

    /// @notice Tracks whether a user has claimed their one-time bonus
    mapping(address => bool) public hasBonusClaimed;

    /// @notice Total number of bonuses claimed
    uint256 public totalBonusesClaimed;

    /// @notice Total amount of bonus tokens distributed (gifts + stakes)
    uint256 public totalBonusDistributed;

    /// @notice Whether the bonus system is currently active
    bool public bonusSystemActive = true;

    /// @notice Current gift amount (can be modified by owner)
    uint256 public currentGiftAmount = DEFAULT_GIFT_AMOUNT;

    /// @notice Current auto-stake amount (can be modified by owner)
    uint256 public currentStakeAmount = DEFAULT_STAKE_AMOUNT;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event TokensStaked(address indexed user, uint256 amount, uint256 totalStaked);
    event TokensUnstaked(address indexed user, uint256 amount, uint256 totalStaked);
    event TokensBurned(address indexed burner, uint256 amount, uint256 totalBurned);
    event AuthorizedBurnerUpdated(address indexed burner, bool authorized);
    event AuthorizedTransferorUpdated(address indexed transferor, bool authorized);
    event EmergencyWithdrawalToggled(bool enabled);
    event BonusClaimed(address indexed user, uint256 giftAmount, uint256 stakeAmount);
    event BonusSystemToggled(bool active);
    event BonusAmountsUpdated(uint256 newGiftAmount, uint256 newStakeAmount);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error InsufficientBalance();
    error InsufficientStakedBalance();
    error BelowMinimumStakeAmount();
    error ExceedsMaximumStakeAmount();
    error StakingDurationNotMet();
    error UnauthorizedBurner();
    error UnauthorizedTransferor();
    error EmergencyWithdrawalDisabled();
    error ZeroAmount();
    error BonusAlreadyClaimed();
    error BonusSystemInactive();
    error InsufficientContractBalance();

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(uint256 initialSupply) ERC20("PlatformToken", "PTK") Ownable(msg.sender) {
        _mint(msg.sender, initialSupply);

        // Owner is automatically authorized for burning and transfers
        authorizedBurners[msg.sender] = true;
        authorizedTransferors[msg.sender] = true;

        emit AuthorizedBurnerUpdated(msg.sender, true);
        emit AuthorizedTransferorUpdated(msg.sender, true);
    }

    // =============================================================
    //                      BONUS SYSTEM FUNCTIONS
    // =============================================================

    /**
     * @notice Claim one-time bonus: gift tokens to wallet and automatically stake some
     * @dev Users receive gift tokens in their wallet + auto-staked tokens. Can only claim once.
     */
    function claimBonusAndStake() external nonReentrant whenNotPaused {
        if (hasBonusClaimed[msg.sender]) revert BonusAlreadyClaimed();
        if (!bonusSystemActive) revert BonusSystemInactive();

        uint256 totalRequired = currentGiftAmount + currentStakeAmount;
        if (balanceOf(address(this)) < totalRequired) revert InsufficientContractBalance();

        // Check if staking the bonus amount would exceed maximum stake limit
        if (stakedBalance[msg.sender] + currentStakeAmount > MAX_STAKE_PER_USER) {
            revert ExceedsMaximumStakeAmount();
        }

        // Mark bonus as claimed
        hasBonusClaimed[msg.sender] = true;

        // Transfer gift tokens to user's wallet
        _transfer(address(this), msg.sender, currentGiftAmount);

        // Auto-stake the stake amount (tokens stay in contract, update mappings)
        stakedBalance[msg.sender] += currentStakeAmount;
        stakingTimestamp[msg.sender] = block.timestamp;
        totalStaked += currentStakeAmount;

        // Update bonus statistics
        totalBonusesClaimed += 1;
        totalBonusDistributed += totalRequired;

        emit BonusClaimed(msg.sender, currentGiftAmount, currentStakeAmount);
        emit TokensStaked(msg.sender, currentStakeAmount, stakedBalance[msg.sender]);
    }

    /**
     * @notice Check if user is eligible for bonus
     * @param user Address to check
     * @return eligible True if user hasn't claimed bonus and system is active
     */
    function isEligibleForBonus(address user) external view returns (bool eligible) {
        return !hasBonusClaimed[user] && bonusSystemActive;
    }

    /**
     * @notice Get bonus system statistics
     * @return active Whether bonus system is active
     * @return currentGift Current gift amount (transferred to wallet)
     * @return currentStake Current auto-stake amount
     * @return totalClaimed Total number of bonuses claimed
     * @return totalDistributed Total amount of bonus tokens distributed
     * @return contractBalance Current contract balance available for bonuses
     */
    function getBonusStats()
        external
        view
        returns (
            bool active,
            uint256 currentGift,
            uint256 currentStake,
            uint256 totalClaimed,
            uint256 totalDistributed,
            uint256 contractBalance
        )
    {
        active = bonusSystemActive;
        currentGift = currentGiftAmount;
        currentStake = currentStakeAmount;
        totalClaimed = totalBonusesClaimed;
        totalDistributed = totalBonusDistributed;
        contractBalance = balanceOf(address(this)) - totalStaked; // Available for bonuses
    }

    // =============================================================
    //                        STAKING FUNCTIONS
    // =============================================================

    /**
     * @notice Stake tokens to become eligible for gifts and bonuses
     * @param amount Amount of tokens to stake
     * @dev Staked tokens are locked and earn eligibility for platform rewards
     */
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (amount < MIN_STAKE_AMOUNT) revert BelowMinimumStakeAmount();
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance();
        if (stakedBalance[msg.sender] + amount > MAX_STAKE_PER_USER) {
            revert ExceedsMaximumStakeAmount();
        }

        // Transfer tokens from user to this contract
        _transfer(msg.sender, address(this), amount);

        // Update staking records
        stakedBalance[msg.sender] += amount;
        stakingTimestamp[msg.sender] = block.timestamp;
        totalStaked += amount;

        emit TokensStaked(msg.sender, amount, stakedBalance[msg.sender]);
    }

    /**
     * @notice Unstake tokens after minimum duration
     * @param amount Amount of tokens to unstake
     * @dev Tokens can only be unstaked after MIN_STAKE_DURATION
     */
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (stakedBalance[msg.sender] < amount) revert InsufficientStakedBalance();

        // Check minimum staking duration (unless emergency withdrawal is enabled)
        if (!emergencyWithdrawalEnabled && block.timestamp < stakingTimestamp[msg.sender] + MIN_STAKE_DURATION) {
            revert StakingDurationNotMet();
        }

        // Update staking records
        stakedBalance[msg.sender] -= amount;
        totalStaked -= amount;

        // Transfer tokens back to user
        _transfer(address(this), msg.sender, amount);

        emit TokensUnstaked(msg.sender, amount, stakedBalance[msg.sender]);
    }

    /**
     * @notice Emergency unstake all tokens (only when emergency withdrawal is enabled)
     * @dev Allows users to unstake immediately in emergency situations
     */
    function emergencyUnstake() external nonReentrant {
        if (!emergencyWithdrawalEnabled) revert EmergencyWithdrawalDisabled();

        uint256 amount = stakedBalance[msg.sender];
        if (amount == 0) revert InsufficientStakedBalance();

        // Update staking records
        stakedBalance[msg.sender] = 0;
        totalStaked -= amount;

        // Transfer tokens back to user
        _transfer(address(this), msg.sender, amount);

        emit TokensUnstaked(msg.sender, amount, 0);
    }

    // =============================================================
    //                        BURNING FUNCTIONS
    // =============================================================

    /**
     * @notice Burn tokens from caller's balance
     * @param amount Amount of tokens to burn
     * @dev Anyone can burn their own tokens
     */
    function burn(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance();

        _burn(msg.sender, amount);
        totalBurned += amount;

        emit TokensBurned(msg.sender, amount, totalBurned);
    }

    /**
     * @notice Burn tokens from a specific address (authorized burners only)
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     * @dev Used by gaming contracts for automatic burns
     */
    function burnFrom(address from, uint256 amount) external nonReentrant whenNotPaused {
        if (!authorizedBurners[msg.sender]) revert UnauthorizedBurner();
        if (amount == 0) revert ZeroAmount();
        if (balanceOf(from) < amount) revert InsufficientBalance();

        // Check allowance if not authorized transferor
        if (!authorizedTransferors[msg.sender]) {
            uint256 currentAllowance = allowance(from, msg.sender);
            if (currentAllowance < amount) revert InsufficientBalance();
            _approve(from, msg.sender, currentAllowance - amount);
        }

        _burn(from, amount);
        totalBurned += amount;

        emit TokensBurned(msg.sender, amount, totalBurned);
    }

    /**
     * @notice Burn tokens and mint new ones (deflationary mechanism)
     * @param burnAmount Amount to burn
     * @param mintTo Address to mint new tokens to
     * @param mintAmount Amount to mint
     * @dev Used for reward distribution with controlled deflation
     */
    function burnAndMint(uint256 burnAmount, address mintTo, uint256 mintAmount) external nonReentrant whenNotPaused {
        if (!authorizedBurners[msg.sender]) revert UnauthorizedBurner();

        if (burnAmount > 0) {
            if (balanceOf(address(this)) < burnAmount) revert InsufficientBalance();
            _burn(address(this), burnAmount);
            totalBurned += burnAmount;
            emit TokensBurned(msg.sender, burnAmount, totalBurned);
        }

        if (mintAmount > 0 && mintTo != address(0)) {
            _mint(mintTo, mintAmount);
        }
    }

    // =============================================================
    //                     AUTHORIZATION FUNCTIONS
    // =============================================================

    /**
     * @notice Set authorized burner status
     * @param burner Address to authorize/deauthorize
     * @param authorized True to authorize, false to deauthorize
     */
    function setAuthorizedBurner(address burner, bool authorized) external onlyOwner {
        authorizedBurners[burner] = authorized;
        emit AuthorizedBurnerUpdated(burner, authorized);
    }

    /**
     * @notice Set authorized transferor status
     * @param transferor Address to authorize/deauthorize
     * @param authorized True to authorize, false to deauthorize
     */
    function setAuthorizedTransferor(address transferor, bool authorized) external onlyOwner {
        authorizedTransferors[transferor] = authorized;
        emit AuthorizedTransferorUpdated(transferor, authorized);
    }

    /**
     * @notice Toggle emergency withdrawal mode
     * @param enabled True to enable emergency withdrawal, false to disable
     */
    function toggleEmergencyWithdrawal(bool enabled) external onlyOwner {
        emergencyWithdrawalEnabled = enabled;
        emit EmergencyWithdrawalToggled(enabled);
    }

    /**
     * @notice Toggle bonus system on/off
     * @param active True to activate, false to deactivate
     */
    function toggleBonusSystem(bool active) external onlyOwner {
        bonusSystemActive = active;
        emit BonusSystemToggled(active);
    }

    /**
     * @notice Update bonus amounts
     * @param newGiftAmount New gift amount to transfer to user wallet
     * @param newStakeAmount New amount to auto-stake for users
     * @dev Both amounts must meet minimum requirements and stake amount can't exceed max per user
     */
    function updateBonusAmounts(uint256 newGiftAmount, uint256 newStakeAmount) external onlyOwner {
        require(newGiftAmount > 0, "Gift amount must be positive");
        require(newStakeAmount >= MIN_STAKE_AMOUNT, "Stake amount too low");
        require(newStakeAmount <= MAX_STAKE_PER_USER, "Stake amount too high");

        currentGiftAmount = newGiftAmount;
        currentStakeAmount = newStakeAmount;
        emit BonusAmountsUpdated(newGiftAmount, newStakeAmount);
    }

    /**
     * @notice Deposit tokens to contract for bonus distribution
     * @param amount Amount of tokens to deposit
     * @dev Owner can deposit tokens to fund the bonus system
     */
    function depositForBonuses(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance();
        _transfer(msg.sender, address(this), amount);
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get user's staking information
     * @param user Address to check
     * @return staked Amount of tokens staked
     * @return timestamp When tokens were last staked
     * @return canUnstake Whether user can unstake now
     */
    function getStakingInfo(address user) external view returns (uint256 staked, uint256 timestamp, bool canUnstake) {
        staked = stakedBalance[user];
        timestamp = stakingTimestamp[user];
        canUnstake = emergencyWithdrawalEnabled || block.timestamp >= timestamp + MIN_STAKE_DURATION;
    }

    /**
     * @notice Get total supply statistics
     * @return circulating Current circulating supply
     * @return staked Total tokens staked
     * @return burned Total tokens burned
     */
    function getSupplyStats() external view returns (uint256 circulating, uint256 staked, uint256 burned) {
        circulating = totalSupply();
        staked = totalStaked;
        burned = totalBurned;
    }

    /**
     * @notice Check if user is eligible for platform benefits
     * @param user Address to check
     * @return eligible True if user has minimum stake and duration
     */
    function isEligibleForBenefits(address user) external view returns (bool eligible) {
        return stakedBalance[user] >= MIN_STAKE_AMOUNT
            && (emergencyWithdrawalEnabled || block.timestamp >= stakingTimestamp[user] + MIN_STAKE_DURATION);
    }

    /**
     * @notice Calculate user's staking weight for rewards
     * @param user Address to check
     * @return weight Staking weight (higher = more rewards)
     */
    function getStakingWeight(address user) external view returns (uint256 weight) {
        uint256 staked = stakedBalance[user];
        if (staked == 0) return 0;

        uint256 duration = block.timestamp - stakingTimestamp[user];

        // Base weight is staked amount
        weight = staked;

        // Bonus for longer staking (max 2x after 30 days)
        if (duration > 30 days) {
            weight *= 2;
        } else if (duration > 7 days) {
            weight = weight * (100 + duration * 100 / 30 days) / 100;
        }

        return weight;
    }

    // =============================================================
    //                       ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Pause all token operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause all token operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Recover accidentally sent tokens (not PTK)
     * @param tokenAddress Address of token to recover
     * @param to Address to send recovered tokens to
     * @param amount Amount to recover
     */
    function recoverToken(address tokenAddress, address to, uint256 amount) external onlyOwner {
        require(tokenAddress != address(this), "Cannot recover PTK tokens");
        IERC20(tokenAddress).transfer(to, amount);
    }

    // =============================================================
    //                        OVERRIDES
    // =============================================================

    /**
     * @notice Override transfer to prevent transferring staked tokens
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        // Allow minting and burning
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        // Allow authorized transferors to move tokens freely
        if (authorizedTransferors[msg.sender]) {
            super._update(from, to, value);
            return;
        }

        // For regular transfers, ensure user has enough non-staked balance
        if (from != address(this) && to != address(this)) {
            uint256 availableBalance = balanceOf(from) - stakedBalance[from];
            require(availableBalance >= value, "Insufficient transferable balance");
        }

        super._update(from, to, value);
    }
}
