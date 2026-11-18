// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract UserStorage is Ownable2Step {
    struct Gem {
        string png_file;
        string fbx_file;
    }

    struct Level {
        uint256 id;
        string name;
        string slug;
        Gem gem;
    }

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
        Level[] levels;
    }

    mapping(string => User) public users;

    error EmptyCode();
    error InvalidUserId();
    error ZeroAddress();

    event UserAdded(string indexed code, uint256 id, string name);
    event LevelAdded(string indexed code, uint256 levelId, string name);

    constructor() Ownable(msg.sender) {}

    function addUser(
        uint256 _id, 
        string memory _name, 
        string memory _code,
        uint256[7] memory _w
    ) external onlyOwner {
        if (bytes(_code).length == 0) revert EmptyCode();
        if (_id == 0) revert InvalidUserId();

        User storage user = users[_code];
        user.id = _id;
        user.name = _name;
        user.code = _code;
        user.wallet = Wallet({
            psc: _w[0],
            blue: _w[1],
            red: _w[2],
            yellow: _w[3],
            irr: _w[4],
            satisfaction: _w[5],
            effect: _w[6]
        });

        emit UserAdded(_code, _id, _name);
    }

    function addLevel(
        string memory _code, 
        uint256 _id, 
        string memory _name, 
        string memory _slug, 
        string memory _png, 
        string memory _fbx
    ) external onlyOwner {
        if (bytes(_code).length == 0) revert EmptyCode();

        users[_code].levels.push(Level({
            id: _id,
            name: _name,
            slug: _slug,
            gem: Gem({
                png_file: _png,
                fbx_file: _fbx
            })
        }));

        emit LevelAdded(_code, _id, _name);
    }
}