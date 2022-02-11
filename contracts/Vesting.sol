// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Vesting {

    // Structs
    struct VestingSchedule {
        uint32 startDay; /* Start day of the grant, in days since the UNIX epoch (start of day). */
        uint32 cliffDuration; /* Duration of the cliff, with respect to the grant start day, in days. */
        uint32 duration; /* Duration of the vesting schedule, with respect to the grant start day, in days. */
        uint32 interval; /* Duration in days of the vesting interval. */
        uint256 amount; /* Total number of tokens that vest. */
        bool isActive;
    }

    // Mappings
    mapping(address => VestingSchedule) public _vestingSchedules;

    // // Date-related constants for sanity-checking dates to reject obvious erroneous inputs
    // // and conversions from seconds to days and years that are more or less leap year-aware.
    // uint32 private constant THOUSAND_YEARS_DAYS = 365243; /* See https://www.timeanddate.com/date/durationresult.html?m1=1&d1=1&y1=2000&m2=1&d2=1&y2=3000 */
    // uint32 private constant TEN_YEARS_DAYS = THOUSAND_YEARS_DAYS / 100; /* Includes leap years (though it doesn't really matter) */
    // uint32 private constant JAN_1_2000_DAYS = 946684800 / (24 * 60 * 60);
    // uint32 private constant JAN_1_3000_DAYS = JAN_1_2000_DAYS + 365243;

    // Events
    event VestingScheduleCreated(
        address indexed beneficiary,
        uint32 startDay,
        uint32 cliffDuration,
        uint32 duration,
        uint32 interval,
        uint256 amount,
        bool isActive
    );

    event GrantRevoked(
        address indexed grantHolder, 
        uint32 onDay
    );

    event VestingTokensGranted(
        address indexed beneficiary,
        uint256 withdrawAmount,
        uint256 pendingAmount
    );

    // Global variables
    address public admin;
    address payable feeAccount;
    uint32 public fee;
    IERC20 public token;
    
    constructor(IERC20 _token, uint32 _fee, address payable _feeAccount) {
        require(address(_token) != address(0));
        admin = msg.sender;
        fee = _fee;
        feeAccount = _feeAccount;
        token = _token;
    }

    // ============================================================================
    // === Methods for administratively creating a vesting schedule for an account.
    // ============================================================================
    
    function vestingFee() public view virtual returns (uint32) {
        return fee;
    }

    function vestingFeeAccount() public view virtual returns (address) {
        return feeAccount;
    }

    function vestingToken() public view virtual returns (IERC20) {
        return token;
    }

    function addVestingSchedule(
        address _beneficiary,
        uint32 _startDay,
        uint32 _cliffDuration,
        uint32 _duration,
        uint32 _interval,
        uint256 _amount
    ) external payable onlyOwner {
        require(
            !hasVestingSchedule(_beneficiary),
            "vesting schedule already exists for given beneficiary"
        );
        // Check that the contract has the balance allocated before setting the vesting
        // PENDING

        require(token.balanceOf(address(this)) >= _amount, "please allocate the tokens to the contract");

        setVestingSchedule(
            _beneficiary,
            _startDay,
            _cliffDuration,
            _duration,
            _interval,
            _amount
        );

    }

    modifier onlyOwner() {
        // Distinguish insufficient overall balance from insufficient vested funds balance in failure msg.
        require(msg.sender == admin, "only owner can call this function");
        _;
    }

    function hasVestingSchedule(address account)
        internal
        view
        returns (bool ok)
    {
        return _vestingSchedules[account].isActive;
    }

    function setVestingSchedule(
        address _beneficiary,
        uint32 _startDay, /* Start day of the grant, in days since the UNIX epoch (start of day). */
        uint32 _cliffDuration, /* Duration of the cliff, with respect to the grant start day, in days. */
        uint32 _duration, /* Duration of the vesting schedule, with respect to the grant start day, in days. */
        uint32 _interval, /* Duration in days of the vesting interval. */
        uint256 _amount /* Total number of tokens that vest. */
    ) internal returns (bool ok) {
        // Check for a valid vesting schedule given (disallow absurd values to reject likely bad input).
        require(
            _duration > 0 &&
                //_duration <= TEN_YEARS_DAYS &&
                _duration <= 3652 &&
                _cliffDuration < _duration &&
                _interval >= 1,
            "invalid vesting schedule"
        );

        // Make sure the duration values are in harmony with interval (both should be an exact multiple of interval).
        require(
            _duration % _interval == 0 && _cliffDuration % _interval == 0,
            "invalid cliff/duration for interval"
        );

        // Make sure no prior vesting is in effect for this beneficiary
        require(!_vestingSchedules[_beneficiary].isActive, "grant already exists");

        // Check for valid vestingAmount
        require(
                _amount > 0 &&
                //_startDay >= JAN_1_2000_DAYS &&
                //_startDay < JAN_1_3000_DAYS,
                _startDay >= 10957 &&
                _startDay < 376200,
            "invalid vesting params"
        );

        // Create and populate a vesting schedule.
        _vestingSchedules[_beneficiary] = VestingSchedule(
            _startDay,
            _cliffDuration,
            _duration,
            _interval,
            _amount,
            true /*isActive*/
        );

        // Emit the event and return success.
        emit VestingScheduleCreated(
            _beneficiary,
            _startDay,
            _cliffDuration,
            _duration,
            _interval,
            _amount,
            true /*isActive*/
        );

        return true;
    }

    function getVestingSchedule(address _beneficiary)
        public
        view
        onlyAdminOrSelf(_beneficiary)
        returns (
            uint32 startDay,
            uint32 cliffDuration,
            uint32 duration,
            uint32 interval,
            uint256 amount,
            bool isActive
        )
    {
        return (
            _vestingSchedules[_beneficiary].startDay,
            _vestingSchedules[_beneficiary].cliffDuration,
            _vestingSchedules[_beneficiary].duration,
            _vestingSchedules[_beneficiary].interval,
            _vestingSchedules[_beneficiary].amount,
            _vestingSchedules[_beneficiary].isActive
        );
    }

    modifier onlyAdminOrSelf(address _account) {
        require(
            msg.sender == admin || msg.sender == _account,
            "caller is not the Owner or Self"
        );
        _;
    }

    function withdraw() external payable returns (bool ok) {
        require(hasVestingSchedule(msg.sender), "no vesting schedule for caller");
        VestingSchedule storage vesting = _vestingSchedules[msg.sender];
        require(
            today() >= vesting.startDay + vesting.cliffDuration,
            "too early to withdraw or cliff not finished"
        );
        require(vesting.amount > 0);
        require(vesting.isActive);
        uint256 vestedAmount = getVestedAmount(msg.sender, today());
        require(vestedAmount > 0, "no tokens available to withdraw");
        token.transfer(msg.sender, vestedAmount);
        /* Emits the VestingTokensGranted event. */
        emit VestingTokensGranted(msg.sender, vestedAmount, vesting.amount - vestedAmount);
        return true;
    }

    function getVestedAmount(address account, uint32 onDay)
        internal
        view
        returns (uint256 amountAvailable)
    {
        uint256 totalTokens = _vestingSchedules[msg.sender].amount;
        uint256 vested = totalTokens - getNotVestedAmount(account, onDay);
        return vested;
    }

    /**
     * @dev Determines the amount of tokens that have not vested in the given account.
     *
     * The math is: not vested amount = vesting amount * (end date - on date)/(end date - start date)
     *
     * @param account = The account to check.
     * @param onDayOrToday = The day to check for, in days since the UNIX epoch. Can pass
     *   the special value 0 to indicate today.
     */
    function getNotVestedAmount(address account, uint32 onDayOrToday)
        internal
        view
        returns (uint256 amountNotVested)
    {
        VestingSchedule storage vesting = _vestingSchedules[account];
        uint32 onDay = _effectiveDay(onDayOrToday);

        // If there's no schedule, or before the vesting cliff, then the full amount is not vested.
        if (
            !vesting.isActive || onDay < vesting.startDay + vesting.cliffDuration
        ) {
            // None are vested (all are not vested)
            return vesting.amount;
        }
        // If after end of vesting, then the not vested amount is zero (all are vested).
        else if (onDay >= vesting.startDay + vesting.duration) {
            // All are vested (none are not vested)
            return uint256(0);
        }
        // Otherwise a fractional amount is vested.
        else {
            // Compute the exact number of days vested.
            uint32 daysVested = onDay - vesting.startDay;
            // Adjust result rounding down to take into consideration the interval.
            uint32 effectiveDaysVested = (daysVested / vesting.interval) *
                vesting.interval;

            // Compute the fraction vested from schedule using 224.32 fixed point math for date range ratio.
            // Note: This is safe in 256-bit math because max value of X billion tokens = X*10^27 wei, and
            // typical token amounts can fit into 90 bits. Scaling using a 32 bits value results in only 125
            // bits before reducing back to 90 bits by dividing. There is plenty of room left, even for token
            // amounts many orders of magnitude greater than mere billions.
            //uint256 vested = grant.amount.mul(effectiveDaysVested).div(vesting.duration);
            uint256 vested = (vesting.amount * effectiveDaysVested) /
                vesting.duration;
            //return grant.amount.sub(vested);
            return vesting.amount - vested;
        }
    }

    // =========================================================================
    // === Check vesting.
    // =========================================================================

    /**
     * @dev returns the day number of the current day, in days since the UNIX epoch.
     */
    function today() public view returns (uint32 dayNumber) {
        return uint32(block.timestamp / (24 * 60 * 60)); // Seconds per day
    }

    function _effectiveDay(uint32 onDayOrToday)
        internal
        view
        returns (uint32 dayNumber)
    {
        return onDayOrToday == 0 ? today() : onDayOrToday;
    }

    /***
     * @dev returns all information about the grant's vesting as of the given day
     * for the given account. Only callable by the account holder or a grantor, so
     * this is mainly intended for administrative use.
     *
     * @param grantHolder = The address to do this for.
     * @param onDayOrToday = The day to check for, in days since the UNIX epoch. Can pass
     *   the special value 0 to indicate today.
     * @return = A tuple with the following values:
     *   amountVested = the amount out of vestingAmount that is vested
     *   amountNotVested = the amount that is vested (equal to vestingAmount - vestedAmount)
     *   amountOfGrant = the amount of tokens subject to vesting.
     *   vestStartDay = starting day of the grant (in days since the UNIX epoch).
     *   vestDuration = grant duration in days.
     *   cliffDuration = duration of the cliff.
     *   vestIntervalDays = number of days between vesting periods.
     *   isActive = true if the vesting schedule is currently active.
     */
    function vestingForAccountAsOf(address account, uint32 onDayOrToday)
        public
        view
        onlyAdminOrSelf(account)
        returns (
            uint256 amountVested,
            uint256 amountNotVested,
            uint256 vestAmount,
            uint32 vestStartDay,
            uint32 vestDuration,
            uint32 cliffDuration,
            uint32 vestIntervalDays,
            bool isActive
        )
    {
        VestingSchedule storage vesting = _vestingSchedules[account];
        uint256 notVestedAmount = getNotVestedAmount(account, onDayOrToday);
        uint256 vestingAmount = vesting.amount;

        return (
            vestingAmount - notVestedAmount,
            notVestedAmount,
            vestingAmount,
            vesting.startDay,
            vesting.duration,
            vesting.cliffDuration,
            vesting.interval,
            vesting.isActive
        );
    }

    /***
     * @dev returns all information about the grant's vesting as of the given day
     * for the current account, to be called by the account holder.
     *
     * @param onDayOrToday = The day to check for, in days since the UNIX epoch. Can pass
     *   the special value 0 to indicate today.
     * @return = A tuple with the following values:
     *   amountVested = the amount out of vestingAmount that is vested
     *   amountNotVested = the amount that is vested (equal to vestingAmount - vestedAmount)
     *   amountOfGrant = the amount of tokens subject to vesting.
     *   vestStartDay = starting day of the grant (in days since the UNIX epoch).
     *   cliffDuration = duration of the cliff.
     *   vestDuration = grant duration in days.
     *   vestIntervalDays = number of days between vesting periods.
     *   isActive = true if the vesting schedule is currently active.
     *   wasRevoked = true if the vesting schedule was revoked.
     */
    function vestingAsOf(uint32 onDayOrToday)
        public
        view
        returns (
            uint256 amountVested,
            uint256 amountNotVested,
            uint256 vestAmount,
            uint32 vestStartDay,
            uint32 vestDuration,
            uint32 cliffDuration,
            uint32 vestIntervalDays,
            bool isActive
        )
    {
        return vestingForAccountAsOf(msg.sender, onDayOrToday);
    }

    /**
     * @dev returns true if the account has sufficient funds available to cover the given amount,
     *   including consideration for vesting tokens.
     *
     * @param account = The account to check.
     * @param amount = The required amount of vested funds.
     * @param onDay = The day to check for, in days since the UNIX epoch.
     */
    function _fundsAreAvailableOn(
        address account,
        uint256 amount,
        uint32 onDay
    ) internal view returns (bool ok) {
        return (amount <= getVestedAmount(account, onDay));
    }

    /**
     * @dev Modifier to make a function callable only when the amount is sufficiently vested right now.
     *
     * @param account = The account to check.
     * @param amount = The required amount of vested funds.
     */
    modifier onlyIfFundsAvailableNow(address account, uint256 amount) {
        // Distinguish insufficient overall balance from insufficient vested funds balance in failure msg.
        require(
            _fundsAreAvailableOn(account, amount, today()),
            token.balanceOf(account) < amount
                ? "insufficient funds"
                : "insufficient vested funds"
        );
        _;
    }

    // =========================================================================
    // === Grant revocation
    // =========================================================================

    /***
     * @dev If the account has a revocable grant, this forces the grant to end based on computing
     * the amount vested up to the given date. All tokens that would no longer vest are returned
     * to the account of the original grantor.
     *
     * @param grantHolder = Address to which tokens will be granted.
     * @param onDay = The date upon which the vesting schedule will be effectively terminated,
     *   in days since the UNIX epoch (start of day).
     */
    function revokeVesting(address account, uint32 onDay)
        public
        onlyOwner
        returns (bool ok)
    {
        VestingSchedule storage vesting = _vestingSchedules[account];
        uint256 notVestedAmount;

        // Make sure a vesting schedule has previously been set.
        require(vesting.isActive, "no active vesting");
        // Fail on likely erroneous input.
        require(onDay <= vesting.startDay + vesting.duration, "no effect");
        // Don"t let grantor revoke anf portion of vested amount.
        require(onDay >= today(), "cannot revoke vested holdings");

        notVestedAmount = getNotVestedAmount(account, onDay);

        // Kill the grant by updating isActive.
        _vestingSchedules[account].isActive = false;

        /* Emits the GrantRevoked event. */
        emit GrantRevoked(account, onDay);
        
        return true;

    }

}
