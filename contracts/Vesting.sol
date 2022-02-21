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
        address allocator; /* Address of the person granting the Vesting. We will use this field to determine is the vesting schedule is active as well, since we can add more fields to this Struct as Solidity has the stack limited. */
    }

    // Mappings
    mapping(address => mapping(address => VestingSchedule))
        public _vestingSchedules;
    mapping(address => mapping(address => uint256)) public _allocations;
    mapping(address => uint256) public _fees;

    // Events
    event VestingScheduleCreated(
        address indexed allocator,
        address indexed token,
        address indexed beneficiary,
        uint32 startDay,
        uint32 cliffDuration,
        uint32 duration,
        uint32 interval,
        uint256 amount
    );

    event GrantRevoked(
        address indexed token,
        address indexed grantHolder,
        uint32 onDay
    );

    event VestingTokensGranted(
        address indexed token,
        address indexed beneficiary,
        uint256 withdrawAmount,
        uint256 pendingAmount
    );

    event VestingFeeCollected(
        address indexed token,
        uint256 amount,
        uint256 originalValue,
        uint256 fee,
        address feeAccount
    );

    // Global variables
    address public admin;
    address payable feeAccount;
    uint32 public fee;

    constructor(uint32 _fee, address payable _feeAccount) {
        require(
            address(_feeAccount) != address(0),
            "Vesting: Fee Account is ZERO_ADDRESS"
        );
        admin = msg.sender;
        fee = _fee;
        feeAccount = _feeAccount;
    }

    // ============================================================================
    // === Methods for administratively creating a vesting schedule for an account.
    // ============================================================================
 
    // When someone deposits coins to the contract, we need to have a mechanism to know
    // only that person is able to allocate those funds to beneficiaries. If not, anybody
    // would be able to allocate funds to beneficiaries if they know how much balance
    // for a specific token is held by the contract.
    function deposit(IERC20 token, uint256 amount) external returns (bool ok) {
        require(amount > 0);
        uint256 contractFee = calculateFee(amount);
        token.transferFrom(msg.sender, address(this), amount - contractFee);
        token.transferFrom(msg.sender, feeAccount, contractFee);
        setInitialAllocation(msg.sender, address(token), amount - contractFee);
        emit VestingFeeCollected(
            address(token),
            amount,
            contractFee,
            fee,
            feeAccount
        );
        updateFeeForToken(address(token), amount);
        return true;
    }

    function setInitialAllocation(
        address owner,
        address token,
        uint256 amount
    ) internal returns (bool ok) {
        if (_allocations[token][owner] > 0) {
            _allocations[token][owner] += amount;
        } else {
            _allocations[token][owner] = amount;
        }
        return true;
    }

    function updateAllocation(
        address owner,
        address token,
        uint256 amount
    ) internal returns (bool ok) {
        require(
            _allocations[token][owner] >= amount,
            "you don't have allocation for this token"
        );
        _allocations[token][owner] = _allocations[token][owner] - amount;
        return true;
    }

    function releaseAllocation(
        address owner,
        address token,
        uint256 amount
    ) internal returns (bool ok) {
        _allocations[token][owner] = _allocations[token][owner] + amount;
        return true;
    }

    function calculateFee(uint256 amount)
        internal
        view
        returns (uint256 __fee)
    {
        __fee = (amount * fee) / 1000;
        return __fee;
    }

    function updateFeeForToken(address token, uint256 amount)
        internal
        returns (bool ok)
    {
        _fees[token] += amount;
        return true;
    }

    function vestingFee() public view virtual returns (uint32) {
        return fee;
    }

    function getFeesForToken(address token) public view virtual returns (uint256) {
        return _fees[token];
    }

    function vestingFeeAccount() public view virtual returns (address) {
        return feeAccount;
    }

    function addVestingSchedule(
        IERC20 _token,
        address _beneficiary,
        uint32 _startDay,
        uint32 _cliffDuration,
        uint32 _duration,
        uint32 _interval,
        uint256 _amount
    ) public {
        // Requires that the person creating the vesting scheduled has the right allocation of tokens
        require(
            _allocations[address(_token)][msg.sender] >= _amount,
            "you haven't allocated the right amount of tokens to the contract"
        );

        // Double check that the contract has funds. This should be always true because of previous check of allocation.
        require(
            _token.balanceOf(address(this)) >= _amount,
            "please allocate the tokens to the contract"
        );

        require(
            !hasVestingScheduleForToken(_beneficiary, address(_token)),
            "vesting schedule of this token already exists for given beneficiary"
        );

        setVestingSchedule(
            msg.sender,
            _token,
            _beneficiary,
            _startDay,
            _cliffDuration,
            _duration,
            _interval,
            _amount
        );
    }

    function hasVestingScheduleForToken(address account, address token)
        internal
        view
        returns (bool ok)
    {
        return _vestingSchedules[token][account].allocator != address(0);
    }

    function setVestingSchedule(
        address _allocator,
        IERC20 _token,
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

        // Make sure no prior vesting for this token is in effect for this beneficiary
        require(
            !(_vestingSchedules[address(_token)][_beneficiary].allocator != address(0)),
            "grant already exists"
        );

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
        _vestingSchedules[address(_token)][_beneficiary] = VestingSchedule(
            _startDay,
            _cliffDuration,
            _duration,
            _interval,
            _amount,
            _allocator
        );

        // Update the allocation of the owner after creating the schedule
        updateAllocation(_allocator, address(_token), _amount);

        // Emit the event and return success.
        emit VestingScheduleCreated(
            _allocator,
            address(_token),
            _beneficiary,
            _startDay,
            _cliffDuration,
            _duration,
            _interval,
            _amount
        );

        return true;
    }

    function getVestingSchedule(address _token, address _beneficiary)
        public
        view
        onlyAllocatorOrSelf(_beneficiary, _token)
        returns (
            uint32 startDay,
            uint32 cliffDuration,
            uint32 duration,
            uint32 interval,
            uint256 amount
        )
    {
        return (
            _vestingSchedules[_token][_beneficiary].startDay,
            _vestingSchedules[_token][_beneficiary].cliffDuration,
            _vestingSchedules[_token][_beneficiary].duration,
            _vestingSchedules[_token][_beneficiary].interval,
            _vestingSchedules[_token][_beneficiary].amount
        );
    }

    function transferVestingSchedule(
        address _token,
        address _from,
        address _to
    ) external onlyAllocatorOrSelf(_from, _token) returns (bool ok) {
        require(
            hasVestingScheduleForToken(_from, address(_token)),
            "no vesting schedule found"
        );
        require(
            hasVestingScheduleForToken(_to, address(_token)),
            "the new beneficiary already has a vesting schedule for that token"
        );
        VestingSchedule storage vesting = _vestingSchedules[address(_token)][
            _from
        ];
        require(
            vesting.allocator != address(0),
            "the vesting schedule you want to transfer is not active"
        );
        // Create a new vesting schedule for the new beneficiary with the same information as the original vesting schedule
        addVestingSchedule(
            IERC20(_token),
            _to,
            vesting.startDay,
            vesting.cliffDuration,
            vesting.duration,
            vesting.interval,
            vesting.amount
        );
        // Mark the original vesting schedule as inactive
        revokeVesting(_from, _token, today());
        return true;
    }

    function withdraw(IERC20 _token) external returns (bool ok) {
        require(
            hasVestingScheduleForToken(msg.sender, address(_token)),
            "no vesting schedule for caller on specified token"
        );
        VestingSchedule storage vesting = _vestingSchedules[address(_token)][
            msg.sender
        ];
        require(
            today() >= vesting.startDay + vesting.cliffDuration,
            "too early to withdraw or cliff not finished"
        );
        require(vesting.amount > 0);
        require(vesting.allocator != address(0));
        uint256 vestedAmount = getVestedAmount(
            msg.sender,
            address(_token),
            today()
        );
        require(vestedAmount > 0, "no tokens available to withdraw");
        _token.transfer(msg.sender, vestedAmount);
        /* Emits the VestingTokensGranted event. */
        emit VestingTokensGranted(
            address(_token),
            msg.sender,
            vestedAmount,
            vesting.amount - vestedAmount
        );
        return true;
    }

    function getVestedAmount(
        address account,
        address token,
        uint32 onDay
    ) internal view returns (uint256 amountAvailable) {
        uint256 totalTokens = _vestingSchedules[token][msg.sender].amount;
        uint256 vested = totalTokens -
            getNotVestedAmount(account, token, onDay);
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
    function getNotVestedAmount(
        address account,
        address token,
        uint32 onDayOrToday
    ) internal view returns (uint256 amountNotVested) {
        VestingSchedule storage vesting = _vestingSchedules[token][account];
        uint32 onDay = _effectiveDay(onDayOrToday);

        // If there's no schedule, or before the vesting cliff, then the full amount is not vested.
        if (
            !(vesting.allocator != address(0)) ||
            onDay < vesting.startDay + vesting.cliffDuration
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
    function vestingForAccountAsOf(
        address account,
        address token,
        uint32 onDayOrToday
    )
        public
        view
        onlyAllocatorOrSelf(account, token)
        returns (
            uint256 amountVested,
            uint256 amountNotVested,
            uint256 vestAmount,
            uint32 vestStartDay,
            uint32 vestDuration,
            uint32 cliffDuration,
            uint32 vestIntervalDays
        )
    {
        VestingSchedule storage vesting = _vestingSchedules[token][account];
        uint256 notVestedAmount = getNotVestedAmount(
            account,
            token,
            onDayOrToday
        );
        uint256 vestingAmount = vesting.amount;

        return (
            vestingAmount - notVestedAmount,
            notVestedAmount,
            vestingAmount,
            vesting.startDay,
            vesting.duration,
            vesting.cliffDuration,
            vesting.interval
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
    function vestingAsOf(address token, uint32 onDayOrToday)
        public
        view
        returns (
            uint256 amountVested,
            uint256 amountNotVested,
            uint256 vestAmount,
            uint32 vestStartDay,
            uint32 vestDuration,
            uint32 cliffDuration,
            uint32 vestIntervalDays
        )
    {
        return vestingForAccountAsOf(msg.sender, token, onDayOrToday);
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
    function revokeVesting(
        address account,
        address token,
        uint32 onDay
    ) public onlyAllocator(account, token) returns (bool ok) {
        VestingSchedule storage vesting = _vestingSchedules[token][account];
        //uint256 notVestedAmount;

        // Make sure a vesting schedule has previously been set.
        require(vesting.allocator != address(0), "no active vesting");
        // Fail on likely erroneous input.
        require(onDay <= vesting.startDay + vesting.duration, "no effect");
        // Don"t let grantor revoke anf portion of vested amount.
        require(onDay >= today(), "cannot revoke vested holdings");

        // Kill the grant by updating the allocator to the 0x0 address.
        vesting.allocator = address(0);
        uint256 amountNotVested = getNotVestedAmount(account, token, onDay);
        // Update allocation and return tokens to allocator
        returnRemainingTokens(msg.sender, IERC20(token), amountNotVested);

        /* Emits the GrantRevoked event. */
        emit GrantRevoked(token, account, onDay);

        return true;
    }

    function returnRemainingTokens(
        address allocator,
        IERC20 token,
        uint256 amount
    ) internal returns (bool ok) {
        releaseAllocation(allocator, address(token), amount);
        require(
            _allocations[address(token)][allocator] >= amount,
            "not enough allocation to perform this task"
        );
        require(
            token.balanceOf(address(this)) >= amount,
            "the balance of the contract is not enough"
        );
        token.transfer(allocator, amount);
        updateAllocation(allocator, address(token), amount);
        return true;
    }

     // Modifiers

    modifier onlyAdmin() {
        // Distinguish insufficient overall balance from insufficient vested funds balance in failure msg.
        require(msg.sender == admin, "only admin can call this function");
        _;
    }

    modifier onlyAllocator(address account, address token) {
        // Distinguish insufficient overall balance from insufficient vested funds balance in failure msg.
        require(
            _vestingSchedules[token][account].allocator == msg.sender,
            "only allocators can call this function"
        );
        _;
    }

    modifier onlyAllocatorOrSelf(address _account, address _token) {
        require(
            _vestingSchedules[_token][_account].allocator == msg.sender ||
                msg.sender == _account,
            "caller is not the Allocator or Self"
        );
        _;
    }
}