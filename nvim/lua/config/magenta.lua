local M = {}

M.profiles = {
  -- Basic configuration:~
  {
    name = "sonnet",
    provider = "anthropic",
    model = "claude-sonnet-4-5",
    fastModel = "claude-haiku-4-5",
    authType = "keychain",
  }
  {
    name = "haiku",
    provider = "anthropic",
    model = "claude-haiku-4-5",
    fastModel = "claude-haiku-4-5",
    authType = "keychain",
  },
  {
    -- With thinking/reasoning:~
    -- Opus 4.7 uses adaptive thinking (no explicit budget needed):
    name = "opus",
    provider = "anthropic",
    model = "claude-opus-4-7",
    thinking = {
      enabled = true,
      displayThinking = false, -- set true to stream thinking summaries
      effort = "max"           -- "low" | "medium" | "high" | "xhigh" | "max"
    }
  }
  -- Older models (Opus 4.6 and earlier) require explicit budget:
  {
    name = "old-opus",
    provider = "anthropic",
    model = "claude-opus-4-6",
    -- apiKeyEnvVar = "ANTHROPIC_API_KEY",
    thinking = {
      enabled = true,
      budgetTokens = 1024 -- must be >= 1024
    }
  }
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
