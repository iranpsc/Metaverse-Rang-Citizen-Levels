// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract LevelKeyNFT is ERC721, Ownable2Step {
    error NotMinter();
    error InvalidLevel();
    error SoulboundToken();
    error ZeroAddress();

    uint8 public constant MAX_LEVEL = 13;

    address public minter;
    uint256 private nextTokenId = 1;
    string private baseTokenURI;

    mapping(uint256 => uint8) public tokenLevel;

    event MinterChanged(address indexed oldMinter, address indexed newMinter);
    event LevelKeyMinted(address indexed to, uint8 indexed level, uint256 indexed tokenId);

    constructor(string memory _baseTokenURI)
        ERC721("Thirteen Level Key", "TLKEY")
        Ownable(msg.sender)
    {
        baseTokenURI = _baseTokenURI;
    }

    modifier onlyMinter() {
        if (msg.sender != minter) revert NotMinter();
        _;
    }

    function setMinter(address _minter) external onlyOwner {
        if (_minter == address(0)) revert ZeroAddress();
        address oldMinter = minter;
        minter = _minter;
        emit MinterChanged(oldMinter, _minter);
    }

    function setBaseURI(string calldata _baseTokenURI) external onlyOwner {
        baseTokenURI = _baseTokenURI;
    }

    function mintLevelKey(address to, uint8 level) external onlyMinter returns (uint256 tokenId) {
        if (level == 0 || level > MAX_LEVEL) revert InvalidLevel();

        tokenId = nextTokenId++;
        tokenLevel[tokenId] = level;

        _safeMint(to, tokenId);

        emit LevelKeyMinted(to, level, tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    // Soulbound logic using OpenZeppelin v5 _update hook:
    // Minting (from address(0)) and burning (to address(0)) are allowed, but wallet-to-wallet transfers are reverted.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);

        if (from != address(0) && to != address(0)) {
            revert SoulboundToken();
        }

        return super._update(to, tokenId, auth);
    }
}