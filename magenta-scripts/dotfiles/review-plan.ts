import { registerScript } from "./magenta-sdk/index.ts";
import {
  REVIEW_PLAN_PARAM_SCHEMA,
  type ReviewPlanParams,
  runReviewPlan,
} from "./review-plan-lib.ts";
registerScript(
  "review-plan",
  "Reviews a plan file from several perspectives in parallel (one thread per perspective), then spawns an agent to revise the plan to address the findings.",
  REVIEW_PLAN_PARAM_SCHEMA,
  async (params: ReviewPlanParams, thread, log) => {
    await runReviewPlan({ params, thread, log });
  },
);
