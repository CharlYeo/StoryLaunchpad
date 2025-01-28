import { ethers, network } from "hardhat";


describe("ERC1155Drop", function () {
    it("Deploy & Mint", async function () {
        const [factoryOwner, erc721Owner, minter] = await ethers.getSigners();

        const NFTFactory = await ethers.getContractFactory("NFTFactory");
        const nftFactory = await NFTFactory.deploy();

        const ERC1155DropImplementation = await ethers.getContractFactory("ERC1155Drop");
        const erc1155DropImplementation = await ERC1155DropImplementation.deploy();
        await nftFactory.update1155Implementation(await erc1155DropImplementation.getAddress());
        await nftFactory.updateMarketFee({
            receiver: factoryOwner.address,
            feePerMint: '100000000000000000'
        })

        const baseSettings = {
            name: "erc1155测试aaaabbb",
            symbol: "erc1155测试aaaabbb",
            baseUri: "ipfs://bafybeicjqcogrntaz656fyphhhfnsepdtz27geqja3hviou6cbwhtt6pfi",
            owner: '0x52b25BbCa381674Fc6bC312f6c96AC5563Fc495A'
        }

        const phases = [{ "maxPerWallet": "2", "merkleRoot": "0xc9c8552a32fffe3133c754c9786fc68071a68616591731504666185a132f8da4", "price": "100000000000000000", "startTimestamp": 1726560900, "endTimestamp": 1726561500, "maxSupply": 0 }, { "maxPerWallet": "2", "merkleRoot": "0x3f13bd1f51964f709b58198664684798df2009a73f0b7be926c55c3de23b6018", "price": "100000000000000000", "startTimestamp": 1726561500, "endTimestamp": 1726562400, "maxSupply": 0 }, { "maxPerWallet": "2", "merkleRoot": "0x3f13bd1f51964f709b58198664684798df2009a73f0b7be926c55c3de23b6018", "price": "100000000000000000", "startTimestamp": 1726562400, "endTimestamp": 1726563600, "maxSupply": 0 }]

        const setMaxSupply = 1;


        const royaltyFeeSettings = {
            receiver: '0x52b25BbCa381674Fc6bC312f6c96AC5563Fc495A',
            feeNumerator: 0,
        }

        const mintFeeReceiver = erc721Owner.address;


        const tx = await nftFactory.deploy1155Drop(baseSettings, phases, setMaxSupply, royaltyFeeSettings, '0x52b25BbCa381674Fc6bC312f6c96AC5563Fc495A', '66e93de22bc2a510b68571b8');
        const receipt = await tx.wait();

        console.log(receipt);
        // const iface = new ethers.Interface([`event ContractCreated(address creator, address owner, address contractAddress)`]);

        // const parsedLog = iface.parseLog(receipt!.logs[3]);

        // const erc1155DropAddress = parsedLog!.args['contractAddress'];

        // const erc1155Drop = new ethers.Contract(erc1155DropAddress, ERC1155DropImplementation.interface, ERC1155DropImplementation.runner)

        // const name = await erc1155Drop.name();
        // const symbol = await erc1155Drop.symbol();
        // const maxSupply = await erc1155Drop.tokensMaxSupply(0);

        // const mintTx = await erc1155Drop.connect(minter).mint(0, 2, 0, [], {
        //     value: '400000000000000000'
        // })

        // const mintReceipt = await mintTx.wait();
        // console.log(mintReceipt.logs[1])

        // const royaltyInfo = await erc1155Drop.royaltyInfo(1, '100000000000000000');
        // const totalSupply = await erc1155Drop['totalSupply(uint256)'](0);
        // console.log(name, symbol, maxSupply, royaltyInfo, totalSupply)

        // console.log(await ethers.provider.getBalance(factoryOwner))
        // console.log(await ethers.provider.getBalance(erc721Owner.address))
    })
})