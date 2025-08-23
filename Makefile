# Makefile for LotteryGame deployment

# Load environment variables
-include .env

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

.PHONY: help install build test deploy-anvil deploy-sepolia verify clean

help: ## Show this help message
	@echo "$(GREEN)LotteryGame Deployment Commands$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'

install: ## Install dependencies
	@echo "$(GREEN)Installing dependencies...$(NC)"
	forge install OpenZeppelin/openzeppelin-contracts
	forge install smartcontractkit/chainlink-brownie-contracts
	forge install foundry-rs/forge-std
	@echo "$(GREEN)Dependencies installed!$(NC)"

build: ## Build contracts
	@echo "$(GREEN)Building contracts...$(NC)"
	forge build
	@echo "$(GREEN)Build complete!$(NC)"

test: ## Run tests
	@echo "$(GREEN)Running tests...$(NC)"
	forge test -vvv
	@echo "$(GREEN)Tests complete!$(NC)"

clean: ## Clean build artifacts
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	forge clean
	mkdir -p deployments

setup-dirs: ## Create necessary directories
	@mkdir -p deployments
	@mkdir -p src
	@mkdir -p script
	@echo "$(GREEN)Directories created!$(NC)"

deploy-anvil: build setup-dirs ## Deploy to Anvil (local)
	@echo "$(GREEN)Deploying to Anvil...$(NC)"
	@anvil --fork-url $(SEPOLIA_RPC_URL) --fork-block-number latest &
	@sleep 2
	forge script script/Deploy.s.sol:DeployLotteryGame \
		--rpc-url http://127.0.0.1:8545 \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
		--broadcast \
		-vvvv
	@echo "$(GREEN)Anvil deployment complete!$(NC)"

deploy-sepolia: build setup-dirs ## Deploy to Sepolia
	@echo "$(GREEN)Deploying to Sepolia...$(NC)"
	@if [ -z "$(PRIVATE_KEY)" ]; then \
		echo "$(RED)Error: PRIVATE_KEY not set in .env file$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(SEPOLIA_RPC_URL)" ]; then \
		echo "$(RED)Error: SEPOLIA_RPC_URL not set in .env file$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(SEPOLIA_SUBSCRIPTION_ID)" ]; then \
		echo "$(RED)Error: SEPOLIA_SUBSCRIPTION_ID not set in .env file$(NC)"; \
		echo "$(YELLOW)Please create a VRF subscription at https://vrf.chain.link/$(NC)"; \
		exit 1; \
	fi
	forge script script/Deploy.s.sol:DeployLotteryGame \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(ETHERSCAN_API_KEY) \
		-vvvv
	@echo "$(GREEN)Sepolia deployment complete!$(NC)"

verify: ## Verify contract on Etherscan
	@echo "$(GREEN)Verifying contract...$(NC)"
	@if [ -z "$(CONTRACT_ADDRESS)" ]; then \
		echo "$(RED)Error: CONTRACT_ADDRESS not provided$(NC)"; \
		echo "$(YELLOW)Usage: make verify CONTRACT_ADDRESS=0x...$(NC)"; \
		exit 1; \
	fi
	forge verify-contract $(CONTRACT_ADDRESS) \
		src/LotteryGame.sol:LotteryGame \
		--chain sepolia \
		--etherscan-api-key $(ETHERSCAN_API_KEY) \
		--constructor-args $$(cast abi-encode "constructor(address,address,uint64,bytes32,address)" \
			0xEcEfF35fE011694DFceA93e97BBa60D2feec2253 \
			0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625 \
			$(SEPOLIA_SUBSCRIPTION_ID) \
			0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c \
			$$(cast wallet address $(PRIVATE_KEY)))
	@echo "$(GREEN)Verification complete!$(NC)"

check-env: ## Check environment variables
	@echo "$(GREEN)Checking environment variables...$(NC)"
	@echo "PRIVATE_KEY: $$(if [ -n "$(PRIVATE_KEY)" ]; then echo "✓ Set"; else echo "✗ Missing"; fi)"
	@echo "SEPOLIA_RPC_URL: $$(if [ -n "$(SEPOLIA_RPC_URL)" ]; then echo "✓ Set"; else echo "✗ Missing"; fi)"
	@echo "SEPOLIA_SUBSCRIPTION_ID: $$(if [ -n "$(SEPOLIA_SUBSCRIPTION_ID)" ]; then echo "✓ Set"; else echo "✗ Missing"; fi)"
	@echo "ETHERSCAN_API_KEY: $$(if [ -n "$(ETHERSCAN_API_KEY)" ]; then echo "✓ Set"; else echo "✗ Missing"; fi)"

fund-subscription: ## Fund VRF subscription (interactive)
	@echo "$(YELLOW)To fund your VRF subscription:$(NC)"
	@echo "1. Go to https://vrf.chain.link/"
	@echo "2. Connect your wallet"
	@echo "3. Select Sepolia network"
	@echo "4. Find your subscription ID: $(SEPOLIA_SUBSCRIPTION_ID)"
	@echo "5. Add funds (minimum 2 LINK tokens recommended)"
	@echo "6. Add your deployed contract as a consumer"

status: ## Show deployment status
	@echo "$(GREEN)Deployment Status$(NC)"
	@echo "=================="
	@if [ -f "deployments/Sepolia_deployment.json" ]; then \
		echo "Sepolia Deployment: ✓ Found"; \
		echo "Contract Address: $$(cat deployments/Sepolia_deployment.json | jq -r '.lotteryGame')"; \
	else \
		echo "Sepolia Deployment: ✗ Not found"; \
	fi
	@if [ -f "deployments/Anvil_deployment.json" ]; then \
		echo "Anvil Deployment: ✓ Found"; \
		echo "Contract Address: $$(cat deployments/Anvil_deployment.json | jq -r '.lotteryGame')"; \
	else \
		echo "Anvil Deployment: ✗ Not found"; \
	fi