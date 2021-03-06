package io.aegeus;

import org.junit.AfterClass;
import org.junit.BeforeClass;

import io.nessus.BlockchainFactory;
import io.nessus.Wallet.Address;
import io.nessus.testing.AbstractBlockchainTest;

public abstract class AbstractAegeusTest extends AbstractBlockchainTest {

    protected static AegeusBlockchain blockchain;
    protected static AegeusNetwork network;
    protected static AegeusWallet wallet;

    protected static Address addrBob;
    protected static Address addrMary;

    @BeforeClass
    public static void beforeClass() throws Exception {

        blockchain = (AegeusBlockchain) BlockchainFactory.getBlockchain(AegeusBlockchain.getAegeusConf(), AegeusBlockchain.class);
        network = (AegeusNetwork) blockchain.getNetwork();
        wallet = (AegeusWallet) blockchain.getWallet();

        importAddresses(wallet, AbstractAegeusTest.class);

        addrBob = wallet.getAddress(LABEL_BOB);
        addrMary = wallet.getAddress(LABEL_MARY);
    }

    @AfterClass
    public static void afterAegeusTest() throws Exception {

        wallet.redeemChange(LABEL_BOB, addrBob);
        wallet.redeemChange(LABEL_MARY, addrMary);
    }
}
