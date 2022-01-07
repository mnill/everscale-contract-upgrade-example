pragma ton-solidity >= 0.52.0;


interface IRoot {
    function deployChildren(
        mapping (address => uint128) _initialBalances,
        uint256[] _lastHashes,
        uint256 _public_key
    ) external returns (address);

    function requestCodeUpgrade(
        uint256 _public_key
    ) external;

//   function expectedChildrenAddress(
//       uint32 _childrenId,
//       uint256 _public_key
//   ) public responsible view returns (address);
}
