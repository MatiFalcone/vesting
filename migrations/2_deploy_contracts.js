const Vesting = artifacts.require("Vesting");
const Token = artifacts.require("Token");

module.exports = async function (deployer) {
  await deployer.deploy(Token);
  const token = await Token.deployed();

  await deployer.deploy(Vesting, token.address);
};