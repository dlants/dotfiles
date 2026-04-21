-- OS-specific magenta.nvim configuration
local is_linux = vim.loop.os_uname().sysname == "Linux"

local M = {}

if is_linux then
  M.profiles = {
    {
      name = "opus-4.7(bedrock)",
      provider = "bedrock",
      model = "us.anthropic.claude-opus-4-7",
      fastModel = "us.anthropic.claude-haiku-4-5-20251001-v1:0",
      env = {
        AWS_PROFILE = "dev.ai-inference",
        AWS_REGION = "us-west-2"
      },
      thinking = {
        enabled = true,
        effort = "max"
      }
    },
    {
      name = "opus-4.7(max)",
      provider = "anthropic",
      model = "claude-opus-4-7",
      authType = "max",
      thinking = {
        enabled = true,
        effort = "max"
      }
    }
  }
  M.chimeVolume = .01
else
  M.profiles = {
    {
      name = "opus-4.7(max)",
      provider = "anthropic",
      model = "claude-opus-4-7",
      authType = "max",
      thinking = {
        enabled = true,
        effort = "max"
      }
    },
    {
      name = "opus-4.7(bedrock)",
      provider = "bedrock",
      model = "us.anthropic.claude-opus-4-7",
      fastModel = "us.anthropic.claude-haiku-4-5-20251001-v1:0",
      env = {
        AWS_PROFILE = "dev.ai-inference",
        AWS_REGION = "us-west-2"
      },
      thinking = {
        enabled = true,
        effort = "max"
      }
    },
  }
  M.chimeVolume = nil -- use default
end

return M
