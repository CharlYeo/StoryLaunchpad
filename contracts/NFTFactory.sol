// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./ERC721Drop.sol";
import "./ERC1155Drop.sol";

contract NFTFactory is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;

    address private drop721Implementation;
    address private drop1155Implementation;

    address private signer;

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public immutable MINT_DATA_TYPEHASH;

    struct MintFeeParams {
        address minter;
        address tokenAddress;
        uint256 tokenId;
        uint256 feeAmount;
        address feeRecipient;
    }

    event ContractCreated(address creator, address owner, address contractAddress, string collectionId);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(bytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")),
                keccak256(bytes("FlowLaunchpad")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );

        MINT_DATA_TYPEHASH = keccak256(
            "MintParams(address minter,address tokenAddress,uint256 tokenId,uint256 feeAmount,address feeRecipient)"
        );
    }

    function update721Implementation(
        address newImplementation
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        drop721Implementation = newImplementation;
    }

    function update1155Implementation(
        address newImplementation
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        drop1155Implementation = newImplementation;
    }

    function updateSigner(address _signer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        signer = _signer;
    }

    function get721ImplementationAddress() external view returns (address) {
        return drop721Implementation;
    }

    function get1155ImplementationAddress() external view returns (address) {
        return drop1155Implementation;
    }

    function deploy721Drop(
        ISettings.BaseSettings calldata _baseSettings,
        ISettings.PhaseSettings[] calldata _phases,
        uint256 _maxSupply,
        ISettings.RoyaltyFeeSettings calldata _royaltyFeeSettings,
        address _mintFeeReceiver,
        string calldata _collectionId
    ) external {
        require(drop721Implementation != address(0), "Implementation not set");

        address payable clone = payable(Clones.clone(drop721Implementation));

        ERC721Drop(clone).initialize(
            _baseSettings,
            _phases,
            _maxSupply,
            _royaltyFeeSettings,
            _mintFeeReceiver
        );

        emit ContractCreated(msg.sender, _baseSettings.owner, clone, _collectionId);
    }

    function deploy1155Drop(
        ISettings.BaseSettings calldata _baseSettings,
        ISettings.PhaseSettings[] calldata _phases,
        uint256 _maxSupply,
        ISettings.RoyaltyFeeSettings calldata _royaltyFeeSettings,
        address _mintFeeReceiver,
        string calldata _collectionId
    ) external {
        require(drop1155Implementation != address(0), "Implementation not set");

        address clone = Clones.clone(drop1155Implementation);

        ERC1155Drop(clone).initialize(
            _baseSettings,
            _phases,
            _maxSupply,
            _royaltyFeeSettings,
            _mintFeeReceiver
        );

        emit ContractCreated(msg.sender, _baseSettings.owner, clone, _collectionId);
    }

    function mint721(
        address tokenAddress,
        uint64 quantity,
        uint32 maxQuantity,
        bytes32[] calldata proof,
        uint256 feeAmount,
        address feeRecipient,
        bytes calldata signature
    ) external payable nonReentrant {
        MintFeeParams memory mintFeeParams = MintFeeParams(msg.sender, tokenAddress, 0, feeAmount, feeRecipient);
        verifySignature(mintFeeParams, signature);
        sendMarketFee(feeAmount, feeRecipient);

        uint256 totalMintPrice = msg.value - feeAmount;

        ERC721Drop(tokenAddress).mint{value: totalMintPrice}(
            msg.sender,
            quantity,
            maxQuantity,
            proof
        );
    }

    function mint1155(
        address tokenAddress,
        uint256 tokenId,
        uint64 quantity,
        uint32 maxQuantity,
        bytes32[] calldata proof,
        uint256 feeAmount,
        address feeRecipient,
        bytes calldata signature
    ) external payable nonReentrant {
        MintFeeParams memory mintFeeParams = MintFeeParams(msg.sender, tokenAddress, tokenId, feeAmount, feeRecipient);
        verifySignature(mintFeeParams, signature);
        sendMarketFee(feeAmount, feeRecipient);

        uint256 totalMintPrice = msg.value - feeAmount;

        ERC1155Drop(tokenAddress).mint{value: totalMintPrice}(
            msg.sender,
            tokenId,
            quantity,
            maxQuantity,
            proof
        );
    }

    function verifySignature(
        MintFeeParams memory mintFeeParams,
        bytes calldata signature
    ) internal view {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(
                    MINT_DATA_TYPEHASH,
                    mintFeeParams.minter,
                    mintFeeParams.tokenAddress,
                    mintFeeParams.tokenId,
                    mintFeeParams.feeAmount,
                    mintFeeParams.feeRecipient
                ))
            )
        );
        address recoveredAddress = digest.recover(signature);
        require(recoveredAddress == signer, "Invalid signer");
    }

    function sendMarketFee(
        uint256 feeAmount,
        address feeRecipient
    ) internal {
        (bool success, ) = feeRecipient.call{value: feeAmount}("");
        require(success, "Transfer failed");
    }
}
