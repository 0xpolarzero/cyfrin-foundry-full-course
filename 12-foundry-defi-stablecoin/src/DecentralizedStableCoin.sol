// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Inherited contracts
import {ERC20} from "solady/tokens/ERC20.sol";

// Libraries/Utilities
import "./libraries/Utils.sol";

/**
 * @title DecentralizedStableCoin.sol
 * @author polarzero
 * @notice Meant to be governed by DSCEngine; this contract is the ERC20 implementation
 * of the stablecoin system.
 * Collateral: Exogenous (Eth & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 * Note: There is no check for self-approval, as it is not really a concern here
 */
contract DecentralizedStableCoin is ERC20 {
    /* -------------------------------------------------------------------------- */
    /*                                CUSTOM ERRORS                               */
    /* -------------------------------------------------------------------------- */

    /// @dev The caller is not the owner of the contract
    error DecentralizedStableCoin__NotDscEngine();

    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */

    /// @dev The owner of the contract (the DSCEngine contract)
    /// Note: We don't need `Ownable` as it would be overkill here
    address private s_dscEngine;

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIERS                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev Restrict access to the owner of the contract
    modifier onlyDscEngine() {
        if (msg.sender != s_dscEngine) revert DecentralizedStableCoin__NotDscEngine();
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  CONSTRUCTOR                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev Give ownership of the contract to the deployer
    constructor() {
        s_dscEngine = msg.sender;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  METADATA                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Retrieve the name of the token (implemented like this due to using Solady)
     * @return The name of the token
     * @dev This is hard-coded for the sake of simplicity
     */
    function name() public pure override returns (string memory) {
        return "DecentralizedStableCoin";
    }

    /**
     * @notice Retrieve the symbol of the token (implemented like this due to using Solady)
     * @return The symbol of the token
     * @dev This is hard-coded for the sake of simplicity
     */
    function symbol() public pure override returns (string memory) {
        return "DSC";
    }

    /* -------------------------------------------------------------------------- */
    /*                                    ERC20                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Burn tokens from the owner's balance
     * @param _amount The amount of tokens to burn
     * @dev This function is only callable by the owner
     * @dev Solady `_burn` function already checks for zero values
     */
    function burn(uint256 _amount) external onlyDscEngine {
        _burn(msg.sender, _amount);
    }

    /**
     * @notice Mint a certain amount of tokens to a specific address
     * @param _to The address of the recipient of the tokens
     * @param _amount The amount of tokens to mint
     * @dev This function is only callable by the owner
     */
    function mint(address _to, uint256 _amount) external onlyDscEngine {
        Utils.assembly_checkAddressNotZero(_to);

        _mint(_to, _amount);
    }

    /**
     * @notice Transfer tokens to a specific address
     * @param _to The address of the recipient of the tokens
     * @param _amount The amount of tokens to transfer
     * @return Whether the transfer was successful or not
     * @dev This function overrides Solady `transfer` function from the `ERC20` contract
     * to check that the recipient is not the zero address
     */
    function transfer(address _to, uint256 _amount) public override returns (bool) {
        Utils.assembly_checkAddressNotZero(_to);

        return super.transfer(_to, _amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  OWNERSHIP                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Retrieve the owner of the contract
     * @return The address of the owner (the DSCEngine contract)
     */
    function owner() external view returns (address) {
        return s_dscEngine;
    }

    function transferOwnership(address _newOwner) external onlyDscEngine {
        Utils.assembly_checkAddressNotZero(_newOwner);

        s_dscEngine = _newOwner;
    }

    /* -------------------------------------------------------------------------- */
    /*                               INTERNAL HOOKS                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Called whenever tokens are transferred (including minting and burning)
     * @param _amount The value transferred
     */
    function _beforeTokenTransfer(address, /* _from */ address, /* _to */ uint256 _amount) internal pure override {
        Utils.assembly_checkValueNotZero(_amount);
    }
}
