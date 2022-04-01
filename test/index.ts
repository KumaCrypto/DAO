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
  TestContract__factory,
} from "../typechain-types";

describe("DAO", function () {
  let DAO: DAO;
  let Token: CryptonToken;
  let TContract: TestContract;

  let signers: SignerWithAddress[];

  const minimumQuorum: number = 51;
  const period: number = 259200; //3 days
  const minimumVotes: number = 1000;
  const zero = ethers.BigNumber.from("0");
  const allowedTokens: BigNumber = ethers.utils.parseEther("1000");

  const defaultAmount: number = 999;

  const ABI = ["function increment(uint256 num)"];
  const iface = new ethers.utils.Interface(ABI);
  const txData = iface.encodeFunctionData("increment", [5]);

  beforeEach(async function () {
    signers = await ethers.getSigners();

    Token = await new CryptonToken__factory(signers[0]).deploy();
    DAO = await new DAO__factory(signers[0]).deploy(
      Token.address,
      minimumQuorum,
      period,
      minimumVotes
    );

    TContract = await new TestContract__factory(signers[0]).deploy();

    await Token.transfer(signers[1].address, allowedTokens);
    await Token.transfer(signers[2].address, allowedTokens);

    await Token.approve(DAO.address, allowedTokens);
    await Token.connect(signers[1]).approve(DAO.address, allowedTokens);
    await Token.connect(signers[2]).approve(DAO.address, allowedTokens);
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

  describe("deposit", () => {
    it("deposit: changed balance", async () => {
      await DAO.deposit(defaultAmount);
      expect(await DAO.getBalance(signers[0].address)).to.eq(defaultAmount);
    });

    it("deposit: incremented activeUsers", async () => {
      const usersBefore = await DAO.getActiveUsers();
      await DAO.deposit(defaultAmount);
      const usersAfter = await DAO.getActiveUsers();

      expect(usersBefore.add(1)).to.eq(usersAfter);
    });

    it("deposit: to emit 'Credited'", async () => {
      await expect(DAO.deposit(defaultAmount))
        .to.emit(DAO, "Credited")
        .withArgs(signers[0].address, defaultAmount);
    });
  });

  describe("receive", () => {
    it("receive: to emit 'Received'", async () => {
      const tx = {
        to: DAO.address,
        value: ethers.utils.parseEther("1"),
      };
      await expect(signers[0].sendTransaction(tx))
        .to.emit(DAO, "Received")
        .withArgs(signers[0].address, tx.value);
    });
  });

  describe("withdraw", () => {
    it("withdrawTokens: is correct", async () => {
      await DAO.deposit(defaultAmount);
      const balanceBefore = await DAO.getBalance(signers[0].address);
      await DAO.withdrawTokens(defaultAmount);
      const balanceAfter = await DAO.getBalance(signers[0].address);

      expect(balanceBefore.sub(defaultAmount)).to.eq(balanceAfter);
    });

    it("withdrawTokens: to emit TokensWithdrawn", async () => {
      await DAO.deposit(defaultAmount + 1);

      await expect(DAO.withdrawTokens(defaultAmount))
        .to.emit(DAO, "TokensWithdrawn")
        .withArgs(signers[0].address, defaultAmount);
    });

    it("withdrawTokens: reverted 'Insufficient funds'", async () => {
      await DAO.deposit(defaultAmount);
      await expect(DAO.withdrawTokens(defaultAmount + 1)).to.be.reverted;
    });

    it("withdrawTokens: reverted 'last voting isn't ended'", async () => {
      await DAO.deposit(defaultAmount);
      await DAO.addProposal(TContract.address, txData, "Some description");
      await DAO.vote(0, true);
      await expect(DAO.withdrawTokens(defaultAmount)).to.be.revertedWith(
        "DAO: The last vote you participated in hasn't ended yet"
      );
    });

    it("withdrawTokens: if balance = 0 => decrement", async () => {
      await DAO.deposit(defaultAmount);
      const usersBefore = await DAO.getActiveUsers();
      await DAO.withdrawTokens(defaultAmount);
      const usersAfter = await DAO.getActiveUsers();

      expect(usersBefore.sub(1)).to.eq(usersAfter);
    });

    it("withdrawETH: to emit ETHWithdrawn", async () => {
      const tx = {
        to: DAO.address,
        value: ethers.utils.parseEther("1"),
      };

      await signers[0].sendTransaction(tx);

      await expect(DAO.withdrawETH(signers[0].address, tx.value))
        .to.emit(DAO, "ETHWithdrawn")
        .withArgs(signers[0].address, tx.value);
    });
  });

  describe("addProposal", () => {
    it("addProposal", async () => {
      await DAO.addProposal(TContract.address, txData, "Some description");

      const time = (
        await ethers.provider.getBlock(await ethers.provider.getBlockNumber())
      ).timestamp;

      const result = await DAO.getProposalById(0);

      expect(result[0]).to.eq(TContract.address);
      expect(result[1]).to.eq(txData);
      expect(result[2]).to.eq("Some description");
      expect(result[3]).to.eq(false);
      expect(result[4]).to.eq(time + period);
      expect(result[5]).to.eq(zero);
      expect(result[6]).to.eq(zero);
      expect(result[7]).to.eq(zero);
    });

    it("addProposal: increment proposalsCounter", async () => {
      const counterBefore = await DAO.getLastProposalId();
      await DAO.addProposal(TContract.address, txData, "Some description");
      const counterAfter = await DAO.getLastProposalId();

      expect(counterBefore.add(1)).to.eq(counterAfter);
    });

    it("addProposal: to emit ProposalAdded", async () => {
      await expect(
        DAO.addProposal(TContract.address, txData, "Some description")
      )
        .to.emit(DAO, "ProposalAdded")
        .withArgs(
          await DAO.getLastProposalId(),
          (
            await ethers.provider.getBlock(
              await ethers.provider.getBlockNumber()
            )
          ).timestamp
        );
    });
  });

  describe("vote", () => {
    beforeEach(async function () {
      await DAO.addProposal(TContract.address, txData, "Some description");
      await DAO.deposit(defaultAmount);
    });

    it("vote: reverted 'timeEnded' ", async () => {
      await ethers.provider.send("evm_increaseTime", [period]);

      await expect(DAO.vote(0, true)).to.be.revertedWith(
        "DAO: The voting is already over"
      );
    });

    it("vote: reverted 'already voted' ", async () => {
      await DAO.vote(0, true);
      await expect(DAO.vote(0, true)).to.be.revertedWith(
        "DAO: You have already voted in this proposal"
      );
    });

    it("vote: increase consentings", async () => {
      await DAO.deposit(defaultAmount);
      const balance = await DAO.getBalance(signers[0].address);

      const consentingBefore = await DAO.getProposalById(0);
      await DAO.vote(0, true);
      const consentingAfter = await DAO.getProposalById(0);

      expect(consentingBefore[5].add(balance)).to.eq(consentingAfter[5]);
    });

    it("vote: increase dissenters", async () => {
      await DAO.deposit(defaultAmount);
      const balance = await DAO.getBalance(signers[0].address);

      const dissentersBefore = await DAO.getProposalById(0);
      await DAO.vote(0, false);
      const dissentersgAfter = await DAO.getProposalById(0);

      expect(dissentersBefore[6].add(balance)).to.eq(dissentersgAfter[6]);
    });

    it("vote: changed isVoted", async () => {
      await DAO.vote(0, true);
      expect(await DAO.isUserVoted(signers[0].address, 0)).to.eq(true);
    });

    it("vote: changed lastVoteEndTime", async () => {
      await DAO.vote(0, true);
      const time = await DAO.getProposalById(0);

      expect(await DAO.userLastVoteEndTime(signers[0].address)).to.eq(time[4]);
    });

    it("vote: usersVoted incremented", async () => {
      const proposalBefore = await DAO.getProposalById(0);
      await DAO.vote(0, true);
      const proposalAfter = await DAO.getProposalById(0);
      expect(proposalBefore[7].add(1)).to.eq(proposalAfter[7]);
    });
  });

  describe("vote exception", () => {
    it("vote: reverted 'no tokens'", async () => {
      await DAO.addProposal(TContract.address, txData, "Some description");

      await expect(DAO.vote(0, true)).to.be.revertedWith(
        "DAO: No tokens on balance"
      );
    });
  });

  describe("finishProposal", () => {
    beforeEach(async function () {
      await DAO.addProposal(TContract.address, txData, "Some description");
      await DAO.deposit(defaultAmount);
      await DAO.connect(signers[1]).deposit(defaultAmount);
      await DAO.connect(signers[2]).deposit(defaultAmount);
    });

    it("finishProposal: reverted 'Voting time is not over yet' ", async () => {
      await expect(DAO.finishProposal(0)).to.be.revertedWith(
        "DAO: Voting time is not over yet"
      );
    });

    it("finishProposal: reverted 'Voting has already ended' ", async () => {
      await ethers.provider.send("evm_increaseTime", [period]);

      await DAO.finishProposal(0);
      await expect(DAO.finishProposal(0)).to.be.revertedWith(
        "DAO: Voting has already ended"
      );
    });

    it("finishProposal: minimum votes less then needed ", async () => {
      await DAO.vote(0, true);
      await ethers.provider.send("evm_increaseTime", [period]);
      await expect(DAO.finishProposal(0))
        .to.emit(DAO, "Finished")
        .withArgs(0, false, TContract.address, defaultAmount, 1);
    });

    it("finishProposal: changed proposal status", async () => {
      await DAO.vote(0, true);
      await ethers.provider.send("evm_increaseTime", [period]);
      await DAO.finishProposal(0);
      const isFinished = await DAO.getProposalById(0);
      expect(isFinished[3]).to.eq(true);
    });

    it("finishProposal: to emit 'Finished'", async () => {
      await DAO.vote(0, true);
      await DAO.connect(signers[1]).vote(0, true);
      await DAO.connect(signers[2]).vote(0, true);
      await ethers.provider.send("evm_increaseTime", [period]);
      await expect(DAO.finishProposal(0))
        .to.emit(DAO, "Finished")
        .withArgs(0, true, TContract.address, defaultAmount * 3, 3);
    });

    it("finishProposal: call target contract", async () => {
      await DAO.vote(0, true);
      await DAO.connect(signers[1]).vote(0, true);
      await DAO.connect(signers[2]).vote(0, true);

      await ethers.provider.send("evm_increaseTime", [period]);
      await DAO.finishProposal(0);
      expect(await TContract.current()).to.eq(5);
    });
    describe("endProposal", () => {
      const ABI = ["function endProposal(uint256 proposalId)"];
      const iface = new ethers.utils.Interface(ABI);
      const txData = iface.encodeFunctionData("endProposal", [0]);

      it("endProposal: ended proposal", async () => {
        await DAO.addProposal(DAO.address, txData, "Some description");

        await DAO.vote(1, true);
        await DAO.connect(signers[1]).vote(1, true);
        await DAO.connect(signers[2]).vote(1, true);

        await ethers.provider.send("evm_increaseTime", [period]);
        await DAO.finishProposal(1);
        const result = await DAO.getProposalById(0);
        expect(result[3]).to.eq(true);
      });

      it("endProposal: reverted 'not a contract'", async () => {
        await ethers.provider.send("evm_increaseTime", [period]);
        await expect(DAO.endProposal(0)).to.be.revertedWith(
          "Only a contract can end proposal"
        );
      });

      it("endProposal: to emit 'FinishedEmergency'", async () => {
        await DAO.addProposal(DAO.address, txData, "Some description");

        await DAO.vote(1, true);
        await DAO.connect(signers[1]).vote(1, true);
        await DAO.connect(signers[2]).vote(1, true);

        await ethers.provider.send("evm_increaseTime", [period]);
        await expect(DAO.finishProposal(1))
          .to.emit(DAO, "FinishedEmergency")
          .withArgs(0);
      });
    });
  });
});
