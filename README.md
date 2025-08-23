# LotteryGame - Decentralized Lottery Platform

A blockchain-based lottery game built on Ethereum with staking mechanics, random number generation via Chainlink VRF, and automated gift distribution.

## 🎯 Features

- **5-Number Lottery**: Players pick 5 numbers (1-49) per round
- **Staking System**: Stake platform tokens to participate and earn rewards
- **Chainlink VRF**: Provably fair random number generation
- **Gift Distribution**: Automated rewards for creators and eligible players
- **Round-Based**: 5-minute rounds with immediate payouts
- **Security**: Built with OpenZeppelin contracts, reentrancy protection

## 🏗️ Architecture

### Core Contracts

- **LotteryGame.sol** - Main lottery logic and game mechanics
- **PlatformToken.sol** - ERC20 token with staking functionality
- **VRFConsumer.sol** - Chainlink VRF integration

### Key Components

- Minimum stake required to participate (10 tokens)
- House edge: 5% on all payouts
- Payout multipliers: 2x (2 matches) → 800x (5 matches)
- Gift system for consecutive players

## 🚀 Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Chainlink VRF subscription
- Sepolia ETH for deployment

### Installation

```bash
git clone git@github.com:Agwara/crystalChain.git
cd crystalChain
make install
```

### Environment Setup

Create `.env` file:

```bash
PRIVATE_KEY=your_private_key
SEPOLIA_RPC_URL=your_rpc_url
SEPOLIA_SUBSCRIPTION_ID=your_vrf_subscription_id
ETHERSCAN_API_KEY=your_etherscan_api_key
```

### Deploy to Sepolia

```bash
make deploy-sepolia
```

### Deploy Locally (Anvil)

```bash
make deploy-anvil
```

## 🎮 How to Play

1. **Stake Tokens**: Minimum 10 tokens required
2. **Place Bet**: Choose 5 unique numbers (1-49)
3. **Wait for Draw**: Numbers drawn via Chainlink VRF after round ends
4. **Claim Winnings**: Automatic payout based on matches
5. **Earn Gifts**: Play consecutive rounds for bonus rewards

## 💰 Payout Structure

| Matches | Multiplier | Example (1 token bet) |
| ------- | ---------- | --------------------- |
| 5/5     | 800x       | 800 tokens            |
| 4/5     | 80x        | 80 tokens             |
| 3/5     | 8x         | 8 tokens              |
| 2/5     | 2x         | 2 tokens              |

_All payouts subject to 5% house edge_

## 🔧 Development Commands

```bash
# Build contracts
make build

# Run tests
make test

# Check environment
make check-env

# Verify contract
make verify CONTRACT_ADDRESS=0x...

# Check deployment status
make status
```

## 📊 Contract Addresses

### Sepolia Testnet

- **Platform Token**: `0xECEfF35FE011694DfCEa93E97bba60D2FEEc2253`
- **VRF Coordinator**: `0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625`
- **LotteryGame**: Deploy using scripts above

## 🛡️ Security Features

- OpenZeppelin security patterns
- Reentrancy protection
- Access control (roles)
- Pausable functionality
- Timelock for critical operations
- Maximum payout limits

## 📄 License

MIT License - see LICENSE file for details.

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Add tests for new functionality
4. Submit pull request

## 📞 Support

For questions or issues, please open a GitHub issue or contact the development team.
