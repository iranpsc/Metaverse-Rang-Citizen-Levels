// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract WhitelistWithLevelsAdvanced is Ownable2Step {
    struct User {
        uint256 id;
        string name;
        string code;
        uint8 level;
        uint256 xp;
        address wallet;
    }

    // Mapping from user wallet address to User struct
    mapping(address => User) public usersByWallet;
    
    // Mapping from user ID to assigned wallet address
    mapping(uint256 => address) public walletById;
    
    // Mapping from user ID to User struct for unassigned or direct ID lookups
    mapping(uint256 => User) public usersById;

    uint256 public userCount;

    error ZeroAddress();
    error UserIdAlreadyExists();
    error WalletAlreadyAssigned();
    error UserIdNotFound();
    error WalletNotAssigned();
    error InvalidUserData();

    event UserAdded(uint256 indexed id, string name, string code, uint8 level, uint256 xp);
    event WalletAssigned(uint256 indexed id, address indexed wallet);

    constructor() Ownable(msg.sender) {}

    // Add user by ID without initial wallet assignment
    function addUser(
        uint256 id,
        string calldata name,
        string calldata code,
        uint8 level,
        uint256 xp
    ) external onlyOwner {
        if (id == 0) revert InvalidUserData();
        if (walletById[id] != address(0) || usersById[id].id != 0) revert UserIdAlreadyExists();

        User memory newUser = User({
            id: id,
            name: name,
            code: code,
            level: level,
            xp: xp,
            wallet: address(0)
        });

        usersById[id] = newUser;
        userCount++;

        emit UserAdded(id, name, code, level, xp);
    }

    // Assign a wallet address to an existing user ID
    function assignWallet(uint256 id, address wallet) external onlyOwner {
        if (wallet == address(0)) revert ZeroAddress();
        if (walletById[id] != address(0)) revert WalletAlreadyAssigned();

        User storage u = usersById[id];
        if (u.id == 0) revert UserIdNotFound();

        u.wallet = wallet;
        usersByWallet[wallet] = u;
        walletById[id] = wallet;

        emit WalletAssigned(id, wallet);
    }

    // Get user info by wallet address
    function getUserByWallet(address wallet) external view returns (
        uint256 id,
        string memory name,
        string memory code,
        uint8 level,
        uint256 xp
    ) {
        User memory u = usersByWallet[wallet];
        if (u.wallet == address(0)) revert WalletNotAssigned();
        return (u.id, u.name, u.code, u.level, u.xp);
    }

    // Get user info by ID
    function getUserById(uint256 id) external view returns (
        uint256 userId,
        string memory name,
        string memory code,
        uint8 level,
        uint256 xp,
        address wallet
    ) {
        User memory u = usersById[id];
        if (u.id == 0) revert UserIdNotFound();
        return (u.id, u.name, u.code, u.level, u.xp, u.wallet);
    }
}