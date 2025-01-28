import { ethers, network } from "hardhat";


describe("ERC721Drop", function () {
    it("Deploy & Mint", async function () {
        const [erc721Owner, minter, signer, feeRecipient] = await ethers.getSigners();

        const NFTFactory = await ethers.getContractFactory("NFTFactory");
        const nftFactory = await NFTFactory.deploy();

        const ERC721DropImplementation = await ethers.getContractFactory("ERC721Drop");
        const erc721DropImplementation = await ERC721DropImplementation.deploy();
        await nftFactory.update721Implementation(await erc721DropImplementation.getAddress());
        await nftFactory.updateSigner(signer.address);
        const baseSettings = {
            name: "TEST",
            symbol: "test",
            baseUri: "http://test.io/",
            owner: erc721Owner.address
        }

        const phases = [
            {
                maxPerWallet: 3,
                merkleRoot: '0x0000000000000000000000000000000000000000000000000000000000000000',
                price: '100000000000000000',//0.1 eth
                startTimestamp: Math.floor(Date.now() / 1000),
                endTimestamp: Math.floor(Date.now() / 1000) + 10,
                maxSupply: 3,
                phaseName: 'public'
            }
        ]

        const setMaxSupply = 3;

        const royaltyFeeSettings = {
            receiver: erc721Owner.address,
            feeNumerator: 1000,
        }

        const mintFeeReceiver = erc721Owner.address;

        const tx = await nftFactory.deploy721Drop(baseSettings, phases, setMaxSupply, royaltyFeeSettings, mintFeeReceiver, 'collectionId');
        const receipt = await tx.wait();

        const nftFactoryAddress = await nftFactory.getAddress();
        const iface = new ethers.Interface([`event ContractCreated(address creator, address owner, address contractAddress, string collectionId)`]);

        const parsedLog = iface.parseLog(receipt!.logs[3]);

        const erc721DropAddress = parsedLog!.args['contractAddress'];

        const domain = {
            name: 'FlowLaunchpad',
            version: '1',
            chainId: network.config.chainId,
            verifyingContract: nftFactoryAddress
        }
        const types = {
            MintParams: [
                { name: 'minter', type: 'address' },
                { name: 'tokenAddress', type: 'address' },
                { name: 'tokenId', type: 'uint256' },
                { name: 'feeAmount', type: 'uint256' },
                { name: 'feeRecipient', type: 'address' },
            ],
        }
        const mintParams = {
            minter: minter.address,
            tokenAddress: erc721DropAddress,
            tokenId: '0',
            feeAmount: '3000000000000000000',
            feeRecipient: feeRecipient.address,
        }

        const signature = await signer.signTypedData(domain, types, mintParams);
        const mintTx = await nftFactory.connect(minter).mint721(erc721DropAddress, 1, 0, [], '3000000000000000000', feeRecipient.address, signature, {
            value: '3100000000000000000'
        })
        await mintTx.wait();
        console.log(await ethers.provider.getBalance(feeRecipient.address))
        console.log(await ethers.provider.getBalance(erc721Owner.address))

    })
})