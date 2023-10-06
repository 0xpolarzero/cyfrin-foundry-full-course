- Applied fixes suggested in the audit report
- Used interfaces for better readability (move events and errors out of the contract)
- Used Solady/Solmate instead of OpenZeppelin
- Refactored DSCEngine with structs, enum, also helps to handle different decimals

- Ask vectorized how to initialize ERC20
  -> if using, say the following:
  > The ERC20 standard allows minting and transferring to and from the zero address
  > minting and transferring zero tokens, as well as self-approvals.
  > For performance, this implementation WILL NOT revert for such actions.
  > Please add any checks with overrides if desired.

## Choices

- Not fixing [G-32] -> much more readable to keep `address(this)` than a hardcoded address

## Add // Node: Fix [X-xx] comment the fix
