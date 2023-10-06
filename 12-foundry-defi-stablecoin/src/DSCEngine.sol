// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "./interfaces/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// Inherited contracts
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

// Libraries/Utilities
import {Utils} from "./libraries/Utils.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author polarzero
 * @notice The core of the decentralized stablecoin system; it has no governance,
 * no fees, and is only backed by wETH and wBTC.
 * It handles all the logic for mining and redeeming DSC, as well as depositing &
 * withdrawing collateral.
 * It is very loosely based on the MakerDAO DSS (DAI) system.
 * It should ALWAYS be "overcollateralized". At no point should the value of all collateral
 * be less or equal to the value of all the DSC.
 */

/// @dev Example:
// Put $100 ETH collateral -> borrow $50 DSC
// If the treshold is 150%, value of ETH needs to stay at least at $75
// If it goes below $75, liquidate
// Then the liquidator gets the $75 worth of ETH by repaying the $50 DSC

contract DSCEngine is ReentrancyGuard {
    using OracleLib for AggregatorV3Interface;
    /* -------------------------------------------------------------------------- */
    /*                                CUSTOM ERRORS                               */
    /* -------------------------------------------------------------------------- */

    /// @dev The transfer of tokens failed
    error DSCEngine__TransferFailed();

    /// @dev The health factor of the user is below the threshold
    error DSCEngine__HealthFactorBelowThreshold(uint256 healthFactor);

    /// @dev The health factor of the user is above the threshold
    error DSCEngine__HealthFactorAboveThreshold(uint256 healthFactor);

    /// @dev The health factor of the user did not improve after liquidation
    error DSCEngine__HealthFactorNotImproved(uint256 healthFactor);

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Emitted when a user deposits collateral
    event CollateralDeposited(address indexed user, address indexed tokenCollateralAddress, uint256 amountCollateral);

    /// @dev Emitted when some collateral is redeemed
    event CollateralRedeemed(
        address indexed from, address indexed to, address indexed tokenCollateralAddress, uint256 amountCollateral
    );

    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */
    /* -------------------------------- CONSTANTS ------------------------------- */
    /// @dev The precision of the DecentralizedStableCoin token
    uint256 private constant DSC_PRECISION = 1e18;

    /// @dev The precision to multiply the price feed by to get a more accurate value
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    /// @dev The liquidation threshold in %
    /// Note: Here the user needs to be at least 200% overcollateralized to not get liquidated
    uint256 private constant LIQUIDATION_THRESHOLD = 50;

    /// @dev The precision of the threshold (50 / 100 since 50% is 0.5)
    uint256 private constant LIQUIDATION_PRECISION = 100;

    /// @dev The minimum health factor to not get liquidated
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    /// @dev The bonus the liquidator gets on the collateral (10%)
    uint256 private constant LIQUIDATION_BONUS = 10;

    /* -------------------------------- CONTRACTS ------------------------------- */
    /// @dev The DecentralizedStableCoin token
    DecentralizedStableCoin private immutable i_dsc;

    /* --------------------------------- STRUCTS -------------------------------- */
    /// @dev User struct to store the collateral deposited and DSC minted
    // @audit-ok Ignore [G-21] It's way more convenient to use a mapping for each deposited token
    // so we don't need to find which token it is on each deposit
    struct UserBalances {
        address userAddress;
        uint256 amountDSCMinted;
        mapping(address tokenAddress => uint256 amountDeposited) amountCollateralDeposited;
    }

    /// @dev Collateral struct to store its address, price feed address and decimals and
    struct Collateral {
        address tokenAddress;
        address priceFeedAddress;
        uint256 decimals;
    }

    /* ----------------------------- STATE VARIABLES ---------------------------- */
    /// @dev Array of collateral tokens addresses
    address[] private s_collateralAddresses;

    /* -------------------------------- MAPPINGS -------------------------------- */
    /// @dev Mapping of token addresses to their collateral information
    mapping(address tokenAddress => Collateral collateralInfo) private s_collaterals;

    /// @dev Mapping of user addresses to their collateral deposited and DSC minted
    mapping(address => UserBalances) private s_userBalances;

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIERS                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev Check that the value is not zero
    /// @param _amount The amount to check
    modifier isMoreThanZero(uint256 _amount) {
        Utils.assembly_checkValueNotZero(_amount);
        _;
    }

    /// @dev Check that the collateral token is allowed
    /// @param _tokenAddress The address of the token to check
    modifier isAllowedToken(address _tokenAddress) {
        Utils.assembly_checkAddressNotZero(s_collaterals[_tokenAddress].tokenAddress);
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Constructor
     * @param _collateralTokens The array of collateral tokens (wETH and wBTC here)
     * Note: see struct Collateral (token address, price feed address and decimals)
     * @param _dscAddress The address of the DecentralizedStableCoin token
     */
    constructor(Collateral[] memory _collateralTokens, address _dscAddress) {
        // Update the price feeds for each token
        // @audit-ok Fix [G-11] Use unchecked to save gas
        for (uint256 i = 0; i < _collateralTokens.length;) {
            s_collaterals[_collateralTokens[i].tokenAddress] = Collateral(
                _collateralTokens[i].tokenAddress, _collateralTokens[i].priceFeedAddress, _collateralTokens[i].decimals
            );
            s_collateralAddresses.push(_collateralTokens[i].tokenAddress);

            unchecked {
                ++i;
            }
        }

        // Initialize the DSC token
        i_dsc = DecentralizedStableCoin(_dscAddress);
    }

    /* -------------------------------------------------------------------------- */
    /*                             EXTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */

    /**
     *
     * @param _collateralTokenAddress The address of the token to deposit as collateral
     * @param _amountCollateral The amount of collateral to deposit
     * @param _amountDscToMint The amount of DecentralizedStableCoin to mint
     * Note: This will both deposit collateral and mint DSC
     */
    function depositCollateralAndMintDsc(
        address _collateralTokenAddress,
        uint256 _amountCollateral,
        uint256 _amountDscToMint
    ) external {
        depositCollateral(_collateralTokenAddress, _amountCollateral);
        mintDsc(_amountDscToMint);
    }

    /**
     * @notice Redeem collateral for DecentralizedStableCoin
     * @param _collateralTokenAddress The address of the token to redeem
     * @param _amountCollateral The amount of collateral to redeem
     * @param _amountDscToBurn The amount of DecentralizedStableCoin to burn
     * Note: This will both burn DSC and redeem collateral
     */
    // @audit-ok Fix [G-33] Remove unnecessary `nonReentrant` modifier
    function redeemCollateralForDsc(
        address _collateralTokenAddress,
        uint256 _amountCollateral,
        uint256 _amountDscToBurn
    ) external {
        burnDsc(_amountDscToBurn);
        redeemCollateral(_collateralTokenAddress, _amountCollateral);
    }

    /**
     * @notice Liquidate a user
     * @param _user The address of the user to liquidate
     * @param _collateralTokenAddress The address of the token to deposit as collateral
     * @param _debtToCover The amount of debt to cover
     * Note: This will cover the debt of the user by liquidating their collateral, and get the liquidator a discount
     * on the collateral
     * Note: A debt can be _partially_ covered, as long as it gets the health factor above the threshold
     * Note: This assumes that the protocol is more that 100% overcollateralized, otherwise there would be
     * no incentive to liquidate
     */
    function liquidate(address _user, address _collateralTokenAddress, uint256 _debtToCover)
        external
        isMoreThanZero(_debtToCover)
        nonReentrant
    {
        // Check the health factor of the user
        uint256 initialUserHealthFactor = _healthFactor(_user);
        if (initialUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorAboveThreshold(initialUserHealthFactor);
        }

        // Get the value of the collateral to cover (in tokens)
        uint256 collateralValueCovered = getAccountCollateralValueFromUsd(_collateralTokenAddress, _debtToCover);

        // Calculate the bonus
        uint256 collateralBonus = (collateralValueCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        // Calculate the total amount of collateral to transfer to the liquidator
        uint256 totalCollateralToRedeem = collateralValueCovered + collateralBonus;

        // Redeem the collateral (+ bonus)
        _redeemCollateral(_user, msg.sender, _collateralTokenAddress, totalCollateralToRedeem);

        // Burn the DSC
        _burnDsc(_user, msg.sender, _debtToCover);

        // Check the health factor of the user after the liquidation
        // It should not have decreased
        uint256 finalUserHealthFactor = _healthFactor(_user);
        if (finalUserHealthFactor < initialUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved(finalUserHealthFactor);
        }

        // And it should not be below the threshold either
        _revertIfHealthFactorBelowThreshold(_user);
    }

    /**
     *
     * @notice Deposit collateral into the contract
     * @param _collateralTokenAddress The address of the token to deposit as collateral
     * @param _amountCollateral The amount of collateral to deposit
     */
    // @audit-ok Fix [G-33] Remove unnecessary `nonReentrant` modifier
    function depositCollateral(address _collateralTokenAddress, uint256 _amountCollateral)
        public
        isMoreThanZero(_amountCollateral)
        isAllowedToken(_collateralTokenAddress)
    {
        // Check the balance before/after in case the token has fees on transfer
        uint256 balanceBefore = IERC20(_collateralTokenAddress).balanceOf(address(this));
        // Transfer the collateral from the user to the contract
        bool success = IERC20(_collateralTokenAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        uint256 balanceAfter = IERC20(_collateralTokenAddress).balanceOf(address(this));

        // Calculate the actual amount of collateral that was transferred
        uint256 actualAmountCollateral = balanceAfter - balanceBefore;

        if (!success) revert DSCEngine__TransferFailed();

        // Update the collateral balance of the user
        // @todo Test gas consumption here
        // 32 727 gas
        // via-ir: 32 549
        // via-ir: 32 659 when storing balance before
        // s_userBalances[msg.sender].amountCollateralDeposited[_collateralTokenAddress] = balance + actualAmountCollateral;
        // 32 599 gas
        // via-ir:  32 531
        s_userBalances[msg.sender].amountCollateralDeposited[_collateralTokenAddress] += actualAmountCollateral;

        emit CollateralDeposited(msg.sender, _collateralTokenAddress, actualAmountCollateral);
    }

    /**
     * @notice Redeem collateral from the contract
     * @param _collateralTokenAddress The address of the token to redeem
     * @param _amoutCollateral The amount of collateral to redeem
     */
    function redeemCollateral(address _collateralTokenAddress, uint256 _amoutCollateral)
        public
        isMoreThanZero(_amoutCollateral)
    {
        _redeemCollateral(msg.sender, msg.sender, _collateralTokenAddress, _amoutCollateral);
        _revertIfHealthFactorBelowThreshold(msg.sender);
    }

    /**
     * @notice Mint DecentralizedStableCoin to the user
     * @param _amount The amount of DecentralizedStableCoin to mint
     * Note: The user must have deposited more collateral than the threshold
     */
    // @audit-ok Fix [G-33] Remove unnecessary `nonReentrant` modifier
    function mintDsc(uint256 _amount) public isMoreThanZero(_amount) {
        s_userBalances[msg.sender].amountDSCMinted += _amount;
        _revertIfHealthFactorBelowThreshold(msg.sender);

        i_dsc.mint(msg.sender, _amount);
    }

    /**
     * @notice Burn DecentralizedStableCoin from the user
     * @param _amount The amount of DecentralizedStableCoin to burn
     */
    function burnDsc(uint256 _amount) public isMoreThanZero(_amount) {
        _burnDsc(msg.sender, msg.sender, _amount);
        // @todo Is this necessary?
        _revertIfHealthFactorBelowThreshold(msg.sender);
    }

    /* -------------------------------------------------------------------------- */
    /*                             EXTERNAL VIEW/PURE                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Get the amount of collateral deposited by a user
     * @param _user The address of the user to get the information of
     * @return The total amount of DSC minted and collateral deposited by the user in USD
     */
    function getAccountInformation(address _user) external view returns (uint256, uint256) {
        return _getAccountInformation(_user);
    }

    /**
     * @notice Get the health factor of a user
     * @param _user The address of the user to get the information of
     * @return The health factor of the user
     */
    function getHealthFactor(address _user) external view returns (uint256) {
        return _healthFactor(_user);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_userBalances[user].amountCollateralDeposited[token];
    }

    function getPrecision() external pure returns (uint256) {
        return DSC_PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralAddresses;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_collaterals[token].priceFeedAddress;
    }

    /* -------------------------------------------------------------------------- */
    /*                              PUBLIC VIEW/PURE                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Get the original value of a token from USD
     * @param _tokenAddress The address of the token to get the price feed for
     * @param _amountUsdWei The amount of USD to get the value of
     * @return The value of the token
     */
    function getAccountCollateralValueFromUsd(address _tokenAddress, uint256 _amountUsdWei)
        public
        view
        returns (uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_collaterals[_tokenAddress].priceFeedAddress);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return (_amountUsdWei * (10 ** s_collaterals[_tokenAddress].decimals))
            / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /**
     * @notice Get the value of all the collateral deposited by a user in USD
     * @param _user The address of the user to get the information of
     * @return totalCollateralValueUsd - The total value in USD
     */
    function getAccountCollateralValueInUsd(address _user) public view returns (uint256 totalCollateralValueUsd) {
        address[] memory collateralAddresses = s_collateralAddresses;

        for (uint256 i = 0; i < collateralAddresses.length;) {
            address tokenAddress = collateralAddresses[i];
            uint256 amount = s_userBalances[_user].amountCollateralDeposited[tokenAddress];
            // @todo Test gas consumption here
            totalCollateralValueUsd += getUsdValue(tokenAddress, amount);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Get the value of a token in USD
     * @param _tokenAddress The address of the token to get the price feed for
     * @param _amount The amount of the token to get the value of
     * @return The value of the token in USD
     * Note:  Chainlink will return the price with 8 decimals
     */
    function getUsdValue(address _tokenAddress, uint256 _amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_collaterals[_tokenAddress].priceFeedAddress);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return (_amount * uint256(price) * ADDITIONAL_FEED_PRECISION / (10 ** s_collaterals[_tokenAddress].decimals));
    }

    /* -------------------------------------------------------------------------- */
    /*                               PRIVATE HELPERS                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Redeem collateral from the contract
     * @param _from The address of the user to redeem from
     * @param _to The address of the user to redeem to
     * @param _collateralTokenAddress The address of the collateral token to redeem
     * @param _amountCollateral The amount of collateral to redeem
     */
    function _redeemCollateral(address _collateralTokenAddress, address _from, address _to, uint256 _amountCollateral)
        private
    {
        s_userBalances[_from].amountCollateralDeposited[_collateralTokenAddress] -= _amountCollateral;

        bool success = IERC20(_collateralTokenAddress).transfer(_to, _amountCollateral);
        if (!success) revert DSCEngine__TransferFailed();

        emit CollateralRedeemed(_from, _to, _collateralTokenAddress, _amountCollateral);
    }

    /**
     * @notice Revert if the health factor of the user is below the threshold
     * @param _user The address of the user to check
     */
    function _revertIfHealthFactorBelowThreshold(address _user) private view {
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) revert DSCEngine__HealthFactorBelowThreshold(userHealthFactor);
    }

    /**
     * @notice Burn DSC from the user and transfer it to the contract
     * @param _onBehalfOf The address of the user to burn DSC from
     * @param _dscFrom The address of the user to transfer the DSC from
     * @param _amount The amount of DSC to burn
     * Note: The function calling this should check that the health factor is above the threshold after
     */
    function _burnDsc(address _onBehalfOf, address _dscFrom, uint256 _amount) private {
        s_userBalances[_onBehalfOf].amountDSCMinted -= _amount;
        bool success = i_dsc.transferFrom(_dscFrom, address(this), _amount);
        if (!success) revert DSCEngine__TransferFailed();

        i_dsc.burn(_amount);
    }

    /**
     * @notice Get the health factor of a user, meaning how close they are to the liquidation threshold
     * If it goes below 1, they can be liquidated
     * @param _user The address of the user to check
     * @return The health factor of the user
     * Note: It will go below 1 if the user is less than 200% overcollateralized
     * (meaning they have less than twice the value of the DSC they minted in collateral)
     */
    function _healthFactor(address _user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueUsd) = _getAccountInformation(_user);

        if (totalDscMinted == 0) return type(uint256).max;

        uint256 collateralValueUsdAdjustedForThreshold =
            (collateralValueUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralValueUsdAdjustedForThreshold * DSC_PRECISION) / totalDscMinted;
    }

    /**
     * @notice Get the account information of a user
     * @param _user The address of the user to get the information of
     * @return totalDscMinted - The total amount of DSC minted by the user
     * @return collateralValueUsd - The value of all the collateral deposited by the user in USD
     */
    function _getAccountInformation(address _user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueUsd)
    {
        totalDscMinted = s_userBalances[_user].amountDSCMinted;
        collateralValueUsd = getAccountCollateralValueInUsd(_user);
    }
}
