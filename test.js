const { Account } = require("@tonclient/appkit");
const { TonClient, signerKeys, builderOpBitString, builderOpInteger} = require("@tonclient/core");
const { libNode } = require("@tonclient/lib-node");
const deepEqual = require('deep-equal');

TonClient.useBinaryLibrary(libNode);

const { RootContract } = require("./artifacts/RootContract")
const { ProxyContract } = require("./artifacts/ProxyContract")
const { ChildrenV1Contract } = require("./artifacts/ChildrenV1Contract")
const { ChildrenV2Contract } = require("./artifacts/ChildrenV2Contract")

const client = new TonClient({
    network: {
        // Local TON OS SE instance URL here
        endpoints: [ "http://localhost" ]
    }
});


async function main(client) {
    try {
        const keys = await TonClient.default.crypto.generate_random_sign_keys();
        const сhildren1_keys = await TonClient.default.crypto.generate_random_sign_keys();
        const сhildren2_keys = await TonClient.default.crypto.generate_random_sign_keys();

        let response;

        //deploy root
        const rootContract = new Account(RootContract, {
            signer: signerKeys(keys),
            client,
            initData: {},
        });
        const rootAddress = await rootContract.getAddress();

        await rootContract.deploy({useGiver: true, initInput: {
                _proxyCode: ProxyContract.code,
                _childrenCode: ChildrenV1Contract.code,
                _childrenVersion: 1,
            }})
        console.log(`root contract deployed at address: ${rootAddress}`);

        //check root static variables correct.
        response = await rootContract.runLocal("childrenCode", {});
        assert(response.decoded.output.childrenCode === ChildrenV1Contract.code);
        response = await rootContract.runLocal("proxyCode", {});
        assert(response.decoded.output.proxyCode === ProxyContract.code);
        response = await rootContract.runLocal("childrenVersion", {});
        assert(response.decoded.output.childrenVersion === '1');


        //deploy children v1
        let initialBalancesMap = getInitialBalances(rootAddress);
        let initialLastHashes = getInitialLastHashes();
        await rootContract.run("deployChildren", {
            _initialBalances: initialBalancesMap,
            _lastHashes: initialLastHashes,
            _public_key: `0x${сhildren1_keys.public}`
        }, {});


        //Calculate off-chain children v1 address by proxy abi.
        let childrenAddress = await getAddressOfChildrenContract(сhildren1_keys, rootAddress);

        //init childrenV1 by address calculated by proxy
        let childrenV1Contract = new Account(ChildrenV1Contract, {
            signer: signerKeys(сhildren1_keys),
            address: childrenAddress,
            client
        })

        //contract deployed
        assert(parseInt(await childrenV1Contract.getBalance(), 16) > 2_500_000_000, "Contract must be deployed");
        console.log("Children deployed on address", childrenAddress);

        //all fields has true values
        assert(await getPublic(childrenV1Contract,"proxyCode") === ProxyContract.code, "Must be equal");
        assert(await getPublic(childrenV1Contract,"childrenVersion") === "1", "Must be equal");
        assert(await getPublic(childrenV1Contract,"root") === rootAddress, "Must be equal");
        assert(deepEqual(await getPublic(childrenV1Contract,"balances"), initialBalancesMap), "Must be equal");
        assert(deepEqual(await getPublic(childrenV1Contract,"lastHashes"), initialLastHashes), "Must be equal");


        //upgrade code in the root to V2
        await rootContract.run("setNewCode", {
            _newCode: ChildrenV2Contract.code,
            _newVersion: 2
        }, {});


        //Request upgrade children to v2
        await childrenV1Contract.run("requestCodeUpgrade", {})

        let childrenV2Contract = new Account(ChildrenV2Contract, {
            signer: signerKeys(сhildren1_keys),
            address: childrenAddress,
            client
        })

        //check all fields migrated successed from v1 to v2.
        assert(await getPublic(childrenV2Contract,"proxyCode") === ProxyContract.code, "Must be equal");
        assert(await getPublic(childrenV2Contract,"childrenVersion") === "2", "Must be equal");
        assert(await getPublic(childrenV2Contract,"root") === rootAddress, "Must be equal");
        assert(deepEqual(await getPublic(childrenV2Contract,"balances"), initialBalancesMap), "Must be equal");
        assert(deepEqual(await getPublic(childrenV2Contract,"lastHashes"), initialLastHashes), "Must be equal");


        await childrenV2Contract.run("approveAddress", {
            _address: rootAddress,
            _value: 1_000_000_000
        })

        let approvedMap = {};
        approvedMap[rootAddress] = 1_000_000_000;

        //check approvedAddresses works correctly
        assert(deepEqual(await getPublic(childrenV2Contract,"approvedAddresses"), approvedMap), "Must be equal");


        await rootContract.run("deployChildren", {
            _initialBalances: initialBalancesMap,
            _lastHashes: initialLastHashes,
            _public_key: `0x${сhildren2_keys.public}`
        }, {});


        //Calculate off-chain children v2 address by proxy abi.
        let secondaryChildrenAddress = await getAddressOfChildrenContract(сhildren2_keys, rootAddress);

        let secondaryChildren = new Account(ChildrenV2Contract, {
            signer: signerKeys(сhildren2_keys),
            address: secondaryChildrenAddress,
            client
        });

        //check contract deployed with version 2
        assert(await getPublic(secondaryChildren,"proxyCode") === ProxyContract.code, "Must be equal");
        assert(await getPublic(secondaryChildren,"childrenVersion") === "2", "Must be equal");
        assert(deepEqual(await getPublic(secondaryChildren,"balances"), initialBalancesMap), "Must be equal");

        console.log("Test successful");
    } catch (e) {
        console.error(e);
    }
}

(async () => {
    try {
        console.log("Hello localhost TON!");
        await main(client);
        process.exit(0);
    } catch (error) {
        if (error.code === 504) {
            console.error(`Network is inaccessible. You have to start TON OS SE using \`tondev se start\`.\n If you run SE on another port or ip, replace http://localhost endpoint with http://localhost:port or http://ip:port in index.js file.`);
        } else {
            console.error(error);
        }
    }
    client.close();
})();

async function getAddressOfChildrenContract(keys, rootAddress) {
    return await (new Account(ProxyContract, {
        signer: signerKeys(keys),
        client,
        initData: {
            root: rootAddress,
            initialData: (await client.boc.encode_boc({
                builder: [],
            })).boc,
        },
    })).getAddress()
}

function assert(condition, error) {
    if (!condition) {
        throw new Error(error || 'Error');
    }
}

async function getPublic(contract, method) {
    return (await contract.runLocal(method, {})).decoded.output[method];
}

const u = (size, x) => {
    if (size === 256) {
        return builderOpBitString(`x${BigInt(x).toString(16).padStart(64, "0")}`)
    } else {
        return builderOpInteger(size, x);
    }
}

const u32 = x => u(32, x);

function getInitialBalances(root_address) {
    let initialBalances = {}
    for (let i = 0; i < 5; i++) {
        initialBalances[root_address.slice(0, -2) + i.toString().padStart(2, '0')] = 1_000_000_000 + i;
    }
    return initialBalances;
}

function getInitialLastHashes() {
    let hashes = [];
    for (let i = 0; i < Math.floor(Math.random() * 15); i++) {
        hashes.push(Math.floor(Math.random() * 100000000000))
    }
    return hashes;
}
