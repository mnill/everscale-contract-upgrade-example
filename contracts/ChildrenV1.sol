pragma ton-solidity >= 0.52.0;

import "./interfaces/IUpgradable.sol";
import "./interfaces/IRoot.sol";

pragma AbiHeader pubkey;

library ChildrenV1ContractErrors {
    uint8 constant error_message_sender_is_not_my_root = 100;
    uint8 constant error_message_sender_is_not_my_owner = 101;
    uint8 constant error_message_insufficient_balance_to_upgrade = 102;
}

contract ChildrenV1Contract is IUpgradable {
    TvmCell public proxyCode;

    address public root;
    uint32  public  childrenVersion;

    mapping (address => uint128) public balances;
    uint256[] public lastHashes;

    modifier onlyRoot() {
        require(msg.sender == root, ChildrenV1ContractErrors.error_message_sender_is_not_my_root);
        _;
    }

    modifier onlyOwner() {
        require(msg.pubkey() == tvm.pubkey(), ChildrenV1ContractErrors.error_message_sender_is_not_my_owner);
        _;
    }

    function initialParams(
        uint32 _childrenVersion,
        TvmCell _proxyCode,
        mapping (address => uint128) _initialBalances,
        uint256[] _lastHashes
    ) public {}

    function requestCodeUpgrade() external onlyOwner {
        require(address(this).balance > 1 ton, ChildrenV1ContractErrors.error_message_insufficient_balance_to_upgrade);
        tvm.accept();
        IRoot(root).requestCodeUpgrade{value: 0.5 ton}(tvm.pubkey());
    }

    function codeUpgrade(TvmCell _code, uint32 _newVersion) override public onlyRoot {
        if (childrenVersion != _newVersion) {

            TvmBuilder data;

            data.store(childrenVersion); //Prev version
            data.store(root); // Root address
            data.store(_newVersion); // new Version

            // To easy decode by decodeFunctionParams put in new cell
            TvmBuilder prevParamData;
            prevParamData.store(proxyCode);
            prevParamData.store(balances);
            prevParamData.store(lastHashes);

            data.storeRef(prevParamData);

            tvm.setcode(_code);
            tvm.setCurrentCode(_code);

            onCodeUpgrade(data.toCell());
        }
    }

    function onCodeUpgrade(TvmCell _data) private {
        tvm.resetStorage();

        uint32 upgradedFromVersion;
        TvmSlice s = _data.toSlice();

        (upgradedFromVersion, root) = s.decode(uint32, address);

        TvmCell initialData = s.loadRef(); //skip coz empty
        TvmSlice params = s.loadRefAsSlice();

        (childrenVersion, proxyCode, balances, lastHashes) = params.decodeFunctionParams(initialParams);
    }
}

