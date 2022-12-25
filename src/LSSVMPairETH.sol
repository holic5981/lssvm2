// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IRoyaltyRegistry} from "manifoldxyz/IRoyaltyRegistry.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {LSSVMPair} from "./LSSVMPair.sol";
import {ICurve} from "./bonding-curves/ICurve.sol";
import {ILSSVMPairFactoryLike} from "./ILSSVMPairFactoryLike.sol";

/**
 * @title An NFT/Token pair where the token is ETH
 *     @author boredGenius and 0xmons
 */
contract LSSVMPairETH is LSSVMPair {
    using SafeTransferLib for address payable;
    using SafeTransferLib for ERC20;

    uint256 internal constant IMMUTABLE_PARAMS_LENGTH = 61;

    constructor(IRoyaltyRegistry royaltyRegistry) LSSVMPair(royaltyRegistry) {}

    /**
     * @inheritdoc LSSVMPair
     */
    function pairVariant() public pure override returns (ILSSVMPairFactoryLike.PairVariant) {
        return ILSSVMPairFactoryLike.PairVariant.ETH;
    }

    /// @inheritdoc LSSVMPair
    function _pullTokenInputAndPayProtocolFee(
        uint256 inputAmount,
        uint256 tradeFeeAmount,
        bool, /*isRouter*/
        address, /*routerCaller*/
        ILSSVMPairFactoryLike _factory,
        uint256 protocolFee
    ) internal override {
        require(msg.value >= inputAmount, "Sent too little ETH");

        // Compute royalties
        uint256 saleAmount = inputAmount - protocolFee;
        (address royaltyRecipient, uint256 royaltyAmount) = _calculateRoyalties(saleAmount);

        // Deduct royalties from sale amount
        unchecked {
            // Safe because we already require saleAmount >= royaltyAmount in _calculateRoyalties()
            saleAmount -= royaltyAmount;
        }

        // Transfer saleAmount ETH to assetRecipient if it's been set
        address payable _assetRecipient = getAssetRecipient();

        // Transfer trade fees only if TRADE pool and they exist
        if (poolType() == PoolType.TRADE && tradeFeeAmount > 0) {
            address payable _feeRecipient = getFeeRecipient();
            // Only send and deduct inputAmount if the fee recipient is not the asset recipient (i.e. the pool)
            if (_feeRecipient != _assetRecipient) {
                saleAmount -= tradeFeeAmount;
                _feeRecipient.safeTransferETH(tradeFeeAmount);
            }
        }

        if (_assetRecipient != address(this)) {
            _assetRecipient.safeTransferETH(saleAmount);
        }

        // Transfer royalties
        if (royaltyAmount != 0) {
            payable(royaltyRecipient).safeTransferETH(royaltyAmount);
        }

        // Take protocol fee
        if (protocolFee != 0) {
            payable(address(_factory)).safeTransferETH(protocolFee);
        }
    }

    /// @inheritdoc LSSVMPair
    function _refundTokenToSender(uint256 inputAmount) internal override {
        // Give excess ETH back to caller
        if (msg.value > inputAmount) {
            payable(msg.sender).safeTransferETH(msg.value - inputAmount);
        }
    }

    /// @inheritdoc LSSVMPair
    function _payProtocolFeeFromPair(ILSSVMPairFactoryLike _factory, uint256 protocolFee) internal override {
        // Take protocol fee
        if (protocolFee > 0) {
            payable(address(_factory)).safeTransferETH(protocolFee);
        }
    }

    /// @inheritdoc LSSVMPair
    function _sendTokenOutput(address payable tokenRecipient, uint256 outputAmount) internal override {
        // Send ETH to caller
        if (outputAmount != 0) {
            tokenRecipient.safeTransferETH(outputAmount);
        }
    }

    /// @inheritdoc LSSVMPair
    /// @dev see LSSVMPairCloner for params length calculation
    function _immutableParamsLength() internal pure override returns (uint256) {
        return IMMUTABLE_PARAMS_LENGTH;
    }

    /**
     * @notice Withdraws all token owned by the pair to the owner address.
     *     @dev Only callable by the owner.
     */
    function withdrawAllETH() external onlyOwner {
        withdrawETH(address(this).balance);
    }

    /**
     * @notice Withdraws a specified amount of token owned by the pair to the owner address.
     *     @dev Only callable by the owner.
     *     @param amount The amount of token to send to the owner. If the pair's balance is less than
     *     this value, the transaction will be reverted.
     */
    function withdrawETH(uint256 amount) public onlyOwner {
        payable(owner()).safeTransferETH(amount);

        // emit event since ETH is the pair token
        emit TokenWithdrawal(amount);
    }

    /// @inheritdoc LSSVMPair
    function withdrawERC20(ERC20 a, uint256 amount) external override onlyOwner {
        a.safeTransfer(msg.sender, amount);
    }

    /**
     * @dev All ETH transfers into the pair are accepted. This is the main method
     *     for the owner to top up the pair's token reserves.
     */
    receive() external payable {
        emit TokenDeposit(msg.value);
    }

    /**
     * @dev All ETH transfers into the pair are accepted. This is the main method
     *     for the owner to top up the pair's token reserves.
     */
    fallback() external payable {
        // Only allow calls without function selector
        require(msg.data.length == _immutableParamsLength());
        emit TokenDeposit(msg.value);
    }
}