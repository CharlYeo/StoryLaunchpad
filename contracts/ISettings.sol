// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ISettings {
    struct BaseSettings {
        string name;
        string symbol;
        string baseUri;
        address owner;
    }

    struct RoyaltyFeeSettings {
        address receiver;
        uint96 feeNumerator;
    }

    struct PhaseSettings {
        string phaseName;
        uint256 maxPerWallet;
        bytes32 merkleRoot;
        uint256 price;
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 maxSupply;
    }
}