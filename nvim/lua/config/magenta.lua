-- OS-specific magenta.nvim configuration
local is_linux = vim.loop.os_uname().sysname == "Linux"

local M = {}

if is_linux then
  M.profiles = {
    {
      name = "opus-5.0(bedrock)",
      provider = "bedrock",
      model = "us.anthropic.claude-opus-5",
      fastModel = "us.anthropic.claude-haiku-4-5-20251001-v1:0",
      env = {
        AWS_PROFILE = "dev.ai-inference",
        AWS_REGION = "us-west-2"
      },
      tokenRefreshCommand = "dev aws login",
      thinking = {
        enabled = true,
        effort = "low"
      }
    },
    -- gpt-5.6-sol is not served by bedrock-mantle; terra is the closest sibling.
    -- Needs bedrock-mantle:CreateInference, which dev.ai-inference lacks today.
    {
      name = "gpt-5.6-terra(bedrock)",
      provider = "openai",
      model = "openai.gpt-5.6-terra",
      fastModel = "openai.gpt-5.6-luna",
      authType = "bedrock",
      env = {
        AWS_PROFILE = "dev.ai-inference",
        AWS_REGION = "us-west-2"
      },
      thinking = {
        enabled = true,
        effort = "low"
      }
    },
    {
      name = "sonnet-5(bedrock)",
      provider = "bedrock",
      model = "us.anthropic.claude-sonnet-5",
      fastModel = "us.anthropic.claude-haiku-4-5-20251001-v1:0",
      thinkingModel = "us.anthropic.claude-opus-5",
      env = {
        AWS_PROFILE = "dev.ai-inference",
        AWS_REGION = "us-west-2"
      },
      tokenRefreshCommand = "dev aws login",
      thinking = {
        enabled = true,
        effort = "medium"
      }
    },
  }
  M.chimeVolume = .01
else
  M.profiles = {
    {
      name = "opus-5.0(max)",
      provider = "anthropic",
      model = "claude-opus-5",
      authType = "max",
      thinking = {
        enabled = true,
        effort = "low"
      }
    },
    {
      name = "gpt-5.6-sol(chatgpt)",
      provider = "openai",
      model = "gpt-5.6-sol",
      fastModel = "gpt-5.6-luna",
      authType = "chatgpt",
      thinking = {
        enabled = true,
        effort = "low"
      }
    },
    {
      name = "gpt-5.6-terra(bedrock)",
      provider = "openai",
      model = "openai.gpt-5.6-terra",
      fastModel = "openai.gpt-5.6-luna",
      authType = "bedrock",
      env = {
        AWS_PROFILE = "dev.admin",
        AWS_REGION = "us-west-2"
      },
      thinking = {
        enabled = true,
        effort = "medium"
      }
    },
    {
      name = "sonnet-5(max)",
      provider = "anthropic",
      model = "claude-sonnet-5",
      thinkingModel = "claude-opus-5",
      authType = "max",
      thinking = {
        enabled = true,
        effort = "medium"
      }
    },
    {
      name = "opus-5.0(bedrock)",
      provider = "bedrock",
      model = "us.anthropic.claude-opus-5",
      fastModel = "us.anthropic.claude-haiku-4-5-20251001-v1:0",
      env = {
        AWS_PROFILE = "dev.ai-inference",
        AWS_REGION = "us-west-2"
      },
      tokenRefreshCommand = "aws sso login --profile dev.ai-inference",
      thinking = {
        enabled = true,
        effort = "low"
      }
    },
  }
  M.chimeVolume = nil -- use default
end

return M
