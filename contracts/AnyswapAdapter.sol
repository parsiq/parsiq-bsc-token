// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "./IParsiqToken.sol";

contract AnyswapAdapter {
    IParsiqToken public immutable token;

    event LogSwapin(bytes32 indexed txhash, address indexed account, uint256 amount);
    event LogSwapout(address indexed account, address indexed bindaddr, uint256 amount);
    event LogChangeMPCOwner(address indexed oldOwner, address indexed newOwner, uint256 indexed effectiveHeight);

    address private _oldOwner;
    address private _newOwner;
    uint256 private _newOwnerEffectiveHeight;

    modifier onlyOwner() {
        require(msg.sender == owner(), "only owner");
        _;
    }

    constructor(IParsiqToken _token) {
        token = _token;
        _newOwner = msg.sender;
        _newOwnerEffectiveHeight = block.number;
    }

    function owner() public view returns (address) {
        if (block.number >= _newOwnerEffectiveHeight) {
            return _newOwner;
        }
        return _oldOwner;
    }

    function Swapin(
        bytes32 txhash,
        address account,
        uint256 amount
    ) public onlyOwner returns (bool) {
        token.mint(account, amount);
        emit LogSwapin(txhash, account, amount);
        return true;
    }

    function Swapout(uint256 amount, address bindaddr) public returns (bool) {
        require(bindaddr != address(0), "bind address is the zero address");
        token.burn(msg.sender, amount);
        emit LogSwapout(msg.sender, bindaddr, amount);
        return true;
    }

    function changeMPCOwner(address newOwner) public onlyOwner returns (bool) {
        require(newOwner != address(0), "AnyswapV3ERC20: address(0x0)");
        _oldOwner = owner();
        _newOwner = newOwner;
        _newOwnerEffectiveHeight = block.number + 13300;
        emit LogChangeMPCOwner(_oldOwner, _newOwner, _newOwnerEffectiveHeight);
        return true;
    }
}
