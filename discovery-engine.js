/**
 * Agent Discovery Engine
 * Scans Moltbook + OpenClaw Agent Registry
 * Integrates with ZopAI for 1600+ agent semantic search
 */

const express = require('express');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 3001;

// Configuration
const MOLTBOOK_GRAPHQL = 'https://api.moltbook.com/graphql';
const ZOPAI_API = 'https://zop.ai/api/search';

// Agent capability tags
const CAPABILITY_TAGS = [
  'trading',
  'research',
  'content',
  'dev',
  'oracle',
  'automation'
];

/**
 * Scan Moltbook for agent registrations
 */
async function scanMoltbookAgents() {
  try {
    const response = await axios.post(MOLTBOOK_GRAPHQL, {
      query: `
        query {
          agents(first: 1000) {
            id
            name
            description
            capabilities
            walletAddress
            stats {
              transactions
              volume
            }
          }
        }
      `
    });

    return response.data?.data?.agents || [];

  } catch (error) {
    console.error('Moltbook scan error:', error.message);
    return [];
  }
}

/**
 * Index ZopAI agents
 */
async function indexZopAIAgents() {
  try {
    const response = await axios.get(ZOPAI_API, {
      params: {
        q: 'agent',
        limit: 100
      }
    });

    return response.data?.results || [];

  } catch (error) {
    console.error('ZopAI index error:', error.message);
    return [];
  }
}

/**
 * Parse capability tags from text
 */
function parseCapabilities(capabilitiesStr) {
  if (!capabilitiesStr) return [];

  const capabilities = capabilitiesStr
    .toLowerCase()
    .split(/[,;\s]+/)
    .filter(cap => CAPABILITY_TAGS.includes(cap.trim()));

  return [...new Set(capabilities)];
}

/**
 * Merge and deduplicate agents
 */
function mergeAndDeduplicate(agents1, agents2) {
  const merged = [...agents1, ...agents2];
  const unique = new Map();

  return merged.filter(agent => {
    const key = agent.id || agent.name;
    if (unique.has(key)) return false;
    unique.set(key, true);
    return true;
  });
}

/**
 * Calculate activity scores
 */
function calculateActivityScores(agents) {
  return agents.map(agent => {
    let score = 0;

    if (agent.walletAddress) score += 30;
    if (agent.stats && (agent.stats.transactions > 0 || agent.stats.volume > 0)) {
      score += 20;
    }

    const capCount = agent.capabilities ? agent.capabilities.length : 0;
    score += Math.min(capCount * 10, 50);

    return {
      ...agent,
      activityScore: Math.min(score, 100)
    };
  });
}

/**
 * Analyze trends
 */
function analyzeTrends(agents) {
  const capabilityCounts = {};
  agents.forEach(agent => {
    agent.capabilities.forEach(cap => {
      capabilityCounts[cap] = (capabilityCounts[cap] || 0) + 1;
    });
  });

  const trending = Object.entries(capabilityCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([cap, count]) => ({ capability: cap, count, percentage: (count / agents.length * 100).toFixed(1) }));

  return {
    totalAgents: agents.length,
    capabilityDistribution: capabilityCounts,
    trendingCapabilities: trending
  };
}

// API endpoints
app.get('/api/agents/discover', async (req, res) => {
  try {
    console.log('🔍 Discovering agents...');

    const moltbookAgents = await scanMoltbookAgents();
    console.log(`✅ Found ${moltbookAgents.length} agents from Moltbook`);

    const zopaiAgents = await indexZopAIAgents();
    console.log(`✅ Indexed ${zopaiAgents.length} agents from ZopAI`);

    const allAgents = mergeAndDeduplicate(moltbookAgents, zopaiAgents);
    console.log(`✅ Total unique agents: ${allAgents.length}`);

    const scoredAgents = calculateActivityScores(allAgents);
    console.log(`✅ Activity scores calculated`);

    const trends = analyzeTrends(scoredAgents);
    console.log(`✅ Trends analyzed`);

    res.json({
      success: true,
      data: {
        total: allAgents.length,
        sources: {
          moltbook: moltbookAgents.length,
          zopai: zopaiAgents.length
        },
        agents: scoredAgents,
        topAgents: scoredAgents.slice(0, 10),
        trends: trends
      }
    });

  } catch (error) {
    console.error('❌ Discovery error:', error.message);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Health check
app.get('/health', (req, rea) => {
  res.json({
    status: 'ok',
    service: 'Agent Discovery Engine',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`🚀 Agent Discovery Engine running on port ${PORT}`);
  console.log(`📍 Moltbook: ${MOLTBOOK_GRAPHQL}`);
  console.log(`📍 ZopAI: ${ZOPAI_API}`);
});
