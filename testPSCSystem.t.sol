// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/LevelRewardNFT.sol";
import "../src/LevelKeyNFT.sol";
import "../src/ThirteenLevelAccess.sol";

contract PSCSystemTest is Test {
    LevelRewardNFT rewardNFT;
    LevelKeyNFT keyNFT;
    ThirteenLevelAccess accessSystem;

    address owner = address(1);
    address player1 = address(2);
    address player2 = address(3);

    function setUp() public {
        vm.startPrank(owner);

        // 1. Deploy NFTs
        rewardNFT = new LevelRewardNFT("https://api.metarang.com/rewards/");
        keyNFT = new LevelKeyNFT("https://api.metarang.com/keys/");

        // 2. Deploy Core Access System
        accessSystem = new ThirteenLevelAccess(address(keyNFT), address(rewardNFT));

        // 3. Set Minter roles
        rewardNFT.setMinter(address(accessSystem));
        keyNFT.setMinter(address(accessSystem));

        vm.stopPrank();

        // Give some ETH to players for key purchases
        vm.deal(player1, 10 ether);
        vm.deal(player2, 10 ether);
    }

    function test_PlayerRegistration() public {
        vm.prank(player1);
        accessSystem.register();

        (bool registered, uint8 level, uint256 xp) = accessSystem.getPlayer(player1);
        
        assertTrue(registered, "Player should be registered");
        assertEq(level, 1, "Initial level should be 1");
        assertEq(xp, 50, "Initial welcome XP should be 50");
        
        // Verify reward NFT minted for level 1
        assertEq(rewardNFT.balanceOf(player1), 1, "Player should receive level 1 reward NFT");
    }

    function test_BuyNextLevelKeyAndAdvance() public {
        // Register player
        vm.prank(player1);
        accessSystem.register();

        // Owner adds XP so player meets level 2 requirement (100 XP)
        vm.prank(owner);
        accessSystem.addXP(player1, 50); // 50 (welcome) + 50 = 100 XP

        // Level 2 price is 0.01 ETH
        uint256 level2Price = 0.01 ether;

        vm.prank(player1);
        accessSystem.buyNextLevelKeyAndAdvance{value: level2Price}();

        // Verify level upgrade
        (, uint8 level,) = accessSystem.getPlayer(player1);
        assertEq(level, 2, "Player level should advance to 2");

        // Verify key NFT and reward NFT received
        assertEq(keyNFT.balanceOf(player1), 1, "Player should hold level 2 key NFT");
        assertEq(rewardNFT.balanceOf(player1), 2, "Player should hold 2 reward NFTs now");
    }

    function test_RevertWhen_InsufficientXP() public {
        vm.prank(player1);
        accessSystem.register();

        // Do not add XP, try to buy level 2 key (requires 100 XP, player has 50)
        uint256 level2Price = 0.01 ether;

        vm.prank(player1);
        vm.expectRevert(ThirteenLevelAccess.NotEnoughXP.selector);
        accessSystem.buyNextLevelKeyAndAdvance{value: level2Price}();
    }

    function test_SoulboundKeyTransferReverts() public {
        vm.prank(player1);
        accessSystem.register();

        vm.prank(owner);
        accessSystem.addXP(player1, 50);

        vm.prank(player1);
        accessSystem.buyNextLevelKeyAndAdvance{value: 0.01 ether};

        uint256 tokenId = accessSystem.keyTokenOf(player1, 2);

        // Try to transfer soulbound key NFT to player2 -> should revert
        vm.prank(player1);
        vm.expectRevert(LevelKeyNFT.SoulboundToken.selector);
        keyNFT.transferFrom(player1, player2, tokenId);
    }
}