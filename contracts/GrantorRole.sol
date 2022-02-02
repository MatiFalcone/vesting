// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @dev GrantorRole trait
 *
 * This adds support for a role that allows creation of vesting token grants, allocated from the
 * role holder's wallet.
 *
 * NOTE: We have implemented a role model only the contract owner can assign/un-assign roles.
 * This is necessary to support enterprise software, which requires a permissions model in which
 * roles can be owner-administered, in contrast to a blockchain community approach in which
 * permissions can be self-administered. Therefore, this implementation replaces the self-service
 * "renounce" approach with one where only the owner is allowed to makes role changes.
 *
 * Owner is not allowed to renounce ownership, lest the contract go without administration. But
 * it is ok for owner to shed initially granted roles by removing role from self.
 */
contract GrantorRole is Ownable, AccessControl {

    bytes32 public constant GRANTOR_ROLE = keccak256("GRANTOR_ROLE");

    event GrantorAdded(address indexed account);
    event GrantorRemoved(address indexed account);

    //Roles.Role private _grantors;
    mapping (address => bool) _grantors;

    constructor () {
        _setupRole(GRANTOR_ROLE, msg.sender);
    }

    modifier onlyGrantor() {
        require(hasRole(GRANTOR_ROLE, msg.sender), "Caller is not a Grantor");
        //require(isGrantor(msg.sender), "onlyGrantor");
        _;
    }

    modifier onlyGrantorOrSelf(address account) {
        require(hasRole(GRANTOR_ROLE, msg.sender) || msg.sender == account, "Caller is not a Grantor or Self");
        _;
    }

    function isGrantor(address account) public view returns (bool) {
        return hasRole(GRANTOR_ROLE, account);
    }

    function addGrantor(address account) public onlyOwner {
        _addGrantor(account);
    }

    function removeGrantor(address account) public onlyOwner {
        _removeGrantor(account);
    }

    function _addGrantor(address account) private {
        require(account != address(0));
        require(!hasRole(GRANTOR_ROLE, account), "Account is a Grantor");
        grantRole(GRANTOR_ROLE, account);
        _grantors[account] = true;
        emit GrantorAdded(account);
    }

    function _removeGrantor(address account) private {
        require(account != address(0));
        require(hasRole(GRANTOR_ROLE, account), "Account is not a Grantor");
        revokeRole(GRANTOR_ROLE, account);
        _grantors[account] = false;
        emit GrantorRemoved(account);
    }

    // =========================================================================
    // === Overridden ERC20 functionality
    // =========================================================================

    /**
     * Ensure there is no way for the contract to end up with no owner. That would inadvertently result in
     * token grant administration becoming impossible. We override this to always disallow it.
     */
    function renounceOwnership() public onlyOwner override {
        require(false, "forbidden");
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) public onlyOwner override {
        _removeGrantor(msg.sender);
        super.transferOwnership(newOwner);
        _addGrantor(newOwner);
    }
}