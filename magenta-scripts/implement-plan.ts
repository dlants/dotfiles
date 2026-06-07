import { registerScript } from "./magenta-sdk/index.ts";
import {
  IMPLEMENT_PLAN_PARAM_SCHEMA,
  type ImplementPlanParams,
  runImplementPlan,
} from "./implement-plan-lib.ts";

registerScript(
  "implement-plan",
  "Implements a plan file stage by stage on a fresh branch, running a gated code-review-and-fix cycle and committing after each stage.",
  IMPLEMENT_PLAN_PARAM_SCHEMA,
  async (params: ImplementPlanParams, thread, log) => {
    await runImplementPlan({ params, thread, log });
  },
);
