// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

contract TestContract {
    uint256 private counter;

    function current() external view returns (uint256) {
        return counter;
    }

    function increment(uint256 num) external {
        require(num <= 10, "Argument must be less then 10");
        counter += num;
    }

    function decrement(uint256 num) external {
        require(num <= 10, "Argument must be less then 10");
        counter -= num;
    }
}
