const { accounts, contract } = require('@openzeppelin/test-environment');
const { BN, ether, expectEvent, expectRevert, time } = require('@openzeppelin/test-helpers');
const { assert } = require('chai');
const { expect } = require('chai')
  .should();
const Web3 = require('web3');
const Token = artifacts.require("Token");
const Vesting = artifacts.require("Vesting");

let web3 = new Web3('http://127.0.0.1:8545');

describe('Vesting', function() {

  const [ deployer, feeAccount ] = accounts;
  let admin, token, fee, vesting;

  beforeEach(async function () {
    // Advance to the next block to correctly read time in the solidity "now" function interpreted by ganache
    admin = deployer;
    token = await Token.new();
    fee = web3.utils.toBN(5)
    vesting = await Vesting.new(token.address, fee, feeAccount);
    //console.log(vesting.methods);
  });

  describe('Token contract deployment', async () => {
    it('contract has a name', async () => {
      const name = await token.name()
      assert.equal(name, 'Vesting')
    })
    it('contract has a symbol', async () => {
      const symbol = await token.symbol()
      assert.equal(symbol, 'VTK')
    })
  })

  describe('Vesting contract deployment', async () => {
    it('contract has a token', async () => {
      const tokenAddress = await vesting.vestingToken()
      assert.equal(tokenAddress, token.address)
    })
    it('contract has a fee', async () => {
      const contractFee = await vesting.vestingFee()
      assert.equal(contractFee.toString(), fee.toString())
    })
    it('contract has a fee account', async () => {
      const contractFeeAccount = await vesting.vestingFeeAccount()
      assert.equal(contractFeeAccount, feeAccount)
    })
  })
/*   it('reverts if the closing time equals the opening time', async function () {
    await expectRevert(IotexPadTokenCrowdsale.new(
      this.rate, this.wallet, this.token.address, this.openingTime, this.openingTime, this.goal, this.teamFund, this.partnersFund, this.advisorsFund, this.reserveFund, this.oneYearReleaseTime
    ), 'TimedCrowdsale: opening time is not before closing time');
  });

  it('reverts if the opening time is in the past', async function () {
    await expectRevert(IotexPadTokenCrowdsale.new(
      this.rate, this.wallet, this.token.address, (await time.latest()).sub(time.duration.days(1)), this.closingTime, this.goal, this.teamFund, this.partnersFund, this.advisorsFund, this.reserveFund, this.oneYearReleaseTime   
    ), 'TimedCrowdsale: opening time is before current time');
  });

  context('with crowdsale', function () {
     beforeEach(async function () {
      this.crowdsale = await IotexPadTokenCrowdsale.new(
        this.rate, this.wallet, this.token.address, this.openingTime, this.closingTime, this.goal, this.teamFund, this.partnersFund, this.advisorsFund, this.reserveFund, this.oneYearReleaseTime
      );
    });

    describe('accepting payments', function () {
      it('should reject payments before start', async function () {
        expect(await this.crowdsale.isOpen()).to.equal(false);
        await expectRevert(this.crowdsale.send(value), 'TimedCrowdsale: not open');
        await expectRevert(this.crowdsale.buyTokens(investor, { from: purchaser, value: value }),
          'TimedCrowdsale: not open'
        );
      });

      it('should accept payments after start', async function () {
        await time.increaseTo(this.openingTime);
        expect(await this.crowdsale.isOpen()).to.equal(true);
        await this.crowdsale.send(value);
        await this.crowdsale.buyTokens(investor, { value: value, from: purchaser });
      });

      it('should reject payments after end', async function () {
        await time.increaseTo(this.afterClosingTime);
        await expectRevert(this.crowdsale.send(value), 'TimedCrowdsale: not open');
        await expectRevert(this.crowdsale.buyTokens(investor, { value: value, from: purchaser }),
          'TimedCrowdsale: not open'
        );
      });

      it('should be ended only after end', async function () {
        expect(await this.crowdsale.hasClosed()).to.equal(false);
        await time.increaseTo(this.afterClosingTime);
        expect(await this.crowdsale.isOpen()).to.equal(false);
        expect(await this.crowdsale.hasClosed()).to.equal(true);
      });

    });
  }); */
});