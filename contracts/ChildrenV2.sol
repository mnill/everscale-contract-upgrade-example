pragma ton-solidity >= 0.52.0;
import "./interfaces/IUpgradable.sol";
import "./interfaces/IRoot.sol";

pragma AbiHeader pubkey;

library ChildrenV2ContractErrors {
    uint8 constant error_message_sender_is_not_my_root = 100;
    uint8 constant error_message_sender_is_not_my_owner = 101;
    uint8 constant error_message_insufficient_balance_to_upgrade = 102;
}

contract ChildrenV2Contract is IUpgradable {
    TvmCell public proxyCode;

    address public root;
    uint32  public childrenVersion;

    mapping (address => uint128) public balances;
    mapping (address => uint128) public approvedAddresses;
    uint256[] public lastHashes;

    modifier onlyRoot() {
        require(msg.sender == root, ChildrenV2ContractErrors.error_message_sender_is_not_my_root);
        _;
    }

    modifier onlyOwner() {
        require(msg.pubkey() == tvm.pubkey(), ChildrenV2ContractErrors.error_message_sender_is_not_my_owner);
        _;
    }

    function approveAddress(address _address, uint128 _value) onlyOwner external {
        tvm.accept();
        approvedAddresses[_address] = _value;
    }

    function requestCodeUpgrade() external onlyOwner {
        require(address(this).balance > 1 ton, ChildrenV2ContractErrors.error_message_insufficient_balance_to_upgrade);
        tvm.accept();
        IRoot(root).requestCodeUpgrade{value: 0.5 ton}(tvm.pubkey());
    }

    function codeUpgrade(TvmCell _code, uint32 _newVersion) override external onlyRoot {
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
            prevParamData.store(approvedAddresses);

            data.storeRef(prevParamData);

            tvm.setcode(_code);
            tvm.setCurrentCode(_code);

            onCodeUpgrade(data.toCell());
        }
    }

    function onCodeUpgrade(TvmCell _data) private {
        tvm.resetStorage();
        TvmSlice s = _data.toSlice();
        uint32 upgradedFromVersion = s.decode(uint32);
        if (upgradedFromVersion == 0) {
            root = s.decode(address);

            TvmCell initialData = s.loadRef(); //skip coz empty
            TvmSlice params = s.loadRefAsSlice();
            (childrenVersion, proxyCode, balances, lastHashes) = params.decodeFunctionParams(initialParams);
        } else {
            (root, childrenVersion) = s.decode(address, uint32);
            TvmSlice params = s.loadRefAsSlice();
            (proxyCode, balances, lastHashes) = params.decodeFunctionParams(prevVersionParams);
        }
    }

    function prevVersionParams(
        TvmCell _proxyCode,
        mapping (address => uint128) _balances,
        uint256[] _lastHashes
    ) public {}

    function initialParams(
        uint32 _childrenVersion,
        TvmCell _proxyCode,
        mapping (address => uint128) _initialBalances,
        uint256[] _lastHashes
    ) public {}

}

