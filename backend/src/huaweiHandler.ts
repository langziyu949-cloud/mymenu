import 'dotenv/config';
import { DeepSeekClient } from './ai/deepSeekClient.js';
import { loadDeepSeekConfig } from './config.js';
import {
  buildHuaweiHandler,
  type HuaweiHttpEvent,
  type HuaweiHttpResponse
} from './huawei/buildHuaweiHandler.js';
import { RecipeService } from './services/recipeService.js';

type RuntimeHandler = (event: HuaweiHttpEvent) => Promise<HuaweiHttpResponse>;

let runtimeHandler: RuntimeHandler | undefined;

export async function handler(event: HuaweiHttpEvent): Promise<HuaweiHttpResponse> {
  if (runtimeHandler === undefined) {
    const config = loadDeepSeekConfig();
    const client = new DeepSeekClient(config);
    const service = new RecipeService(client);
    runtimeHandler = buildHuaweiHandler({ service });
  }
  return runtimeHandler(event);
}
