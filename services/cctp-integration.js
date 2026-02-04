/**
 * CCTP Integration Service
 * Circle Transfer Protocol (CCTP) for USDC payments
 * Enables agent-native commerce
 */

const axios = require('axios');

// CCTP Configuration (Circle Transfer Protocol)
const CCTP_BASE_URL = 'https://api.circle.com/v3';
const CCTP_API_KEY = process.env.CIRCLE_API_KEY || '';

// USDC contract address on Base
const USDC_BASE = '0x833589fCD6eDbF4E2608BC1146A412e5C6';

// Smart contract addresses (will be deployed)
const AGENT_REGISTRY_ADDRESS = process.env.AGENT_REGISTRY_ADDRESS || '';
const MARKETPLACE_ADDRESS = process.env.MARKETPLACE_ADDRESS || '';

/**
 * Create CCTP transfer intent
 * @param {string} sender - From address (agent wallet)
 * @param {string} recipient - To address (task creator or agent)
 * @param {number} amount - USDC amount (in wei, 6 decimals)
 * @param {object} metadata - Additional metadata
 */
async function createTransferIntent(sender, recipient, amount, metadata = {}) {
  try {
    console.log(`🔄 Creating CCTP intent: ${sender} -> ${recipient}: ${amount} USDC`);

    const response = await axios.post(
      `${CCTP_BASE_URL}/transfers/transferIntents`,
      {
        headers: {
          'Authorization': `Bearer ${CCTP_API_KEY}`,
          'Content-Type': 'application/json'
        },
        data: {
          sourceAddress: sender,
          destinationAddress: recipient,
          amount: {
            currency: 'USD',
            amount: (amount / 1e6).toString(), // Convert wei to USDC (6 decimals)
            value: (amount / 1e6).toString()
          },
          idempotencyKey: `transfer-${Date.now()}-${Math.random().toString(36).substring(0, 8)}`,
          metadata: JSON.stringify(metadata)
        }
      }
    );

    console.log('✅ CCTP intent created:', response.data);

    return {
      success: true,
      id: response.data?.id,
      status: response.data?.status || 'created'
    };

  } catch (error) {
    console.error('❌ CCTP error:', error.message);
    return {
      success: false,
      error: error.message
    };
  }
}

/**
 * Execute CCTP transfer
 * @param {string} intentId - CCTP intent ID
 * @param {string} senderSignature - Signature from sender wallet
 */
async function executeTransfer(intentId, senderSignature) {
  try {
    console.log(`⚡ Executing CCTP transfer: ${intentId}`);

    const response = await axios.post(
      `${CCTP_BASE_URL}/transfers/execute`,
      {
        headers: {
          'Authorization': `Bearer ${CCTP_API_KEY}`,
          'Content-Type': 'application/json'
        },
        data: {
          id: intentId,
          signature: senderSignature
        }
      }
    );

    console.log('✅ CCTP transfer executed:', response.data);

    return {
      success: true,
      txHash: response.data?.transfer?.txHash,
      status: response.data?.transfer?.status || 'completed'
    };

  } catch (error) {
    console.error('❌ CCTP execution error:', error.message);
    return {
      success: false,
      error: error.message
    };
  }
}

/**
 * Get transfer status
 * @param {string} intentId - CCTP intent ID
 */
async function getTransferStatus(intentId) {
  try {
    console.log(`📊 Checking CCTP transfer status: ${intentId}`);

    const response = await axios.get(
      `${CCTP_BASE_URL}/transfers/transferIntents/${intentId}`,
      {
        headers: {
          'Authorization': `Bearer ${CCTP_API_KEY}`
        }
      }
    );

    console.log('✅ CCTP status:', response.data);

    return response.data;

  } catch (error) {
    console.error('❌ CCTP status error:', error.message);
    return null;
  }
}

/**
 * Agent payment for task completion
 * Simplified flow: Agent calls this to receive payment from task creator
 */
async function receiveTaskPayment(taskId, taskCreator, agentAddress, amount) {
  console.log(`💰 Agent receiving payment for task ${taskId}: ${amount} USDC`);

  // Create CCTP transfer intent
  const intent = await createTransferIntent(
    taskCreator,
    agentAddress,
    amount,
    {
      type: 'task_payment',
      taskId: taskId.toString(),
      marketplace: MARKETPLACE_ADDRESS
    }
  );

  if (!intent.success) {
    throw new Error(`Failed to create CCTP intent: ${intent.error}`);
  }

  console.log(`✅ Payment intent created: ${intent.id}`);

  return {
    intentId: intent.id,
    status: 'created'
  };
}

/**
 * Verify payment status
 */
async function verifyPayment(intentId) {
  const status = await getTransferStatus(intentId);

  if (!status) {
    throw new Error(`Failed to get CCTP status`);
  }

  if (status.status === 'completed') {
    return {
      success: true,
      completed: true,
      txHash: status.transfer?.txHash
    };
  }

  return {
    success: true,
    completed: false,
    status: status.status
  };
}

/**
 * USDC balance check
 * @param {string} address - Wallet address
 */
async function getUSDCBalance(address) {
  try {
    console.log(`💳 Checking USDC balance for ${address}`);

    const response = await axios.post(
      `${CCTP_BASE_URL}/wallets/balance`,
      {
        headers: {
          'Authorization': `Bearer ${CCTP_API_KEY}`,
          'Content-Type': 'application/json'
        },
        data: {
          addresses: [address],
          tokenAddresses: [USDC_BASE]
        }
      }
    );

    const balance = response.data?.balances?.[address]?.[USDC_BASE];
    const amount = balance?.amount || '0';

    console.log(`✅ Balance: ${amount} USDC`);

    return {
      success: true,
      balance: amount,
      address: address
    };

  } catch (error) {
    console.error('❌ Balance check error:', error.message);
    return {
      success: false,
      error: error.message,
      balance: '0'
    };
  }
}

/**
 * Multi-agent payment split
 * Automatically distribute payment among multiple agents
 */
async function splitPayment(sender, recipients, amounts) {
  console.log(`💰 Splitting payment to ${recipients.length} agents`);

  const totalAmount = amounts.reduce((sum, amt) => sum + amt, 0);

  for (let i = 0; i < recipients.length; i++) {
    const intent = await createTransferIntent(
      sender,
      recipients[i],
      amounts[i],
      {
        type: 'split_payment',
        splitIndex: i,
        totalRecipients: recipients.length
      }
    );

    if (!intent.success) {
      console.error(`❌ Failed to create split intent for agent ${i}`);
    }
  }

  return {
    success: true,
    totalAmount
  };
}

module.exports = {
  createTransferIntent,
  executeTransfer,
  getTransferStatus,
  receiveTaskPayment,
  verifyPayment,
  getUSDCBalance,
  splitPayment,

  // Configuration
  CCTP_BASE_URL,
  USDC_BASE,
  CCTP_API_KEY,
  AGENT_REGISTRY_ADDRESS,
  MARKETPLACE_ADDRESS
};
