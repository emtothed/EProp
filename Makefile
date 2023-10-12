include .env


deploy:
	@forge script script/DeployeProp.s.sol --rpc-url http://127.0.0.1:8545/ --private-key $(ANVIL_PRIVATE_KEY) --broadcast

mint: 
	@forge script script/interaction.s.sol:MintNft --rpc-url http://127.0.0.1:8545/ --private-key $(ANVIL_PRIVATE_KEY) --broadcast



sepoliaDeploy:
	@forge script script/DeployeProp.s.sol --rpc-url $(SEPOLIA_RPC_URL) --private-key $(SEPOLIA_PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY)


sepoliaMint:
	@forge script script/interaction.s.sol:MintNft --rpc-url $(SEPOLIA_RPC_URL) --private-key $(SEPOLIA_PRIVATE_KEY) --broadcast


mint_with_cast:
	@cast send 0x5FbDB2315678afecb367f032d93F642f64180aa3 "function mintProp(address,uint256,uint256,uint256,uint256)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 55 65 1 1 --rpc-url $(ANVIL_RPC_URL) --private-key $(ANVIL_PRIVATE_KEY)