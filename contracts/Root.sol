pragma ton-solidity >= 0.52.0;
pragma AbiHeader pubkey;

import "./Proxy.sol";
import "./interfaces/IRoot.sol";
import "./interfaces/IUpgradable.sol";

library RootContractErrors {
    uint8 constant error_tvm_pubkey_not_set = 100;
    uint8 constant error_message_sender_is_not_my_owner = 101;
    uint8 constant error_children_code_version_not_set = 102;
    uint8 constant error_children_address_is_wrong = 103;
}

contract RootContract is IRoot {
    TvmCell public childrenCode;
    TvmCell public proxyCode;

    uint32 public childrenVersion;

    constructor(TvmCell _proxyCode, TvmCell _childrenCode, uint32 _childrenVersion) public {
        require(tvm.pubkey() != 0, RootContractErrors.error_tvm_pubkey_not_set);
        require(tvm.pubkey() == msg.pubkey(), RootContractErrors.error_message_sender_is_not_my_owner);
        require(_childrenVersion > 0, RootContractErrors.error_children_code_version_not_set);

        tvm.accept();
        childrenCode = _childrenCode;
        proxyCode = _proxyCode;
        childrenVersion = _childrenVersion;
    }

    modifier onlyOwner() {
        require(tvm.pubkey() != 0 && tvm.pubkey() == msg.pubkey(), RootContractErrors.error_message_sender_is_not_my_owner);
        _;
    }

    modifier onlyChildren(uint256 _public_key) {
        require(msg.sender == calcChildrenAddress(_public_key), RootContractErrors.error_children_address_is_wrong);
        _;
    }

    function calcChildrenAddress(uint256 _public_key) private inline view returns (address) {
        return address(tvm.hash(getStateInitForChildren(_public_key)));
    }

    function getStateInitForChildren(uint256 _public_key) private inline view returns (TvmCell) {
        // We use empty cell, but it can be not empty to make different addresses for same pubkey.
        TvmBuilder builder;


        TvmCell stateInit = tvm.buildStateInit({
            contr: Proxy,
            varInit: {
                root: address(this),
                initialData: builder.toCell()
            },
            pubkey: _public_key,
            code: proxyCode
        });
        return stateInit;
    }

    function setNewCode(TvmCell _newCode, uint32 _newVersion) onlyOwner external {
        tvm.accept();
        childrenCode = _newCode;
        childrenVersion = _newVersion;
    }

    function requestCodeUpgrade(uint256 _public_key) override external onlyChildren(_public_key) {
        address children = calcChildrenAddress(_public_key);
        IUpgradable(children).codeUpgrade{value: 0, flag: 64}(childrenCode, childrenVersion);
    }

    function deployChildren(
        mapping (address => uint128) _initialBalances,
        uint256[] _lastHashes,
        uint256 _public_key
    ) override external onlyOwner returns (address)  {
        tvm.accept();

        TvmBuilder params;
        params.store(childrenVersion);
        params.store(proxyCode);
        params.store(_initialBalances);
        params.store(_lastHashes);

        TvmCell stateInit = getStateInitForChildren(_public_key);

        new Proxy{
            stateInit: stateInit,
            value: 3_000_000_000,
            flag: 0
        } (childrenCode, params.toCell());
    }
}

