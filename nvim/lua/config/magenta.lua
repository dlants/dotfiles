local M = {}

M.profiles = {
  {
    name = "claude haiku 4.5",
    provider = "anthropic",
    model = "claude-haiku-4-5",
    fastModel = "claude-haiku-4-5",
    authType = "keychain",
  },
  -- {
  --   name = "claude opus-4.6",
  --   provider = "anthropic",
  --   model = "claude-opus-4-6",
  --   authType = "keychain",
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
