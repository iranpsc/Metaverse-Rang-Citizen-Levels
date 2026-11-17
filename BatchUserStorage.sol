// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract BatchUserStorage is Ownable2Step {
    struct Wallet { 
        uint256 psc; 
        uint256 blue; 
        uint256 red; 
        uint256 yellow; 
        uint256 irr; 
        uint256 satisfaction; 
        uint256 effect; 
    }
    
    struct User { 
        uint256 id; 
        string name; 
        string code; 
        Wallet wallet; 
    }

    mapping(string => User) public users;

    error LengthMismatch();
    error EmptyArray();
    error InvalidUserData();

    event UsersBatchAdded(uint256 count);

    constructor() Ownable(msg.sender) {}

    function addUsersBatch(
        uint256[] calldata _ids, 
        string[] calldata _names, 
        string[] calldata _codes,
        uint256[] calldata _wallets 
    ) external onlyOwner {
        uint256 len = _ids.length;
        if (len == 0) revert EmptyArray();
        if (len != _names.length || len != _codes.length || _wallets.length != len * 7) {
            revert LengthMismatch();
        }

        for (uint256 i = 0; i < len; ) {
            if (_ids[i] == 0) revert InvalidUserData();

            users[_codes[i]] = User({
                id: _ids[i],
                name: _names[i],
                code: _codes[i],
                wallet: Wallet({
                    psc: _wallets[i * 7],
                    blue: _wallets[i * 7 + 1],
                    red: _wallets[i * 7 + 2],
                    yellow: _wallets[i * 7 + 3],
                    irr: _wallets[i * 7 + 4],
                    satisfaction: _wallets[i * 7 + 5],
                    effect: _wallets[i * 7 + 6]
                })
            });

            unchecked { ++i; }
        }

        emit UsersBatchAdded(len);
    }
}