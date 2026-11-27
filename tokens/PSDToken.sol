// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PSDToken
 * @notice Standalone ERC-20 token for MetaRang Multiverse with a hard cap of 2,000,000,000 PSD.
 * @dev Implements OpenZeppelin v5 compatible ERC20, Burnable, Pausable, and Role-Based Access Control
 *      with zero external imports for offline Remix and Hardhat compilation.
 *      Supports zero initial mint so the token can be deployed before official liquidity/supply launch.
 */
contract PSDToken {
    // ------------------------------------------------------------
    // Constants & Roles
    // ------------------------------------------------------------
    string public constant name = "MetaRang PSD";
    string public constant symbol = "PSD";
    uint8 public constant decimals = 18;

    /// @notice Hard supply cap updated per specification: 2,000,000,000 PSD
    uint256 public constant MAX_SUPPLY = 2_000_000_000 * 10 ** 18;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------
    uint256 private _totalSupply;
    bool private _paused;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(bytes32 => mapping(address => bool)) private _roles;

    // ------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------
    error ZeroAddress();
    error CapExceeded(uint256 requestedTotal, uint256 maxSupply);
    error EnforcedPause();
    error ExpectedPause();
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error AccessControlBadConfirmation();
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);

    // ------------------------------------------------------------
    // Events
    // ------------------------------------------------------------
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Paused(address account);
    event Unpaused(address account);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    // ------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------
    modifier onlyRole(bytes32 role) {
        if (!_roles[role][msg.sender]) {
            revert AccessControlUnauthorizedAccount(msg.sender, role);
        }
        _;
    }

    modifier whenNotPaused() {
        if (_paused) revert EnforcedPause();
        _;
    }

    modifier whenPaused() {
        if (!_paused) revert ExpectedPause();
        _;
    }

    /**
     * @param admin_ Governance admin address (Gnosis Safe 2-of-3 on Arbitrum One).
     * @param initialMintTo_ Recipient of initial supply (can be address(0) when initialMintAmount_ == 0).
     * @param initialMintAmount_ Initial minted amount in wei (pass 0 to deploy with zero circulating supply).
     */
    constructor(address admin_, address initialMintTo_, uint256 initialMintAmount_) {
        if (admin_ == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);

        if (initialMintAmount_ > 0) {
            if (initialMintTo_ == address(0)) revert ZeroAddress();
            _mint(initialMintTo_, initialMintAmount_);
        }
    }

    // ------------------------------------------------------------
    // ERC-20 View Functions
    // ------------------------------------------------------------
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function paused() external view returns (bool) {
        return _paused;
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return _roles[role][account];
    }

    // ------------------------------------------------------------
    // ERC-20 Core Functions
    // ------------------------------------------------------------
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value, true);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        return true;
    }

    // ------------------------------------------------------------
    // Supply Management (Capped Mint & Burn)
    // ------------------------------------------------------------
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }

    function burnFrom(address account, uint256 value) external {
        _spendAllowance(account, msg.sender, value);
        _burn(account, value);
    }

    // ------------------------------------------------------------
    // Role & Emergency Administration
    // ------------------------------------------------------------
    function grantRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address callerConfirmation) external {
        if (callerConfirmation != msg.sender) revert AccessControlBadConfirmation();
        _revokeRole(role, callerConfirmation);
    }

    function pause() external onlyRole(PAUSER_ROLE) whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyRole(PAUSER_ROLE) whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    // ------------------------------------------------------------
    // Internal Helpers
    // ------------------------------------------------------------
    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) revert ERC20InvalidSender(address(0));
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        _update(from, to, value);
    }

    function _mint(address account, uint256 value) internal {
        if (account == address(0)) revert ERC20InvalidReceiver(address(0));
        uint256 newTotal = _totalSupply + value;
        if (newTotal > MAX_SUPPLY) revert CapExceeded(newTotal, MAX_SUPPLY);
        _update(address(0), account, value);
    }

    function _burn(address account, uint256 value) internal {
        if (account == address(0)) revert ERC20InvalidSender(address(0));
        _update(account, address(0), value);
    }

    function _update(address from, address to, uint256 value) internal whenNotPaused {
        if (from == address(0)) {
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                _balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                _totalSupply -= value;
            }
        } else {
            unchecked {
                _balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal {
        if (owner == address(0)) revert ERC20InvalidApprover(address(0));
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }

    function _grantRole(bytes32 role, address account) internal {
        if (!_roles[role][account]) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function _revokeRole(bytes32 role, address account) internal {
        if (_roles[role][account]) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }
}
