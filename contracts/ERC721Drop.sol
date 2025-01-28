// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "erc721a-upgradeable/contracts/extensions/ERC721AQueryableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./ISettings.sol";

contract ERC721Drop is
    ERC721AQueryableUpgradeable,
    OwnableUpgradeable,
    ERC2981Upgradeable
{
    string public baseTokenURI;

    uint256 public maxSupply;

    address public mintFeeReceiver;
    address public minterAddress;

    ISettings.PhaseSettings[] public phases;

    mapping(uint256 => uint256) private amountMintedForPhase;
    mapping(address => mapping(uint256 => uint64)) private amountMintedPerWalletForPhase;

    error ExceedMaxSupply();
    error ExceedPhaseMaxSupply();
    error ExceedMaxPerWallet();
    error InvalidPrice();
    error InvalidProof();
    error PhaseNotActive();
    error InvalidPhaseTimestamp();
    error InvalidPhase();
    error InvalidAddress();
    
    event TokensMinted(uint256 indexed phaseIndex, address to, uint256 quantity);
    event PhaseUpdated(uint256 indexed phaseIndex, ISettings.PhaseSettings settings);
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
        ISettings.RoyaltyFeeSettings calldata _royaltyFee,
        address _mintFeeReceiver
    ) public initializerERC721A initializer {
        __ERC721A_init(_baseSettings.name, _baseSettings.symbol);
        __Ownable_init(_baseSettings.owner);
        
        _updatePhases(_phases);

        maxSupply = _maxSupply;

        if (_mintFeeReceiver == address(0)) {
            revert InvalidAddress();
        } else {
            mintFeeReceiver = _mintFeeReceiver;
        }

        baseTokenURI = _baseSettings.baseUri;

        minterAddress = msg.sender;

        _setDefaultRoyalty(
            _royaltyFee.receiver,
            _royaltyFee.feeNumerator
        );
    }

    // ========= EXTERNAL MINTING METHODS =========
    function mint(
        address account,
        uint64 quantity,
        uint32 maxQuantity,
        bytes32[] calldata proof
    ) external payable OnlyMinter {
        uint256 phaseIndex = getActivePhaseFromTimestamp(uint64(block.timestamp));
        uint64 updatedAmountMinted = _checkPhaseMint(
            account,
            quantity,
            maxQuantity,
            proof,
            phaseIndex,
            msg.value
        );

        _mintPhase(account, quantity, phaseIndex, updatedAmountMinted);
    }

    function _checkPhaseMint(
        address account,
        uint64 quantity,
        uint32 maxQuantity,
        bytes32[] calldata proof,
        uint256 phaseIndex,
        uint256 balance
    ) internal view returns (uint64) {
        ISettings.PhaseSettings memory phase = phases[phaseIndex];

        if (totalSupply() + quantity > maxSupply) 
            revert ExceedMaxSupply();

        if (phase.maxSupply > 0) {
            if (amountMintedForPhase[phaseIndex] + quantity > phase.maxSupply) 
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

        uint256 amountMinted = amountMintedPerWalletForPhase[account][phaseIndex];
        uint256 updatedAmountMinted = amountMinted + quantity;

        if ((maxQuantity == 0 && phase.maxPerWallet > 0 && updatedAmountMinted > phase.maxPerWallet) || (maxQuantity > 0 && updatedAmountMinted > maxQuantity)) {
            revert  ExceedMaxPerWallet();
        }

        return uint64(updatedAmountMinted);
    }

    function _mintPhase(
        address account,
        uint64 quantity,
        uint256 phaseIndex,
        uint64 updatedAmountMinted
    ) internal {
        amountMintedForPhase[phaseIndex] += quantity;
        amountMintedPerWalletForPhase[account][phaseIndex] = updatedAmountMinted;
        if (phases[phaseIndex].price > 0) {
            uint256 payment = quantity * phases[phaseIndex].price;
            (bool success, ) = mintFeeReceiver.call{value: payment}("");
            require(success, "Transfer failed.");
        }
        _mint(account, quantity);
        emit TokensMinted(phaseIndex, account, quantity);
    }

    function updatePhases(
        ISettings.PhaseSettings[] calldata newPhases
    ) external onlyOwner {
        _updatePhases(newPhases);
    }

    function _updatePhases(
        ISettings.PhaseSettings[] calldata newPhases
    ) internal {
        delete phases;
        for (uint256 i = 0;i < newPhases.length;) {
            if (i >= 1) {
                if (
                    newPhases[i].startTimestamp < newPhases[i -1].endTimestamp
                ) {
                    revert  InvalidPhaseTimestamp();
                }
            }
            _validatePhaseTimestamp(newPhases[i].startTimestamp, newPhases[i].endTimestamp);
            phases.push(newPhases[i]);
            emit PhaseUpdated(i, newPhases[i]);

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

    function setBaseURI(string memory baseURI) external onlyOwner {
        baseTokenURI = baseURI;
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
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
        emit RoyaltyUpdated(receiver, feeNumerator);
    }

    // ========= VIEW METHODS =========
    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function tokenURI(uint256 tokenId) public view virtual override(ERC721AUpgradeable, IERC721AUpgradeable) returns (string memory) {
        if (!_exists(tokenId)) _revert(URIQueryForNonexistentToken.selector);
        return bytes(baseTokenURI).length != 0 ? string(abi.encodePacked(baseTokenURI, _toString(tokenId), '.json')) : '';
    }

    function getNumPhases() external view returns (uint256) {
        return phases.length;
    }

    function getActivePhaseFromTimestamp(
        uint64 timestamp
    ) public view returns(uint256) {
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
        uint256 phaseIndex,
        address wallet
    ) external view returns (uint64) {
        return amountMintedPerWalletForPhase[wallet][phaseIndex];
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(IERC721AUpgradeable, ERC721AUpgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return
            ERC721AUpgradeable.supportsInterface(interfaceId) ||
            ERC2981Upgradeable.supportsInterface(interfaceId);
    }
}
