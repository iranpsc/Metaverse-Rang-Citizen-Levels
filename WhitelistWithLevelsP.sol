// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILevelKeyNFT {
    function mintLevelKey(address to, uint8 level) external returns (uint256);
}

interface ILevelRewardNFT {
    function mintLevelReward(address to, uint8 level) external returns (uint256);
}

contract WhitelistWithLevels {
    struct User {
        uint256 id;
        string name;
        string code;
        uint8 level;
        uint256 xp;
        address wallet;
        bool registered;
    }

    mapping(address => User) public usersByWallet;
    mapping(uint256 => address) public walletById;
    uint256 public userCount;

    error WalletZeroAddress();
    error UserIdAlreadyExists();
    error WalletAlreadyAssigned();
    error UserIdNotFound();
    error WalletNotAssigned();

    event UserAdded(uint256 indexed id, string name, string code, uint8 level, uint256 xp, address wallet);
    event WalletAssigned(uint256 indexed id, address wallet);

    function addUser(
        uint256 id,
        string calldata name,
        string calldata code,
        uint8 level,
        uint256 xp
    ) external {
        if (walletById[id] != address(0)) revert UserIdAlreadyExists();

        usersByWallet[address(0)] = User(id, name, code, level, xp, address(0), false);
        walletById[id] = address(0);
        userCount++;

        emit UserAdded(id, name, code, level, xp, address(0));
    }

    function assignWallet(uint256 id, address wallet) external {
        if (wallet == address(0)) revert WalletZeroAddress();
        if (walletById[id] != address(0)) revert WalletAlreadyAssigned();

        User storage u = usersByWallet[address(0)];
        if (u.id != id) revert UserIdNotFound();

        u.wallet = wallet;
        u.registered = true;
        usersByWallet[wallet] = u;
        walletById[id] = wallet;

        emit WalletAssigned(id, wallet);
    }

    function getUser(address wallet) external view returns (User memory) {
        User memory u = usersByWallet[wallet];
        if (u.wallet == address(0)) revert WalletNotAssigned();
        return u;
    }
}

contract ThirteenLevelAccessWithWhitelist {
    WhitelistWithLevels public immutable whitelist;
    ILevelKeyNFT public immutable keyNFT;
    ILevelRewardNFT public immutable rewardNFT;

    uint8 public constant MAX_LEVEL = 13;

    struct Player {
        bool registered;
        uint8 level;
        uint256 xp;
    }

    mapping(address => Player) public players;

    error NotInWhitelist();
    error AlreadyRegistered();
    error ZeroAddress();

    event PlayerRegistered(address indexed player, uint8 level, uint256 xp);
    event LevelAdvanced(address indexed player, uint8 fromLevel, uint8 toLevel, uint256 keyTokenId, uint256 rewardTokenId);

    constructor(
        address _whitelist,
        address _keyNFT,
        address _rewardNFT
    ) {
        if (_whitelist == address(0) || _keyNFT == address(0) || _rewardNFT == address(0)) {
            revert ZeroAddress();
        }
        whitelist = WhitelistWithLevels(_whitelist);
        keyNFT = ILevelKeyNFT(_keyNFT);
        rewardNFT = ILevelRewardNFT(_rewardNFT);
    }

    function registerFromWhitelist() external {
        WhitelistWithLevels.User memory u = whitelist.getUser(msg.sender);
        if (!u.registered) revert NotInWhitelist();
        if (players[msg.sender].registered) revert AlreadyRegistered();

        players[msg.sender] = Player({
            registered: true,
            level: u.level,
            xp: u.xp
        });

        uint256 rewardTokenId = rewardNFT.mintLevelReward(msg.sender, u.level);

        emit PlayerRegistered(msg.sender, u.level, u.xp);
        emit LevelAdvanced(msg.sender, 0, u.level, 0, rewardTokenId);
    }

    function getPlayer(address user) external view returns (bool registered, uint8 level, uint256 xp) {
        Player memory p = players[user];
        return (p.registered, p.level, p.xp);
    }
}