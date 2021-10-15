const BN = web3.utils.BN;

require('chai')
  .use(require('chai-as-promised'))
  .use(require('chai-bn')(BN))
  .should();

const {increaseTime} = require('./utils.js');
const {signERC2612Permit} = require('eth-permit');

const OneToken = new BN(web3.utils.toWei('1', 'ether'));

const ParsiqToken = artifacts.require('ParsiqToken');
const TestERC20Token = artifacts.require('TestERC20Token');

contract('Parsiq Token', async (accounts) => {
  const admin = accounts[0];
  const user1 = accounts[1];
  const user2 = accounts[2];
  const bridge = accounts[3];
  let token;

  beforeEach(async () => {
    token = await ParsiqToken.new();
    await token.authorizeBridge(bridge);
    await token.mint(bridge, web3.utils.toWei('50000000', 'ether'), {
      from: bridge,
    });
    await token.transfer(admin, web3.utils.toWei('1000', 'ether'), {
      from: bridge,
    });
  });

  describe('Default', () => {
    it('receives token name', async () => {
      (await token.name()).should.equal('Parsiq Token');
    });

    it('receives token symbol', async () => {
      (await token.symbol()).should.equal('PRQ');
    });

    it('receives decimals', async () => {
      (await token.decimals()).should.bignumber.equal('18');
    });

    it('DOMAIN_SEPARATOR, PERMIT_TYPEHASH', async () => {
      const name = await token.name();

      expect(await token.DOMAIN_SEPARATOR()).to.eq(
        web3.utils.sha3(
          web3.eth.abi.encodeParameters(
            ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
            [
              web3.utils.sha3(
                'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
              ),
              web3.utils.sha3(name),
              web3.utils.sha3('1'),
              1,
              token.address,
            ]
          )
        )
      );
      expect(await token.PERMIT_TYPEHASH()).to.eq(
        web3.utils.sha3(
          'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
        )
      );
    });
  });

  describe('Transfer', () => {
    beforeEach(async () => {
      await token.pause();
    });

    it('allows owner to transfer tokens', async () => {
      await token.transfer(user2, OneToken);

      (await token.balanceOf(user2)).should.be.bignumber.equal(OneToken);
    });

    it('should not transfer when transfers are disabled', async () => {
      await token.transfer(user1, OneToken);

      await token.transfer(user2, OneToken, {
        from: user1,
      }).should.be.rejected;
    });

    it('should transfer when transfers are enabled', async () => {
      await token.unpause();
      await token.transfer(user1, OneToken);

      await token.transfer(user2, OneToken, {
        from: user1,
      });

      (await token.balanceOf(user2)).should.be.bignumber.equal(OneToken);
    });

    it('stranger cannot transfer tokens', async () => {
      await token.transfer(user2, OneToken, {
        from: user2,
      }).should.be.rejected;
    });

    it('cannot transfer to address(0)', async () => {
      await token.transfer('0x0', OneToken).should.be.rejected;
    });
  });

  describe('Burning', () => {
    it('should allow burning', async () => {
      const totalSupply = await token.totalSupply();
      const balance = await token.balanceOf(admin);

      await token.burn(OneToken);

      (await token.balanceOf(admin)).should.bignumber.equal(
        balance.sub(OneToken)
      );
      (await token.totalSupply()).should.bignumber.equal(
        totalSupply.sub(OneToken)
      );
    });
  });

  describe('Governance', () => {
    beforeEach(async () => {
      await token.transfer(user1, OneToken);
    });

    describe('Governance board perspective', () => {
      it('forbids to call governedTransfer without a review', async () => {
        await token.governedTransfer(user1, user2, OneToken).should.be.rejected;
      });

      it('forbids to call governedTransfer before decision period', async () => {
        await token.review(user1);
        await increaseTime(86400 / 2);

        await token.governedTransfer(user1, user2, OneToken).should.be.rejected;
      });

      it('allows governance board to governedTransfer on decision time', async () => {
        await token.review(user1);
        await increaseTime(86401);

        await token.governedTransfer(user1, user2, OneToken);

        (await token.balanceOf(user2)).should.bignumber.equal(OneToken);
      });

      it('forbids to call governedTransfer after decision period', async () => {
        await token.review(user1);
        await increaseTime(86401 * 2);

        await token.governedTransfer(user1, user2, OneToken).should.be.rejected;
      });

      it('allows to resolve without a review', async () => {
        await token.review(user1);
        await increaseTime(86400 / 2);

        await token.resolve(user1);
      });

      it('forbids to call governedTransfer after resolve', async () => {
        await token.review(user1);
        await increaseTime(86400 / 2);

        await token.resolve(user1);

        await token.governedTransfer(user1, user2, OneToken).should.be.rejected;
      });
    });

    describe('User perspective', () => {
      it('forbids to move funds under review', async () => {
        await token.review(user1);

        await token.transfer(user2, OneToken, {from: user1}).should.be.rejected;
      });

      it('forbids to move funds under review after review period', async () => {
        await token.review(user1);
        await increaseTime(86401);

        await token.transfer(user2, OneToken, {from: user1}).should.be.rejected;
      });

      it('allows to move funds after decision period', async () => {
        await token.review(user1);
        await increaseTime(86401 * 2);

        await token.transfer(user2, OneToken, {from: user1});

        (await token.balanceOf(user2)).should.bignumber.equal(OneToken);
      });

      it('allows to move funds on resolve', async () => {
        await token.review(user1);
        await increaseTime(86400 / 2);
        await token.resolve(user1);

        await token.transfer(user2, OneToken, {from: user1});

        (await token.balanceOf(user2)).should.bignumber.equal(OneToken);
      });
    });

    describe('Takeaway', () => {
      it('should pass governance', async () => {
        await token.electGovernanceBoard(user1);

        await token.takeGovernance({from: user1});

        (await token.governanceBoard()).should.equal(user1);
      });
    });
  });

  describe('Mint', () => {
    it('non authorized should not mint', async () => {
      await token.mint(OneToken, {from: admin}).should.be.rejected;
    });
  });

  describe('Transfer Many', () => {
    it('should send to 100 users', async () => {
      const N = 100;
      const to = [];
      const value = [];
      for (let i = 0; i < N; i++) {
        const account = accounts[i + 1];
        to.push(account);
        value.push(1);
      }

      const tx = await token.transferMany(to, value);
    });
  });

  describe('Token Recovery', () => {
    let erc20Token;

    beforeEach(async () => {
      erc20Token = await TestERC20Token.new();

      await erc20Token.mint(user1, OneToken);
      await erc20Token.transfer(token.address, OneToken, {
        from: user1,
      });
    });

    it('owner can recover other tokens', async () => {
      await token.recoverTokens(erc20Token.address, user1, OneToken);

      (await erc20Token.balanceOf(token.address)).should.be.bignumber.equal(
        '0'
      );
      (await erc20Token.balanceOf(user1)).should.be.bignumber.equal(OneToken);
    });

    it('stranger cannot recover other tokens', async () => {
      await token.recoverTokens(erc20Token.address, user1, OneToken, {
        from: user1,
      }).should.be.rejected;
    });
  });

  describe('Permit', () => {
    it('permit', async () => {
      const testAmount = OneToken.mul(new BN(10));
      const result = await signERC2612Permit(
        web3.currentProvider,
        token.address,
        admin,
        user1,
        testAmount
      );

      await token.permit(
        admin,
        user1,
        testAmount,
        result.deadline,
        result.v,
        result.r,
        result.s
      );

      (await token.allowance(admin, user1)).should.be.bignumber.eq(testAmount);
      (await token.nonces(admin)).should.be.bignumber.eq(new BN(1));
    });
  });
});
