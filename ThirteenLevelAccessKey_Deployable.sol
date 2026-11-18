// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILevelKeyReceiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

contract ThirteenLevelAccessKeyDeployable {
    uint8 public constant MIN_LEVEL = 1;
    uint8 public constant MAX_LEVEL = 13;
    uint256 public constant WELCOME_XP = 50;

    bytes4 private constant ERC721_RECEIVED = 0x150b7a02;
    bytes4 private constant ERC165_INTERFACE_ID = 0x01ffc9a7;
    bytes4 private constant ERC721_INTERFACE_ID = 0x80ac58cd;
    bytes4 private constant ERC721_METADATA_INTERFACE_ID = 0x5b5e139f;

    string public constant name = "Thirteen Level Access Key";
    string public constant symbol = "TLAK";
    string public baseTokenURI;

    address public owner;
    address public pendingOwner;
    bool public paused;
    bool public soulboundKeys;
    uint256 private locked;

    uint256 private nextTokenId;

    mapping(uint256 => address) private tokenOwner;
    mapping(address => uint256) private ownedTokenCount;
    mapping(uint256 => address) private tokenApprovals;
    mapping(address => mapping(address => bool)) private operatorApprovals;

    mapping(uint256 => uint8) private tokenKeyLevel;
    mapping(address => mapping(uint8 => uint256)) private userLevelKey;

    struct Player {
        bool registered;
        uint8 level;
        uint256 xp;
        uint256 joinedAt;
        uint256 updatedAt;
        uint256 totalSpent;
        uint256 keysMinted;
    }

    mapping(address => Player) private players;

    mapping(uint8 => uint256) public levelPrice;
    mapping(uint8 => uint256) public levelXPRequired;
    mapping(uint8 => bool) public levelKeySaleEnabled;
    mapping(uint8 => bool) public levelRoomEnabled;
    mapping(uint8 => bool) public levelFeatureEnabled;

    mapping(address => mapping(uint8 => uint256)) private roomEnterCounter;
    mapping(address => mapping(uint8 => uint256)) private featureUseCounter;

    error NotOwner();
    error NotPendingOwner();
    error ZeroAddress();
    error Paused();
    error NotPaused();
    error Reentrant();
    error InvalidLevel();
    error AlreadyRegistered();
    error NotRegistered();
    error AlreadyAtMaxLevel();
    error SaleDisabled();
    error RoomDisabled();
    error FeatureDisabled();
    error InsufficientXP();
    error WrongPayment();
    error AccessDenied();
    error TokenMissing();
    error NotApprovedOrOwner();
    error TransferToZero();
    error ApproveToOwner();
    error Soulbound();
    error ReceiverRejected();
    error LengthMismatch();
    error WithdrawFailed();
    error DirectPaymentDisabled();

    event OwnershipTransferStarted(address indexed oldOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event PauseChanged(bool paused);
    event SoulboundChanged(bool enabled);
    event BaseURIChanged(string baseURI);
    event PlayerRegistered(address indexed player, uint8 level, uint256 xp);
    event XPAdded(address indexed player, uint256 amount, uint256 newXP);
    event PlayerLevelSet(address indexed player, uint8 oldLevel, uint8 newLevel);
    event LevelRuleSet(uint8 indexed level, uint256 price, uint256 xpRequired, bool saleEnabled);
    event LevelAccessSet(uint8 indexed level, bool roomEnabled, bool featureEnabled);
    event KeyPurchased(address indexed player, uint256 indexed tokenId, uint8 indexed level, uint256 price);
    event LevelAdvanced(address indexed player, uint8 fromLevel, uint8 toLevel, uint256 tokenId);
    event RoomEntered(address indexed player, uint8 indexed level, uint256 count);
    event FeatureUsed(address indexed player, uint8 indexed level, uint256 count);
    event Withdrawal(address indexed to, uint256 amount);

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    modifier whenPaused() {
        if (!paused) revert NotPaused();
        _;
    }

    modifier nonReentrant() {
        if (locked == 1) revert Reentrant();
        locked = 1;
        _;
        locked = 0;
    }

    modifier onlyRegistered(address account) {
        if (!players[account].registered) revert NotRegistered();
        _;
    }

    constructor() {
        owner = msg.sender;
        soulboundKeys = true;
        nextTokenId = 1;

        for (uint8 level = MIN_LEVEL; level <= MAX_LEVEL; level++) {
            levelKeySaleEnabled[level] = true;
            levelRoomEnabled[level] = true;
            levelFeatureEnabled[level] = true;
            levelPrice[level] = uint256(level - 1) * 0.01 ether;
            levelXPRequired[level] = uint256(level - 1) * 100;
        }
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, owner);
    }

    function cancelOwnershipTransfer() external onlyOwner {
        pendingOwner = address(0);
    }

    function pause() external onlyOwner whenNotPaused {
        paused = true;
        emit PauseChanged(true);
    }

    function unpause() external onlyOwner whenPaused {
        paused = false;
        emit PauseChanged(false);
    }

    function setSoulboundKeys(bool enabled) external onlyOwner {
        soulboundKeys = enabled;
        emit SoulboundChanged(enabled);
    }

    function setBaseTokenURI(string calldata newBaseURI) external onlyOwner {
        baseTokenURI = newBaseURI;
        emit BaseURIChanged(newBaseURI);
    }

    function setLevelRule(
        uint8 level,
        uint256 price,
        uint256 xpRequired,
        bool saleEnabled
    ) external onlyOwner {
        _checkLevel(level);
        levelPrice[level] = price;
        levelXPRequired[level] = xpRequired;
        levelKeySaleEnabled[level] = saleEnabled;
        emit LevelRuleSet(level, price, xpRequired, saleEnabled);
    }

    function setLevelAccess(
        uint8 level,
        bool roomEnabled,
        bool featureEnabled
    ) external onlyOwner {
        _checkLevel(level);
        levelRoomEnabled[level] = roomEnabled;
        levelFeatureEnabled[level] = featureEnabled;
        emit LevelAccessSet(level, roomEnabled, featureEnabled);
    }

    function addXP(address account, uint256 amount)
        external
        onlyOwner
        onlyRegistered(account)
    {
        Player storage p = players[account];
        p.xp += amount;
        p.updatedAt = block.timestamp;
        emit XPAdded(account, amount, p.xp);
    }

    function addXPBatch(address[] calldata accounts, uint256[] calldata amounts)
        external
        onlyOwner
    {
        if (accounts.length != amounts.length) revert LengthMismatch();

        for (uint256 i = 0; i < accounts.length; i++) {
            if (!players[accounts[i]].registered) revert NotRegistered();
            players[accounts[i]].xp += amounts[i];
            players[accounts[i]].updatedAt = block.timestamp;
            emit XPAdded(accounts[i], amounts[i], players[accounts[i]].xp);
        }
    }

    function adminSetPlayerLevel(address account, uint8 newLevel)
        external
        onlyOwner
        onlyRegistered(account)
    {
        _checkLevel(newLevel);
        Player storage p = players[account];
        uint8 oldLevel = p.level;
        p.level = newLevel;
        p.updatedAt = block.timestamp;
        emit PlayerLevelSet(account, oldLevel, newLevel);
    }

    function register() external whenNotPaused {
        if (players[msg.sender].registered) revert AlreadyRegistered();

        players[msg.sender] = Player({
            registered: true,
            level: MIN_LEVEL,
            xp: WELCOME_XP,
            joinedAt: block.timestamp,
            updatedAt: block.timestamp,
            totalSpent: 0,
            keysMinted: 0
        });

        emit PlayerRegistered(msg.sender, MIN_LEVEL, WELCOME_XP);
    }

    function getPlayer(address account)
        external
        view
        returns (
            bool registered,
            uint8 level,
            uint256 xp,
            uint256 joinedAt,
            uint256 updatedAt,
            uint256 totalSpent,
            uint256 keysMinted
        )
    {
        Player storage p = players[account];
        return (
            p.registered,
            p.level,
            p.xp,
            p.joinedAt,
            p.updatedAt,
            p.totalSpent,
            p.keysMinted
        );
    }

    function myLevel() external view returns (uint8) {
        return players[msg.sender].level;
    }

    function myXP() external view returns (uint256) {
        return players[msg.sender].xp;
    }

    function isRegistered(address account) external view returns (bool) {
        return players[account].registered;
    }

    function canBuyNextLevelKey(address account)
        external
        view
        returns (
            bool allowed,
            uint8 targetLevel,
            uint256 price,
            uint256 xpRequired
        )
    {
        Player storage p = players[account];

        if (!p.registered || p.level >= MAX_LEVEL) {
            return (false, p.level, 0, 0);
        }

        targetLevel = p.level + 1;
        price = levelPrice[targetLevel];
        xpRequired = levelXPRequired[targetLevel];
        allowed = levelKeySaleEnabled[targetLevel] && p.xp >= xpRequired;
    }

    function buyNextLevelKeyAndAdvance()
        external
        payable
        whenNotPaused
        nonReentrant
        onlyRegistered(msg.sender)
        returns (uint256 tokenId)
    {
        Player storage p = players[msg.sender];

        if (p.level >= MAX_LEVEL) revert AlreadyAtMaxLevel();

        uint8 oldLevel = p.level;
        uint8 targetLevel = oldLevel + 1;

        if (!levelKeySaleEnabled[targetLevel]) revert SaleDisabled();
        if (p.xp < levelXPRequired[targetLevel]) revert InsufficientXP();
        if (msg.value != levelPrice[targetLevel]) revert WrongPayment();

        tokenId = _mintKey(msg.sender, targetLevel);

        p.level = targetLevel;
        p.totalSpent += msg.value;
        p.keysMinted += 1;
        p.updatedAt = block.timestamp;

        emit KeyPurchased(msg.sender, tokenId, targetLevel, msg.value);
        emit LevelAdvanced(msg.sender, oldLevel, targetLevel, tokenId);
    }

    function keyLevel(uint256 tokenId) external view returns (uint8) {
        if (!_exists(tokenId)) revert TokenMissing();
        return tokenKeyLevel[tokenId];
    }

    function keyForLevel(address account, uint8 level) external view returns (uint256) {
        _checkLevel(level);
        return userLevelKey[account][level];
    }

    function hasKeyForLevel(address account, uint8 level) external view returns (bool) {
        _checkLevel(level);
        uint256 tokenId = userLevelKey[account][level];
        return tokenId != 0 && tokenOwner[tokenId] == account;
    }

    function canAccessLevel(address account, uint8 requiredLevel)
        public
        view
        returns (bool)
    {
        _checkLevel(requiredLevel);
        Player storage p = players[account];
        return p.registered && p.level >= requiredLevel;
    }

    function enterLevelRoom(uint8 level)
        external
        whenNotPaused
        onlyRegistered(msg.sender)
        returns (bool)
    {
        _checkLevel(level);
        if (!levelRoomEnabled[level]) revert RoomDisabled();
        if (players[msg.sender].level < level) revert AccessDenied();

        roomEnterCounter[msg.sender][level] += 1;
        emit RoomEntered(msg.sender, level, roomEnterCounter[msg.sender][level]);
        return true;
    }

    function useLevelFeature(uint8 level)
        external
        whenNotPaused
        onlyRegistered(msg.sender)
        returns (bool)
    {
        _checkLevel(level);
        if (!levelFeatureEnabled[level]) revert FeatureDisabled();
        if (players[msg.sender].level < level) revert AccessDenied();

        featureUseCounter[msg.sender][level] += 1;
        emit FeatureUsed(msg.sender, level, featureUseCounter[msg.sender][level]);
        return true;
    }

    function roomEnterCount(address account, uint8 level) external view returns (uint256) {
        _checkLevel(level);
        return roomEnterCounter[account][level];
    }

    function featureUseCount(address account, uint8 level) external view returns (uint256) {
        _checkLevel(level);
        return featureUseCounter[account][level];
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == ERC165_INTERFACE_ID ||
            interfaceId == ERC721_INTERFACE_ID ||
            interfaceId == ERC721_METADATA_INTERFACE_ID;
    }

    function totalSupply() external view returns (uint256) {
        return nextTokenId - 1;
    }

    function balanceOf(address account) public view returns (uint256) {
        if (account == address(0)) revert ZeroAddress();
        return ownedTokenCount[account];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address currentOwner = tokenOwner[tokenId];
        if (currentOwner == address(0)) revert TokenMissing();
        return currentOwner;
    }

    function approve(address to, uint256 tokenId) external {
        address currentOwner = ownerOf(tokenId);

        if (to == currentOwner) revert ApproveToOwner();
        if (msg.sender != currentOwner && !operatorApprovals[currentOwner][msg.sender]) {
            revert NotApprovedOrOwner();
        }

        tokenApprovals[tokenId] = to;
        emit Approval(currentOwner, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        if (!_exists(tokenId)) revert TokenMissing();
        return tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address currentOwner, address operator)
        external
        view
        returns (bool)
    {
        return operatorApprovals[currentOwner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotApprovedOrOwner();
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public {
        transferFrom(from, to, tokenId);

        if (!_checkReceiver(from, to, tokenId, data)) {
            revert ReceiverRejected();
        }
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (!_exists(tokenId)) revert TokenMissing();

        return string(
            abi.encodePacked(
                baseTokenURI,
                "level/",
                _toString(tokenKeyLevel[tokenId]),
                "/key/",
                _toString(tokenId)
            )
        );
    }

    function withdraw(address payable to, uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) amount = address(this).balance;

        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert WithdrawFailed();

        emit Withdrawal(to, amount);
    }

    receive() external payable {
        revert DirectPaymentDisabled();
    }

    function _mintKey(address to, uint8 unlockedLevel) internal returns (uint256 tokenId) {
        if (to == address(0)) revert ZeroAddress();

        tokenId = nextTokenId;
        nextTokenId += 1;

        tokenOwner[tokenId] = to;
        ownedTokenCount[to] += 1;
        tokenKeyLevel[tokenId] = unlockedLevel;

        if (userLevelKey[to][unlockedLevel] == 0) {
            userLevelKey[to][unlockedLevel] = tokenId;
        }

        emit Transfer(address(0), to, tokenId);
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return tokenOwner[tokenId] != address(0);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId)
        internal
        view
        returns (bool)
    {
        address currentOwner = tokenOwner[tokenId];
        if (currentOwner == address(0)) revert TokenMissing();

        return
            spender == currentOwner ||
            tokenApprovals[tokenId] == spender ||
            operatorApprovals[currentOwner][spender];
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        if (soulboundKeys) revert Soulbound();
        if (to == address(0)) revert TransferToZero();
        if (ownerOf(tokenId) != from) revert NotApprovedOrOwner();

        delete tokenApprovals[tokenId];

        ownedTokenCount[from] -= 1;
        ownedTokenCount[to] += 1;
        tokenOwner[tokenId] = to;

        uint8 level = tokenKeyLevel[tokenId];

        if (userLevelKey[from][level] == tokenId) {
            userLevelKey[from][level] = 0;
        }

        if (userLevelKey[to][level] == 0) {
            userLevelKey[to][level] = tokenId;
        }

        emit Transfer(from, to, tokenId);
    }

    function _checkReceiver(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal returns (bool) {
        if (to.code.length == 0) return true;

        try ILevelKeyReceiver(to).onERC721Received(
            msg.sender,
            from,
            tokenId,
            data
        ) returns (bytes4 result) {
            return result == ERC721_RECEIVED;
        } catch {
            return false;
        }
    }

    function _checkLevel(uint8 level) internal pure {
        if (level < MIN_LEVEL || level > MAX_LEVEL) revert InvalidLevel();
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;

        while (temp != 0) {
            digits += 1;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);

        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }
}