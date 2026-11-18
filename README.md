<div align="center">

# 🌌 Metaverse Rang — Citizen Levels & PSC Ecosystem
### **Production-Grade 13-Level Access & Supply Chain Smart Contract Architecture**

[![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.24-383838?style=for-the-badge&logo=solidity&logoColor=white)](https://soliditylang.org/)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin_v5-Secure-4E5EE4?style=for-the-badge&logo=openzeppelin&logoColor=white)](https://openzeppelin.com/)
[![Foundry](https://img.shields.io/badge/Tested_with-Foundry-FF5722?style=for-the-badge&logo=fire&logoColor=white)](https://getfoundry.sh/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

</div>

---

## 📖 Project Overview

The **Metaverse Rang Citizen Levels** smart contract suite is an advanced, secure, and gas-optimized ecosystem built on **OpenZeppelin v5** and **Solidity 0.8.24**. This system manages user progression across **13 Levels** and associated steps, issues Soulbound access keys (ERC-721), reward tokens, multi-tier assets (ERC-1155), and handles Merkle Tree whitelist verifications for the **Paradise Supply Chain (PSC)** project.

---

## 🛠️ Ecosystem Architecture & Smart Contract Suite

All smart contracts in this repository leverage **Custom Errors** for maximum gas efficiency and the **`Ownable2Step`** pattern for secure administrative control:

1. **`LevelRewardNFT.sol`** — Manages level reward NFTs with secure two-step ownership management.
2. **`LevelKeyNFT.sol`** — Level access keys featuring a secure **Soulbound** structure (non-transferable between wallets).
3. **`LevelAssets1155.sol`** — Manages multi-tier assets, items, and rewards using standard ERC-1155 with separated asset policies.
4. **`MerkleWhitelist.sol`** — Merkle Tree-based whitelist verification system for secure registration and distribution.
5. **`BatchUserStorage.sol`** — Handles bulk user data registration and internal wallet balances in batches.
6. **`ProductionLevelSystem.sol`** — Core logic engine for user progression across 13 levels and 7 steps based on XP.
7. **`ThirteenLevelAccess.sol`** — Central hub for access control, ETH payments for key purchases, and level rule configurations.
8. **`WhitelistWithLevels.sol`** — Initial registration logic and user identification based on IDs and custom codes.
9. **`ThirteenLevelAccessWithWhitelist.sol`** — Bridge contract connecting the whitelist to NFT reward and key minting modules.
10. **`WhitelistWithLevelsAdvanced.sol`** — Advanced whitelist implementation supporting dynamic wallet address assignment to user IDs.
11. **`UserStorage.sol`** — Comprehensive data storage structure for user details, multi-token balances, and 3D gem assets.
12. **`ThirteenLevelAccessKey_Deployable.sol`** — Unified, optimized, and non-reentrant contract variant optimized for mainnet bytecode limits.
13. **`PSCSystem.t.sol`** — Comprehensive unit and scenario test suite (powered by Foundry) ensuring absolute system reliability.

---

## ⚙️ Security & Optimizations

* **OpenZeppelin v5 Integration:** Utilizes modern hook functions (`_update`) for robust transfer controls.
* **Custom Errors:** Completely replaces costly revert string messages with custom errors to drastically minimize gas overhead.
* **Two-Step Ownership Transfer (`Ownable2Step`):** Prevents accidental ownership transfers to zero or incorrect addresses.
* **Reentrancy Guards:** Full protection on all financial functions and level key purchasing workflows.

---

## 🚀 Getting Started & Installation

To set up the project, install dependencies, and run tests using **Foundry** or **Hardhat**:

```bash
# Clone the repository
git clone [https://github.com/ParsaAbolhasani/Metaverse-Rang-Citizen-Levels.git](https://github.com/ParsaAbolhasani/Metaverse-Rang-Citizen-Levels.git)
cd Metaverse-Rang-Citizen-Levels

# Install OpenZeppelin dependencies
forge install OpenZeppelin/openzeppelin-contracts

# Compile the contracts
forge build

# Run unit tests with gas reporting
forge test --gas-report


📦 Deployment

To execute the master deployment script and automatically handle contract wiring on your target network:
npx hardhat run scripts/deploy-psc-ecosystem.js --network sepolia

👨‍💻 Author

    Name: Parsa Abolhasani Rad 
    Role: Senior Blockchain Developer & Full-Stack Web3 Engineer

    Affiliation: Member of the Association of Iranian Blockchain

    GitHub Profile: @ParsaAbolhasani

📄 License

This project is licensed under the MIT License. See the LICENSE file for details.
