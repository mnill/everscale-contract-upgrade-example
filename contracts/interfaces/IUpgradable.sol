pragma ton-solidity >= 0.52.0;


interface IUpgradable {
    function codeUpgrade(
        TvmCell _code,
        uint32 _newVersion
    ) external;
}
