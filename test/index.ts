/* eslint-disable prettier/prettier */
/* eslint-disable node/no-missing-import */
/* eslint-disable camelcase */

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from "ethers";

import {
  DAO,
  DAO__factory,
  CryptonToken,
  CryptonToken__factory,
  TestContract,
  TestContract__factory
} from "../typechain-types";

describe("DAO", function () {
  let DAO: DAO;
  let Token: CryptonToken;
  let TContract: TestContract;

  let signers: SignerWithAddress[];

  const minimumQuorum: number = 51;
  const period: number = 259200; //3 days
  const minimumVotes: BigNumber = ethers.utils.parseEther("1000");
  const zero = ethers.BigNumber.from("0");

  const defaultAmount: number = 1000;

  beforeEach(async function () {
    signers = await ethers.getSigners();

    Token = await new CryptonToken__factory(signers[0]).deploy();
    DAO = await new DAO__factory(signers[0]).deploy(Token.address, minimumQuorum, period, minimumVotes);
    TContract = await new TestContract__factory(signers[0]).deploy();

    await Token.transfer(signers[1].address, minimumVotes);
    await Token.transfer(signers[2].address, minimumVotes);

    await Token.approve(DAO.address, minimumVotes);
    await Token.connect(signers[1]).approve(DAO.address, minimumVotes);
    await Token.connect(signers[2]).approve(DAO.address, minimumVotes);
  });

  describe("Checking getters", () => {

    it("getToken", async () => {
      expect(await DAO.getToken()).to.eq(Token.address);
    });

    it("getMinQuorum", async () => {
      expect(await DAO.getMinQuorum()).to.eq(minimumQuorum);
    });

    it("getDebatePeriod", async () => {
      expect(await DAO.getDebatePeriod()).to.eq(period);
    });

    it("getMinVotes", async () => {
      expect(await DAO.getMinVotes()).to.eq(minimumVotes);
    });

    it("balances", async () => {
      expect(await DAO.getBalance(signers[0].address)).to.eq(0);
    });

  });

  describe("deposit & withdraw", () => {

    it("deposit changed balance", async () => {
      await DAO.deposit(defaultAmount);
      expect(await DAO.getBalance(signers[0].address)).to.eq(defaultAmount);
    });

    it("deposit to emit 'credited'", async () => {
      await expect(DAO.deposit(defaultAmount)).to.emit(DAO, "credited").withArgs(signers[0].address, defaultAmount);
    });

    // it("withdraw reverted 'Insufficient funds'", async () => {
    //   console.log(ethers.utils.formatEther(await ethers.provider.getBalance(signers[0].address)));
    //   await expect(DAO.withdraw(defaultAmount)).to.be.revertedWith("DAO: Insufficient funds on the balance");
    // });

    // it("withdraw reverted 'last voting isn't ended'", async () => {
    //   await DAO.deposit(defaultAmount)
    //   await expect(DAO.withdraw(defaultAmount)).to.be.revertedWith("DAO: The last vote you participated in hasn't ended yet");
    // });

  });

  describe("addProposal", () => {

    it("addProposal", async () => {
      let ABI = ["function increment(uint256 num)"];
      let iface = new ethers.utils.Interface(ABI);
      const txData = iface.encodeFunctionData("increment", [5]);
      await DAO.addProposal(TContract.address, txData, "Some description");
      const time = ((await ethers.provider.getBlock(await ethers.provider.getBlockNumber()))).timestamp;
      const result = await DAO.getProposalById(0);
      expect(result[0]).to.eq(TContract.address);
      expect(result[1]).to.eq(txData);
      expect(result[2]).to.eq(time);
      expect(result[3]).to.eq(zero);
      expect(result[4]).to.eq(zero);
      expect(result[5]).to.eq(zero);
      expect(result[6]).to.eq(zero);
      expect(result[7]).to.eq("Some description");
    });
  });

});