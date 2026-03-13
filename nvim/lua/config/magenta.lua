local M = {}

M.profiles = {
  {
    name = "opus-4.6(gateway)",
    provider = "anthropic",
    model = "claude-opus-4-6",
    apiKeyEnvVar = "HACKATHON_ANTHROPIC_API_KEY",
    baseUrl = "https://internal-devci.poc.learning.amplify.com/llm-gateway/chat/completions",
    -- authType = "max",
    thinking = {
      enabled = true,
      budgetTokens = 1024
    }
  },
  -- {
  --   name = "sonnet-4.5(gateway)",
  --   provider = "anthropic",
  --   model = "claude-sonnet-4-5",
  --   apiKeyEnvVar = "HACKATHON_ANTHROPIC_API_KEY",
  --   baseUrl = "https://internal-devci.poc.learning.amplify.com/llm-gateway/chat/completions",
  --   -- authType = "max",
  --   thinking = {
  --     enabled = true,
  --     budgetTokens = 1024
  --   }
  -- },
}
M.editPrediction = {
  profile = {
    provider = "anthropic",
    model = "claude-haiku-4-5",
    authType = "max",
  }
}
M.chimeVolume = nil -- use default

return M
