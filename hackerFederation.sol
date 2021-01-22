// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "https://github.com/chunqizhi/openzeppelin-contracts/blob/zcq/contracts/token/ERC20/ERC20.sol";
import "https://github.com/chunqizhi/hackerLeague/blob/main/hackerFederationOracle.sol";

contract HackerFederation {
    // 顶点地址
    address public rootAddress;
    // 初始兑换值
    uint public usdtPerHE3 = 4000000;
    // 更新预言机周期
    uint public constant PERIOD = 2 minutes;
    // 算力小数点位数
    uint public hashRateDecimals = 5;
    // 销毁地址
    address public burnAddress = 0xC206F4CC6ef3C7bD1c3aade977f0A28ac42F3E37;
    // 每 10 usdt = 1 T
    uint public hashRatePerUsdt = 10;
    // usdtPerHE3 的小数点位数
    uint public usdtPerHE3Decimals = 6;
    //
    address public owner;
    // 用户信息
    struct User {
        address superior;
        uint256 hashRate;
        bool isUser;
    }
    // 保存用户信息对应关系
    mapping(address => User) public users;
    // 预言机地址
    // 获取 HE3/HE1 与 DAI 的交易对
    HackerFederationOracle private oracleHE3ToDai = HackerFederationOracle(0x24248815dd3E61d9FBA7551550A3a77E013ffef7);
    // 获取 DAI 与 USDT 的交易对
    HackerFederationOracle private oracleDaiToUsdt = HackerFederationOracle(0x52b1e1A756CD76C9BFd62B430b65C4214A0Fa86B);
    // 对应 oracleHE3ToDai 预言机的 blockTimestampLast
    uint  public OracleHE3ToDaiBlockTimestampLast = oracleHE3ToDai.blockTimestampLast();
    // 对应 oracleDaiToUsdt 预言机的 blockTimestampLast
    uint  public OracleDaiToUsdtBlockTimestampLast = oracleDaiToUsdt.blockTimestampLast();
    // DAI erc20 代币地址
    address private daiTokenAddress = 0x9154091d89064B625b4A5f59fD5a8416690289A9;
    // HE1 erc20 代币地址
    address private he1TokenAddress = 0x0480F9dd2a0D29ED3daeF8a3c4a9cA922a637bb7;
    // HE3 erc20 代币地址
    address private he3TokenAddress = 0xbFb8c255993C4A7c8b1912Eb0261278126E2dA77;

    // 用户算力购买情况事件
    event LogBuyHashRate(address indexed owner, address indexed superior, uint hashRate);

    constructor(address _rootAddress) public {
        //
        owner = msg.sender;
        //
        rootAddress = _rootAddress;
    }

    // 函数修改器，只有 owner 满足条件
    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    // 更改管理员
    function setOwner(address _newOwnerAddress) public onlyOwner {
        owner = _newOwnerAddress;
    }

    // 更改销毁地址
    function setBurnAddress(address _newBurnAddress) public onlyOwner {
        burnAddress = _newBurnAddress;
    }

    /**
     * 用户使用 he1 购买算力
     * 需要该用户拥有 HE-1 代币
     *
     * Requirements:
     *
     * - `_tokenAmount` 使用 token 数量购买算力
     * - `_superior` 直接上级
     */
    function buyHashRateWithHE1(uint256 _tokenAmount, address _superior) public {
        _buyHashRate(ERC20(he1TokenAddress), _tokenAmount, _tokenAmount, _superior);
    }

    /**
     * 用户使用 he3 购买算力
     * 需要该用户拥有 HE-3 代币
     *
     * Requirements:
     *
     * - `_tokenAmount` 使用 token 数量购买算力
     * - `_superior` 直接上级
     */
    function buyHashRateWithHE3(uint256 _tokenAmount, address _superior) public {
        // 如果过了 PERIOD，就触发预言机合约
        uint timeElapsed1 = block.timestamp - OracleHE3ToDaiBlockTimestampLast;
        if (timeElapsed1 > PERIOD) {
            // 更新预言机的状态值
            oracleHE3ToDai.update();
            // 保持对应关系
            OracleHE3ToDaiBlockTimestampLast = oracleHE3ToDai.blockTimestampLast();
        }
        uint timeElapsed2 = block.timestamp - OracleDaiToUsdtBlockTimestampLast;
        if (timeElapsed2 > PERIOD) {
            oracleDaiToUsdt.update();
            OracleDaiToUsdtBlockTimestampLast = oracleDaiToUsdt.blockTimestampLast();
        }
        // 从预言机获取 HE3 与 DAI的交易对价格
        uint dai = oracleHE3ToDai.consult(he3TokenAddress, _tokenAmount);
        // 从预言机获取 DAI 与 usdt 的交易对价格
        uint usdt = oracleDaiToUsdt.consult(daiTokenAddress, dai);

        // 其中一个合约更新了，就需要更新当前的 usdtPerHE3 的值
        if (timeElapsed1 > PERIOD || timeElapsed2 > PERIOD) {
            usdtPerHE3 =  usdt * 10 ** 12 * 10 ** usdtPerHE3Decimals / _tokenAmount;
        }
        //
        _buyHashRate(ERC20(he3TokenAddress), _tokenAmount, usdt, _superior);
    }

    /**
     * 用户购买算力
     * 需要该用户拥有 HE-1 或者 HE-3 代币
     *
     * Requirements:
     *
     * - `_token` HE-1 或者 HE-3 的合约地址
     * - `_tokenAmount` 使用 token 数量购买算力
     * - `_usdtAmount` _tokenAmount 与 usdt 的价格
     * - `_superior` 直接上级
     */
    function _buyHashRate(ERC20 _tokenAddress,uint _tokenAmount, uint256 _usdtAmount, address _superior) internal {
        // 判断上级是否是 user 或 rootAddress，如果都不是，抛出错误
        if (!(users[_superior].isUser || _superior == rootAddress)) {
            require(users[_superior].isUser, "Superior should be a user or rootAddress");
        }
        // 是否拥有 _amount 数量的 _token 代币
        require(
            _tokenAddress.allowance(msg.sender, address(this)) >= _tokenAmount,
            "Token allowance too low"
        );
        // 销毁对应的代币
        bool sent = _tokenAddress.transferFrom(msg.sender, burnAddress, _tokenAmount);
        require(sent, "Token transfer failed");
        // 10 000000 USDT = 1 00000T, 10 为小数点
        // 计算当前能买多少算力
        uint hashRate = _usdtAmount / hashRatePerUsdt / 10;
        // 单次购买不的少于 1T 算力
        require(hashRate >= 1 * 10 ** hashRateDecimals, "Need buy 1T at least");
        //
        if (users[msg.sender].isUser) {
            // 再次购买，不改变直接上级，直接更新算力
            users[msg.sender].hashRate += hashRate;
        } else {
            // 第一次购买算力，更新用户信息
            users[msg.sender].superior = _superior;
            users[msg.sender].hashRate = hashRate;
            users[msg.sender].isUser = true;
        }
        // 触发购买算力事件
        emit LogBuyHashRate(msg.sender, _superior, hashRate);
    }
}