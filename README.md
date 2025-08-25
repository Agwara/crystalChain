# Decentralized Lottery System

A fully decentralized lottery system built on Ethereum, featuring provably fair number generation using Chainlink VRF, token staking mechanics, and automated gift distribution.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [System Architecture](#system-architecture)
- [Smart Contracts](#smart-contracts)
- [Getting Started](#getting-started)
- [Deployment](#deployment)
- [Usage](#usage)
- [Security Features](#security-features)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)

## Overview

This lottery system implements a decentralized gambling platform where users stake platform tokens to participate in lottery rounds. The system features:

- **Provably Fair**: Uses Chainlink VRF for verifiable random number generation
- **Staking-Based**: Users must stake tokens to participate, creating long-term engagement
- **Automated Gifts**: Regular gift distribution to active participants and creators
- **Multi-Tier Winnings**: 5-tier prize structure based on number matches
- **Administrative Controls**: Timelock-protected administrative functions

## Features

### Core Lottery Mechanics

- 5-minute lottery rounds with automatic progression
- Players select 5 numbers from 1-49
- Multiple bet sizes supported (minimum 1 PTK)
- Provably fair random number generation via Chainlink VRF
- Multi-tier prize structure (2-5 matches)

### Token Economics

- **PlatformToken (PTK)**: ERC20 token with staking capabilities
- **Minimum Stake**: 10 PTK required for betting eligibility
- **Staking Benefits**: Higher staking weight increases gift eligibility
- **Burn Mechanism**: 5% of winnings burned for deflationary pressure

### Gift System

- **Creator Gifts**: Platform creator receives gifts each round
- **User Gifts**: Random selection of eligible users receive gifts
- **Eligibility**: Requires 3+ consecutive rounds of participation
- **Cooldown**: 24-hour cooldown between gifts per user

### Security & Governance

- **Access Control**: Role-based permissions for different functions
- **Timelock**: 24-hour timelock for critical parameter changes
- **Emergency Controls**: Pause/unpause functionality
- **Reentrancy Protection**: Full reentrancy guards on critical functions

## System Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  PlatformToken  │    │ LotteryGameCore │    │   LotteryGift   │
│                 │    │                 │    │                 │
│ • Staking       │◄──►│ • Betting       │◄──►│ • Distribution  │
│ • Burning       │    │ • Rounds        │    │ • Selection     │
│ • Rewards       │    │ • Claiming      │    │ • Cooldowns     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲                       ▲                       ▲
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 ▼
                    ┌─────────────────┐    ┌─────────────────┐
                    │  LotteryAdmin   │    │  Chainlink VRF  │
                    │                 │    │                 │
                    │ • Governance    │    │ • RNG Service   │
                    │ • Timelocks     │    │ • Verification  │
                    │ • Emergency     │    │ • Callbacks     │
                    └─────────────────┘    └─────────────────┘
```

## Smart Contracts

### Core Contracts

| Contract              | Description               | Key Functions                                   |
| --------------------- | ------------------------- | ----------------------------------------------- |
| `PlatformToken.sol`   | ERC20 token with staking  | `stake()`, `unstake()`, `burnFrom()`            |
| `LotteryGameCore.sol` | Main lottery logic        | `placeBet()`, `claimWinnings()`, `endRound()`   |
| `LotteryGift.sol`     | Gift distribution system  | `distributeGifts()`, `fundGiftReserve()`        |
| `LotteryAdmin.sol`    | Administrative functions  | `setMaxPayoutPerRound()`, `pause()`             |
| `VRFConsumer.sol`     | Chainlink VRF integration | `_requestRandomWords()`, `fulfillRandomWords()` |

### Contract Addresses

#### Sepolia Testnet

- **PlatformToken**: `[Your existing address]`
- **LotteryGameCore**: `[Deploy using guide]`
- **LotteryGift**: `[Deploy using guide]`
- **LotteryAdmin**: `[Deploy using guide]`

#### Mainnet

- **PlatformToken**: `[To be deployed]`
- **LotteryGameCore**: `[To be deployed]`
- **LotteryGift**: `[To be deployed]`
- **LotteryAdmin**: `[To be deployed]`

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 16+ and npm/yarn
- Git

### Installation

```bash
# Clone the repository
git clone https://github.com/agwara/crystalChain
cd crystalChain

# Install Foundry dependencies
forge install


```

### Environment Setup

Create a `.env` file:

```bash
# Network Configuration
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_INFURA_KEY

# Deployment
PRIVATE_KEY=your_private_key_here
PLATFORM_TOKEN_ADDRESS=your_existing_token_address

# Chainlink VRF
VRF_SUBSCRIPTION_ID=your_subscription_id

# Verification
ETHERSCAN_API_KEY=your_etherscan_api_key
```

## Deployment

### Quick Deploy to Sepolia

```bash
# Deploy all contracts
forge script script/DeployLottery.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY

# Set up VRF subscription
# Visit https://vrf.chain.link and add your Core contract as consumer

# Configure token permissions
cast send $PLATFORM_TOKEN_ADDRESS \
    "setAuthorizedBurner(address,bool)" \
    $CORE_CONTRACT_ADDRESS true \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

For detailed deployment instructions, see [Deployment Guide](docs/deployment.md).

## Usage

### For Players

1. **Stake Tokens**: Minimum 10 PTK required

   ```solidity
   platformToken.stake(10 * 10**18);
   ```

2. **Place Bets**: Select 5 unique numbers (1-49)

   ```solidity
   lotteryCore.placeBet([1,15,23,35,42], betAmount);
   ```

3. **Claim Winnings**: After round ends and numbers are drawn
   ```solidity
   lotteryCore.claimWinnings(roundId, betIndices);
   ```

### For Administrators

1. **Manage Settings**: Update payout limits (with timelock)

   ```solidity
   adminContract.scheduleMaxPayoutChange(newAmount);
   // Wait 24 hours
   adminContract.setMaxPayoutPerRound(newAmount);
   ```

2. **Emergency Controls**: Pause system if needed

   ```solidity
   adminContract.pause();
   ```

3. **Gift Distribution**: Distribute gifts after each round
   ```solidity
   giftContract.distributeGifts(roundId);
   ```

### Prize Structure

| Matches | Payout Multiplier | Example (1 PTK bet) |
| ------- | ----------------- | ------------------- |
| 5/5     | 800x              | 800 PTK             |
| 4/5     | 80x               | 80 PTK              |
| 3/5     | 8x                | 8 PTK               |
| 2/5     | 2x                | 2 PTK               |
| 0-1/5   | 0x                | 0 PTK               |

_All payouts subject to 5% house edge_

## Security Features

### Access Controls

- **Role-based permissions** for different contract functions
- **Multi-signature support** for critical operations
- **Timelock protection** for parameter changes

### Economic Security

- **Minimum stake requirements** prevent spam
- **Maximum bet limits** prevent manipulation
- **Burn mechanisms** create deflationary pressure

### Technical Security

- **Reentrancy guards** on all external calls
- **Input validation** for all user inputs
- **Overflow protection** using Solidity 0.8+
- **Pausable contracts** for emergency stops

### Randomness Security

- **Chainlink VRF** for verifiable randomness
- **Request validation** prevents manipulation
- **Emergency fallback** for VRF failures

## Testing

### Run Unit Tests

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run with gas reporting
forge test --gas-report
```

### Coverage

```bash
# Generate coverage report
forge coverage

# Generate HTML coverage report
forge coverage --report lcov
genhtml lcov.info --output-directory coverage
```

#### LotteryGameCore

```solidity
function placeBet(uint256[5] calldata numbers, uint256 amount) external
function claimWinnings(uint256 roundId, uint256[] calldata betIndices) external
function getCurrentRound() external view returns (Round memory)
function getUserStats(address user) external view returns (UserStats memory)
```

#### PlatformToken

```solidity
function stake(uint256 amount) external
function unstake(uint256 amount) external
function getStakingWeight(address user) external view returns (uint256)
function isEligibleForBenefits(address user) external view returns (bool)
```

#### LotteryGift

```solidity
function distributeGifts(uint256 roundId) external
function fundGiftReserve(uint256 amount) external
function getGiftReserveStatus() external view returns (uint256, uint256)
```

For complete API documentation, see [API Reference](docs/api.md).

## Configuration

### Default Parameters

```solidity
// Lottery Parameters
uint256 public constant ROUND_DURATION = 5 minutes;
uint256 public constant MIN_BET_AMOUNT = 1 * 10**18; // 1 PTK
uint256 public constant MAX_BET_PER_USER_PER_ROUND = 1000 * 10**18; // 1000 PTK

// Token Parameters
uint256 public constant MIN_STAKE_AMOUNT = 10 * 10**18; // 10 PTK
uint256 public constant MIN_STAKE_DURATION = 24 hours;

// Gift Parameters
uint256 public constant CONSECUTIVE_PLAY_REQUIREMENT = 3;
uint256 public constant GIFT_COOLDOWN = 24 hours;
```

### Customizable Parameters

- Maximum payout per round
- Gift recipient count
- Gift amounts (creator and user)
- House edge percentage

## Monitoring & Analytics

### Key Metrics to Track

- **Round Statistics**: Participation, total bets, prize pools
- **User Engagement**: Consecutive rounds, staking levels
- **Economic Health**: Token supply, burn rate, gift distribution
- **Technical Performance**: VRF response times, gas usage

### Events for Monitoring

```solidity
event RoundStarted(uint256 indexed roundId, uint256 startTime, uint256 endTime);
event BetPlaced(uint256 indexed roundId, address indexed user, uint256[5] numbers, uint256 amount);
event NumbersDrawn(uint256 indexed roundId, uint256[5] winningNumbers);
event GiftDistributed(uint256 indexed roundId, address indexed recipient, uint256 amount, bool isCreator);
```

## Troubleshooting

### Common Issues

1. **VRF Not Responding**

   - Check subscription funding
   - Verify consumer registration
   - Check gas limits

2. **Betting Fails**

   - Ensure minimum stake requirement met
   - Check token allowance
   - Verify round is active

3. **Gift Distribution Fails**
   - Check gift reserve balance
   - Verify eligible participants
   - Ensure round numbers are drawn

### Emergency Procedures

```bash
# Pause the system
cast send $ADMIN_CONTRACT "pause()"

# Emergency withdraw funds
cast send $ADMIN_CONTRACT "emergencyWithdraw(uint256)" $AMOUNT

# Enable emergency unstaking
cast send $PLATFORM_TOKEN "toggleEmergencyWithdrawal(bool)" true
```

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Workflow

1. Fork the repository
2. Create a feature branch
3. Make changes with tests
4. Submit a pull request

### Code Standards

- Follow Solidity style guide
- Include comprehensive tests
- Add documentation for new features
- Use semantic commit messages

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [OpenZeppelin](https://openzeppelin.com/) for secure contract libraries
- [Chainlink](https://chain.link/) for VRF services
- [Foundry](https://getfoundry.sh/) for development framework

## Disclaimer

This software is provided "as is" without warranty. Users should conduct their own security audits before deploying to mainnet. Gambling may be subject to legal restrictions in your jurisdiction.
