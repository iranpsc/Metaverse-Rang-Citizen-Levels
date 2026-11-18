// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract MerkleWhitelist is Ownable2Step {
    bytes32 public merkleRoot;

    mapping(address => bool) public claimed;

    error NotWhitelisted();
    error AlreadyClaimed();
    error InvalidMerkleRoot();

    event MerkleRootUpdated(bytes32 indexed root);
    event Claimed(address indexed user);

    constructor(bytes32 _root) Ownable(msg.sender) {
        if (_root == bytes32(0)) revert InvalidMerkleRoot();
        merkleRoot = _root;
    }

    // =========================
    // ADMIN
    // =========================

    function setMerkleRoot(bytes32 _root) external onlyOwner {
        if (_root == bytes32(0)) revert InvalidMerkleRoot();
        merkleRoot = _root;
        emit MerkleRootUpdated(_root);
    }

    // =========================
    // VERIFY
    // =========================

    function isWhitelisted(
        address user,
        bytes32[] calldata proof
    ) external view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(user));
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }

    // =========================
    // CLAIM / REGISTER GATE
    // =========================

    function claim(bytes32[] calldata proof) external {
        if (claimed[msg.sender]) revert AlreadyClaimed();

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        bool ok = MerkleProof.verify(proof, merkleRoot, leaf);

        if (!ok) revert NotWhitelisted();

        claimed[msg.sender] = true;

        emit Claimed(msg.sender);
    }
}