How to upgrade contracts in everscale.

To run test just:
```
everdev se start 
npm i
npm run test
```

Inspired by https://github.com/Skydev0h/FTC-DeNS

This realisation is not tested in production, just to show you the right way.

Why to use Proxy.sol - To detach the address of the contract from its real code.

We always deploy children contract via Proxy.sol and instantly upgrade Proxy to actual code.
So for v1 and v2 we will have the same address.

Why tvm.resetStorage() - TON-Solidity has fields representation on BoC structure.

If we have such state variable in our contract:

```
TvmCell proxyCode;
mapping (address => uint128) balances;
uint32 version;
address root;
uint256[] lastHashes;
```

Solidity will make representation on storage like this (just for example):

![storage_before.png](https://github.com/mnill/everscale-contract-upgrade-example/blob/master/images/storage_before.png?raw=true)

If after upgrade state variables structures are changed and will be like this:

```
TvmCell proxyCode;
mapping (address => uint128) balances;
mapping (address => uint128) approvedAddresses;
uint32 version;
address root;
uint256[] lastHashes;
```

So solidity will expect another storage representation structure, like this:

![storage_before.png](https://github.com/mnill/everscale-contract-upgrade-example/blob/master/images/storage_after.png?raw=true)

For now, we have no build in mechanism to migrate storage structure, 
so we use a workaround:

```
function codeUpgrade(TvmCell _code, uint32 _newVersion) override public onlyRoot {
  if (childrenVersion != _newVersion) {
    TvmBuilder data;

    // Just pack all state variables to TvmCell
    data.store(childrenVersion); 
    data.store(root);
    data.store(_newVersion);

    TvmBuilder prevParamData;
    prevParamData.store(proxyCode);
    revParamData.store(balances);
    prevParamData.store(lastHashes);

    data.storeRef(prevParamData);

    // Set code to new in the nexts transactions
    tvm.setcode(_code);
    // Set code to new right now in this transaction
    tvm.setCurrentCode(_code);

    // Call onCodeUpgrade of new code with TvmCell 
    // whic one contain all data we would like to save
    onCodeUpgrade(data.toCell());
  }
  
  // onCodeUpgrade from new code (V2)
  function onCodeUpgrade(TvmCell _data) private {
        // Reset all storage, (exclude service vars = pubkey, constructor flag, replayTs)
        tvm.resetStorage();
        
        // Just decode all data and write in new storage structure.
        TvmSlice s = _data.toSlice();
        uint32 upgradedFromVersion = s.decode(uint32);
        (root, childrenVersion) = s.decode(address, uint32);
        TvmSlice params = s.loadRefAsSlice();
        (proxyCode, balances, lastHashes) = params.decodeFunctionParams(prevVersionParams);
    }
    
    function prevVersionParams(
        TvmCell _proxyCode,
        mapping (address => uint128) _balances,
        uint256[] _lastHashes
    ) public {}
}
```
