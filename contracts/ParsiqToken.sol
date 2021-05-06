// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract ParsiqToken is IERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant TOTAL_CAP = 500000000 * 10**18;
    uint256 private constant MAX_UINT256 = ~uint256(0);
    string public constant name = "Parsiq Token";
    string public constant symbol = "PRQ";
    uint8 public constant decimals = 18;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;
    mapping(address => uint256) public reviewPeriods;
    mapping(address => uint256) public decisionPeriods;
    mapping(address => bool) public bridges;
    uint256 public reviewPeriod = 86400; // 1 day
    uint256 public decisionPeriod = 86400; // 1 day after review period
    uint256 public cap = 310256872 * 10**18; // 500 000 000 - 189 743 128 (retention wallet at 25.02.2021)
    address public governanceBoard;
    address public pendingGovernanceBoard;
    bool public paused = false;

    event Paused();
    event Unpaused();
    event Reviewing(address indexed account, uint256 reviewUntil, uint256 decideUntil);
    event Resolved(address indexed account);
    event ReviewPeriodChanged(uint256 reviewPeriod);
    event DecisionPeriodChanged(uint256 decisionPeriod);
    event GovernanceBoardChanged(address indexed from, address indexed to);
    event GovernedTransfer(address indexed from, address indexed to, uint256 amount);
    event BridgeAdded(address indexed bridge);
    event BridgeRemoved(address indexed bridge);
    event CapChanged(uint256 amount);

    modifier whenNotPaused() {
        require(!paused || msg.sender == governanceBoard, "Pausable: paused");
        _;
    }

    modifier onlyGovernanceBoard() {
        require(msg.sender == governanceBoard, "Sender is not governance board");
        _;
    }

    modifier onlyPendingGovernanceBoard() {
        require(msg.sender == pendingGovernanceBoard, "Sender is not the pending governance board");
        _;
    }

    modifier onlyResolved(address account) {
        require(decisionPeriods[account] < block.timestamp, "Account is being reviewed");
        _;
    }

    modifier onlyBridge() {
        require(bridges[msg.sender] == true, "Not a bridge");
        _;
    }

    constructor() {
        _setGovernanceBoard(msg.sender);

        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    function pause() public onlyGovernanceBoard {
        require(!paused, "Pausable: paused");
        paused = true;
        emit Paused();
    }

    function unpause() public onlyGovernanceBoard {
        require(paused, "Pausable: unpaused");
        paused = false;
        emit Unpaused();
    }

    function review(address account) public onlyGovernanceBoard {
        _review(account);
    }

    function resolve(address account) public onlyGovernanceBoard {
        _resolve(account);
    }

    function electGovernanceBoard(address newGovernanceBoard) public onlyGovernanceBoard {
        pendingGovernanceBoard = newGovernanceBoard;
    }

    function takeGovernance() public onlyPendingGovernanceBoard {
        _setGovernanceBoard(pendingGovernanceBoard);
        pendingGovernanceBoard = address(0);
    }

    function _setGovernanceBoard(address newGovernanceBoard) internal {
        emit GovernanceBoardChanged(governanceBoard, newGovernanceBoard);
        governanceBoard = newGovernanceBoard;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount)
        public
        override
        onlyResolved(msg.sender)
        onlyResolved(recipient)
        whenNotPaused
        returns (bool)
    {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount)
        public
        override
        onlyResolved(msg.sender)
        onlyResolved(spender)
        whenNotPaused
        returns (bool)
    {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20};
     *
     * Requirements:
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        public
        override
        onlyResolved(msg.sender)
        onlyResolved(sender)
        onlyResolved(recipient)
        whenNotPaused
        returns (bool)
    {
        _transfer(sender, recipient, amount);
        if (_allowances[sender][msg.sender] < MAX_UINT256) {
            // treat MAX_UINT256 approve as infinite approval
            _approve(
                sender,
                msg.sender,
                _allowances[sender][msg.sender].sub(amount, "ERC20: transfer amount exceeds allowance")
            );
        }
        return true;
    }

    /**
     * @dev Allows governance board to transfer funds.
     *
     * This allows to transfer tokens after review period have elapsed,
     * but before decision period is expired. So, basically governanceBoard have a time-window
     * to move tokens from reviewed account.
     * After decision period have been expired remaining tokens are unlocked.
     */
    function governedTransfer(
        address from,
        address to,
        uint256 value
    ) public onlyGovernanceBoard returns (bool) {
        require(block.timestamp > reviewPeriods[from], "Review period is not elapsed");
        require(block.timestamp <= decisionPeriods[from], "Decision period expired");

        _transfer(from, to, value);
        emit GovernedTransfer(from, to, value);
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue)
        public
        onlyResolved(msg.sender)
        onlyResolved(spender)
        whenNotPaused
        returns (bool)
    {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        onlyResolved(msg.sender)
        onlyResolved(spender)
        whenNotPaused
        returns (bool)
    {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender].sub(subtractedValue, "ERC20: decreased allowance below zero")
        );
        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) public onlyResolved(msg.sender) whenNotPaused {
        _burn(msg.sender, amount);
    }

    function transferMany(address[] calldata recipients, uint256[] calldata amounts)
        external
        onlyResolved(msg.sender)
        whenNotPaused
    {
        require(recipients.length == amounts.length, "ParsiqToken: Wrong array length");

        uint256 total = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            total = total.add(amounts[i]);
        }

        _balances[msg.sender] = _balances[msg.sender].sub(total, "ERC20: transfer amount exceeds balance");

        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint256 amount = amounts[i];
            require(recipient != address(0), "ERC20: transfer to the zero address");
            require(decisionPeriods[recipient] < block.timestamp, "Account is being reviewed");

            _balances[recipient] = _balances[recipient].add(amount);
            emit Transfer(msg.sender, recipient, amount);
        }
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // Need to unwrap modifiers to eliminate Stack too deep error
        require(decisionPeriods[owner] < block.timestamp, "Account is being reviewed");
        require(decisionPeriods[spender] < block.timestamp, "Account is being reviewed");
        require(!paused || msg.sender == governanceBoard, "Pausable: paused");
        require(deadline >= block.timestamp, "ParsiqToken: EXPIRED");
        bytes32 digest =
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
                )
            );

        address recoveredAddress = ecrecover(digest, v, r, s);

        require(recoveredAddress != address(0) && recoveredAddress == owner, "ParsiqToken: INVALID_SIGNATURE");
        _approve(owner, spender, value);
    }

    function setReviewPeriod(uint256 _reviewPeriod) public onlyGovernanceBoard {
        reviewPeriod = _reviewPeriod;
        emit ReviewPeriodChanged(reviewPeriod);
    }

    function setDecisionPeriod(uint256 _decisionPeriod) public onlyGovernanceBoard {
        decisionPeriod = _decisionPeriod;
        emit DecisionPeriodChanged(decisionPeriod);
    }

    function recoverTokens(
        IERC20 token,
        address to,
        uint256 amount
    ) public onlyGovernanceBoard {
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "ERC20: Insufficient balance");
        token.safeTransfer(to, amount);
    }

    function mint(address account, uint256 amount) public whenNotPaused onlyBridge {
        require(_totalSupply.add(amount) <= cap, "Exceeds cap");

        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external whenNotPaused onlyBridge {
        _burn(account, amount);
    }

    function authorizeBridge(address _bridge) public onlyGovernanceBoard {
        bridges[_bridge] = true;
        emit BridgeAdded(_bridge);
    }

    function deauthorizeBridge(address _bridge) public onlyGovernanceBoard {
        bridges[_bridge] = false;
        emit BridgeRemoved(_bridge);
    }

    function setCap(uint256 _cap) public onlyGovernanceBoard {
        require(_cap <= TOTAL_CAP, "Exceeds total cap");
        cap = _cap;
        emit CapChanged(_cap);
    }

    function _review(address account) internal {
        uint256 reviewUntil = block.timestamp.add(reviewPeriod);
        uint256 decideUntil = block.timestamp.add(reviewPeriod.add(decisionPeriod));
        reviewPeriods[account] = reviewUntil;
        decisionPeriods[account] = decideUntil;
        emit Reviewing(account, reviewUntil, decideUntil);
    }

    function _resolve(address account) internal {
        reviewPeriods[account] = 0;
        decisionPeriods[account] = 0;
        emit Resolved(account);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }
}
