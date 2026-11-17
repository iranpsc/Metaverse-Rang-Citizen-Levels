// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

interface ILevelRewardNFT {
    function mintLevelReward(address to, uint8 level) external returns (uint256);
}

contract ProductionLevelSystem is Ownable2Step {
    uint8 public constant MAX_LEVEL = 13;
    uint8 public constant MAX_STEP = 7;
    uint256 public constant WELCOME_XP = 50;

    ILevelRewardNFT public rewardNFT;

    struct Player {
        bool registered;
        uint8 level;
        uint8 step;
        uint256 xp;
    }

    mapping(address => Player) public players;
    mapping(address => bool) public whitelist;

    mapping(uint8 => mapping(uint8 => uint256)) public stepXPRequired;
    mapping(uint8 => uint256) public levelPrice;

    error NotWhitelisted();
    error AlreadyRegistered();
    error NotRegistered();
    error MaxStepReached();
    error MaxLevelReached();
    error InsufficientXP();
    error WrongPayment();
    error ZeroAddress();

    event Registered(address indexed user);
    event StepAdvanced(address indexed user, uint8 level, uint8 fromStep, uint8 toStep);
    event LevelAdvanced(address indexed user, uint8 fromLevel, uint8 toLevel);
    event WhitelistUpdated(address indexed user, bool status);

    constructor(address _rewardNFT, address initialOwner)
        Ownable(initialOwner)
    {
        if (_rewardNFT == address(0) || initialOwner == address(0)) revert ZeroAddress();
        rewardNFT = ILevelRewardNFT(_rewardNFT);

        for (uint8 level = 1; level <= MAX_LEVEL; level++) {
            levelPrice[level] = uint256(level - 1) * 0.01 ether;

            for (uint8 step = 1; step <= MAX_STEP; step++) {
                stepXPRequired[level][step] = uint256(step - 1) * 50;
            }
        }
    }

    function register() external {
        if (!whitelist[msg.sender]) revert NotWhitelisted();
        if (players[msg.sender].registered) revert AlreadyRegistered();

        players[msg.sender] = Player(true, 1, 1, WELCOME_XP);
        rewardNFT.mintLevelReward(msg.sender, 1);

        emit Registered(msg.sender);
    }

    function advanceStep() external {
        Player storage p = players[msg.sender];
        if (!p.registered) revert NotRegistered();
        if (p.step >= MAX_STEP) revert MaxStepReached();

        uint8 nextStep = p.step + 1;
        if (p.xp < stepXPRequired[p.level][nextStep]) revert InsufficientXP();

        emit StepAdvanced(msg.sender, p.level, p.step, nextStep);
        p.step = nextStep;
    }

    function buyNextLevelKeyAndAdvance() external payable {
        Player storage p = players[msg.sender];

        if (!p.registered) revert NotRegistered();
        if (p.step != MAX_STEP) revert MaxStepReached();
        if (p.level >= MAX_LEVEL) revert MaxLevelReached();

        uint8 nextLevel = p.level + 1;
        if (msg.value != levelPrice[nextLevel]) revert WrongPayment();

        rewardNFT.mintLevelReward(msg.sender, nextLevel);

        emit LevelAdvanced(msg.sender, p.level, nextLevel);

        p.level = nextLevel;
        p.step = 1;
    }

    function setWhitelist(address user, bool status) external onlyOwner {
        if (user == address(0)) revert ZeroAddress();
        whitelist[user] = status;
        emit WhitelistUpdated(user, status);
    }

    function setRewardNFT(address _rewardNFT) external onlyOwner {
        if (_rewardNFT == address(0)) revert ZeroAddress();
        rewardNFT = ILevelRewardNFT(_rewardNFT);
    }
}