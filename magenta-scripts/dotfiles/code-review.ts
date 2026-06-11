import { registerScript } from "./magenta-sdk/index.ts";
import {
  CODE_REVIEW_PARAM_SCHEMA,
  type CodeReviewParams,
  runReview,
} from "./code-review-lib.ts";

registerScript(
  "code-review",
  "Reviews a git changeset against the repo's Copilot review instructions, spawning one review thread per applicable instruction file.",
  CODE_REVIEW_PARAM_SCHEMA,
  async (params: CodeReviewParams, thread, log) => {
    await runReview({ params, thread, log });
  },
);
