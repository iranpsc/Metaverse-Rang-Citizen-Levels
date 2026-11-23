// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title MockERC20
 * @notice Enterprise-grade ERC20 mock with EIP-2612 Permit, Burnable, and Role-Based Access Control.
 */
contract MockERC20 is ERC20, ERC20Burnable, ERC20Permit, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    error ZeroAddress();
    error ZeroAmount();

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        address admin_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (admin_ == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);

        if (initialSupply > 0) {
            _mint(admin_, initialSupply);
        }
    }

    /**
     * @notice Mints tokens to a target address. Restricted to MINTER_ROLE.
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        _mint(to, amount);
    }
}
