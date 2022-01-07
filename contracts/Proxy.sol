pragma ton-solidity >= 0.52.0;

library ProxyContractErrors {
    uint8 constant error_message_sender_is_not_my_owner = 100;
}


contract Proxy {
    address static root; // Root contract
    TvmCell static initialData;

    modifier onlyRoot {
        require(msg.sender == root, ProxyContractErrors.error_message_sender_is_not_my_owner);
        _;
    }

    constructor(TvmCell _code, TvmCell _params) public onlyRoot {
        TvmBuilder builder;

        builder.store(uint32(0));    // Upgraded from version 0
        builder.store(root);         // Root address. Address depend on this data

        builder.store(initialData);  // Static data. Address depend on this data
        builder.store(_params);      // Dynamic params. Address not depend on this params.

        //Set code for next transactions.
        tvm.setcode(_code);
        //Set new code right now for current transaction
        tvm.setCurrentCode(_code);

        // call onCodeUpgrade from new code/
        onCodeUpgrade(builder.toCell());
    }

    function onCodeUpgrade(TvmCell _data) private {}
}
