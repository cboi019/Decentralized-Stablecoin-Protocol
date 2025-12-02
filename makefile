include .env

TEST: 
	forge test --rpc-url $(SEPOLIA_RPC_URL) -vvvv

ANVIL-TEST: 
	forge test --fork-url $(ANVIL_FORK_URL) -vvvv

Deploy-ANVIL:
		forge script script/DEFI-STABLECOIN.s.sol:deployDSC --fork-url $(ANVIL_FORK_URL) --account myAnvilWallet 

DEPLOY-SEPOLIA:
		forge script script/DEFI-STABLECOIN.s.sol:deployDSC --fork-url $(SEPOLIA_RPC_URL) --account mainKey --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) --via-ir