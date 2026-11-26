// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../governance/HadETasarEngine.sol";

contract MockCitizenshipLevelProvider is ICitizenshipLevelProvider {
    mapping(address => uint8) private _levels;

    function setLevel(address user, uint8 level) external {
        _levels[user] = level;
    }

    function getCitizenLevel(address user) external view override returns (uint8) {
        return _levels[user];
    }
}