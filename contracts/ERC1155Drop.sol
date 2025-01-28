// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./ISettings.sol";

contract ERC1155Drop is
    ERC1155SupplyUpgradeable,
    OwnableUpgradeable,
    ERC2981Upgradeable
{
    string public name;
    string public symbol;

    mapping(uint256 => uint256) public tokensMaxSupply;

    address public mintFeeReceiver;
    address public minterAddress;

    mapping(uint256 => ISettings.PhaseSettings[]) public tokensPhases;

    mapping(uint256 => mapping (uint256 => uint256)) private amountMintedForPhase;
    mapping(uint256 => mapping(address => mapping(uint256 => uint64))) private amountMintedPerWalletForPhase;

    uint256 public currentTokenId;

    error ExceedMaxSupply();
    error ExceedPhaseMaxSupply();
    error ExceedMaxPerWallet();
    error InvalidPrice();
    error InvalidProof();
    error PhaseNotActive();
    error InvalidPhaseTimestamp();
    error InvalidPhase();
    error InvalidAddress();

    event TokensMinted(uint256 indexed tokenId, uint256 indexed phaseIndex, address to, uint256 quantity);
    event PhaseUpdated(uint256 indexed tokenId, uint256 indexed phaseIndex, ISettings.PhaseSettings settings);
    event MintFeeReceiverUpdated(address receiver);
    event RoyaltyUpdated(address royaltyAddress, uint96 royaltyAmount);
    event BaseURIUpdated(string baseURI);

    constructor() {
        _disableInitializers();
    }

    modifier OnlyMinter() {
        require(msg.sender == minterAddress, "Caller is not a minter");
        _;
    }

    function initialize(
        ISettings.BaseSettings calldata _baseSettings,
        ISettings.PhaseSettings[] calldata _phases,
        uint256 _maxSupply,
        ISettings.RoyaltyFeeSettings calldata _royaltyFeeSettings,
        address _mintFeeReceiver
    ) public initializer {
        currentTokenId ++;
        __ERC1155_init(_baseSettings.baseUri);
        __Ownable_init(_baseSettings.owner);

        name = _baseSettings.name;
        symbol = _baseSettings.symbol;
        _updatePhases(currentTokenId ,_phases);

        tokensMaxSupply[currentTokenId] = _maxSupply;

        if (_mintFeeReceiver == address(0)) {
            revert InvalidAddress();
        } else {
            mintFeeReceiver = _mintFeeReceiver;
        }

        minterAddress = msg.sender;

        _setDefaultRoyalty(
            _royaltyFeeSettings.receiver,
            _royaltyFeeSettings.feeNumerator
        );
    }

    // ========= EXTERNAL MINTING METHODS =========
    function mint(
        address account,
        uint256 tokenId,
        uint64 quantity,
        uint32 maxQuantity,
        bytes32[] calldata proof
    ) external payable OnlyMinter{
        uint256 phaseIndex = getActivePhaseFromTimestamp(tokenId, uint64(block.timestamp));
        uint64 updatedAmountMinted = _checkPhaseMint(
            account,
            tokenId,
            quantity,
            maxQuantity,
            proof,
            phaseIndex,
            msg.value
        );

        _mintPhase(account, quantity, tokenId, phaseIndex, updatedAmountMinted);
    }

    function _checkPhaseMint(
        address account,
        uint256 tokenId,
        uint64 quantity,
        uint32 maxQuantity,
        bytes32[] calldata proof,
        uint256 phaseIndex,
        uint256 balance
    ) internal view returns (uint64) {
        ISettings.PhaseSettings memory phase = tokensPhases[tokenId][phaseIndex];

        if (totalSupply(tokenId) + quantity > tokensMaxSupply[tokenId]) 
            revert ExceedMaxSupply();

        if (phase.maxSupply > 0) {
            if (amountMintedForPhase[tokenId][phaseIndex] + quantity > phase.maxSupply) 
                revert ExceedPhaseMaxSupply();
        }

        if (balance != quantity * phase.price) 
            revert  InvalidPrice();

        if (phase.merkleRoot != bytes32(0)) {
            bool validProof = MerkleProof.verify(
                proof,
                phase.merkleRoot,
                keccak256(abi.encodePacked(account, maxQuantity))
            );
            if (!validProof) 
                revert  InvalidProof();
        }

        uint256 amountMinted = amountMintedPerWalletForPhase[tokenId][account][phaseIndex];
        uint256 updatedAmountMinted = amountMinted + quantity;

        if ((maxQuantity == 0 && phase.maxPerWallet > 0 && updatedAmountMinted > phase.maxPerWallet) || (maxQuantity > 0 && updatedAmountMinted > maxQuantity)) {
            revert ExceedMaxPerWallet();
        }

        return uint64(updatedAmountMinted);
    }

    function _mintPhase(
        address account,
        uint64 quantity,
        uint256 tokenId,
        uint256 phaseIndex,
        uint64 updatedAmountMinted
    ) internal {
        amountMintedForPhase[tokenId][phaseIndex] += quantity;
        amountMintedPerWalletForPhase[tokenId][account][phaseIndex] = updatedAmountMinted;
        if (tokensPhases[tokenId][phaseIndex].price > 0) {
            uint256 payment = quantity * tokensPhases[tokenId][phaseIndex].price;
            (bool success, ) = mintFeeReceiver.call{value: payment}("");
            require(success, "Transfer failed.");
        }
        _mint(account, tokenId, quantity, "");
        emit TokensMinted(tokenId, phaseIndex, account, quantity);
    }

    // ========= OWNER METHODS =========
    function updatePhases(
        uint256 tokenId,
        ISettings.PhaseSettings[] calldata newPhases
    ) external onlyOwner {
       _updatePhases(tokenId, newPhases);
    }
    
    function _updatePhases(
        uint256 tokenId,
        ISettings.PhaseSettings[] calldata newPhases
    ) internal {
        delete tokensPhases[tokenId];
        for (uint256 i = 0;i < newPhases.length;) {
            if (i >= 1) {
                if (
                    newPhases[i].startTimestamp < newPhases[i -1].endTimestamp
                ) {
                    revert  InvalidPhaseTimestamp();
                }
            }
            _validatePhaseTimestamp(newPhases[i].startTimestamp, newPhases[i].endTimestamp);
            tokensPhases[tokenId].push(newPhases[i]);
            emit PhaseUpdated(tokenId, i, newPhases[i]);

            unchecked {
                ++i;
            }
        }
    }

    function _validatePhaseTimestamp(
        uint256 startTimestamp,
        uint256 endTimestamp
    ) internal pure{
        if (startTimestamp >= endTimestamp) {
            revert InvalidPhaseTimestamp();
        }
    }

    function createToken(
        ISettings.PhaseSettings[] calldata _phases,
        uint256 _maxSupply
    ) external onlyOwner {
        currentTokenId ++ ;
        for (uint256 i = 0;i < _phases.length;) {
            if (i >= 1) {
                if (
                    _phases[i].startTimestamp < _phases[i -1].endTimestamp
                ) {
                    revert InvalidPhaseTimestamp();
                }
            }
            _validatePhaseTimestamp(_phases[i].startTimestamp, _phases[i].endTimestamp);
            tokensPhases[currentTokenId].push(_phases[i]);
            emit PhaseUpdated(currentTokenId, i, _phases[i]);

            unchecked {
                ++i;
            }
        }
        tokensMaxSupply[currentTokenId] += _maxSupply;
    }

    function setBaseURI(string memory baseURI) external onlyOwner {
        _setURI(baseURI);
        emit BaseURIUpdated(baseURI);
    }
    
    function setMintFeeReceiver(address receiver) external onlyOwner {
        if (receiver == address(0)) {
            revert InvalidAddress();
        }
        mintFeeReceiver = receiver;
        emit MintFeeReceiverUpdated(receiver);
    }

    function setRoyaltyInfo(
        address recipient,
        uint96 feeNumerator
    ) external onlyOwner {
        _setDefaultRoyalty(recipient, feeNumerator);
        emit RoyaltyUpdated(recipient, feeNumerator);
    }

    // ========= VIEW METHODS =========
    function uri(uint256 tokenId) public view override returns (string memory) {
        return bytes(super.uri(tokenId)).length != 0 ? string(abi.encodePacked(super.uri(tokenId), Strings.toString(tokenId), '.json')) : '';
    }

    function getNumPhases(uint256 tokenId) external view returns (uint256) {
        return tokensPhases[tokenId].length;
    }

    function getActivePhaseFromTimestamp(
        uint256 tokenId,
        uint64 timestamp
    ) public view returns(uint256) {
        ISettings.PhaseSettings[] memory phases = tokensPhases[tokenId];
        for (uint256 i = 0; i < phases.length;) {
            if (timestamp >= phases[i].startTimestamp && timestamp <= phases[i].endTimestamp) {
                return i;
            }

            unchecked {
                ++i;
            }
        }
        revert InvalidPhase();
    }

    function getAmountMintedPerWalletForPhase(
        uint256 tokenId,
        uint256 phaseIndex,
        address wallet
    ) external view returns (uint64) {
        return amountMintedPerWalletForPhase[tokenId][wallet][phaseIndex];
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC1155Upgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
