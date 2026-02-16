-- OS-specific magenta.nvim configuration
local is_linux = vim.loop.os_uname().sysname == "Linux"

local M = {}

if is_linux then
  M.profiles = {
    {
      name = "opus-4.6(bedrock-global)",
      provider = "bedrock",
      model = "global.anthropic.claude-opus-4-6-v1",
      fastModel = "global.anthropic.claude-haiku-4-5-20251001-v1:0",
      authType = "max",
      env = {
        AWS_PROFILE = "dev.ai-inference",
        AWS_REGION = "us-west-2"
      },
      thinking = {
        enabled = true,
        budgetTokens = 4096
      }
    },
    {
      name = "opus-4.6(bedrock)",
      provider = "bedrock",
      model = "us.anthropic.claude-opus-4-6-v1",
      fastModel = "global.anthropic.claude-haiku-4-5-20251001-v1:0",
      authType = "max",
      env = {
        AWS_PROFILE = "dev.ai-inference",
        AWS_REGION = "us-west-2"
      },
      thinking = {
        enabled = true,
        budgetTokens = 1024
      }
    },
    {
      name = "sonnet-4.5(max)",
      provider = "anthropic",
      model = "claude-sonnet-4-5",
      authType = "max",
      thinking = {
        enabled = true,
        budgetTokens = 1024
      }
    },
  }
  M.editPrediction = {
    profile = {
      provider = "bedrock",
      model = "global.anthropic.claude-haiku-4-5-20251001-v1:0",
    }
  }
  M.chimeVolume = .01

  M.pkb = {
    path = "~/pkb",
    embeddingModel = {
      provider = "bedrock",
      model = "cohere.embed-v4:0",
      region = "us-west-2", -- optional, defaults to us-west-2
    },
  }
else
  M.profiles = {
    {
      name = "opus-4.6(max)",
      provider = "anthropic",
      model = "claude-opus-4-6",
      authType = "max",
      thinking = {
        enabled = true,
        budgetTokens = 1024
      }
    },
    {
      name = "sonnet-4.5(max)",
      provider = "anthropic",
      model = "claude-sonnet-4-5",
      authType = "max",
      thinking = {
        enabled = true,
        budgetTokens = 1024
      }
    },
  }
  M.editPrediction = {
    profile = {
      provider = "anthropic",
      model = "claude-haiku-4-5",
      authType = "max",
    }
  }
  M.chimeVolume = nil -- use default
end

return M
