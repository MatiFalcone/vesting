const Vesting = artifacts.require("Vesting");
const Token = artifacts.require("Token");

module.exports = async function (deployer, network, accounts) {
  await deployer.deploy(Token);
  const token = await Token.deployed();
  const fee = 5;

  await deployer.deploy(Vesting, token.address, fee, accounts[0]);
};