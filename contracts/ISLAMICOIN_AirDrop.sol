// SPDX-License-Identifier: MIT



pragma solidity ^0.8.4;

contract ISLAMICOIN_AirDrop {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}